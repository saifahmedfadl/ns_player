import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:ns_player/src/core/encryption/video_encryption_service.dart';
import 'package:path_provider/path_provider.dart';

/// Service for downloading videos with resume capability
class VideoDownloadService {
  static final Map<String, VideoDownloadTask> _activeTasks = {};

  /// Start or resume a video download
  static Future<VideoDownloadTask> startDownload({
    required String videoId,
    required String quality,
    required String url,
    Map<String, String>? headers,
    void Function(DownloadProgress progress)? onProgress,
    void Function(String filePath)? onComplete,
    void Function(dynamic error)? onError,
  }) async {
    final taskKey = '${videoId}_$quality';

    // Check if task already exists
    if (_activeTasks.containsKey(taskKey)) {
      final existingTask = _activeTasks[taskKey]!;
      if (existingTask.status == DownloadStatus.downloading) {
        return existingTask;
      }
    }

    final task = VideoDownloadTask(
      videoId: videoId,
      quality: quality,
      url: url,
      headers: headers,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    );

    _activeTasks[taskKey] = task;

    // Start download in background
    task._startDownload();

    return task;
  }

  /// Cancel a download
  static Future<void> cancelDownload(String videoId, String quality) async {
    final taskKey = '${videoId}_$quality';
    final task = _activeTasks[taskKey];

    if (task != null) {
      await task.cancel();
      _activeTasks.remove(taskKey);
    }

    // Delete partial files
    await _deletePartialFiles(videoId, quality);
  }

  /// Get active download task
  static VideoDownloadTask? getActiveTask(String videoId, String quality) {
    return _activeTasks['${videoId}_$quality'];
  }

  /// Check if a download is in progress
  static bool isDownloading(String videoId, String quality) {
    final task = _activeTasks['${videoId}_$quality'];
    return task?.status == DownloadStatus.downloading;
  }

  /// Delete partial download files
  static Future<void> _deletePartialFiles(
      String videoId, String quality) async {
    try {
      final directory = await _getDownloadDirectory();
      final safeVideoId = videoId.replaceAll(RegExp(r'[^\w]'), '_');
      final safeQuality = quality.replaceAll(RegExp(r'[^\w]'), '_');

      final partialFile =
          File('${directory.path}/ns_${safeVideoId}_$safeQuality.partial');
      final progressFile =
          File('${directory.path}/ns_${safeVideoId}_$safeQuality.progress');

      if (await partialFile.exists()) await partialFile.delete();
      if (await progressFile.exists()) await progressFile.delete();
    } catch (_) {}
  }

  static Future<Directory> _getDownloadDirectory() async {
    Directory? directory;
    if (Platform.isAndroid) {
      directory = await getApplicationDocumentsDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    final downloadDir = Directory('${directory.path}/ns_player_videos');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
  }

  /// Get resume position for a partial download
  static Future<int> getResumePosition(String videoId, String quality) async {
    try {
      final directory = await _getDownloadDirectory();
      final safeVideoId = videoId.replaceAll(RegExp(r'[^\w]'), '_');
      final safeQuality = quality.replaceAll(RegExp(r'[^\w]'), '_');

      final progressFile =
          File('${directory.path}/ns_${safeVideoId}_$safeQuality.progress');

      if (await progressFile.exists()) {
        final content = await progressFile.readAsString();
        return int.tryParse(content) ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  /// Save resume position
  static Future<void> _saveResumePosition(
      String videoId, String quality, int position) async {
    try {
      final directory = await _getDownloadDirectory();
      final safeVideoId = videoId.replaceAll(RegExp(r'[^\w]'), '_');
      final safeQuality = quality.replaceAll(RegExp(r'[^\w]'), '_');

      final progressFile =
          File('${directory.path}/ns_${safeVideoId}_$safeQuality.progress');
      await progressFile.writeAsString(position.toString());
    } catch (_) {}
  }
}

/// Represents a video download task
class VideoDownloadTask {
  final String videoId;
  final String quality;
  final String url;
  final Map<String, String>? headers;
  final void Function(DownloadProgress progress)? onProgress;
  final void Function(String filePath)? onComplete;
  final void Function(dynamic error)? onError;

  DownloadStatus _status = DownloadStatus.pending;
  bool _isCancelled = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  double _speed = 0;
  http.Client? _client;
  StreamSubscription? _connectivitySubscription;

  DownloadStatus get status => _status;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  double get speed => _speed;
  double get progress => _totalBytes > 0 ? _downloadedBytes / _totalBytes : 0;

  VideoDownloadTask({
    required this.videoId,
    required this.quality,
    required this.url,
    this.headers,
    this.onProgress,
    this.onComplete,
    this.onError,
  });

  Future<void> _startDownload() async {
    _status = DownloadStatus.downloading;
    _isCancelled = false;

    // Listen for connectivity changes
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      if (result.contains(ConnectivityResult.none) &&
          _status == DownloadStatus.downloading) {
        _status = DownloadStatus.paused;
        _notifyProgress();
      }
    });

    try {
      // Check for resume position
      final resumePosition =
          await VideoDownloadService.getResumePosition(videoId, quality);
      _downloadedBytes = resumePosition;

      // Create HTTP client
      _client = http.Client();

      // Build request with range header for resume
      final request = http.Request('GET', Uri.parse(url));
      if (headers != null) {
        request.headers.addAll(headers!);
      }
      if (resumePosition > 0) {
        request.headers['Range'] = 'bytes=$resumePosition-';
      }

      final response = await _client!.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('Failed to download: ${response.statusCode}');
      }

      // Get total size
      if (response.statusCode == 206) {
        // Partial content - parse Content-Range header
        final contentRange = response.headers['content-range'];
        if (contentRange != null) {
          final match = RegExp(r'bytes \d+-\d+/(\d+)').firstMatch(contentRange);
          if (match != null) {
            _totalBytes = int.parse(match.group(1)!);
          }
        }
      } else {
        _totalBytes = response.contentLength ?? 0;
      }

      // Create data stream controller for encryption
      final streamController = StreamController<List<int>>();

      // Start encryption in parallel
      final encryptionFuture = VideoEncryptionService.encryptAndSave(
        dataStream: streamController.stream,
        videoId: videoId,
        quality: quality,
        totalBytes: _totalBytes,
        onProgress: (bytesWritten, total) {
          // Progress is tracked separately
        },
        isCancelled: () => _isCancelled,
      );

      // Process download stream
      int lastProgressUpdate = 0;
      int bytesInLastSecond = 0;
      DateTime lastSpeedUpdate = DateTime.now();

      await for (final chunk in response.stream) {
        if (_isCancelled) {
          streamController.close();
          throw DownloadCancelledException();
        }

        streamController.add(chunk);
        _downloadedBytes += chunk.length;
        bytesInLastSecond += chunk.length;

        // Calculate speed every second
        final now = DateTime.now();
        final elapsed = now.difference(lastSpeedUpdate).inMilliseconds;
        if (elapsed >= 1000) {
          _speed = bytesInLastSecond / (elapsed / 1000);
          bytesInLastSecond = 0;
          lastSpeedUpdate = now;
        }

        // Update progress every 100KB or 1%
        if (_downloadedBytes - lastProgressUpdate > 102400 ||
            (_totalBytes > 0 &&
                (_downloadedBytes - lastProgressUpdate) / _totalBytes > 0.01)) {
          lastProgressUpdate = _downloadedBytes;
          await VideoDownloadService._saveResumePosition(
              videoId, quality, _downloadedBytes);
          _notifyProgress();
        }
      }

      streamController.close();

      // Wait for encryption to complete
      final filePath = await encryptionFuture;

      _status = DownloadStatus.completed;
      _notifyProgress();
      onComplete?.call(filePath);

      // Clean up progress file
      await _cleanupProgressFile();
    } catch (e) {
      if (e is DownloadCancelledException) {
        _status = DownloadStatus.cancelled;
      } else {
        _status = DownloadStatus.failed;
        onError?.call(e);
      }
      _notifyProgress();
    } finally {
      _client?.close();
      _connectivitySubscription?.cancel();
    }
  }

  void _notifyProgress() {
    onProgress?.call(DownloadProgress(
      videoId: videoId,
      quality: quality,
      downloadedBytes: _downloadedBytes,
      totalBytes: _totalBytes,
      speed: _speed,
      status: _status,
    ));
  }

  Future<void> cancel() async {
    _isCancelled = true;
    _status = DownloadStatus.cancelled;
    _client?.close();
    _connectivitySubscription?.cancel();
    await _cleanupProgressFile();
  }

  Future<void> _cleanupProgressFile() async {
    try {
      final directory = await VideoDownloadService._getDownloadDirectory();
      final safeVideoId = videoId.replaceAll(RegExp(r'[^\w]'), '_');
      final safeQuality = quality.replaceAll(RegExp(r'[^\w]'), '_');

      final progressFile =
          File('${directory.path}/ns_${safeVideoId}_$safeQuality.progress');
      if (await progressFile.exists()) {
        await progressFile.delete();
      }
    } catch (_) {}
  }
}

/// Download progress information
class DownloadProgress {
  final String videoId;
  final String quality;
  final int downloadedBytes;
  final int totalBytes;
  final double speed;
  final DownloadStatus status;

  double get percentage =>
      totalBytes > 0 ? (downloadedBytes / totalBytes) * 100 : 0;

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
    if (totalBytes < 1024) {
      return '$totalBytes B';
    } else if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    } else if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  DownloadProgress({
    required this.videoId,
    required this.quality,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.speed,
    required this.status,
  });
}

/// Download status enum
enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}
