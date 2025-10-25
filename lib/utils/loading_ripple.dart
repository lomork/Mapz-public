import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class LoadingRipple extends StatefulWidget {
  const LoadingRipple({super.key});

  @override
  State<LoadingRipple> createState() => _LoadingRippleState();
}

class _LoadingRippleState extends State<LoadingRipple> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _RipplePainter(progress: _controller.value),
        );
      },
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double progress;

  _RipplePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    const int numberOfRings = 3;
    for (int i = 0; i < numberOfRings; i++) {
      final delayFactor = i / numberOfRings;
      final ringProgress = (progress - delayFactor).abs();

      if (ringProgress > 0) {
        final currentRadius = maxRadius * ringProgress;
        final rippleColor = Colors.blueAccent.withOpacity((1.0 - ringProgress).clamp(0.0, 0.3));

        final paint = Paint()
          ..color = rippleColor
          ..style = ui.PaintingStyle.fill;

        canvas.drawCircle(center, currentRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}