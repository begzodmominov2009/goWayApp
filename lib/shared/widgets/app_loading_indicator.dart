import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Drop-in replacement for [CircularProgressIndicator]: a rotating
/// gradient ring built on [AppTheme.primaryColor] by default, adapting
/// to the current dark/light theme.
class AppLoadingIndicator extends StatefulWidget {
  static const double _defaultSize = 36.0;

  final Color? color;
  final double strokeWidth;
  final Animation<Color?>? valueColor;

  const AppLoadingIndicator({
    super.key,
    this.color,
    this.strokeWidth = 3.0,
    this.valueColor,
  });

  @override
  State<AppLoadingIndicator> createState() => _AppLoadingIndicatorState();
}

class _AppLoadingIndicatorState extends State<AppLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ringColor = widget.valueColor?.value ?? widget.color ?? AppTheme.primaryColor;
    final trackColor = isDark ? AppTheme.darkBorder : AppTheme.borderColor;

    return SizedBox(
      width: AppLoadingIndicator._defaultSize,
      height: AppLoadingIndicator._defaultSize,
      child: RotationTransition(
        turns: _controller,
        child: CustomPaint(
          painter: _GradientRingPainter(
            color: ringColor,
            trackColor: trackColor,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _GradientRingPainter extends CustomPainter {
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  _GradientRingPainter({
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = -math.pi / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);

    final gradientPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withOpacity(0.0),
          color.withOpacity(0.25),
          color,
        ],
        stops: const [0.0, 0.55, 1.0],
        transform: const GradientRotation(startAngle),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle, 1.5 * math.pi, false, gradientPaint);
  }

  @override
  bool shouldRepaint(covariant _GradientRingPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}