// lib/screens/animated_splash_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mapz/screens/auth/auth_gate.dart';

// Helper class to hold the random properties for each tree
class _Tree {
  final String assetPath;
  final double height;
  final double horizontalOffset;
  final double verticalOffset;

  _Tree({
    required this.assetPath,
    required this.height,
    required this.horizontalOffset,
    required this.verticalOffset,
  });
}

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen> with TickerProviderStateMixin {
  late AnimationController _introController;
  late AnimationController _exitController;
  late AnimationController _backgroundController;

  late Animation<Offset> _carPositionAnimation;
  late Animation<double> _carRotationAnimation;
  late Animation<double> _backgroundAnimation;

  final List<String> _treeAssets = [
    'assets/images/Tree1.svg',
    'assets/images/Tree2.svg',
    'assets/images/Tree3.svg',
  ];

  final List<_Tree> _trees = [];
  double _backgroundWidth = 0;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _exitController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _backgroundController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );

    _carPositionAnimation = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(_introController);
    _carRotationAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(_exitController);
    _backgroundAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(_backgroundController);

    _startAnimationSequence();
  }

  Future<void> _startAnimationSequence() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    _generateRandomTrees();

    final screenWidth = MediaQuery.of(context).size.width;
    const carSize = 80.0;
    final centerScreenX = (screenWidth / 2) - (carSize / 2);

    _carPositionAnimation = Tween<Offset>(
      begin: Offset(-carSize, 0),
      end: Offset(centerScreenX, 0),
    ).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOut),
    );

    _backgroundAnimation = Tween<double>(
      begin: 0.0,
      end: -_backgroundWidth,
    ).animate(
      CurvedAnimation(parent: _backgroundController, curve: Curves.linear),
    );

    _introController.forward();
    _backgroundController.repeat();

    await Future.delayed(const Duration(seconds: 4));

    if (mounted) {
      _triggerExitAnimation(centerScreenX, screenWidth);
    }
  }

  void _generateRandomTrees() {
    final screenWidth = MediaQuery.of(context).size.width;
    final random = Random();

    _backgroundWidth = screenWidth * 3;
    const treeCount = 15;

    for (int i = 0; i < treeCount; i++) {
      _trees.add(_Tree(
        assetPath: _treeAssets[random.nextInt(_treeAssets.length)],
        height: random.nextDouble() * 60 + 80,
        horizontalOffset: random.nextDouble() * _backgroundWidth,
        verticalOffset: random.nextDouble() * 20,
      ));
    }
  }

  void _triggerExitAnimation(double startX, double screenWidth) {
    _introController.stop();
    _backgroundController.stop();

    _carPositionAnimation = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: Offset(startX, 0), end: Offset(startX - 20, 0)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(begin: Offset(startX - 20, 0), end: Offset(screenWidth + 100, 0)),
        weight: 85,
      ),
    ]).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeIn));

    _carRotationAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.4), weight: 40),
      TweenSequenceItem(tween: Tween(begin: -0.4, end: -0.2), weight: 45),
    ]).animate(_exitController);

    _exitController.forward().then((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthGate()),
      );
    });
  }

  @override
  void dispose() {
    _introController.dispose();
    _exitController.dispose();
    _backgroundController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const carSize = 80.0;
    final theme = Theme.of(context);
    final onSurfaceColor = theme.colorScheme.onSurface;

    // --- NEW: Define specific tree colors for light and dark themes ---
    final isDarkMode = theme.brightness == Brightness.dark;
    final treeColor = isDarkMode
        ? Colors.green.shade900.withOpacity(0.7) // A very dark, subtle green for night
        : Colors.green.shade800; // A solid dark green for daytime

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: AnimatedBuilder(
        animation: Listenable.merge([_introController, _exitController, _backgroundController]),
        builder: (context, carChild) {
          return Stack(
            children: [
              // Render the pre-generated random trees
              ..._trees.map((tree) {
                final treeWidth = tree.height * 0.6;
                final leftPosition = (_backgroundAnimation.value + tree.horizontalOffset) % _backgroundWidth;

                return Positioned(
                  left: leftPosition,
                  bottom: MediaQuery.of(context).size.height / 2 + 10 + tree.verticalOffset,
                  child: SvgPicture.asset(
                    tree.assetPath,
                    height: tree.height,
                    width: treeWidth,
                    // --- UPDATED: Use the new theme-specific treeColor ---
                    colorFilter: ColorFilter.mode(treeColor, BlendMode.srcIn),
                  ),
                );
              }).toList(),

              // Road
              Align(
                alignment: Alignment.center,
                child: Container(
                  height: 3,
                  width: double.infinity,
                  color: theme.dividerColor,
                ),
              ),
              // Car
              Positioned(
                child: Transform.translate(
                  offset: _carPositionAnimation.value,
                  child: Transform.rotate(
                    angle: _carRotationAnimation.value,
                    origin: Offset(carSize * 0.75, carSize * 0.5),
                    child: carChild,
                  ),
                ),
                top: MediaQuery.of(context).size.height / 2 - (carSize / 2),
              ),
            ],
          );
        },
        child: SvgPicture.asset(
          'assets/images/my_car.svg',
          height: carSize,
          colorFilter: ColorFilter.mode(onSurfaceColor, BlendMode.srcIn),
        ),
      ),
    );
  }
}