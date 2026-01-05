# NS Player

A modern, feature-rich HLS video player for Flutter with secure video downloads, YouTube-style controls, and built-in fullscreen support.

## Features

- **YouTube-style Controls**: Modern, minimal UI with double-tap to seek, gesture-based progress bar
- **Video Downloads**: Download videos per quality with progress tracking and resume capability
- **Secure Encryption**: AES-256 encrypted local storage - videos only playable through this player
- **Built-in Fullscreen**: Smooth fullscreen mode that works consistently across devices
- **Quality Selection**: Easy quality switching with download options per quality
- **Playback Controls**: Speed control, loop toggle, and more
- **Performance Optimized**: Stream-based decryption for long viewing sessions without overheating

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  ns_player:
    path: ../ns_player  # or your path
```

## Usage

### Basic Usage

```dart
import 'package:ns_player/ns_player.dart';

NsPlayer(
  url: 'https://example.com/video.m3u8',
  videoId: 'unique_video_id',  // Used for download management
  aspectRatio: 16 / 9,
  autoPlay: true,
)
```

### With Callbacks

```dart
NsPlayer(
  url: 'https://example.com/video.m3u8',
  videoId: 'video_123',
  headers: {'Referer': 'https://example.com'},
  autoPlay: false,
  onVideoInitCompleted: (controller) {
    print('Video initialized');
  },
  onFullScreenChanged: (isFullScreen) {
    print('Fullscreen: $isFullScreen');
  },
  onPlayingVideo: (videoType) {
    print('Playing: $videoType');
  },
)
```

### Download Management

Videos can be downloaded directly from the settings menu in the player. Each quality option shows:
- Download button (if not downloaded)
- Download progress with speed and percentage (while downloading)
- Delete button (if downloaded)

Downloaded videos are automatically played from local storage when available.

### Programmatic Download Control

```dart
final downloadManager = VideoDownloadManager();

// Start download
await downloadManager.startDownload(
  videoId: 'video_123',
  quality: '720x1280',
  url: 'https://example.com/720p.m3u8',
);

// Check if downloaded
final isDownloaded = await downloadManager.isDownloaded('video_123', '720x1280');

// Delete download
await downloadManager.deleteDownload('video_123', '720x1280');

// Get storage used
final totalBytes = await downloadManager.getTotalStorageUsed();
```

## API Reference

### NsPlayer Widget

| Parameter | Type | Description |
|-----------|------|-------------|
| `url` | `String` | Video source URL (HLS, MP4, MKV, WEBM) |
| `videoId` | `String?` | Unique identifier for download management |
| `aspectRatio` | `double` | Video aspect ratio (default: 16/9) |
| `headers` | `Map<String, String>?` | HTTP headers for video requests |
| `autoPlay` | `bool` | Auto-play on init (default: true) |
| `primaryColor` | `Color?` | Primary color for controls |
| `onVideoInitCompleted` | `Function?` | Called when video initializes |
| `onFullScreenChanged` | `Function?` | Called on fullscreen toggle |
| `onPlayingVideo` | `Function?` | Called when playback starts |
| `onPlayButtonTap` | `Function?` | Called on play/pause tap |

## Security

Downloaded videos are encrypted using AES-256-CTR encryption:
- Each video has a unique encryption key derived from its ID
- Files are stored with `.nsv` extension and cannot be played by other apps
- Stream-based decryption ensures minimal memory usage during playback

## Performance

The player is optimized for long viewing sessions:
- Stream-based decryption (no full file loading)
- Efficient chunk processing (64KB chunks)
- Wakelock management during playback
- Automatic cleanup of temporary files

## Supported Formats

- HLS (.m3u8)
- MP4
- MKV
- WEBM

## Android Permissions

Add to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

## License

MIT License
