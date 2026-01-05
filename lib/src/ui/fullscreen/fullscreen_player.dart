import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../widgets/double_tap_seek.dart';
import '../widgets/video_controls.dart';

/// Fullscreen video player page
class FullscreenPlayer extends StatefulWidget {
  final VideoPlayerController controller;
  final VoidCallback onExitFullscreen;
  final VoidCallback onSettingsTap;

  const FullscreenPlayer({
    super.key,
    required this.controller,
    required this.onExitFullscreen,
    required this.onSettingsTap,
  });

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  bool _showControls = true;
  late double _aspectRatio;

  @override
  void initState() {
    super.initState();
    // Cache aspect ratio to avoid rebuilds
    _aspectRatio = widget.controller.value.aspectRatio;

    // Set orientation and UI mode after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
  }

  @override
  void dispose() {
    // Restore orientation and UI
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _seekForward() {
    final newPosition =
        widget.controller.value.position + const Duration(seconds: 10);
    final duration = widget.controller.value.duration;
    widget.controller.seekTo(newPosition > duration ? duration : newPosition);
  }

  void _seekBackward() {
    final newPosition =
        widget.controller.value.position - const Duration(seconds: 10);
    widget.controller
        .seekTo(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          widget.onExitFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Video player - use cached aspect ratio
            Center(
              child: AspectRatio(
                aspectRatio: _aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),
            // Double tap seek handler
            DoubleTapSeek(
              onSeekForward: _seekForward,
              onSeekBackward: _seekBackward,
              onSingleTap: _toggleControls,
              child: const SizedBox.expand(),
            ),
            // Controls overlay
            VideoControls(
              controller: widget.controller,
              isFullScreen: true,
              showControls: _showControls,
              onToggleControls: _toggleControls,
              onToggleFullScreen: widget.onExitFullscreen,
              onSettingsTap: widget.onSettingsTap,
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper class to manage fullscreen navigation
class FullscreenManager {
  static bool _isFullscreen = false;

  static bool get isFullscreen => _isFullscreen;

  /// Enter fullscreen mode
  static Future<void> enterFullscreen(
    BuildContext context, {
    required VideoPlayerController controller,
    required VoidCallback onExitFullscreen,
    required VoidCallback onSettingsTap,
  }) async {
    if (_isFullscreen) return;
    _isFullscreen = true;

    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FullscreenPlayer(
            controller: controller,
            onExitFullscreen: () {
              exitFullscreen(context);
              onExitFullscreen();
            },
            onSettingsTap: onSettingsTap,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Simple fade with no extra effects for better performance
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 150),
      ),
    );

    _isFullscreen = false;
  }

  /// Exit fullscreen mode
  static void exitFullscreen(BuildContext context) {
    if (!_isFullscreen) return;
    _isFullscreen = false;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}
