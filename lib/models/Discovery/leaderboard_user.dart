import 'tier.dart';

class LeaderboardUser {
  final String uid;
  final String name;
  final String photoURL;
  final double percentage;
  final Tier tier;

  LeaderboardUser({
    required this.uid,
    required this.name,
    required this.photoURL,
    required this.percentage,
    required this.tier,
  });
}