import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../download/hls_download_service.dart';
import '../encryption/video_encryption_service.dart';

/// Local HTTP server for serving decrypted HLS content
/// Binds only to localhost for security
class LocalHlsServer {
  static LocalHlsServer? _instance;
  HttpServer? _server;
  int? _port;
  String? _currentVideoId;
  String? _currentQuality;
  String? _currentDirectory;

  LocalHlsServer._();

  static LocalHlsServer get instance {
    _instance ??= LocalHlsServer._();
    return _instance!;
  }

  /// Get the current server URL if running
  String? get serverUrl => _port != null ? 'http://127.0.0.1:$_port' : null;

  /// Check if server is running
  bool get isRunning => _server != null;

  /// Start serving a downloaded HLS video
  /// Returns the URL to the master playlist
  Future<String> startServing({
    required String videoId,
    required String quality,
    required String downloadDirectory,
  }) async {
    // If already serving the same video, return existing URL
    if (_server != null &&
        _currentVideoId == videoId &&
        _currentQuality == quality) {
      return '$serverUrl/manifest.m3u8';
    }

    // Stop any existing server
    await stop();

    _currentVideoId = videoId;
    _currentQuality = quality;
    _currentDirectory = downloadDirectory;

    // Find an available port
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0, // Let the OS assign a port
    );
    _port = _server!.port;

    // Handle requests
    _server!.listen(_handleRequest);

    return '$serverUrl/manifest.m3u8';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;

      // Set CORS headers
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add('Access-Control-Allow-Methods', 'GET');

      if (path == '/manifest.m3u8') {
        await _serveManifest(request);
      } else if (path.endsWith('.ts')) {
        await _serveSegment(request, path);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not found');
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Error: $e');
    } finally {
      await request.response.close();
    }
  }

  Future<void> _serveManifest(HttpRequest request) async {
    if (_currentDirectory == null || _currentVideoId == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('No video loaded');
      return;
    }

    final manifestFile = File('$_currentDirectory/manifest.nsm');
    if (!await manifestFile.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Manifest not found');
      return;
    }

    // Read and decrypt manifest
    final encryptedData = await manifestFile.readAsBytes();
    final decryptedData =
        VideoEncryptionService.xorDecrypt(encryptedData, _currentVideoId!);
    final manifestContent = utf8.decode(decryptedData);

    // Update segment URLs to point to local server
    final updatedManifest = _updateManifestUrls(manifestContent);

    request.response.headers.contentType =
        ContentType('application', 'x-mpegURL');
    request.response.write(updatedManifest);
  }

  String _updateManifestUrls(String manifest) {
    // Replace segment filenames with full local URLs
    final lines = manifest.split('\n');
    final buffer = StringBuffer();

    for (final line in lines) {
      if (line.trim().endsWith('.ts')) {
        // Replace with local server URL
        final segmentName = line.trim();
        buffer.writeln('$serverUrl/$segmentName');
      } else {
        buffer.writeln(line);
      }
    }

    return buffer.toString();
  }

  Future<void> _serveSegment(HttpRequest request, String path) async {
    if (_currentDirectory == null || _currentVideoId == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('No video loaded');
      return;
    }

    // Extract segment name from path (e.g., /seg_000.ts -> seg_000)
    final segmentName = path.substring(1).replaceAll('.ts', '');
    final segmentFile = File('$_currentDirectory/$segmentName.nss');

    if (!await segmentFile.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Segment not found: $segmentName');
      return;
    }

    // Set response headers
    request.response.headers.contentType = ContentType('video', 'MP2T');
    final fileSize = await segmentFile.length();
    request.response.headers.contentLength = fileSize;

    // Stream decrypt directly to response using small chunks
    // This uses constant ~64KB RAM regardless of segment size
    // Much better for low-end devices and long videos
    final raf = await segmentFile.open();
    try {
      // IMPORTANT: Use the same key generation as VideoEncryptionService
      // The key is SHA256 hash of 'ns_player_secure_' + videoId
      final keyData =
          sha256.convert('ns_player_secure_$_currentVideoId'.codeUnits).bytes;
      final keyBytes = Uint8List.fromList(keyData);
      int keyIndex = 0;
      const bufferSize = 64 * 1024; // 64KB buffer - optimal for streaming

      while (true) {
        final buffer = await raf.read(bufferSize);
        if (buffer.isEmpty) break;

        // XOR decrypt in-place (no extra memory allocation)
        for (int i = 0; i < buffer.length; i++) {
          buffer[i] ^= keyBytes[keyIndex % keyBytes.length];
          keyIndex++;
        }

        // Send decrypted chunk immediately to player
        request.response.add(buffer);
      }
    } finally {
      await raf.close();
    }
  }

  /// Stop the server
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
    _currentVideoId = null;
    _currentQuality = null;
    _currentDirectory = null;
  }

  /// Clean up resources
  Future<void> dispose() async {
    await stop();
    _instance = null;
  }
}

/// Manager for local HLS playback using temp file decryption
/// Uses VideoPlayerController.file() - NO network_security_config.xml needed!
/// Files are decrypted on-demand with streaming (low RAM) and deleted after playback
class LocalHlsPlaybackManager {
  static final LocalHlsPlaybackManager _instance = LocalHlsPlaybackManager._();

  String? _currentTempDir;

  LocalHlsPlaybackManager._();

  static LocalHlsPlaybackManager get instance => _instance;

  /// Get playback URL for a downloaded video
  /// On iOS: Returns HTTP URL from local server (iOS AVPlayer doesn't support local HLS files)
  /// On Android: Returns file path (works with VideoPlayerController.file())
  /// Note: url parameter is kept for API compatibility but not used for matching
  Future<String?> getPlaybackUrl({
    required String videoId,
    required String quality,
    String? url,
  }) async {
    // Check if video is downloaded using only videoId + quality
    // URL matching removed to fix offline playback
    final isDownloaded = await HlsDownloadService.isDownloaded(
      videoId,
      quality,
    );

    if (!isDownloaded) {
      if (kDebugMode) {
        print(
            'LocalHlsPlaybackManager: Video not downloaded for ID: $videoId, quality: $quality');
      }
      return null;
    }

    // Get download directory
    final baseDir = await getApplicationDocumentsDirectory();
    final safeVideoId = videoId.replaceAll(RegExp(r'[^\w]'), '_');
    final safeQuality = quality.replaceAll(RegExp(r'[^\w]'), '_');
    final downloadDir =
        '${baseDir.path}/ns_player_hls/${safeVideoId}_$safeQuality';

    if (kDebugMode) {
      print('LocalHlsPlaybackManager: Checking download dir: $downloadDir');
    }

    final directory = Directory(downloadDir);
    if (!await directory.exists()) {
      if (kDebugMode) {
        print('LocalHlsPlaybackManager: Directory does not exist');
      }
      return null;
    }

    // Check if manifest exists
    final manifestFile = File('$downloadDir/manifest.nsm');
    if (!await manifestFile.exists()) {
      if (kDebugMode) {
        print('LocalHlsPlaybackManager: manifest.nsm missing');
      }
      return null;
    }

    // iOS: Use local HTTP server (AVPlayer doesn't support local HLS files)
    // Android: Use temp file approach (works with VideoPlayerController.file())
    if (Platform.isIOS) {
      if (kDebugMode) {
        print(
            'LocalHlsPlaybackManager: iOS detected - using local HTTP server');
      }

      // Start local HTTP server to serve HLS content
      final serverUrl = await LocalHlsServer.instance.startServing(
        videoId: videoId,
        quality: quality,
        downloadDirectory: downloadDir,
      );

      if (kDebugMode) {
        print('LocalHlsPlaybackManager: iOS server URL: $serverUrl');
      }

      return serverUrl;
    }

    // Android: Use temp file approach
    final tempPath = await _prepareTempPlayback(
      videoId: videoId,
      downloadDir: downloadDir,
    );

    if (kDebugMode) {
      print('LocalHlsPlaybackManager: Final playback path: $tempPath');
    }
    return tempPath;
  }

  /// Prepare temp directory with decrypted files for playback
  /// Uses streaming decryption (64KB chunks) to minimize RAM usage
  Future<String?> _prepareTempPlayback({
    required String videoId,
    required String downloadDir,
  }) async {
    // 1. Clean up ALL old temp playback files from previous sessions
    try {
      final cacheDir = await getTemporaryDirectory();
      if (await cacheDir.exists()) {
        final entities = cacheDir.listSync();
        for (final entity in entities) {
          if (entity is Directory &&
              entity.path.contains('ns_player_playback_')) {
            await entity.delete(recursive: true);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error cleaning up old temp files: $e');
      }
    }

    // 2. Clean up previous temp files
    await _cleanupTempFiles();

    // 3. Create unique temp directory for THIS specific playback session
    final cacheDir = await getTemporaryDirectory();
    final safeVideoId = videoId.replaceAll(RegExp(r'[^\w]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final playbackDir = Directory(
        '${cacheDir.path}/ns_player_playback_${safeVideoId}_$timestamp');

    if (await playbackDir.exists()) {
      await playbackDir.delete(recursive: true);
    }
    await playbackDir.create(recursive: true);

    _currentTempDir = playbackDir.path;

    // 4. Decrypt manifest
    final encryptedManifest = File('$downloadDir/manifest.nsm');
    if (!await encryptedManifest.exists()) {
      return null;
    }

    final encryptedManifestData = await encryptedManifest.readAsBytes();
    final decryptedManifestData =
        VideoEncryptionService.xorDecrypt(encryptedManifestData, videoId);
    final manifestContent = utf8.decode(decryptedManifestData);

    // Parse manifest to get segment count
    final segmentCount = _countSegments(manifestContent);

    // Decrypt all segments using streaming (low RAM usage)
    for (int i = 0; i < segmentCount; i++) {
      final segmentName = 'seg_${i.toString().padLeft(3, '0')}';
      final encryptedSegment = File('$downloadDir/$segmentName.nss');

      if (!await encryptedSegment.exists()) {
        return null; // Incomplete download
      }

      // Decrypt to temp file using VideoEncryptionService
      await _decryptToFile(
        source: encryptedSegment,
        destination: File('${playbackDir.path}/$segmentName.ts'),
        videoId: videoId,
      );
    }

    // Write manifest with local file paths
    // Pass playbackDir path for iOS absolute URL generation
    final localManifest = _updateManifestForLocalFiles(
      manifestContent,
      playbackDirPath: playbackDir.path,
    );
    final tempManifest = File('${playbackDir.path}/manifest.m3u8');
    await tempManifest.writeAsString(localManifest);

    if (kDebugMode) {
      print(
          'LocalHlsPlaybackManager: Platform: ${Platform.isIOS ? "iOS" : "Android"}');
      print('LocalHlsPlaybackManager: Manifest path: ${tempManifest.path}');
      print('LocalHlsPlaybackManager: Segment count: $segmentCount');
      print('LocalHlsPlaybackManager: First 5 lines of manifest:');
      final lines = localManifest.split('\n');
      for (int i = 0; i < lines.length && i < 5; i++) {
        print('  $i: ${lines[i]}');
      }
    }

    // Return file path for VideoPlayerController.file()
    return tempManifest.path;
  }

  /// Decrypt file to destination using VideoEncryptionService
  Future<void> _decryptToFile({
    required File source,
    required File destination,
    required String videoId,
  }) async {
    // Read encrypted data
    final encryptedData = await source.readAsBytes();

    // Decrypt using the same method used during encryption
    final decryptedData =
        VideoEncryptionService.xorDecrypt(encryptedData, videoId);

    // Write decrypted data
    await destination.writeAsBytes(decryptedData);
  }

  int _countSegments(String manifest) {
    int count = 0;
    for (final line in manifest.split('\n')) {
      if (line.trim().endsWith('.ts')) {
        count++;
      }
    }
    return count;
  }

  String _updateManifestForLocalFiles(
    String manifest, {
    required String playbackDirPath,
  }) {
    final lines = manifest.split('\n');
    final buffer = StringBuffer();
    int segmentCount = 0;

    for (final line in lines) {
      if (line.trim().endsWith('.ts')) {
        final segmentFilename = line.trim();

        // IMPORTANT: When using VideoPlayerController.file() on both iOS and Android,
        // the player resolves segment paths RELATIVE to the manifest file's directory.
        // Using file:// URLs causes error -12865 (kCMFormatDescriptionError_InvalidMediaType) on iOS.
        //
        // The correct approach is to use relative paths (just the filename)
        // since all segments are in the same directory as the manifest.
        buffer.writeln(segmentFilename);

        if (kDebugMode && segmentCount == 0) {
          print(
              'LocalHlsPlaybackManager: First segment (relative): $segmentFilename');
          print(
              'LocalHlsPlaybackManager: Full path would be: $playbackDirPath/$segmentFilename');
        }
        segmentCount++;
      } else {
        buffer.writeln(line);
      }
    }

    if (kDebugMode) {
      print(
          'LocalHlsPlaybackManager: Generated manifest with $segmentCount segments');
      print(
          'LocalHlsPlaybackManager: Platform: ${Platform.isIOS ? "iOS" : "Android"}');
    }

    return buffer.toString();
  }

  /// Clean up temp files immediately
  Future<void> _cleanupTempFiles() async {
    if (_currentTempDir != null) {
      try {
        final dir = Directory(_currentTempDir!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
      _currentTempDir = null;
    }
  }

  /// Stop playback and cleanup temp files
  Future<void> stopPlayback() async {
    await _cleanupTempFiles();
  }

  /// Check if a video quality is available for offline playback
  Future<bool> isAvailableOffline({
    required String videoId,
    required String quality,
  }) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final safeVideoId = videoId.replaceAll(RegExp(r'[^\w]'), '_');
    final safeQuality = quality.replaceAll(RegExp(r'[^\w]'), '_');
    final downloadDir =
        '${baseDir.path}/ns_player_hls/${safeVideoId}_$safeQuality';

    final manifestFile = File('$downloadDir/manifest.nsm');
    final metadataFile = File('$downloadDir/metadata.json');

    return await manifestFile.exists() && await metadataFile.exists();
  }
}
