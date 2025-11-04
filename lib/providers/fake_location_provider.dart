import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FakeLocationProvider with ChangeNotifier {
  bool _isFaking = false;
  bool _isAdmin = false;
  Timer? _simulationTimer;

  // This is the stream other parts of your app will listen to.
  final StreamController<LocationData> _fakeLocationController =
  StreamController<LocationData>.broadcast();
  Stream<LocationData> get fakeLocationStream => _fakeLocationController.stream;

  bool get isFaking => _isFaking;
  bool get isAdmin => _isAdmin;

  Future<void> updateAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _isAdmin = false;
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;
        _isAdmin = data.containsKey('is_admin') && data['is_admin'] == true;
      } else {
        _isAdmin = false;
      }
    } catch (e) {
      _isAdmin = false;
    }
    // We don't notify listeners here, as it's only used by the service.
  }

  /// Sets a single, static fake location.
  void setManualFakeLocation(LatLng point) async {
    await updateAdminStatus();
    _isFaking = true;
    _simulationTimer?.cancel();
    _broadcastFakeData(point, 0); // 0 speed since it's static
    notifyListeners();
  }

  /// Starts a simulated route between a list of points.
  void startRouteSimulation(List<LatLng> points, double speedKmph) async {
    if (points.isEmpty) return;

    await updateAdminStatus();
    _isFaking = true;
    _simulationTimer?.cancel();
    notifyListeners();

    int currentIndex = 0;
    double speedMps = speedKmph * 1000 / 3600; // Convert km/h to m/s
    const int tickDuration = 1; // 1 second update interval

    _simulationTimer = Timer.periodic(const Duration(seconds: tickDuration), (timer) {
      if (currentIndex >= points.length) {
        stopSimulation();
        return;
      }

      final point = points[currentIndex];
      _broadcastFakeData(point, speedMps);

      // This is a simple simulation: 1 point per second.
      // A more advanced version would calculate distance and time.
      currentIndex++;
    });
  }

  /// Stops the simulation and broadcast.
  void stopSimulation() {
    _isFaking = false;
    _simulationTimer?.cancel();
    notifyListeners();
  }

  /// Helper to create and broadcast a fake LocationData object.
  void _broadcastFakeData(LatLng point, double speed) {
    final fakeData = LocationData.fromMap({
      'latitude': point.latitude,
      'longitude': point.longitude,
      'accuracy': 5.0,
      'altitude': 0.0,
      'speed': speed,
      'speed_accuracy': 1.0,
      'heading': 0.0,
      'time': DateTime.now().millisecondsSinceEpoch.toDouble(),
      'is_mock': 1, // Flag it as a mock location
    });
    _fakeLocationController.add(fakeData);
  }

  @override
  void dispose() {
    _fakeLocationController.close();
    _simulationTimer?.cancel();
    super.dispose();
  }
}