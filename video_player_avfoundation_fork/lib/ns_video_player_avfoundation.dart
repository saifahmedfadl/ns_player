library ns_video_player_avfoundation;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// iOS implementation of video_player with custom buffer control
class NsVideoPlayerAvfoundation extends VideoPlayerPlatform {
  static const MethodChannel _channel =
      MethodChannel('flutter.io/videoPlayer/ios');

  /// Registers this class as the default instance of [VideoPlayerPlatform].
  static void registerWith() {
    VideoPlayerPlatform.instance = NsVideoPlayerAvfoundation();
  }

  /// Set buffer configuration
  static Future<bool> setBufferConfig(Map<String, int> config) async {
    try {
      final result =
          await _channel.invokeMethod<bool>('setBufferConfig', config);
      return result ?? false;
    } catch (e) {
      print('NsVideoPlayerAvfoundation: Failed to set buffer config: $e');
      return false;
    }
  }

  /// Get current buffer configuration
  static Future<Map<String, dynamic>?> getBufferConfig() async {
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getBufferConfig');
      return result?.cast<String, dynamic>();
    } catch (e) {
      print('NsVideoPlayerAvfoundation: Failed to get buffer config: $e');
      return null;
    }
  }

  @override
  Future<void> init() async {
    await _channel.invokeMethod<void>('init');
  }

  @override
  Future<void> dispose(int textureId) async {
    await _channel.invokeMethod<void>('dispose', {'textureId': textureId});
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    final Map<String, dynamic> dataSourceDescription = <String, dynamic>{};

    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        dataSourceDescription['asset'] = dataSource.asset;
        dataSourceDescription['packageName'] = dataSource.package;
        break;
      case DataSourceType.network:
        dataSourceDescription['uri'] = dataSource.uri;
        dataSourceDescription['formatHint'] =
            _videoFormatStringMap[dataSource.formatHint];
        dataSourceDescription['httpHeaders'] = dataSource.httpHeaders;
        break;
      case DataSourceType.file:
        dataSourceDescription['uri'] = dataSource.uri;
        break;
      case DataSourceType.contentUri:
        dataSourceDescription['uri'] = dataSource.uri;
        break;
    }

    final Map<String, dynamic>? response =
        await _channel.invokeMapMethod<String, dynamic>(
      'create',
      dataSourceDescription,
    );

    return response?['textureId'] as int?;
  }

  @override
  Future<void> setLooping(int textureId, bool looping) async {
    await _channel.invokeMethod<void>('setLooping', {
      'textureId': textureId,
      'looping': looping,
    });
  }

  @override
  Future<void> play(int textureId) async {
    await _channel.invokeMethod<void>('play', {'textureId': textureId});
  }

  @override
  Future<void> pause(int textureId) async {
    await _channel.invokeMethod<void>('pause', {'textureId': textureId});
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    await _channel.invokeMethod<void>('setVolume', {
      'textureId': textureId,
      'volume': volume,
    });
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {
    await _channel.invokeMethod<void>('setPlaybackSpeed', {
      'textureId': textureId,
      'speed': speed,
    });
  }

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    await _channel.invokeMethod<void>('seekTo', {
      'textureId': textureId,
      'position': position.inMilliseconds,
    });
  }

  @override
  Future<Duration> getPosition(int textureId) async {
    final int? position = await _channel.invokeMethod<int>('position', {
      'textureId': textureId,
    });
    return Duration(milliseconds: position ?? 0);
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return EventChannel('flutter.io/videoPlayer/videoEvents$textureId')
        .receiveBroadcastStream()
        .map((dynamic event) {
      final Map<dynamic, dynamic> map = event as Map<dynamic, dynamic>;
      switch (map['event']) {
        case 'initialized':
          return VideoEvent(
            eventType: VideoEventType.initialized,
            duration: Duration(milliseconds: map['duration'] as int),
            size: Size(
              (map['width'] as num).toDouble(),
              (map['height'] as num).toDouble(),
            ),
          );
        case 'completed':
          return VideoEvent(eventType: VideoEventType.completed);
        case 'bufferingUpdate':
          final List<dynamic> values = map['values'] as List<dynamic>;
          return VideoEvent(
            eventType: VideoEventType.bufferingUpdate,
            buffered: values.map<DurationRange>((dynamic value) {
              final List<dynamic> range = value as List<dynamic>;
              return DurationRange(
                Duration(milliseconds: range[0] as int),
                Duration(milliseconds: range[1] as int),
              );
            }).toList(),
          );
        case 'bufferingStart':
          return VideoEvent(eventType: VideoEventType.bufferingStart);
        case 'bufferingEnd':
          return VideoEvent(eventType: VideoEventType.bufferingEnd);
        default:
          return VideoEvent(eventType: VideoEventType.unknown);
      }
    });
  }

  @override
  Widget buildView(int textureId) {
    return Texture(textureId: textureId);
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    // Not implemented in this version
  }

  static const Map<VideoFormat, String> _videoFormatStringMap = {
    VideoFormat.ss: 'ss',
    VideoFormat.hls: 'hls',
    VideoFormat.dash: 'dash',
    VideoFormat.other: 'other',
  };
}
