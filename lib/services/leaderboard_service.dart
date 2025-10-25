import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/discovery/leaderboard_user.dart';
import '../models/discovery/tier.dart';

class LeaderboardService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  /// Fetches the national leaderboard for a given country.
  Future<List<LeaderboardUser>> getNationalLeaderboard(String country) async {

    try {

      final querySnapshot = await _db
          .collection('users')
          .orderBy('discovery.$country', descending: true)
          .limit(100)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return [];
      }

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        final percentage = (data['discovery']?[country] as num? ?? 0).toDouble();
        return LeaderboardUser(
          name: data['displayName'] ?? 'Anonymous',
          percentage: percentage,
          tier: TierManager.getTier(percentage),
        );
      }).toList();
    } catch (e) {
      print("Error fetching national leaderboard from Firestore: $e");
      return []; // Return empty list on error
    }
  }

  /// Fetches users who are in the same tier as the current user.
  Future<List<LeaderboardUser>> getRivals(Tier userTier) async {
    // For simplicity, this example just returns a few users from the national leaderboard.
    // A true "rivals" query is more complex and would require fetching all users
    // and filtering them in the app, which can be inefficient.
    final allUsers = await getNationalLeaderboard('Canada'); // Assuming rivals are from the primary country
    return allUsers.where((user) => user.tier == userTier).take(5).toList();
  }

  /// Fetches users the current user is sharing their location with.
  Future<List<LeaderboardUser>> getLocationSharers() async {

    return [];
  }
}