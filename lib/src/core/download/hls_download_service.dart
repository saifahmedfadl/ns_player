import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../model/m3u8.dart';
import '../encryption/video_encryption_service.dart';

/// Parsed segment info from HLS playlist
class HlsSegmentInfo {
  final String url;
  final double duration;
  final int index;

  HlsSegmentInfo({
    required this.url,
    required this.duration,
    required this.index,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'duration': duration,
        'index': index,
      };

  factory HlsSegmentInfo.fromJson(Map<String, dynamic> json) => HlsSegmentInfo(
        url: json['url'] as String,
        duration: (json['duration'] as num).toDouble(),
        index: json['index'] as int,
      );
}

/// Service for downloading HLS video streams (all segments)
class HlsDownloadService {
  static final Map<String, HlsDownloadTask> _activeTasks = {};
  static final StreamController<HlsDownloadProgress> _progressController =
      StreamController<HlsDownloadProgress>.broadcast();

  /// Stream of download progress updates for all downloads
  static Stream<HlsDownloadProgress> get progressStream =>
      _progressController.stream;

  /// Start downloading an HLS stream
  static Future<HlsDownloadTask> startDownload({
    required String videoId,
    required M3U8Data quality,
    Map<String, String>? headers,
    void Function(HlsDownloadProgress progress)? onProgress,
    void Function(String directoryPath)? onComplete,
    void Function(dynamic error)? onError,
  }) async {
    final qualityName = quality.dataQuality ?? 'unknown';
    final taskKey = '${videoId}_$qualityName';

    // Check if task already exists and is downloading
    if (_activeTasks.containsKey(taskKey)) {
      final existingTask = _activeTasks[taskKey]!;
      if (existingTask.status == HlsDownloadStatus.downloading) {
        return existingTask;
      }
    }

    // Check if download is paused and can be resumed
    final pausedState = await _loadPausedState(videoId, qualityName);

    final task = HlsDownloadTask(
      videoId: videoId,
      quality: quality,
      headers: headers,
      onProgress: (progress) {
        onProgress?.call(progress);
        _progressController.add(progress);
      },
      onComplete: onComplete,
      onError: onError,
      resumeFromSegment: pausedState?['lastCompletedSegment'] as int?,
    );

    _activeTasks[taskKey] = task;

    // Start download in background
    task._startDownload();

    return task;
  }

  /// Pause a download
  static Future<void> pauseDownload(String videoId, String quality) async {
    final taskKey = '${videoId}_$quality';
    final task = _activeTasks[taskKey];

    if (task != null) {
      await task.pause();
    }
  }

  /// Resume a paused download
  static Future<HlsDownloadTask?> resumeDownload({
    required String videoId,
    required String quality,
    required M3U8Data qualityData,
    Map<String, String>? headers,
    void Function(HlsDownloadProgress progress)? onProgress,
    void Function(String directoryPath)? onComplete,
    void Function(dynamic error)? onError,
  }) async {
    final pausedState = await _loadPausedState(videoId, quality);
    if (pausedState == null) return null;

    return startDownload(
      videoId: videoId,
      quality: qualityData,
      headers: headers,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    );
  }

  /// Get all active download tasks
  static List<HlsDownloadTask> getActiveDownloads() {
    return _activeTasks.values.toList();
  }

  /// Cancel a download
  static Future<void> cancelDownload(String videoId, String quality) async {
    final taskKey = '${videoId}_$quality';
    final task = _activeTasks[taskKey];

    if (task != null) {
      await task.cancel();
      _activeTasks.remove(taskKey);
    }

    // Clear paused state
    await _clearPausedState(videoId, quality);

    // Delete partial files
    await _deleteDownloadDirectory(videoId, quality);
  }

  /// Get active download task
  static HlsDownloadTask? getActiveTask(String videoId, String quality) {
    return _activeTasks['${videoId}_$quality'];
  }

  /// Check if a download is in progress
  static bool isDownloading(String videoId, String quality) {
    final task = _activeTasks['${videoId}_$quality'];
    return task?.status == HlsDownloadStatus.downloading;
  }

  /// Check if a download is paused
  static Future<bool> isPaused(String videoId, String quality) async {
    final task = _activeTasks['${videoId}_$quality'];
    if (task?.status == HlsDownloadStatus.paused) return true;

    // Check persisted state
    final pausedState = await _loadPausedState(videoId, quality);
    return pausedState != null;
  }

  /// Check if HLS is fully downloaded
  /// Uses only videoId + quality as identifier (no URL matching)
  /// This ensures offline playback works regardless of which URL was used to request
  static Future<bool> isDownloaded(String videoId, String quality,
      {String? url}) async {
    try {
      final directory = await _getDownloadDirectory(videoId, quality);
      final metadataFile = File('${directory.path}/metadata.json');
      final manifestFile = File('${directory.path}/manifest.nsm');

      if (!await metadataFile.exists() || !await manifestFile.exists()) {
        return false;
      }

      // Read metadata to verify completion
      final metadataContent = await metadataFile.readAsString();
      final metadata = jsonDecode(metadataContent) as Map<String, dynamic>;

      // Check completion flag
      if (metadata['isComplete'] != true) {
        return false;
      }

      // NOTE: URL matching removed intentionally
      // Downloads are identified by videoId + quality only
      // This fixes offline playback when master URL differs from variant URL

      final segmentCount = metadata['segmentCount'] as int? ?? 0;

      // Verify all segments exist
      for (int i = 0; i < segmentCount; i++) {
        final segmentFile =
            File('${directory.path}/seg_${i.toString().padLeft(3, '0')}.nss');
        if (!await segmentFile.exists()) {
          return false;
        }
      }

      if (kDebugMode) {
        print('HlsDownloadService: Download verified for $videoId/$quality');
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get the path to the downloaded HLS directory
  static Future<String?> getDownloadPath(String videoId, String quality) async {
    if (!await isDownloaded(videoId, quality)) {
      return null;
    }
    final directory = await _getDownloadDirectory(videoId, quality);
    return directory.path;
  }

  /// Delete a downloaded HLS stream
  static Future<void> deleteDownload(String videoId, String quality) async {
    await _clearPausedState(videoId, quality);
    await _deleteDownloadDirectory(videoId, quality);
  }

  /// Get total size of downloaded files
  static Future<int> getDownloadedSize(String videoId, String quality) async {
    try {
      final directory = await _getDownloadDirectory(videoId, quality);
      if (!await directory.exists()) {
        if (kDebugMode) {
          print(
              'HlsDownloadService: Directory does not exist for size calculation');
        }
        return 0;
      }

      int totalSize = 0;
      int fileCount = 0;

      // Recursively calculate size of all files in directory
      await for (final entity in directory.list(recursive: false)) {
        if (entity is File) {
          try {
            final fileSize = await entity.length();
            totalSize += fileSize;
            fileCount++;

            if (kDebugMode && fileCount <= 5) {
              // Log first few files for debugging
              print(
                  'HlsDownloadService: File ${entity.path.split('/').last} = $fileSize bytes');
            }
          } catch (e) {
            if (kDebugMode) {
              print('HlsDownloadService: Error reading file size: $e');
            }
          }
        }
      }

      if (kDebugMode) {
        print(
            'HlsDownloadService: Total size for $videoId/$quality = $totalSize bytes ($fileCount files)');
      }

      return totalSize;
    } catch (e) {
      if (kDebugMode) {
        print('HlsDownloadService: Error calculating downloaded size: $e');
      }
      return 0;
    }
  }

  /// Get all downloads (completed, paused, in-progress)
  static Future<List<DownloadInfo>> getAllDownloads() async {
    final downloads = <DownloadInfo>[];

    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final hlsDir = Directory('${baseDir.path}/ns_player_hls');

      if (!await hlsDir.exists()) return downloads;

      await for (final entity in hlsDir.list()) {
        if (entity is Directory) {
          final metadataFile = File('${entity.path}/metadata.json');
          if (await metadataFile.exists()) {
            try {
              final content = await metadataFile.readAsString();
              final metadata = jsonDecode(content) as Map<String, dynamic>;
              downloads.add(DownloadInfo.fromMetadata(metadata, entity.path));
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    return downloads;
  }

  // Persistence helpers for pause/resume
  static String _getPauseKey(String videoId, String quality) =>
      'hls_pause_${videoId}_$quality';

  static Future<void> _savePausedState(
    String videoId,
    String quality,
    int lastCompletedSegment,
    List<HlsSegmentInfo> segments,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getPauseKey(videoId, quality);
    final state = {
      'videoId': videoId,
      'quality': quality,
      'lastCompletedSegment': lastCompletedSegment,
      'totalSegments': segments.length,
      'pausedAt': DateTime.now().toIso8601String(),
    };
    await prefs.setString(key, jsonEncode(state));
  }

  static Future<Map<String, dynamic>?> _loadPausedState(
      String videoId, String quality) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getPauseKey(videoId, quality);
    final stateJson = prefs.getString(key);
    if (stateJson == null) return null;
    return jsonDecode(stateJson) as Map<String, dynamic>;
  }

  static Future<void> _clearPausedState(String videoId, String quality) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getPauseKey(videoId, quality);
    await prefs.remove(key);
  }

  /// Get download directory for a video quality
  static Future<Directory> _getDownloadDirectory(
      String videoId, String quality) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final safeVideoId = videoId.replaceAll(RegExp(r'[^\w]'), '_');
    final safeQuality = quality.replaceAll(RegExp(r'[^\w]'), '_');

    final downloadDir =
        Directory('${baseDir.path}/ns_player_hls/${safeVideoId}_$safeQuality');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
  }

  /// Delete download directory
  static Future<void> _deleteDownloadDirectory(
      String videoId, String quality) async {
    try {
      final directory = await _getDownloadDirectory(videoId, quality);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }
}

/// Download info for listing all downloads
class DownloadInfo {
  final String videoId;
  final String quality;
  final String directoryPath;
  final int segmentCount;
  final int totalBytes;
  final bool isComplete;
  final DateTime? downloadedAt;

  DownloadInfo({
    required this.videoId,
    required this.quality,
    required this.directoryPath,
    required this.segmentCount,
    required this.totalBytes,
    required this.isComplete,
    this.downloadedAt,
  });

  factory DownloadInfo.fromMetadata(
      Map<String, dynamic> metadata, String path) {
    final qualityData = metadata['quality'] as Map<String, dynamic>?;
    return DownloadInfo(
      videoId: metadata['videoId'] as String? ?? '',
      quality: qualityData?['dataQuality'] as String? ?? 'unknown',
      directoryPath: path,
      segmentCount: metadata['segmentCount'] as int? ?? 0,
      totalBytes: metadata['totalBytes'] as int? ?? 0,
      isComplete: metadata['isComplete'] as bool? ?? false,
      downloadedAt: metadata['downloadedAt'] != null
          ? DateTime.tryParse(metadata['downloadedAt'] as String)
          : null,
    );
  }
}

/// Represents an HLS download task
class HlsDownloadTask {
  final String videoId;
  final M3U8Data quality;
  final Map<String, String>? headers;
  final void Function(HlsDownloadProgress progress)? onProgress;
  final void Function(String directoryPath)? onComplete;
  final void Function(dynamic error)? onError;
  final int? resumeFromSegment;

  HlsDownloadStatus _status = HlsDownloadStatus.pending;
  bool _isCancelled = false;
  bool _isPaused = false;
  int _downloadedSegments = 0;
  int _totalSegments = 0;
  int _downloadedBytes = 0;
  final int _totalBytes = 0;
  double _speed = 0;
  String? _lastError;
  http.Client? _client;
  List<HlsSegmentInfo> _segments = [];

  HlsDownloadStatus get status => _status;
  int get downloadedSegments => _downloadedSegments;
  int get totalSegments => _totalSegments;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  double get speed => _speed;
  double get progress =>
      _totalSegments > 0 ? _downloadedSegments / _totalSegments : 0;

  HlsDownloadTask({
    required this.videoId,
    required this.quality,
    this.headers,
    this.onProgress,
    this.onComplete,
    this.onError,
    this.resumeFromSegment,
  });

  Future<void> _startDownload() async {
    _status = HlsDownloadStatus.downloading;
    _isCancelled = false;
    _isPaused = false;

    try {
      var playlistUrl = quality.dataURL;
      if (playlistUrl == null) {
        throw Exception('No playlist URL provided');
      }

      _client = http.Client();

      // Step 1: Fetch and parse the playlist with EXTINF durations
      // With retry logic for rate limiting
      http.Response? playlistResponse;
      for (int retry = 0; retry < 3; retry++) {
        playlistResponse = await _client!.get(
          Uri.parse(playlistUrl),
          headers: headers,
        );

        if (playlistResponse.statusCode == 429) {
          final retryAfter = playlistResponse.headers['retry-after'];
          final waitSeconds =
              (retryAfter != null ? int.tryParse(retryAfter) ?? 5 : 5) + 2;
          if (kDebugMode) {
            print(
                'HlsDownloadService: Playlist fetch rate limited, waiting ${waitSeconds}s');
          }
          await Future.delayed(Duration(seconds: waitSeconds));
          continue;
        }
        break;
      }

      if (playlistResponse!.statusCode != 200) {
        throw HttpException(
            'Failed to fetch playlist: ${playlistResponse.statusCode}');
      }

      var playlistContent = utf8.decode(playlistResponse.bodyBytes);

      // Check if this is a master playlist (contains EXT-X-STREAM-INF)
      // If so, we need to fetch the actual media playlist
      if (playlistContent.contains('#EXT-X-STREAM-INF')) {
        if (kDebugMode) {
          print(
              'HlsDownload: Detected master playlist, fetching media playlist...');
        }
        // This is a master playlist - find the matching quality playlist
        final mediaPlaylistUrl = _findMediaPlaylistUrl(
          playlistContent,
          playlistUrl,
          quality.dataQuality,
        );
        if (mediaPlaylistUrl == null) {
          throw Exception(
              'Could not find media playlist for quality: ${quality.dataQuality}');
        }

        if (kDebugMode) {
          print('HlsDownload: Using media playlist: $mediaPlaylistUrl');
        }

        // Fetch the actual media playlist with retry for rate limiting
        for (int retry = 0; retry < 3; retry++) {
          playlistResponse = await _client!.get(
            Uri.parse(mediaPlaylistUrl),
            headers: headers,
          );

          if (playlistResponse.statusCode == 429) {
            final retryAfter = playlistResponse.headers['retry-after'];
            final waitSeconds =
                (retryAfter != null ? int.tryParse(retryAfter) ?? 5 : 5) + 2;
            if (kDebugMode) {
              print(
                  'HlsDownloadService: Media playlist fetch rate limited, waiting ${waitSeconds}s');
            }
            await Future.delayed(Duration(seconds: waitSeconds));
            continue;
          }
          break;
        }

        if (playlistResponse!.statusCode != 200) {
          throw HttpException(
              'Failed to fetch media playlist: ${playlistResponse.statusCode}');
        }

        playlistUrl = mediaPlaylistUrl;
        playlistContent = utf8.decode(playlistResponse.bodyBytes);
      }

      _segments = _parsePlaylistWithDurations(playlistContent, playlistUrl);

      _totalSegments = _segments.length;
      _notifyProgress();

      if (_totalSegments == 0) {
        throw Exception('No segments found in playlist');
      }

      // Step 2: Get download directory
      final directory = await HlsDownloadService._getDownloadDirectory(
        videoId,
        quality.dataQuality ?? 'unknown',
      );

      // Step 3: Check for resume - find last downloaded segment
      int startSegment = resumeFromSegment ?? 0;
      if (startSegment == 0) {
        // Check existing files for resume
        for (int i = 0; i < _segments.length; i++) {
          final segmentFile =
              File('${directory.path}/seg_${i.toString().padLeft(3, '0')}.nss');
          if (await segmentFile.exists()) {
            startSegment = i + 1;
            _downloadedSegments = i + 1;
            _downloadedBytes += await segmentFile.length();
          } else {
            break;
          }
        }
      } else {
        _downloadedSegments = startSegment;
      }

      // Step 4: Download remaining segments with retry logic
      DateTime lastSpeedUpdate = DateTime.now();
      int bytesInLastSecond = 0;
      const maxRetries = 3;

      for (int i = startSegment; i < _segments.length; i++) {
        if (_isCancelled) {
          throw DownloadCancelledException();
        }

        if (_isPaused) {
          // Save pause state
          await HlsDownloadService._savePausedState(
            videoId,
            quality.dataQuality ?? 'unknown',
            _downloadedSegments,
            _segments,
          );
          _status = HlsDownloadStatus.paused;
          _notifyProgress();
          return;
        }

        final segment = _segments[i];
        List<int>? segmentData;

        // Retry logic for segment download with rate limit handling
        for (int retry = 0; retry < maxRetries; retry++) {
          try {
            segmentData = await _downloadSegment(segment.url);
            break;
          } catch (e) {
            if (e is RateLimitException) {
              // Rate limited - wait the specified time plus some buffer
              final waitTime = e.retryAfterSeconds + 2;
              if (kDebugMode) {
                print(
                    'HlsDownloadService: Rate limited, waiting ${waitTime}s before retry ${retry + 1}/$maxRetries');
              }
              await Future.delayed(Duration(seconds: waitTime));
            } else {
              if (retry == maxRetries - 1) rethrow;
              // Exponential backoff for other errors
              await Future.delayed(Duration(seconds: 2 << retry));
            }
          }
        }

        // Small delay between segments to avoid rate limiting (50ms)
        // await Future.delayed(const Duration(milliseconds: 50));

        if (segmentData == null) {
          throw Exception(
              'Failed to download segment $i after $maxRetries retries');
        }

        // Encrypt and save segment
        final encryptedData =
            VideoEncryptionService.xorEncrypt(segmentData, videoId);
        final segmentFile =
            File('${directory.path}/seg_${i.toString().padLeft(3, '0')}.nss');
        await segmentFile.writeAsBytes(encryptedData);

        _downloadedSegments = i + 1;
        _downloadedBytes += segmentData.length;
        bytesInLastSecond += segmentData.length;

        // Calculate speed
        final now = DateTime.now();
        final elapsed = now.difference(lastSpeedUpdate).inMilliseconds;
        if (elapsed >= 1000) {
          _speed = bytesInLastSecond / (elapsed / 1000);
          bytesInLastSecond = 0;
          lastSpeedUpdate = now;
        }

        _notifyProgress();
      }

      // Step 5: Save encrypted manifest with ORIGINAL EXTINF durations
      final localManifest = _generateLocalManifestWithDurations(_segments);
      final encryptedManifest = VideoEncryptionService.xorEncrypt(
        utf8.encode(localManifest),
        videoId,
      );
      final manifestFile = File('${directory.path}/manifest.nsm');
      await manifestFile.writeAsBytes(encryptedManifest);

      // Step 6: Save metadata with completion flag and original URL
      final metadata = {
        'videoId': videoId,
        'masterUrl': quality.dataURL, // Store the URL to verify later
        'quality': quality.toJson(),
        'segmentCount': _segments.length,
        'downloadedAt': DateTime.now().toIso8601String(),
        'totalBytes': _downloadedBytes,
        'isComplete': true,
        'segments': _segments.map((s) => s.toJson()).toList(),
      };
      final metadataFile = File('${directory.path}/metadata.json');
      await metadataFile.writeAsString(jsonEncode(metadata));

      // Clear any paused state
      await HlsDownloadService._clearPausedState(
        videoId,
        quality.dataQuality ?? 'unknown',
      );

      _status = HlsDownloadStatus.completed;
      _notifyProgress();
      onComplete?.call(directory.path);
    } catch (e) {
      if (e is DownloadCancelledException) {
        _status = HlsDownloadStatus.cancelled;
        _notifyProgress();
      } else {
        _status = HlsDownloadStatus.failed;
        _lastError = e.toString();
        if (kDebugMode) {
          print('HlsDownloadService: Download failed with error: $_lastError');
        }
        _notifyProgress();
        onError?.call(e);
      }
    } finally {
      _client?.close();
    }
  }

  /// Pause the download
  Future<void> pause() async {
    _isPaused = true;
    _status = HlsDownloadStatus.paused;
    _speed = 0;
    _notifyProgress();

    // Save paused state immediately
    if (_segments.isNotEmpty) {
      await HlsDownloadService._savePausedState(
        videoId,
        quality.dataQuality ?? 'unknown',
        _downloadedSegments,
        _segments,
      );
    }
  }

  Future<List<int>> _downloadSegment(String url) async {
    final response = await _client!.get(
      Uri.parse(url),
      headers: headers,
    );

    if (response.statusCode == 429) {
      // Rate limited - check Retry-After header
      final retryAfter = response.headers['retry-after'];
      final waitSeconds =
          retryAfter != null ? int.tryParse(retryAfter) ?? 5 : 5;
      throw RateLimitException(waitSeconds);
    }

    if (response.statusCode != 200) {
      throw HttpException('Failed to download segment: ${response.statusCode}');
    }

    return response.bodyBytes;
  }

  /// Find the media playlist URL from a master playlist for a specific quality
  String? _findMediaPlaylistUrl(
      String masterContent, String masterUrl, String? targetQuality) {
    final lines = masterContent.split('\n');
    final basePath = masterUrl.substring(0, masterUrl.lastIndexOf('/') + 1);
    final uri = Uri.parse(masterUrl);

    String? currentResolution;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        // Extract resolution from this line
        final resMatch = RegExp(r'RESOLUTION=(\d+x\d+)').firstMatch(line);
        currentResolution = resMatch?.group(1);
        continue;
      }

      // If we have a resolution and this line is a URL
      if (currentResolution != null &&
          line.isNotEmpty &&
          !line.startsWith('#')) {
        // Check if this matches our target quality
        if (targetQuality == null ||
            currentResolution == targetQuality ||
            line.contains(targetQuality.replaceAll('x', '').toLowerCase()) ||
            line.contains(targetQuality.split('x').last)) {
          // Build full URL
          if (line.startsWith('http')) {
            return line;
          } else if (line.startsWith('/')) {
            return '${uri.scheme}://${uri.host}$line';
          } else {
            return '$basePath$line';
          }
        }
        currentResolution = null;
      }
    }

    // If no match found, return the first media playlist
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty && !line.startsWith('#') && line.contains('.m3u8')) {
        if (line.startsWith('http')) {
          return line;
        } else if (line.startsWith('/')) {
          return '${uri.scheme}://${uri.host}$line';
        } else {
          return '$basePath$line';
        }
      }
    }

    return null;
  }

  /// Parse playlist and extract segment URLs with their EXTINF durations
  List<HlsSegmentInfo> _parsePlaylistWithDurations(
      String content, String baseUrl) {
    final segments = <HlsSegmentInfo>[];
    final lines = content.split('\n');

    // Get base URL for relative paths
    final uri = Uri.parse(baseUrl);
    final basePath = baseUrl.substring(0, baseUrl.lastIndexOf('/') + 1);

    double currentDuration = 10.0; // Default duration
    int segmentIndex = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Parse EXTINF duration
      if (line.startsWith('#EXTINF:')) {
        // Format: #EXTINF:10.0, or #EXTINF:10.0
        final durationStr = line.substring(8).split(',')[0].trim();
        currentDuration = double.tryParse(durationStr) ?? 10.0;
        continue;
      }

      // Skip other tags and empty lines
      if (line.isEmpty || line.startsWith('#')) continue;

      // This is a segment URL
      String segmentUrl;
      if (line.startsWith('http://') || line.startsWith('https://')) {
        segmentUrl = line;
      } else if (line.startsWith('/')) {
        // Absolute path
        segmentUrl = '${uri.scheme}://${uri.host}$line';
      } else {
        // Relative path
        segmentUrl = '$basePath$line';
      }

      segments.add(HlsSegmentInfo(
        url: segmentUrl,
        duration: currentDuration,
        index: segmentIndex,
      ));
      segmentIndex++;
      currentDuration = 10.0; // Reset to default for next segment
    }

    return segments;
  }

  /// Generate local manifest preserving original EXTINF durations
  String _generateLocalManifestWithDurations(List<HlsSegmentInfo> segments) {
    if (segments.isEmpty) return '';

    // Calculate max duration for TARGETDURATION
    double maxDuration = 0;
    for (final seg in segments) {
      if (seg.duration > maxDuration) {
        maxDuration = seg.duration;
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('#EXTM3U');
    buffer.writeln('#EXT-X-VERSION:3');
    buffer.writeln('#EXT-X-PLAYLIST-TYPE:VOD');
    buffer.writeln('#EXT-X-TARGETDURATION:${maxDuration.ceil()}');
    buffer.writeln('#EXT-X-MEDIA-SEQUENCE:0');

    for (int i = 0; i < segments.length; i++) {
      // Use original duration from the segment
      buffer.writeln('#EXTINF:${segments[i].duration.toStringAsFixed(6)},');
      buffer.writeln('seg_${i.toString().padLeft(3, '0')}.ts');
    }

    buffer.writeln('#EXT-X-ENDLIST');
    return buffer.toString();
  }

  void _notifyProgress() {
    final progress = HlsDownloadProgress(
      videoId: videoId,
      quality: quality.dataQuality ?? 'unknown',
      downloadedSegments: _downloadedSegments,
      totalSegments: _totalSegments,
      downloadedBytes: _downloadedBytes,
      totalBytes: quality.fileSize ?? _downloadedBytes,
      speed: _speed,
      status: _status,
      errorMessage: _lastError,
    );

    onProgress?.call(progress);
    HlsDownloadService._progressController.add(progress);
  }

  Future<void> cancel() async {
    _isCancelled = true;
    _status = HlsDownloadStatus.cancelled;
    _client?.close();
  }
}

/// HLS download progress information
class HlsDownloadProgress {
  final String videoId;
  final String quality;
  final int downloadedSegments;
  final int totalSegments;
  final int downloadedBytes;
  final int totalBytes;
  final double speed;
  final HlsDownloadStatus status;
  final String? errorMessage;

  double get percentage =>
      totalSegments > 0 ? (downloadedSegments / totalSegments) * 100 : 0;

  String get speedFormatted {
    if (speed < 1024) {
      return '${speed.toStringAsFixed(0)} B/s';
    } else if (speed < 1024 * 1024) {
      return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
  }

  String get sizeFormatted {
    final size = totalBytes > 0 ? totalBytes : downloadedBytes;
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    } else if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  String get progressText => '$downloadedSegments / $totalSegments segments';

  HlsDownloadProgress({
    required this.videoId,
    required this.quality,
    required this.downloadedSegments,
    required this.totalSegments,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.speed,
    required this.status,
    this.errorMessage,
  });

  /// Create a copy with error message
  HlsDownloadProgress copyWithError(String error) {
    return HlsDownloadProgress(
      videoId: videoId,
      quality: quality,
      downloadedSegments: downloadedSegments,
      totalSegments: totalSegments,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      speed: 0,
      status: HlsDownloadStatus.failed,
      errorMessage: error,
    );
  }
}

/// HLS download status enum
enum HlsDownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

/// Exception for cancelled downloads
class DownloadCancelledException implements Exception {
  @override
  String toString() => 'Download was cancelled';
}

/// Exception for rate limiting (HTTP 429)
class RateLimitException implements Exception {
  final int retryAfterSeconds;

  RateLimitException(this.retryAfterSeconds);

  @override
  String toString() => 'Rate limited. Retry after $retryAfterSeconds seconds';
}
