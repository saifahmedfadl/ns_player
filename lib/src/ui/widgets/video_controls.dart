import 'dart:async';
import 'dart:ui';

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
  static const Color _glassBase = Color(0x1AFFFFFF);
  static const Color _glassHighlight = Color(0x33FFFFFF);
  static const Color _glassBorder = Color(0x4DFFFFFF);
  static const Color _accent = Color(0xFF67E8F9);
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Timer? _hideTimer;
  bool _dragging = false;
  double _lastVolume = 1.0;

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

  void _toggleMute(double currentVolume) {
    if (currentVolume > 0) {
      _lastVolume = currentVolume;
      widget.controller.setVolume(0);
    } else {
      widget.controller.setVolume(_lastVolume == 0 ? 1.0 : _lastVolume);
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

  Widget _buildVolumeButton() {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        final volume = value.volume;
        return _buildGlassIconButton(
          icon:
              volume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          onTap: () {
            _resetHideTimer();
            _toggleMute(volume);
          },
          size: widget.isFullScreen ? 44 : 40,
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isFullScreen ? 24.0 : 12.0,
        vertical: 8.0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildVolumeButton(),
          _buildGlassIconButton(
            icon: Icons.more_vert,
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
        // SizedBox(width: widget.isFullScreen ? 28 : 16),
        _buildPlayPauseButton(),
        // SizedBox(width: widget.isFullScreen ? 28 : 16),
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
    return _buildGlassIconButton(
      icon: icon,
      onTap: onTap,
      size: widget.isFullScreen ? 46 : 40,
    );
  }

  Widget _buildPlayPauseButton() {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        final isBuffering = value.isBuffering;
        final isPlaying = value.isPlaying;

        return _buildGlassIconButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTap: () {
            _resetHideTimer();
            if (isPlaying) {
              widget.controller.pause();
            } else {
              widget.controller.play();
            }
          },
          size: widget.isFullScreen ? 72 : 64,
          child: isBuffering
              ? SizedBox(
                  width: widget.isFullScreen ? 40 : 32,
                  height: widget.isFullScreen ? 40 : 32,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isFullScreen ? 24.0 : 12.0,
        vertical: widget.isFullScreen ? 16.0 : 8.0,
      ),
      child: _buildGlassPanel(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: _buildProgressBar(),
        ),
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

        return SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: widget.controller,
                builder: (context, value, child) {
                  return Text(
                    '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  );
                },
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: _accent,
                    inactiveTrackColor:
                        Colors.white.withAlpha((0.3 * 255).round()),
                    thumbColor: _accent,
                    overlayColor: _accent.withAlpha((0.2 * 255).round()),
                    secondaryActiveTrackColor:
                        Colors.white.withAlpha((0.5 * 255).round()),
                  ),
                  child: Slider(
                    value: duration > 0 ? position.clamp(0, duration) : 0,
                    min: 0,
                    max: duration > 0 ? duration : 1,
                    secondaryTrackValue:
                        duration > 0 ? buffered.clamp(0, duration) : 0,
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
                ),
              ),
              InkWell(
                onTap: () {
                  _resetHideTimer();
                  widget.onToggleFullScreen();
                },
                child: Icon(
                    widget.isFullScreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: Colors.white),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildGlassIconButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 44,
    Widget? child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: widget.showControls ? 1 : 0.96,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutBack,
        child: _buildGlassPanel(
          height: size,
          width: size,
          shape: BoxShape.circle,
          child: Center(
            child: child ??
                Icon(
                  icon,
                  color: Colors.white,
                  size: size * 0.48,
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassPanel({
    required Widget child,
    double? height,
    double? width,
    BoxShape shape = BoxShape.rectangle,
  }) {
    return ClipRRect(
      borderRadius: shape == BoxShape.circle
          ? BorderRadius.circular(999)
          : BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: _glassBase,
            borderRadius: shape == BoxShape.circle
                ? BorderRadius.circular(999)
                : BorderRadius.circular(16),
            border: Border.all(color: _glassBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha((0.35 * 255).round()),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_glassHighlight, Colors.transparent],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
