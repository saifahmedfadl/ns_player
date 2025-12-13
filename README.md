# NSPlayer

NSPlayer is a HLS (.m3u8) video player for Flutter. The NSPlayer allows you to select HLS video streaming by selecting the quality.

## Features

- Play HLS (.m3u8) video streams
- Select video quality
- Customizable UI
- Fullscreen support
- Rewind and fast forward functionality

## Installation

Add the following to your `pubspec.yaml` file:

```yaml
dependencies:
  ns_player: ^0.0.3
```

Then run 
```flutter pub get```.
Uses the following permissions in the AndroidManifest.xml file:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```
Uses
Basic usage of NSPlayer is as follows:
```
import 'package:flutter/material.dart';
import 'package:ns_player/ns_player.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: VideoPlayerScreen(),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(
      'https://example.com/video.m3u8',
    )..initialize().then((_) {
        setState(() {});
      });
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying
                ? _controller.pause()
                : _controller.play();
          });
        },
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}
```
Customization
```
PlayerBottomBar(
  controller: _controller,
  showBottomBar: true,
  fullScreen: false,
  videoDuration: "00:00:00",
  videoSeek: "00:00:00",
  videoStyle: VideoStyle(
    playButtonIconColor: Colors.white,
    forwardIconColor: Colors.white,
    backwardIconColor: Colors.white,
  ),
  onPlayButtonTap: () {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  },
  onFastForward: (value) {
    // Handle fast forward
  },
  onRewind: (value) {
    // Handle rewind
  },
),
```

License
This structure includes sections for features, installation, basic usage, customization, and license. Adjust the content as needed to fit your package's specifics.
