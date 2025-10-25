import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapz/screens/map/map_screen.dart';
import 'package:mapz/screens/main_screen.dart';

class SplashScreen extends StatelessWidget {
  final User user;
  const SplashScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return RippleSplashScreen(user: user);
  }
}

class RippleSplashScreen extends StatefulWidget {
  final User user;
  const RippleSplashScreen({super.key, required this.user});

  @override
  State<RippleSplashScreen> createState() => _RippleSplashScreenState();
}

class _RippleSplashScreenState extends State<RippleSplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rippleAnimation;
  Offset _rippleOrigin = Offset.zero;
  ui.Image? _appLogoImage;

  @override
  void initState() {
    super.initState();

    // --- SPEED CHANGE ---
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    _rippleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    );

    Timer(const Duration(seconds: 4), _navigateToMap);

    _loadLogoImage();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setRandomOrigin();
      _controller.repeat();
    });
  }

  Future<void> _loadLogoImage() async {
    final ByteData data = await rootBundle.load('assets/images/ic_launcher_foreground.png');
    final Uint8List bytes = data.buffer.asUint8List();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    setState(() {
      _appLogoImage = frame.image;
    });
  }

  void _setRandomOrigin() {
    final size = MediaQuery.of(context).size;
    final corners = [
      const Offset(0, 0),
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    setState(() {
      _rippleOrigin = corners[Random().nextInt(4)];
    });
  }

  void _navigateToMap() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => MainScreen(user: widget.user),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rippleAnimation,
      builder: (context, child) {
        return Scaffold(
          body: Stack(
            children: [
              Container(color: const Color(0xff121212)),
              CustomPaint(
                painter: _RipplePainter(
                  progress: _rippleAnimation.value,
                  origin: _rippleOrigin,
                  appLogo: _appLogoImage,
                ),
                child: Container(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double progress;
  final Offset origin;
  final ui.Image? appLogo;

  _RipplePainter({required this.progress, required this.origin, this.appLogo});

  @override
  void paint(Canvas canvas, Size size) {
    final maxRadius = sqrt(pow(size.width, 2) + pow(size.height, 2));
    final Color finalBgColor = const Color(0xff1a2130);

    final backgroundPaint = Paint()..color = Color.lerp(const Color(0xff121212), finalBgColor, progress)!;
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    const int numberOfRings = 3;
    const double waveFrequency = 15;
    const double waveAmplitude = 10;

    for (int i = 0; i < numberOfRings; i++) {
      final delayFactor = i / numberOfRings;
      final ringProgress = ((progress - delayFactor) / (1.0 - delayFactor)).clamp(0.0, 1.0);

      if (ringProgress > 0) {
        final currentRadius = maxRadius * ringProgress;
        final rippleColor = Colors.blueAccent.withOpacity((1.0 - ringProgress) * 0.5);

        final paint = Paint()
          ..color = rippleColor
          ..style = ui.PaintingStyle.fill; // THE FIX IS HERE: Changed 'painting' to 'ui'

        Path path = Path();
        for (double angle = 0; angle <= 2 * pi; angle += 0.05) {
          final double waveOffset = sin(angle * waveFrequency + progress * 2 * pi * 3) * waveAmplitude;
          final double effectiveRadius = currentRadius + waveOffset;

          final double x = origin.dx + effectiveRadius * cos(angle);
          final double y = origin.dy + effectiveRadius * sin(angle);

          if (angle == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    }

    if (appLogo != null) {
      const double logoSize = 120.0;
      final logoRect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: logoSize,
        height: logoSize,
      );

      final logoRevealProgress = (progress - 0.3).clamp(0.0, 1.0) / 0.7;
      final logoOpacity = logoRevealProgress;
      final logoScale = 0.8 + (0.2 * logoRevealProgress);

      final Matrix4 transform = Matrix4.identity()
        ..translate(logoRect.center.dx, logoRect.center.dy)
        ..scale(logoScale)
        ..translate(-logoRect.center.dx, -logoRect.center.dy);

      canvas.save();
      canvas.transform(transform.storage);

      final logoPaint = Paint()..color = Colors.white.withOpacity(logoOpacity);

      canvas.drawImageRect(
        appLogo!,
        Rect.fromLTWH(0, 0, appLogo!.width.toDouble(), appLogo!.height.toDouble()),
        logoRect,
        logoPaint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.origin != origin || oldDelegate.appLogo != appLogo;
  }
}