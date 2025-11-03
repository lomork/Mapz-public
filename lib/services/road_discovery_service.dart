import 'dart:async';
import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:isar/isar.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/discovered_road.dart';
import '../api/google_maps_api_service.dart';
import 'notification_service.dart';

class RoadDiscoveryService {
  final Isar isar;
  final GoogleMapsApiService _apiService;

  final List<LatLng> _pathBuffer = [];
  final int _batchSize = 50;

  final Location _location = Location();
  final NotificationService _notificationService = NotificationService();
  StreamSubscription<LocationData>? _locationSubscription;

  bool _isHighAccuracy = false;

  Timer? _stopTimer;
  bool _isNotificationActive = false;
  static const double _speedThreshold = 1.0;

  RoadDiscoveryService(this.isar, this._apiService);

  Future<void> addDrivenPath(List<LatLng> path) async {

  }

  Future<void> addLocationPoint(LatLng point) async {
    _pathBuffer.add(point);
    if (_pathBuffer.length >= _batchSize) {
      // Copy the buffer and clear it, so we don't block new points coming in
      final List<LatLng> pathToProcess = List.from(_pathBuffer);
      _pathBuffer.clear();

      // Process the path in the background
      _snapAndStorePath(pathToProcess);
    }
  }

  void _handleLocationUpdate(LocationData locationData) {
    if (locationData.latitude == null || locationData.longitude == null) return;

    final newPoint = LatLng(locationData.latitude!, locationData.longitude!);


    final speed = locationData.speed ?? 0.0;

    if (speed > _speedThreshold) { // User is moving
      _stopTimer?.cancel();
      if (!_isHighAccuracy) {
        _location.changeSettings(
          accuracy: LocationAccuracy.high, // Switch to high accuracy
          interval: 1000, // 1 second
          distanceFilter: 2,  // 2 meters
        );
        _isHighAccuracy = true;
        print("MOVEMENT DETECTED: Switching to HIGH accuracy.");
        _location.changeNotificationOptions(
          channelName: 'Road Discovery',
          title: 'Road Discovery Activated', // MOVING state
          description: 'Tracking your journey to discover new roads.',
          iconName: '@drawable/ic_mapz_notification',
        );
      }
      if (!_isNotificationActive) {
        _notificationService.showDiscoveryActiveNotification();
        _isNotificationActive = true;
      }
      addLocationPoint(newPoint);
    } else { // User has stopped
      if (_isHighAccuracy) {
        if (_stopTimer == null || !_stopTimer!.isActive) {
          print("STOP DETECTED: Starting 1-minute timer to switch to LOW accuracy.");
          _stopTimer = Timer(const Duration(minutes: 1), () {
            _location.changeSettings(
              accuracy: LocationAccuracy.low, // Switch back to low accuracy
              interval: 30000, // 30 seconds
              distanceFilter: 50, // 50 meters
            );
            _isHighAccuracy = false;
            print("TIMER ELAPSED: Switched to LOW accuracy.");
            _location.changeNotificationOptions(
              channelName: 'Road Discovery',
              title: 'Road Discovery Idling', // IDLING state
              description: 'Waiting for movement to start discovery.',
              iconName: '@drawable/ic_mapz_notification',
            );
            if (_isNotificationActive) {
              _notificationService.cancelDiscoveryActiveNotification();
              _isNotificationActive = false;
            }
          });
        }
      }
    }
  }

  // --- NEW: Method to start the background location listener ---
  Future<void> startDiscovery() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    await _location.enableBackgroundMode(enable: true);

    await _location.changeNotificationOptions(
      channelName: 'Road Discovery',
      title: 'Road Discovery Idling', // Initial state
      description: 'Waiting for movement to start discovery.',
      iconName: '@drawable/ic_mapz_notification', // From your notification_service.dart
      // We use the icon from your service, but let the location package manage the notification.
    );

    _isHighAccuracy = false;
    await _location.changeSettings(
      accuracy: LocationAccuracy.low, // Use low accuracy to save power
      interval: 30000, // Check every 30 seconds
      distanceFilter: 50, // Only update if moved 50 meters
    );

    _locationSubscription?.cancel();
    _locationSubscription = _location.onLocationChanged.listen(_handleLocationUpdate);
  }

  // --- NEW: Method to stop the service ---
  void stopDiscovery() {
    _location.enableBackgroundMode(enable: false);
    _locationSubscription?.cancel();
    _notificationService.cancelDiscoveryActiveNotification();
    _isNotificationActive = false;
    _stopTimer?.cancel();
  }

  Future<void> _snapAndStorePath(List<LatLng> path) async {
    try {
      final result = await _apiService.snapToRoads(path);
      if (result.containsKey('snappedPoints')) {
        final List<DiscoveredRoad> newRoads = [];
        for (var point in result['snappedPoints']) {
          final String? placeId = point['placeId'];
          if (placeId != null) {
            newRoads.add(
              DiscoveredRoad()
                ..placeId = placeId
                ..latitude = point['location']['latitude']
                ..longitude = point['location']['longitude'],
            );
          }
        }

        if (newRoads.isNotEmpty) {
          // Write all new, unique road segments to the local database
          await isar.writeTxn(() async {
            await isar.discoveredRoads.putAll(newRoads);
          });
          print("Saved ${newRoads.length} new road segments to local DB.");
        }
      }
    } catch (e) {
      print("Error in _snapAndStorePath: $e");
    }
  }

  // Calculates the discovery percentage
  Future<double> calculateDiscoveryPercentage(String country) async {
    // --- FIX: Instead of an API call, we use a map of estimated values ---
    // These are example numbers. You can adjust them or add more countries.
    const Map<String, int> totalRoadsByCountry = {
      'Canada': 950000,
      'United States': 6500000,
      'United Kingdom': 400000,
      'Germany': 644000,
      'France': 1000000,
      'Australia': 873000,
    };

    // Look up the total for the selected country, with a fallback default.
    final totalRoadsInCountry = totalRoadsByCountry[country] ?? 1000000;

    // This part of your code is correct and reads from your local database.
    final discoveredRoadCount = await isar.discoveredRoads.count();

    if (totalRoadsInCountry == 0) return 0.0;

    // Calculate the percentage based on the estimated total.
    return (discoveredRoadCount / totalRoadsInCountry) * 100;
  }

  // Gets all discovered points for the "My Atlas" map
  Future<List<LatLng>> getAllDiscoveredPoints() async {
    final roads = await isar.discoveredRoads.where().findAll();
    return roads.map((road) => LatLng(road.latitude, road.longitude)).toList();
  }

  // Updates your cloud database (e.g., Firebase) with the new percentage
  Future<void> updateCloudPercentage(double percentage, String country) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // Not logged in, can't save.

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      // This command updates the user's document in Firestore.
      await userDocRef.set({
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'discovery': {
          country: percentage,
        }
      }, SetOptions(merge: true)); // merge:true is crucial to avoid erasing data for other countries.
      print("Successfully synced discovery percentage for $country to Firestore.");
    } catch (e) {
      print("Could not update percentage on cloud: $e");
    }
  }

  Future<void> forceProcessBuffer() async {
    if (_pathBuffer.isEmpty) {
      print("Buffer is empty, nothing to process.");
      return;
    }

    // Copy the buffer and clear it, just like the automatic batching
    final List<LatLng> pathToProcess = List.from(_pathBuffer);
    _pathBuffer.clear();

    print("Forcing processing of ${pathToProcess.length} buffered points.");
    // Process the path in the background
    await _snapAndStorePath(pathToProcess);
  }
}