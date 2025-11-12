import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mapz/services/leaderboard_service.dart';
import 'package:provider/provider.dart';

import '../../../models/discovery/leaderboard_user.dart';
import '../../../models/discovery/tier.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _searchController = TextEditingController();
  List<LeaderboardUser> _searchResults = [];
  bool _isLoadingSearch = false;
  String _searchError = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers() async {
    final username = _searchController.text.trim();
    if (username.length < 3) {
      setState(() {
        _searchError = 'Username must be at least 3 characters';
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isLoadingSearch = true;
      _searchError = '';
      _searchResults = [];
    });

    try {
      final service = context.read<LeaderboardService>();
      final results = await service.searchUserByUsername(username);

      // Get current user's friends and requests to filter search
      final friends = await service.getFriendsList();
      final pending = await service.getPendingRequests();

      final friendIds = friends.map((f) => f.uid).toSet();
      final pendingIds = pending.map((p) => p.uid).toSet();

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      // Filter out self, current friends, and pending requests
      final filteredResults = results.where((user) {
        return user.uid != currentUserId &&
            !friendIds.contains(user.uid) &&
            !pendingIds.contains(user.uid);
      }).toList();

      setState; {
        _searchResults = filteredResults;
        if (filteredResults.isEmpty) {
          _searchError = 'No users found.';
        }
      }
    } catch (e) {
      setState(() {
        _searchError = 'Error searching: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoadingSearch = false;
      });
    }
  }

  Future<void> _sendFriendRequest(String targetUserId, String targetUsername) async {
    final service = context.read<LeaderboardService>();
    try {
      await service.sendFriendRequest(targetUserId, targetUsername);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend request sent to $targetUsername')),
      );
      // Re-run search to remove them from the list
      _searchUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  Future<void> _acceptFriendRequest(String requesterId, String requesterUsername) async {
    final service = context.read<LeaderboardService>();
    try {
      await service.acceptFriendRequest(requesterId, requesterUsername);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You are now friends with $requesterUsername')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  Future<void> _removeFriend(String friendId, String friendName) async {
    final service = context.read<LeaderboardService>();
    try {
      await service.removeFriend(friendId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $friendName from friends')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.read<LeaderboardService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Friends'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- Search Bar ---
          _buildSectionTitle('Find Friends'),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search by username',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _searchUsers,
              ),
              errorText: _searchError.isNotEmpty ? _searchError : null,
            ),
            onSubmitted: (_) => _searchUsers(),
          ),
          if (_isLoadingSearch)
            const Center(child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            )),

          // --- Search Results ---
          ..._searchResults.map((user) {
            return ListTile(
              title: Text(user.name),
              trailing: IconButton(
                icon: const Icon(Icons.person_add),
                onPressed: () => _sendFriendRequest(user.uid, user.name),
              ),
            );
          }),

          const SizedBox(height: 24),

          // --- Pending Requests ---
          _buildSectionTitle('Pending Requests'),
          StreamBuilder<List<LeaderboardUser>>(
            stream: service.getPendingRequestsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Text('No pending requests.');
              }
              final requests = snapshot.data!;
              return Column(
                children: requests.map((user) {
                  return ListTile(
                    title: Text(user.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () => _acceptFriendRequest(user.uid, user.name),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () => _removeFriend(user.uid, user.name), // Re-using remove logic
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 24),

          // --- Current Friends ---
          _buildSectionTitle('Current Friends'),
          StreamBuilder<List<LeaderboardUser>>(
            stream: service.getFriendsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Text('You haven\'t added any friends yet.');
              }
              final friends = snapshot.data!;
              return Column(
                children: friends.map((user) {
                  return ListTile(
                    title: Text(user.name),
                    trailing: IconButton(
                      icon: const Icon(Icons.person_remove, color: Colors.grey),
                      onPressed: () => _removeFriend(user.uid, user.name),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}