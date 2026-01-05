import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Modern YouTube-style video controls overlay
class VideoControls extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isFullScreen;
  final VoidCallback onToggleFullScreen;
  final VoidCallback onSettingsTap;
  final bool showControls;
  final VoidCallback onToggleControls;

  const VideoControls({
    super.key,
    required this.controller,
    required this.isFullScreen,
    required this.onToggleFullScreen,
    required this.onSettingsTap,
    required this.showControls,
    required this.onToggleControls,
  });

  @override
  State<VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<VideoControls>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Timer? _hideTimer;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    if (widget.showControls) {
      _animationController.forward();
      _startHideTimer();
    }
  }

  @override
  void didUpdateWidget(VideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showControls != oldWidget.showControls) {
      if (widget.showControls) {
        _animationController.forward();
        _startHideTimer();
      } else {
        _animationController.reverse();
        _hideTimer?.cancel();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (widget.controller.value.isPlaying && !_dragging) {
      _hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted &&
            widget.showControls &&
            widget.controller.value.isPlaying) {
          widget.onToggleControls();
        }
      });
    }
  }

  void _resetHideTimer() {
    if (widget.showControls) {
      _startHideTimer();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: IgnorePointer(
        ignoring: !widget.showControls,
        child: Stack(
          children: [
            // Top gradient - IgnorePointer ensures hits pass through to background
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withAlpha((0.7 * 255).round()),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Bottom gradient - IgnorePointer ensures hits pass through to background
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withAlpha((0.7 * 255).round()),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Top bar with settings
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),
            // Center play/pause button
            Center(
              child: _buildCenterControls(),
            ),
            // Bottom bar with progress and controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isFullScreen ? 24.0 : 12.0,
        vertical: 8.0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildIconButton(
            icon: Icons.settings_rounded,
            onTap: () {
              _resetHideTimer();
              widget.onSettingsTap();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCenterControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // // Rewind 10 seconds
        // _buildSeekButton(
        //   icon: Icons.replay_10_rounded,
        //   onTap: () {
        //     _resetHideTimer();
        //     final newPosition =
        //         widget.controller.value.position - const Duration(seconds: 10);
        //     widget.controller.seekTo(
        //       newPosition < Duration.zero ? Duration.zero : newPosition,
        //     );
        //   },
        // ),
        // const SizedBox(width: 40),
        // Play/Pause
        _buildPlayPauseButton(),
        // const SizedBox(width: 40),
        // // Forward 10 seconds
        // _buildSeekButton(
        //   icon: Icons.forward_10_rounded,
        //   onTap: () {
        //     _resetHideTimer();
        //     final newPosition =
        //         widget.controller.value.position + const Duration(seconds: 10);
        //     final duration = widget.controller.value.duration;
        //     widget.controller.seekTo(
        //       newPosition > duration ? duration : newPosition,
        //     );
        //   },
        // ),
      ],
    );
  }

  Widget _buildSeekButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: widget.isFullScreen ? 32 : 25,
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        final isBuffering = value.isBuffering;
        final isPlaying = value.isPlaying;

        return GestureDetector(
          onTap: () {
            _resetHideTimer();
            if (isPlaying) {
              widget.controller.pause();
            } else {
              widget.controller.play();
            }
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: isBuffering
                ? SizedBox(
                    width: widget.isFullScreen ? 40 : 32,
                    height: widget.isFullScreen ? 40 : 32,
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: widget.isFullScreen ? 48 : 40,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isFullScreen ? 24.0 : 12.0,
        vertical: widget.isFullScreen ? 16.0 : 4.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          _buildProgressBar(),

          // Time and fullscreen
          Row(
            children: [
              // Current time / Duration
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: widget.controller,
                builder: (context, value, child) {
                  return Text(
                    '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
              const Spacer(),
              // Fullscreen button
              _buildIconButton(
                icon: widget.isFullScreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                onTap: () {
                  _resetHideTimer();
                  widget.onToggleFullScreen();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        final duration = value.duration.inMilliseconds.toDouble();
        final position = value.position.inMilliseconds.toDouble();
        final buffered = value.buffered.isNotEmpty
            ? value.buffered.last.end.inMilliseconds.toDouble()
            : 0.0;

        return SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 3),
            activeTrackColor: Colors.red,
            inactiveTrackColor: Colors.white.withAlpha((0.3 * 255).round()),
            thumbColor: Colors.red,
            overlayColor: Colors.red.withAlpha((0.3 * 255).round()),
            secondaryActiveTrackColor:
                Colors.white.withAlpha((0.5 * 255).round()),
          ),
          child: Slider(
            value: duration > 0 ? position.clamp(0, duration) : 0,
            min: 0,
            max: duration > 0 ? duration : 1,
            secondaryTrackValue: duration > 0 ? buffered.clamp(0, duration) : 0,
            onChangeStart: (_) {
              _dragging = true;
              _hideTimer?.cancel();
            },
            onChanged: (newValue) {
              widget.controller
                  .seekTo(Duration(milliseconds: newValue.toInt()));
            },
            onChangeEnd: (_) {
              _dragging = false;
              _startHideTimer();
            },
          ),
        );
      },
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          color: Colors.white,
          size: widget.isFullScreen ? 28 : 24,
        ),
      ),
    );
  }
}
