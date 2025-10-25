import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class AnimatedRouteLine extends StatefulWidget {
  const AnimatedRouteLine({super.key});

  @override
  State<AnimatedRouteLine> createState() => _AnimatedRouteLineState();
}

class _AnimatedRouteLineState extends State<AnimatedRouteLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RoutePainter(progress: _controller.value, context: context),
          );
        },
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final double progress;
  final BuildContext context;

  _RoutePainter({required this.progress, required this.context});

  @override
  void paint(Canvas canvas, Size size) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final Paint backgroundPaint = Paint()
      ..color = isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final Paint foregroundPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    Path path = Path();
    path.moveTo(0, size.height / 2);
    path.quadraticBezierTo(size.width / 2, 0, size.width, size.height / 2);

    canvas.drawPath(path, backgroundPaint);

    for (ui.PathMetric pathMetric in path.computeMetrics()) {
      final extractPath =
      pathMetric.extractPath(0.0, pathMetric.length * progress);
      canvas.drawPath(extractPath, foregroundPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}