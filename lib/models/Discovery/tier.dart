import 'package:flutter/material.dart';

enum Tier { diamond, platinum, gold, silver, bronze, iron }

class TierManager {
  static Tier getTier(double percentage) {
    if (percentage >= 10.0) return Tier.diamond;
    if (percentage >= 5.0) return Tier.platinum;
    if (percentage >= 2.0) return Tier.gold;
    if (percentage >= 0.5) return Tier.silver;
    if (percentage >= 0.1) return Tier.bronze;
    return Tier.iron;
  }

  static Color getColor(Tier tier) {
    switch (tier) {
      case Tier.diamond: return Colors.cyan;
      case Tier.platinum: return Colors.grey.shade400;
      case Tier.gold: return Colors.amber;
      case Tier.silver: return const Color(0xFFC0C0C0);
      case Tier.bronze: return const Color(0xFFCD7F32);
      case Tier.iron: return Colors.brown.shade800;
    }
  }

  static String getName(Tier tier) {
    return tier.name[0].toUpperCase() + tier.name.substring(1);
  }
}