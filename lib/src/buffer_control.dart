import 'dart:io';

import 'package:flutter/services.dart';

/// Buffer configuration for video player
/// Controls how much video data is buffered ahead of playback
class NsBufferConfig {
  /// Minimum buffer duration in milliseconds
  final int minBufferMs;

  /// Maximum buffer duration in milliseconds
  final int maxBufferMs;

  /// Buffer duration required to start playback in milliseconds
  final int bufferForPlaybackMs;

  /// Buffer duration required after rebuffering in milliseconds
  final int bufferForPlaybackAfterRebufferMs;

  /// Back buffer duration in milliseconds (how much played content to keep)
  final int backBufferDurationMs;

  const NsBufferConfig({
    this.minBufferMs = 2500,
    this.maxBufferMs = 30000,
    this.bufferForPlaybackMs = 1500,
    this.bufferForPlaybackAfterRebufferMs = 3000,
    this.backBufferDurationMs = 30000,
  });

  /// Minimal buffering preset (15s max) - saves bandwidth
  static const minimal = NsBufferConfig(
    minBufferMs: 2000,
    maxBufferMs: 15000,
    bufferForPlaybackMs: 1000,
    bufferForPlaybackAfterRebufferMs: 2000,
    backBufferDurationMs: 15000,
  );

  /// Low buffering preset (30s max) - good balance
  static const low = NsBufferConfig(
    minBufferMs: 2500,
    maxBufferMs: 30000,
    bufferForPlaybackMs: 1500,
    bufferForPlaybackAfterRebufferMs: 3000,
    backBufferDurationMs: 30000,
  );

  /// Medium buffering preset (60s max) - smooth playback
  static const medium = NsBufferConfig(
    minBufferMs: 5000,
    maxBufferMs: 60000,
    bufferForPlaybackMs: 2500,
    bufferForPlaybackAfterRebufferMs: 5000,
    backBufferDurationMs: 60000,
  );

  /// High buffering preset (120s max) - best quality
  static const high = NsBufferConfig(
    minBufferMs: 15000,
    maxBufferMs: 120000,
    bufferForPlaybackMs: 5000,
    bufferForPlaybackAfterRebufferMs: 10000,
    backBufferDurationMs: 120000,
  );

  Map<String, int> toMap() => {
        'minBufferMs': minBufferMs,
        'maxBufferMs': maxBufferMs,
        'bufferForPlaybackMs': bufferForPlaybackMs,
        'bufferForPlaybackAfterRebufferMs': bufferForPlaybackAfterRebufferMs,
        'backBufferDurationMs': backBufferDurationMs,
      };

  @override
  String toString() => 'NsBufferConfig(maxBuffer: ${maxBufferMs}ms)';
}

/// Buffer presets for easy configuration
enum BufferPreset {
  /// Minimal buffering - saves bandwidth (15s max)
  minimal,

  /// Low buffering - good balance (30s max)
  low,

  /// Medium buffering - smooth playback (60s max)
  medium,

  /// High buffering - best quality, high bandwidth (120s max)
  high,
}

/// Controller for video player buffer settings
///
/// Usage:
/// ```dart
/// // Initialize with minimal buffer (recommended for bandwidth saving)
/// await NsBufferControl.initialize(BufferPreset.minimal);
///
/// // Or use custom config
/// await NsBufferControl.setConfig(NsBufferConfig(
///   maxBufferMs: 20000,  // 20 seconds max buffer
/// ));
/// ```
class NsBufferControl {
  static NsBufferConfig _currentConfig = NsBufferConfig.low;

  /// Get current buffer configuration
  static NsBufferConfig get currentConfig => _currentConfig;

  /// Initialize buffer control with a preset
  /// Call this before creating any video players
  static Future<bool> initialize(
      [BufferPreset preset = BufferPreset.low]) async {
    return usePreset(preset);
  }

  /// Set buffer configuration using a preset
  static Future<bool> usePreset(BufferPreset preset) async {
    switch (preset) {
      case BufferPreset.minimal:
        return setConfig(NsBufferConfig.minimal);
      case BufferPreset.low:
        return setConfig(NsBufferConfig.low);
      case BufferPreset.medium:
        return setConfig(NsBufferConfig.medium);
      case BufferPreset.high:
        return setConfig(NsBufferConfig.high);
    }
  }

  /// Set custom buffer configuration
  /// Call this before creating video players
  static Future<bool> setConfig(NsBufferConfig config) async {
    _currentConfig = config;

    // Determine the correct channel based on platform
    final channelName = Platform.isAndroid
        ? 'flutter.io/videoPlayer/android'
        : 'flutter.io/videoPlayer/ios';

    final channel = MethodChannel(channelName);

    try {
      final result =
          await channel.invokeMethod<bool>('setBufferConfig', config.toMap());
      return result ?? false;
    } on PlatformException catch (e) {
      print('NsBufferControl: Failed to set buffer config: ${e.message}');
      return false;
    } on MissingPluginException {
      // Plugin not available, config is already stored
      return true;
    }
  }

  /// Get current buffer configuration from native player
  static Future<Map<String, dynamic>?> getBufferStatus() async {
    // Determine the correct channel based on platform
    final channelName = Platform.isAndroid
        ? 'flutter.io/videoPlayer/android'
        : 'flutter.io/videoPlayer/ios';

    final channel = MethodChannel(channelName);

    try {
      final result =
          await channel.invokeMethod<Map<dynamic, dynamic>>('getBufferConfig');
      return result?.cast<String, dynamic>();
    } on PlatformException catch (e) {
      print('NsBufferControl: Failed to get buffer status: ${e.message}');
      return null;
    } on MissingPluginException {
      return _currentConfig.toMap().cast<String, dynamic>();
    }
  }
}
