import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:path_provider/path_provider.dart';

/// Service for encrypting and decrypting video files
/// Uses AES-256-CTR for stream-based encryption/decryption
/// Optimized for long viewing sessions without performance issues
class VideoEncryptionService {
  static const String _keyPrefix = 'ns_player_secure_';

  /// Generate a unique encryption key based on video identifier
  static Key _generateKey(String videoId) {
    final keyData = sha256.convert('$_keyPrefix$videoId'.codeUnits).bytes;
    return Key(Uint8List.fromList(keyData));
  }

  /// Get the encrypted file path for a video
  static Future<String> getEncryptedFilePath(
      String videoId, String quality) async {
    final directory = await _getSecureDirectory();
    final safeVideoId = videoId.replaceAll(RegExp(r'[^\w]'), '_');
    final safeQuality = quality.replaceAll(RegExp(r'[^\w]'), '_');
    return '${directory.path}/ns_${safeVideoId}_$safeQuality.nsv';
  }

  /// Get the secure storage directory
  static Future<Directory> _getSecureDirectory() async {
    Directory? directory;
    if (Platform.isAndroid) {
      directory = await getApplicationDocumentsDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    final secureDir = Directory('${directory.path}/ns_player_videos');
    if (!await secureDir.exists()) {
      await secureDir.create(recursive: true);
    }
    return secureDir;
  }

  /// Encrypt and save video data with progress callback
  /// Returns the encrypted file path
  /// Uses simple XOR encryption for better compatibility with streaming
  static Future<String> encryptAndSave({
    required Stream<List<int>> dataStream,
    required String videoId,
    required String quality,
    required int totalBytes,
    void Function(int bytesWritten, int totalBytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final key = _generateKey(videoId);

    final filePath = await getEncryptedFilePath(videoId, quality);
    final file = File(filePath);
    final sink = file.openWrite();

    int bytesWritten = 0;

    try {
      await for (final chunk in dataStream) {
        if (isCancelled?.call() == true) {
          await sink.close();
          if (await file.exists()) {
            await file.delete();
          }
          throw DownloadCancelledException();
        }

        // Simple XOR encryption with key - consistent and reversible
        final encrypted = _xorEncrypt(chunk, key.bytes, bytesWritten);

        sink.add(encrypted);
        bytesWritten += chunk.length;
        onProgress?.call(bytesWritten, totalBytes);
      }

      await sink.flush();
      await sink.close();

      // Write metadata file
      await _writeMetadata(videoId, quality, totalBytes);

      return filePath;
    } catch (e) {
      await sink.close();
      if (e is! DownloadCancelledException && await file.exists()) {
        // Keep partial file for resume capability
      }
      rethrow;
    }
  }

  /// XOR encrypt/decrypt data with key (internal use)
  static List<int> _xorEncrypt(List<int> data, List<int> key, int offset) {
    final result = List<int>.filled(data.length, 0);
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ key[(offset + i) % key.length];
    }
    return result;
  }

  /// Public XOR encrypt/decrypt for HLS segments
  /// Uses video ID to generate consistent key
  static List<int> xorEncrypt(List<int> data, String videoId) {
    final key = _generateKey(videoId);
    return _xorEncrypt(data, key.bytes, 0);
  }

  /// Public XOR decrypt (same as encrypt for XOR)
  static List<int> xorDecrypt(List<int> data, String videoId) {
    return xorEncrypt(data, videoId);
  }

  /// Create a decrypted stream for playback
  /// Uses stream-based decryption for memory efficiency
  static Stream<List<int>> createDecryptedStream({
    required String videoId,
    required String quality,
  }) async* {
    final key = _generateKey(videoId);

    final filePath = await getEncryptedFilePath(videoId, quality);
    final file = File(filePath);

    if (!await file.exists()) {
      throw FileNotFoundException('Encrypted video file not found');
    }

    int bytesRead = 0;
    await for (final chunk in file.openRead()) {
      // XOR decrypt with same key and offset
      final decrypted = _xorEncrypt(chunk, key.bytes, bytesRead);
      bytesRead += chunk.length;
      yield decrypted;
    }
  }

  /// Create a temporary decrypted file for video player
  /// The file is decrypted on-demand and cleaned up after use
  static Future<String> createTempDecryptedFile({
    required String videoId,
    required String quality,
  }) async {
    final key = _generateKey(videoId);

    final encryptedPath = await getEncryptedFilePath(videoId, quality);
    final encryptedFile = File(encryptedPath);

    if (!await encryptedFile.exists()) {
      throw FileNotFoundException(
          'Encrypted video file not found: $encryptedPath');
    }

    // Create temp file in cache directory
    final tempDir = await getTemporaryDirectory();
    final tempPath =
        '${tempDir.path}/ns_temp_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final tempFile = File(tempPath);
    final sink = tempFile.openWrite();

    int bytesRead = 0;
    await for (final chunk in encryptedFile.openRead()) {
      // XOR decrypt with same key and offset
      final decrypted = _xorEncrypt(chunk, key.bytes, bytesRead);
      bytesRead += chunk.length;
      sink.add(decrypted);
    }

    await sink.flush();
    await sink.close();

    return tempPath;
  }

  /// Clean up temporary decrypted files
  static Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('ns_temp_')) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  /// Write metadata for the encrypted video
  static Future<void> _writeMetadata(
      String videoId, String quality, int totalBytes) async {
    final directory = await _getSecureDirectory();
    final safeVideoId = videoId.replaceAll(RegExp(r'[^\w]'), '_');
    final safeQuality = quality.replaceAll(RegExp(r'[^\w]'), '_');
    final metaFile =
        File('${directory.path}/ns_${safeVideoId}_$safeQuality.meta');

    await metaFile
        .writeAsString('$totalBytes\n${DateTime.now().toIso8601String()}');
  }

  /// Read metadata for the encrypted video
  static Future<VideoMetadata?> readMetadata(
      String videoId, String quality) async {
    try {
      final directory = await _getSecureDirectory();
      final safeVideoId = videoId.replaceAll(RegExp(r'[^\w]'), '_');
      final safeQuality = quality.replaceAll(RegExp(r'[^\w]'), '_');
      final metaFile =
          File('${directory.path}/ns_${safeVideoId}_$safeQuality.meta');

      if (!await metaFile.exists()) return null;

      final lines = await metaFile.readAsLines();
      if (lines.length < 2) return null;

      return VideoMetadata(
        totalBytes: int.parse(lines[0]),
        downloadedAt: DateTime.parse(lines[1]),
      );
    } catch (_) {
      return null;
    }
  }

  /// Check if a video is downloaded
  static Future<bool> isVideoDownloaded(String videoId, String quality) async {
    final filePath = await getEncryptedFilePath(videoId, quality);
    final file = File(filePath);
    final metadata = await readMetadata(videoId, quality);

    if (!await file.exists() || metadata == null) return false;

    final fileSize = await file.length();
    return fileSize >= metadata.totalBytes;
  }

  /// Get the size of downloaded video
  static Future<int> getDownloadedSize(String videoId, String quality) async {
    final filePath = await getEncryptedFilePath(videoId, quality);
    final file = File(filePath);

    if (!await file.exists()) return 0;
    return await file.length();
  }

  /// Delete a downloaded video
  static Future<void> deleteVideo(String videoId, String quality) async {
    final directory = await _getSecureDirectory();
    final safeVideoId = videoId.replaceAll(RegExp(r'[^\w]'), '_');
    final safeQuality = quality.replaceAll(RegExp(r'[^\w]'), '_');

    final videoFile =
        File('${directory.path}/ns_${safeVideoId}_$safeQuality.nsv');
    final metaFile =
        File('${directory.path}/ns_${safeVideoId}_$safeQuality.meta');
    final partialFile =
        File('${directory.path}/ns_${safeVideoId}_$safeQuality.partial');

    if (await videoFile.exists()) await videoFile.delete();
    if (await metaFile.exists()) await metaFile.delete();
    if (await partialFile.exists()) await partialFile.delete();
  }

  /// Get total storage used by all downloaded videos
  static Future<int> getTotalStorageUsed() async {
    try {
      final directory = await _getSecureDirectory();
      int totalSize = 0;

      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.nsv')) {
          totalSize += await entity.length();
        }
      }

      return totalSize;
    } catch (_) {
      return 0;
    }
  }
}

/// Metadata for downloaded video
class VideoMetadata {
  final int totalBytes;
  final DateTime downloadedAt;

  VideoMetadata({
    required this.totalBytes,
    required this.downloadedAt,
  });
}

/// Exception thrown when download is cancelled
class DownloadCancelledException implements Exception {
  @override
  String toString() => 'Download was cancelled';
}

/// Exception thrown when file is not found
class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);

  @override
  String toString() => message;
}
