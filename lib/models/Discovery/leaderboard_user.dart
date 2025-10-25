import 'package:cloud_firestore/cloud_firestore.dart';
import 'tier.dart';

class LeaderboardUser {
  final String name;
  final double percentage;
  final Tier tier;

  LeaderboardUser({
    required this.name,
    required this.percentage,
    required this.tier,
  });

  factory LeaderboardUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final double percentage = (data['percentage'] ?? 0.0).toDouble();

    return LeaderboardUser(
      name: data['displayName'] ?? 'Unknown User',
      percentage: percentage,
      tier: TierManager.getTier(percentage),
    );
  }
}