import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/discovered_road.dart';
import '../api/google_maps_api_service.dart';
import '../providers/fake_location_provider.dart';
import 'notification_service.dart';
import '../providers/fake_location_provider.dart';
import '../services/database_service.dart';
import '../models/discovery/tier.dart';

class RoadDiscoveryService {
  final GoogleMapsApiService _apiService;
  final FakeLocationProvider _fakeLocationProvider;

  final List<LatLng> _pathBuffer = [];
  final int _batchSize = 50;

  final Location _location = Location();
  final NotificationService _notificationService = NotificationService();
  StreamSubscription<LocationData>? _locationSubscription;
  StreamSubscription<LocationData>? _fakeLocationSubscription;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot>? _userSettingsStream;
  bool _isSharingEnabled = false;

  bool _isHighAccuracy = false;
  Timer? _stopTimer;
  bool _isNotificationActive = false;
  static const double _speedThreshold = 1.0;
  final DatabaseService _dbService = DatabaseService();

  LocationData? _lastLocationData;

  RoadDiscoveryService(this._apiService, this._fakeLocationProvider);

  Map<String, int> get _totalRoadsData => {
    'Canada': 950000,
    'United States': 6500000,
    'United Kingdom': 400000,
    'Germany': 644000,
    'France': 1000000,
    'Australia': 873000,
    // Added a few more for robustness
    'Italy': 487700,
    'Spain': 666000,
    'Japan': 1200000,
    'India': 6000000,
  };

  Future<void> addDrivenPath(List<LatLng> path) async {}

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

  void _handleLocationUpdate(LocationData locationData, {bool isFaking = false}) {
    if (locationData.latitude == null || locationData.longitude == null) return;

    final newPoint = LatLng(locationData.latitude!, locationData.longitude!);
    double speed = locationData.speed ?? 0.0;

    if (speed == 0.0 && _lastLocationData != null && _lastLocationData!.latitude != null) {

      const double earthRadius = 6371000; // meters
      final dLat = (locationData.latitude! - _lastLocationData!.latitude!) * (pi / 180);
      final dLon = (locationData.longitude! - _lastLocationData!.longitude!) * (pi / 180);
      final a = sin(dLat / 2) * sin(dLat / 2) +
          cos(_lastLocationData!.latitude! * (pi / 180)) *
              cos(locationData.latitude! * (pi / 180)) *
              sin(dLon / 2) * sin(dLon / 2);
      final c = 2 * atan2(sqrt(a), sqrt(1 - a));
      final distance = earthRadius * c;

      final timeDiff = (locationData.time ?? 0) - (_lastLocationData!.time ?? 0);
      if (timeDiff > 0) {
        // timeDiff is usually in ms
        speed = distance / (timeDiff / 1000);
      }
    }
    _lastLocationData = locationData;

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
      _updateLiveLocationIfSharing(newPoint);
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

  Future<void> _updateLiveLocationIfSharing(LatLng point) async {
    // If setting is off, do nothing.
    if (!_isSharingEnabled) return;

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      // Write the GeoPoint and a timestamp
      await _db.collection('users').doc(userId).set({
        'live_location': GeoPoint(point.latitude, point.longitude),
        'location_last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print("Live location updated.");
    } catch (e) {
      print("Failed to update live location: $e");
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

    _locationSubscription?.cancel();
    _fakeLocationSubscription?.cancel();
    _userSettingsStream?.cancel();

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      _userSettingsStream = _db
          .collection('users')
          .doc(userId)
          .snapshots()
          .listen((doc) {
        _isSharingEnabled = doc.data()?['isSharingLocation'] ?? false;
        print("Location sharing setting changed: $_isSharingEnabled");
      }, onError: (e) {
        print("Error listening to user settings: $e");
        _isSharingEnabled = false;
      });
    }

    _locationSubscription = _location.onLocationChanged.listen((locationData) {
      if (!_fakeLocationProvider.isFaking) {
        _handleLocationUpdate(locationData);
      }
    });

    _fakeLocationSubscription =
        _fakeLocationProvider.fakeLocationStream.listen((locationData) {
          // --- THIS IS YOUR NEW ADMIN LOGIC ---
          if (_fakeLocationProvider.isFaking) {
            // Only process the point if the user is an admin
            if (_fakeLocationProvider.isAdmin) {
              _handleLocationUpdate(locationData, isFaking: true);
            } else {
              // If not an admin, we still update the notification
              // but do NOT call _handleLocationUpdate (which saves points).
              _location.changeNotificationOptions(
                title: 'FAKE GPS ACTIVE',
                description: 'Discovery paused. Admin mode is off.',
              );
            }
          }
        });
  }

  void stopDiscovery() {
    _location.enableBackgroundMode(enable: false);
    _locationSubscription?.cancel();
    _notificationService.cancelDiscoveryActiveNotification();
    _fakeLocationSubscription?.cancel();
    _userSettingsStream?.cancel();
    _isNotificationActive = false;
    _stopTimer?.cancel();
  }

  Future<void> _snapAndStorePath(List<LatLng> path) async {
    try {
      final result = await _apiService.snapToRoads(path);

      if (result.containsKey('snappedPoints')) {
        String batchCountry = 'Unknown';
        String batchCity = 'Unknown';
        String batchState = 'Unknown';

        if (path.isNotEmpty) {
          try {
            final geocodeResult = await _apiService.reverseGeocode(path.first);
            if (geocodeResult['status'] == 'OK' && geocodeResult['results'].isNotEmpty) {
              final List components = geocodeResult['results'][0]['address_components'];

              // Extract Country
              final countryComp = components.firstWhere((c) => (c['types'] as List).contains('country'), orElse: () => null);
              if (countryComp != null) batchCountry = countryComp['long_name'];

              // Extract City (Locality)
              final cityComp = components.firstWhere((c) => (c['types'] as List).contains('locality'), orElse: () => null);
              if (cityComp != null) batchCity = cityComp['long_name'];

              // Extract State (Admin Area 1)
              final stateComp = components.firstWhere((c) => (c['types'] as List).contains('administrative_area_level_1'), orElse: () => null);
              if (stateComp != null) batchState = stateComp['long_name'];
            }
          } catch (geoError) {
            print("Error determining location details: $geoError");
          }
        }

        final List<DiscoveredRoad> newRoads = [];
        for (var point in result['snappedPoints']) {
          final String? placeId = point['placeId'];
          if (placeId != null) {
            newRoads.add(
              DiscoveredRoad(
                placeId: placeId,
                latitude: point['location']['latitude'],
                longitude: point['location']['longitude'],
                country: batchCountry,
                city: batchCity,
                state: batchState,
              ),
            );
          }
        }

        if (newRoads.isNotEmpty) {
          await _dbService.insertRoads(newRoads);
          print("Saved ${newRoads.length} segments for $batchCity, $batchCountry.");
        }
      }
    } catch (e) {
      print("Error in _snapAndStorePath: $e");
    }
  }

  Future<List<Map<String, dynamic>>> getVisitedCountries() async {
    final rawStats = await _dbService.getCountryStats();
    return rawStats.map((stat) {
      final String country = stat['country'];
      final int count = stat['count'];
      final int total = _totalRoadsData[country] ?? 1000000;
      final double percentage = (count / total).clamp(0.0, 1.0);
      return {
        'name': country,
        'count': count,
        'percentage': percentage,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getVisitedStates(String country) async {
    final rawStats = await _dbService.getStateStats(country);
    return rawStats.map((stat) {
      final String state = stat['state'];
      final int count = stat['count'];
      // Heuristic: Average state has ~100k segments?
      // You can refine this map later.
      final int estimatedTotal = 100000;
      final double percentage = (count / estimatedTotal).clamp(0.0, 1.0);
      return {
        'name': state,
        'count': count,
        'percentage': percentage,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getVisitedCities(String country, String state) async {
    final rawStats = await _dbService.getCityStats(country, state);
    return rawStats.map((stat) {
      final String city = stat['city'];
      final int count = stat['count'];
      final int estimatedTotal = _estimateTotalRoadsForCity(city);
      final double percentage = (count / estimatedTotal).clamp(0.0, 1.0);
      return {
        'name': city,
        'count': count,
        'percentage': percentage,
      };
    }).toList();
  }

  int _estimateTotalRoadsForCity(String city) {
    // You can add specific overrides here if you want
    switch (city.toLowerCase()) {
      case 'toronto': return 25000;
      case 'new york': return 30000;
      case 'halifax': return 6000;
      case 'north york': return 8000;
      default: return 5000; // Default generic city size (segments)
    }
  }

  Future<double> calculateDiscoveryPercentage(String country) async {

    final totalRoadsInCountry = _totalRoadsData[country] ?? 1000000;

    final discoveredRoadCount = await _dbService.getRoadsCount(country: country);

    if (totalRoadsInCountry == 0) return 0.0;

    return (discoveredRoadCount / totalRoadsInCountry) * 100;
  }

  // Gets all discovered points for the "My Atlas" map
  Future<List<LatLng>> getAllDiscoveredPoints() async {
    final roads = await _dbService.getAllDiscoveredRoads();
    return roads.map((road) => LatLng(road.latitude, road.longitude)).toList();
  }

  Future<double> getCloudDiscoveryPercentage(String country) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0.0; // Not logged in

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      final doc = await userDocRef.get();

      if (doc.exists && doc.data()!.containsKey('discovery')) {
        final discoveryData = doc.data()!['discovery'] as Map<String, dynamic>;
        if (discoveryData.containsKey(country)) {
          // Ensure it's a double, as Firestore can store numbers as int or double
          return (discoveryData[country] as num).toDouble();
        }
      }
    } catch (e) {
      print("Could not fetch cloud percentage: $e");
    }
    return 0.0; // Default to 0 if not found or on error
  }

  // Updates your cloud database (e.g., Firebase) with the new percentage
// lib/services/road_discovery_service.dart

  // Updates your cloud database (e.g., Firebase) with the new percentage
  Future<void> updateCloudPercentage(double localPercentage, String country) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // Not logged in, can't save.

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      // --- READ FROM FIREBASE FIRST ---
      final doc = await userDocRef.get();
      double cloudPercentage = 0.0;
      bool shouldUpdate = false;

      // Base data to set/merge
      // This ensures displayName and photoURL are always present
      final Map<String, dynamic> baseUserData = {
        'displayName': user.displayName,
        'photoURL': user.photoURL,
      };

      if (doc.exists && doc.data()!.containsKey('discovery')) {
        final discoveryData = doc.data()!['discovery'] as Map<String, dynamic>;
        if (discoveryData.containsKey(country)) {
          cloudPercentage = (discoveryData[country] as num).toDouble();
        } else {
          // Cloud doc exists, but not for this country. We should update.
          shouldUpdate = true;
        }
      } else {
        // The user document or 'discovery' map doesn't exist. We must update.
        shouldUpdate = true;
      }

      // --- COMPARE AND ONLY WRITE IF HIGHER OR IF IT'S A NEW ENTRY ---
      if (localPercentage > cloudPercentage || shouldUpdate) {
        // The local value is newer/higher OR this is the user's first sync
        // for this country.
        final newTier = TierManager.getTier(localPercentage);
        final tierString = newTier.name;

        // We merge the base user data with the new discovery data
        await userDocRef.set({
          ...baseUserData,
          'discovery': {
            country: localPercentage, // Save the bigger number or new number
          },
          'tier': tierString,
        }, SetOptions(merge: true)); // SetOptions(merge: true) is crucial

        print("Successfully synced discovery percentage for $country to Firestore.");
      } else {
        // The cloud value is higher. Do nothing.
        print("Cloud percentage is already higher ($cloudPercentage) than local ($localPercentage). No update needed.");

        // Still, let's make sure their profile info is up-to-date
        // This is a "merge" so it won't overwrite the discovery map
        await userDocRef.set(baseUserData, SetOptions(merge: true));
      }
    } catch (e) {
      print("Could not update percentage on cloud: $e");
    }
  }

  Future<void> forceProcessBuffer() async {
    if (_pathBuffer.isEmpty) {
      print("Buffer is empty, nothing to process.");
      return;
    }
    final List<LatLng> pathToProcess = List.from(_pathBuffer);
    _pathBuffer.clear();

    print("Forcing processing of ${pathToProcess.length} buffered points.");
    await _snapAndStorePath(pathToProcess);
  }
}