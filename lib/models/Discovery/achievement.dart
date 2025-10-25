import 'package:flutter/material.dart';

class Achievement {
  final String name;
  final IconData icon;
  final double percentRequired;

  Achievement({
    required this.name,
    required this.icon,
    required this.percentRequired,
  });
}