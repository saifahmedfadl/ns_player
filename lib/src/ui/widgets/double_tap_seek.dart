import 'dart:async';

import 'package:flutter/material.dart';

/// Widget for handling double-tap to seek forward/backward
class DoubleTapSeek extends StatefulWidget {
  final Widget child;
  final Duration seekDuration;
  final VoidCallback onSeekForward;
  final VoidCallback onSeekBackward;
  final VoidCallback onSingleTap;

  const DoubleTapSeek({
    super.key,
    required this.child,
    this.seekDuration = const Duration(seconds: 10),
    required this.onSeekForward,
    required this.onSeekBackward,
    required this.onSingleTap,
  });

  @override
  State<DoubleTapSeek> createState() => _DoubleTapSeekState();
}

class _DoubleTapSeekState extends State<DoubleTapSeek>
    with TickerProviderStateMixin {
  Timer? _singleTapTimer;
  bool _showLeftRipple = false;
  bool _showRightRipple = false;
  int _leftTapCount = 0;
  int _rightTapCount = 0;

  late AnimationController _leftAnimationController;
  late AnimationController _rightAnimationController;
  late Animation<double> _leftFadeAnimation;
  late Animation<double> _rightFadeAnimation;

  @override
  void initState() {
    super.initState();
    _leftAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _rightAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _leftFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _leftAnimationController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );
    _rightFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _rightAnimationController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    _leftAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _showLeftRipple = false;
          _leftTapCount = 0;
        });
      }
    });

    _rightAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _showRightRipple = false;
          _rightTapCount = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _singleTapTimer?.cancel();
    _leftAnimationController.dispose();
    _rightAnimationController.dispose();
    super.dispose();
  }

  void _handleTap(TapDownDetails details) {
    _singleTapTimer?.cancel();
    _singleTapTimer = Timer(const Duration(milliseconds: 200), () {
      widget.onSingleTap();
    });
  }

  void _handleDoubleTap(TapDownDetails details) {
    _singleTapTimer?.cancel();

    // Use RenderBox to get the actual width of this widget instead of screen width
    final RenderBox box = context.findRenderObject() as RenderBox;
    final width = box.size.width;
    final tapX = details.localPosition.dx;
    final isLeftSide = tapX < width / 2;

    if (isLeftSide) {
      _handleLeftDoubleTap();
    } else {
      _handleRightDoubleTap();
    }
  }

  void _handleLeftDoubleTap() {
    setState(() {
      _showLeftRipple = true;
      _leftTapCount++;
    });
    _leftAnimationController.forward(from: 0);
    widget.onSeekBackward();
  }

  void _handleRightDoubleTap() {
    setState(() {
      _showRightRipple = true;
      _rightTapCount++;
    });
    _rightAnimationController.forward(from: 0);
    widget.onSeekForward();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main content
        GestureDetector(
          onTapDown: _handleTap,
          onDoubleTapDown: _handleDoubleTap,
          onDoubleTap: () {},
          behavior: HitTestBehavior.opaque,
          child: widget.child,
        ),
        // Left ripple effect
        if (_showLeftRipple)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width / 2,
            child: FadeTransition(
              opacity: _leftFadeAnimation,
              child: _buildRippleContent(
                isLeft: true,
                tapCount: _leftTapCount,
              ),
            ),
          ),
        // Right ripple effect
        if (_showRightRipple)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width / 2,
            child: FadeTransition(
              opacity: _rightFadeAnimation,
              child: _buildRippleContent(
                isLeft: false,
                tapCount: _rightTapCount,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRippleContent({required bool isLeft, required int tapCount}) {
    final seconds = tapCount * widget.seekDuration.inSeconds;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            Colors.white.withAlpha((0.3 * 255).round()),
            Colors.transparent,
          ],
        ),
        borderRadius: BorderRadius.horizontal(
          left: isLeft ? Radius.zero : const Radius.circular(100),
          right: isLeft ? const Radius.circular(100) : Radius.zero,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLeft ? Icons.replay_10_rounded : Icons.forward_10_rounded,
              color: Colors.white,
              size: 40,
            ),
            const SizedBox(height: 4),
            Text(
              '$seconds seconds',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
