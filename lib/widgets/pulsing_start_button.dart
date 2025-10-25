import 'package:flutter/material.dart';

class PulsingStartButton extends StatefulWidget {
  final VoidCallback onPressed;
  const PulsingStartButton({super.key, required this.onPressed});

  @override
  State<PulsingStartButton> createState() => _PulsingStartButtonState();
}

class _PulsingStartButtonState extends State<PulsingStartButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 1.05).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
      ),
      child: ElevatedButton.icon(
        onPressed: widget.onPressed,
        icon: const Icon(Icons.navigation_outlined),
        label: const Text("Start"),
        style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.blue,
            padding: const EdgeInsets.symmetric(vertical: 12)),
      ),
    );
  }
}