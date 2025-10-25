import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/discovery/leaderboard_user.dart';

class LeaderboardData {
  final List<LeaderboardUser> users;
  LeaderboardData({required this.users});
}

class SettingsProvider with ChangeNotifier {
  String _selectedCountry = 'Canada';
  bool _isDiscoveryOn = true;

  String get selectedCountry => _selectedCountry;
  bool get isDiscoveryOn => _isDiscoveryOn;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  final Map<String, LeaderboardData> _leaderboardCache = {};

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedCountry = prefs.getString('selectedCountry') ?? 'Canada';
    _isDiscoveryOn = prefs.getBool('isDiscoveryOn') ?? true;
    notifyListeners();
  }

  Future<void> updateCountry(String newCountry) async {
    _selectedCountry = newCountry;
    notifyListeners(); // Immediately notify UI of the change
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedCountry', newCountry);
  }

  Future<void> updateDiscovery(bool isEnabled) async {
    _isDiscoveryOn = isEnabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDiscoveryOn', isEnabled);
  }

  void updateTheme(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  Future<LeaderboardData> getLeaderboard(String country) async {
    if (_leaderboardCache.containsKey(country)) {
      print("Returning leaderboard for $country from CACHE.");
      return _leaderboardCache[country]!;
    } else {
      print("Fetching leaderboard for $country from FIRESTORE.");
      final data = await _fetchFromFirestore(country);
      _leaderboardCache[country] = data;
      return data;
    }
  }

  // --- FIX: Added the missing Firestore fetch method ---
  Future<LeaderboardData> _fetchFromFirestore(String country) async {
    // This is a placeholder that mimics your actual fetching logic.
    // In a real app, this would be in your LeaderboardService.
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('leaderboards')
          .doc(country)
          .collection('users')
          .orderBy('percentage', descending: true)
          .limit(50)
          .get();

      final users = snapshot.docs.map((doc) => LeaderboardUser.fromFirestore(doc)).toList();
      return LeaderboardData(users: users);
    } catch (e) {
      print("Error fetching from Firestore: $e");
      return LeaderboardData(users: []); // Return empty list on error
    }
  }
}