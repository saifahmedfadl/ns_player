import 'package:flutter/material.dart';

/// Modern balloon-style loading animation for video player
class VideoLoadingAnimation extends StatefulWidget {
  final Color? primaryColor;
  final Color? secondaryColor;
  final String? loadingText;

  const VideoLoadingAnimation({
    super.key,
    this.primaryColor,
    this.secondaryColor,
    this.loadingText,
  });

  @override
  State<VideoLoadingAnimation> createState() => _VideoLoadingAnimationState();
}

class _VideoLoadingAnimationState extends State<VideoLoadingAnimation>
    with TickerProviderStateMixin {
  static const Color _accent = Color(0xFF67E8F9);
  static const Color _accentSoft = Color(0x8067E8F9);
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotationAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.primaryColor ?? _accent;
    final secondaryColor = widget.secondaryColor ?? _accentSoft;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        gradient: RadialGradient(
          colors: [
            Colors.black.withAlpha((0.6 * 255).round()),
            Colors.black,
          ],
          radius: 1.2,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated loading indicator
            AnimatedBuilder(
              animation:
                  Listenable.merge([_pulseAnimation, _rotationAnimation]),
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer ring
                        Transform.rotate(
                          angle: _rotationAnimation.value * 2 * 3.14159,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: secondaryColor,
                                width: 3,
                              ),
                            ),
                            child: CustomPaint(
                              painter: _ArcPainter(
                                color: primaryColor,
                                progress: 0.3,
                              ),
                            ),
                          ),
                        ),
                        // Inner circle
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryColor.withAlpha((0.12 * 255).round()),
                            border: Border.all(
                              color:
                                  primaryColor.withAlpha((0.35 * 255).round()),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: primaryColor,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            // Loading text with fade animation
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.5 + (_pulseAnimation.value - 0.8) * 1.25,
                  child: Text(
                    widget.loadingText ?? 'Loading video...',
                    style: TextStyle(
                      color: Colors.white.withAlpha((0.8 * 255).round()),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for drawing arc
class _ArcPainter extends CustomPainter {
  final Color color;
  final double progress;

  _ArcPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawArc(rect, -1.57, progress * 2 * 3.14159, false, paint);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

/// Buffering indicator overlay
class BufferingIndicator extends StatelessWidget {
  const BufferingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha((0.3 * 255).round()),
      child: const Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            color: Color(0xFF67E8F9),
            strokeWidth: 3,
          ),
        ),
      ),
    );
  }
}
