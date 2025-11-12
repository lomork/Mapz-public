import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/discovery/leaderboard_user.dart';
import '../models/discovery/tier.dart';

class LeaderboardService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _currentUserId {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }
    return user.uid;
  }

  String get _currentUsername {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }
    return user.displayName ?? 'Anonymous';
  }

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
        final data = doc.data() as Map<String, dynamic>?;
        final percentage =
        (data?['discovery']?[country] as num? ?? 0).toDouble();

        return LeaderboardUser(
          uid: doc.id, // <-- PASS THE USER'S ID
          name: data?['displayName'] ?? 'Anonymous',
          photoURL: data?['photoURL'] ?? '', // <-- PASS THE PHOTO URL
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
    try {
      // Convert your Enum to a String, or however you store it
      final tierString = userTier.name;

      final querySnapshot = await _db
          .collection('users')
          .where('tier', isEqualTo: tierString)
          .limit(5)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return [];
      }

      // This now only maps 5 documents, not 100
      return querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        final percentage =
        (data?['discovery']?['Canada'] as num? ?? 0).toDouble(); // Assuming 'Canada' for this example

        return LeaderboardUser(
          uid: doc.id,
          name: data?['displayName'] ?? 'Anonymous',
          photoURL: data?['photoURL'] ?? '',
          percentage: percentage,
          tier: userTier, // We already know the tier
        );
      }).toList();
    } catch (e) {
      print("Error fetching rivals from Firestore: $e");
      return [];
    }
  }

  /// Fetches users the current user is sharing their location with.
  Future<List<LeaderboardUser>> getLocationSharers() async {
    // This now just returns the list of friends.
    // The "live location" part is a much bigger feature.
    return getFriendsList();
  }

  Future<void> updateSharingPreference(bool isSharing) async {
    await _db.collection('users').doc(_currentUserId).set({
      'isSharingLocation': isSharing,
    }, SetOptions(merge: true));
  }

  /// Searches for users by their username (must be 3+ chars)
  Future<List<LeaderboardUser>> searchUserByUsername(String username) async {
    if (username.length < 3) return [];

    final usernameLower = username.toLowerCase();

    final querySnapshot = await _db
        .collection('users')
        .where('username_lowercase', isGreaterThanOrEqualTo: usernameLower)
        .where('username_lowercase', isLessThanOrEqualTo: '$usernameLower\uf8ff')
        .limit(10)
        .get();

    return querySnapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      // We don't know their percentage, so default to 0
      const percentage = 0.0;
      return LeaderboardUser(
        uid: doc.id,
        name: data?['displayName'] ?? 'Anonymous',
        photoURL: data?['photoURL'] ?? '',
        percentage: percentage,
        tier: TierManager.getTier(percentage),
      );
    }).toList();
  }

  /// Sends a friend request to a target user
  Future<void> sendFriendRequest(String targetUserId, String targetUsername) async {
    final myId = _currentUserId;
    final myUsername = _currentUsername;

    // Use batch write to update both documents
    final batch = _db.batch();

    // Add to my 'sent_requests'
    final myRef = _db.collection('users').doc(myId);
    batch.set(myRef, {
      'sent_requests': {targetUserId: targetUsername}
    }, SetOptions(merge: true));

    // Add to their 'pending_requests'
    final targetRef = _db.collection('users').doc(targetUserId);
    batch.set(targetRef, {
      'pending_requests': {myId: myUsername}
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Accepts a friend request from a requester
  Future<void> acceptFriendRequest(String requesterId, String requesterUsername) async {
    final myId = _currentUserId;
    final myUsername = _currentUsername;

    final batch = _db.batch();

    // 1. Add to my 'friends' list
    final myRef = _db.collection('users').doc(myId);
    batch.set(myRef, {
      'friends': {requesterId: requesterUsername}
    }, SetOptions(merge: true));
    // 2. Remove from my 'pending_requests'
    batch.update(myRef, {
      'pending_requests.$requesterId': FieldValue.delete(),
    });

    // 3. Add to their 'friends' list
    final requesterRef = _db.collection('users').doc(requesterId);
    batch.set(requesterRef, {
      'friends': {myId: myUsername}
    }, SetOptions(merge: true));
    // 4. Remove from their 'sent_requests'
    batch.update(requesterRef, {
      'sent_requests.$myId': FieldValue.delete(),
    });

    await batch.commit();
  }

  /// Removes a friend or declines a request
  Future<void> removeFriend(String friendId) async {
    final myId = _currentUserId;

    final batch = _db.batch();

    // 1. Remove from my friends, pending, and sent
    final myRef = _db.collection('users').doc(myId);
    batch.update(myRef, {
      'friends.$friendId': FieldValue.delete(),
      'pending_requests.$friendId': FieldValue.delete(),
      'sent_requests.$friendId': FieldValue.delete(),
    });

    // 2. Remove me from their friends, pending, and sent
    final friendRef = _db.collection('users').doc(friendId);
    batch.update(friendRef, {
      'friends.$myId': FieldValue.delete(),
      'pending_requests.$myId': FieldValue.delete(),
      'sent_requests.$myId': FieldValue.delete(),
    });

    await batch.commit();
  }

  /// Helper to convert a user document map into a list of LeaderboardUsers
  List<LeaderboardUser> _mapToUserList(Map<String, dynamic>? dataMap) {
    if (dataMap == null) return [];
    return dataMap.entries.map((entry) {
      return LeaderboardUser(
        uid: entry.key,
        name: entry.value.toString(),
        photoURL: '', // We don't store this in the map, default it
        percentage: 0,
        tier: Tier.iron,
      );
    }).toList();
  }

  /// Gets a stream of the user's pending requests
  Stream<List<LeaderboardUser>> getPendingRequestsStream() {
    return _db.collection('users').doc(_currentUserId).snapshots().map((doc) {
      final data = doc.data();
      return _mapToUserList(data?['pending_requests']);
    });
  }

  /// Gets a stream of the user's friends
  Stream<List<LeaderboardUser>> getFriendsStream() {
    return _db.collection('users').doc(_currentUserId).snapshots().map((doc) {
      final data = doc.data();
      return _mapToUserList(data?['friends']);
    });
  }

  /// Gets a one-time list of the user's friends
  Future<List<LeaderboardUser>> getFriendsList() async {
    final doc = await _db.collection('users').doc(_currentUserId).get();
    final data = doc.data();
    return _mapToUserList(data?['friends']);
  }

  /// Gets a one-time list of the user's pending requests
  Future<List<LeaderboardUser>> getPendingRequests() async {
    final doc = await _db.collection('users').doc(_currentUserId).get();
    final data = doc.data();
    return _mapToUserList(data?['pending_requests']);
  }
}