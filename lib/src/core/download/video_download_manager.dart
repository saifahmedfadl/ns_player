import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ns_player/src/core/download/video_download_service.dart';
import 'package:ns_player/src/core/encryption/video_encryption_service.dart';

/// Manager for handling video downloads across the app
class VideoDownloadManager extends ChangeNotifier {
  static final VideoDownloadManager _instance =
      VideoDownloadManager._internal();
  factory VideoDownloadManager() => _instance;
  VideoDownloadManager._internal();

  final Map<String, DownloadProgress> _downloadProgress = {};
  final Map<String, bool> _downloadedVideos = {};

  /// Get download progress for a video
  DownloadProgress? getProgress(String videoId, String quality) {
    return _downloadProgress['${videoId}_$quality'];
  }

  /// Check if video is downloaded
  Future<bool> isDownloaded(String videoId, String quality) async {
    final key = '${videoId}_$quality';
    if (_downloadedVideos.containsKey(key)) {
      return _downloadedVideos[key]!;
    }

    final isDownloaded =
        await VideoEncryptionService.isVideoDownloaded(videoId, quality);
    _downloadedVideos[key] = isDownloaded;
    return isDownloaded;
  }

  /// Start downloading a video
  Future<void> startDownload({
    required String videoId,
    required String quality,
    required String url,
    Map<String, String>? headers,
  }) async {
    await VideoDownloadService.startDownload(
      videoId: videoId,
      quality: quality,
      url: url,
      headers: headers,
      onProgress: (progress) {
        _downloadProgress['${videoId}_$quality'] = progress;
        notifyListeners();
      },
      onComplete: (filePath) {
        _downloadedVideos['${videoId}_$quality'] = true;
        notifyListeners();
      },
      onError: (error) {
        if (kDebugMode) {
          print('Download error: $error');
        }
        notifyListeners();
      },
    );
  }

  /// Cancel a download
  Future<void> cancelDownload(String videoId, String quality) async {
    await VideoDownloadService.cancelDownload(videoId, quality);
    _downloadProgress.remove('${videoId}_$quality');
    notifyListeners();
  }

  /// Delete a downloaded video
  Future<void> deleteDownload(String videoId, String quality) async {
    await VideoEncryptionService.deleteVideo(videoId, quality);
    _downloadedVideos['${videoId}_$quality'] = false;
    _downloadProgress.remove('${videoId}_$quality');
    notifyListeners();
  }

  /// Get downloaded video size
  Future<int> getDownloadedSize(String videoId, String quality) async {
    return await VideoEncryptionService.getDownloadedSize(videoId, quality);
  }

  /// Get total storage used
  Future<int> getTotalStorageUsed() async {
    return await VideoEncryptionService.getTotalStorageUsed();
  }

  /// Check if download is in progress
  bool isDownloading(String videoId, String quality) {
    return VideoDownloadService.isDownloading(videoId, quality);
  }

  /// Get decrypted file path for playback
  Future<String> getDecryptedFilePath(String videoId, String quality) async {
    return await VideoEncryptionService.createTempDecryptedFile(
      videoId: videoId,
      quality: quality,
    );
  }

  /// Cleanup temporary files
  Future<void> cleanupTempFiles() async {
    await VideoEncryptionService.cleanupTempFiles();
  }

  /// Format bytes to human readable string
  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
}
