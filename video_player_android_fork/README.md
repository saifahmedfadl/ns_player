# NS Video Player Android

A forked version of `video_player_android` with custom buffer control.

## Features

- Custom buffer configuration to reduce bandwidth usage
- Compatible with `video_player` package
- Uses ExoPlayer with configurable `DefaultLoadControl`

## Usage

### 1. Add to your app's pubspec.yaml

```yaml
dependencies:
  video_player: ^2.10.1
  
dependency_overrides:
  video_player_android:
    path: ../ns_video_player_android
```

### 2. Set buffer configuration

```dart
import 'package:ns_video_player_android/ns_video_player_android.dart';

// Set buffer config before creating video players
await NsVideoPlayerAndroid.setBufferConfig(NsBufferConfig.minimal);

// Then use video_player as usual
final controller = VideoPlayerController.networkUrl(
  Uri.parse('https://example.com/video.m3u8'),
);
await controller.initialize();
```

## Buffer Presets

| Preset | Max Buffer | Use Case |
|--------|------------|----------|
| `minimal` | 15 seconds | Save bandwidth |
| `low` | 30 seconds | Good balance |
| `medium` | 60 seconds | Smooth playback |
| `high` | 120 seconds | Best quality |

## License

BSD-3-Clause (same as original video_player)
