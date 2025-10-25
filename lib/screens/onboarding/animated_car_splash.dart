// lib/screens/animated_car_splash.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mapz/screens/main_screen.dart';

class AnimatedCarSplash extends StatefulWidget {
  final User user;
  const AnimatedCarSplash({super.key, required this.user});

  @override
  State<AnimatedCarSplash> createState() => _AnimatedCarSplashState();
}

class _AnimatedCarSplashState extends State<AnimatedCarSplash> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _carAnimation;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 2), // Duration for one pass
      vsync: this,
    );

    // Initialize with a default animation; it will be updated once the screen size is known.
    _carAnimation = Tween<double>(begin: 0, end: 0).animate(_controller);

    // This triggers all your background loading tasks.
    // We'll just simulate it with a delay for this example.
    _initializeApp();

    // This ensures we get the screen dimensions before starting the animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLoadingAnimation();
    });
  }

  Future<void> _initializeApp() async {
    // In a real app, you would await your Firebase initialization,
    // settings loading, etc., here. We'll use a delay to simulate loading.
    await Future.delayed(const Duration(seconds: 3));

    // When loading is done, trigger the car's exit animation.
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _startExitAnimation();
    }
  }

  void _startLoadingAnimation() {
    final screenWidth = MediaQuery.of(context).size.width;
    const carSize = 80.0;

    // Car moves from just off-screen left to just off-screen right
    _carAnimation = Tween<double>(begin: -carSize, end: screenWidth).animate(_controller)
      ..addListener(() {
        setState(() {}); // Rebuild the widget on every animation frame
      });

    // Loop the animation continuously while loading.
    _controller.repeat();
  }

  void _startExitAnimation() {
    final screenWidth = MediaQuery.of(context).size.width;
    final currentCarPosition = _carAnimation.value;

    _controller.stop(); // Stop the repeating animation

    // Create a new, faster animation for the exit.
    _carAnimation = Tween<double>(
      begin: currentCarPosition,
      end: screenWidth + 100, // Animate fully off-screen
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeIn, // The easeIn curve creates an acceleration effect
      ),
    );

    // Run the exit animation forward once.
    _controller.duration = const Duration(milliseconds: 600);
    _controller.forward().then((_) {
      // After the animation finishes, navigate to the main screen.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => MainScreen(user: widget.user)),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const carSize = 80.0;

    return Scaffold(
      backgroundColor: const Color(0xff1a2130), // A dark, modern blue-grey
      body: Stack(
        children: [
          // The Road Line
          Align(
            alignment: Alignment.center,
            child: Container(
              height: 3,
              width: double.infinity,
              color: Colors.grey.shade700,
            ),
          ),

          // The Animated Car Icon
          Positioned(
            left: _carAnimation.value,
            // Center the icon vertically on the road line
            top: MediaQuery.of(context).size.height / 2 - (carSize / 2),
            child: const Icon(
              Icons.directions_car, // Using a built-in Material icon
              color: Colors.white,
              size: carSize,
            ),
          ),

          // Optional: Loading Text
          if (_isLoading)
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 80.0),
                child: Text(
                  "Loading...",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}