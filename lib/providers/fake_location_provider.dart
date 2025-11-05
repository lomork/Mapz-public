import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:mapz/api/google_maps_api_service.dart';
import 'package:mapz/models/place.dart'; // Make sure you have this model
import 'package:uuid/uuid.dart';

class FakeLocationProvider with ChangeNotifier {
  final GoogleMapsApiService _apiService;
  FakeLocationProvider(this._apiService); // Now requires the API service

  // --- State for UI ---
  bool _isFaking = false;
  bool _isAdmin = false;
  String? _sessionToken;
  PlaceDetails? _fromPlace;
  PlaceDetails? _toPlace;
  List<PlaceSuggestion> _fromSuggestions = [];
  List<PlaceSuggestion> _toSuggestions = [];
  String? _routeEta;
  String? _routeDistance;
  Set<Polyline> _polylines = {};
  LatLngBounds? _routeBounds;

  // --- State for Simulation ---
  Timer? _simulationTimer;
  List<LatLng> _routePoints = [];
  double _totalRouteDistance = 0.0;
  DateTime? _simulationStartTime;
  double _simulationSpeedMps = 13.89; // Default 50 km/h in m/s

  // --- Stream for Location ---
  final StreamController<LocationData> _fakeLocationController =
  StreamController<LocationData>.broadcast();
  Stream<LocationData> get fakeLocationStream => _fakeLocationController.stream;

  // --- Getters ---
  bool get isFaking => _isFaking;
  bool get isAdmin => _isAdmin;
  PlaceDetails? get fromPlace => _fromPlace;
  PlaceDetails? get toPlace => _toPlace;
  List<PlaceSuggestion> get fromSuggestions => _fromSuggestions;
  List<PlaceSuggestion> get toSuggestions => _toSuggestions;
  String? get routeEta => _routeEta;
  String? get routeDistance => _routeDistance;
  Set<Polyline> get polylines => _polylines;
  LatLngBounds? get routeBounds => _routeBounds;

  // --- 1. SESSION TOKEN MANAGEMENT ---
  void generateSessionToken() {
    // Only generate if one doesn't exist
    if (_sessionToken == null) {
      _sessionToken = const Uuid().v4();
      notifyListeners();
    }
  }

  void clearSessionToken() {
    _sessionToken = null;
    _fromSuggestions = [];
    _toSuggestions = [];
    // Don't clear from/to place if faking
    if (!_isFaking) {
      _fromPlace = null;
      _toPlace = null;
      _clearRoute();
    }
    notifyListeners();
  }

  // --- 2. ADMIN STATUS ---
  Future<void> updateAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _isAdmin = false;
      notifyListeners();
      return;
    }
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;
        _isAdmin = data.containsKey('the_admin') && data['the_admin'] == true;
      } else {
        _isAdmin = false;
      }
    } catch (e) {
      _isAdmin = false;
    }
    notifyListeners();
  }

  // --- 3. UI & ROUTE LOGIC ---

  void swapFromAndTo() {
    final temp = _fromPlace;
    _fromPlace = _toPlace;
    _toPlace = temp;
    _getFakeRoute(); // Recalculate route
    notifyListeners();
  }

  void clearSuggestions(bool isFrom) {
    if (isFrom) {
      _fromSuggestions = [];
    } else {
      _toSuggestions = [];
    }
    notifyListeners();
  }

  Future<void> fetchSuggestions(String input, {required bool isFromField}) async {
    if (_sessionToken == null || input.isEmpty) {
      isFromField ? _fromSuggestions = [] : _toSuggestions = [];
      notifyListeners();
      return;
    }
    try {
      final result =
      await _apiService.getPlaceSuggestions(input, _sessionToken!);
      if (result['status'] == 'OK') {
        final suggestions = (result['predictions'] as List)
            .map((p) => PlaceSuggestion(p['place_id'], p['description']))
            .toList();
        if (isFromField) {
          _fromSuggestions = suggestions;
        } else {
          _toSuggestions = suggestions;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching suggestions: $e");
    }
  }

  Future<void> setPlace({
    required PlaceSuggestion suggestion,
    required bool isFromField,
  }) async {
    if (_sessionToken == null) return;
    try {
      final result =
      await _apiService.getPlaceDetails(suggestion.placeId, _sessionToken!);
      if (result['status'] == 'OK') {
        final placeJson = result['result'];
        final location = placeJson['geometry']['location'];
        final latLng = LatLng(location['lat'], location['lng']);
        final place = PlaceDetails(
          placeId: placeJson['place_id'],
          name: placeJson['name'],
          address: placeJson['formatted_address'],
          coordinates: latLng,
        );

        if (isFromField) {
          _fromPlace = place;
          _fromSuggestions = [];
        } else {
          _toPlace = place;
          _toSuggestions = [];
        }

        // If both are set, get the route
        if (_fromPlace != null && _toPlace != null) {
          await _getFakeRoute();
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error setting place: $e");
    }
  }

  Future<void> _getFakeRoute() async {
    if (_fromPlace == null || _toPlace == null) return;

    try {
      final result = await _apiService.getDirections(
        origin: _fromPlace!.coordinates,
        destination: _toPlace!.coordinates,
        travelMode: 'driving',
      );

      if (result['status'] == 'OK' && (result['routes'] as List).isNotEmpty) {
        final route = result['routes'][0];

        // 3. Get ETA and Distance
        final leg = route['legs'][0];
        _routeEta = leg['duration']['text'];
        _routeDistance = leg['distance']['text'];

        // 4. Get Polyline
        final overviewPolyline = route['overview_polyline']['points'];
        _routePoints = PolylinePoints()
            .decodePolyline(overviewPolyline)
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        _polylines = {
          Polyline(
            polylineId: const PolylineId('fake_route'),
            color: Colors.blue,
            width: 5,
            points: _routePoints,
          )
        };

        // 5. Get Map Bounds
        final bounds = route['bounds'];
        _routeBounds = LatLngBounds(
          southwest: LatLng(bounds['southwest']['lat'], bounds['southwest']['lng']),
          northeast: LatLng(bounds['northeast']['lat'], bounds['northeast']['lng']),
        );

        // 6. Calculate total route distance for interpolation
        _totalRouteDistance = 0.0;
        for (int i = 0; i < _routePoints.length - 1; i++) {
          _totalRouteDistance += _calculateDistance(
            _routePoints[i].latitude,
            _routePoints[i].longitude,
            _routePoints[i + 1].latitude,
            _routePoints[i + 1].longitude,
          );
        }
      }
    } catch (e) {
      debugPrint("Error getting fake route: $e");
      _clearRoute();
    }
    notifyListeners();
  }

  void _clearRoute() {
    _polylines = {};
    _routePoints = [];
    _routeEta = null;
    _routeDistance = null;
    _routeBounds = null;
    _totalRouteDistance = 0;
    notifyListeners();
  }

  // --- 4. SIMULATION LOGIC (THE FIX) ---

  void startRouteSimulation(double speedKmph) async {
    if (_routePoints.isEmpty) return;

    await updateAdminStatus(); // Ensure admin status is fresh
    _isFaking = true;
    _simulationSpeedMps = speedKmph * 1000 / 3600; // km/h to m/s
    _simulationStartTime = DateTime.now();
    _simulationTimer?.cancel();

    // Broadcast the very first point immediately
    _broadcastLocationForTime(Duration.zero);

    _simulationTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
          final elapsed = DateTime.now().difference(_simulationStartTime!);
          _broadcastLocationForTime(elapsed);
        });

    notifyListeners();
  }

  void _broadcastLocationForTime(Duration elapsed) {
    double distanceTravelled = elapsed.inMilliseconds * _simulationSpeedMps / 1000.0;

    if (distanceTravelled >= _totalRouteDistance) {
      // Reached destination
      final endPoint = _routePoints.last;
      _broadcastFakeData(endPoint, 0, 0); // 0 speed, 0 bearing
      stopSimulation();
      return;
    }

    // Find current position on the polyline
    double distanceSoFar = 0.0;
    for (int i = 0; i < _routePoints.length - 1; i++) {
      final p1 = _routePoints[i];
      final p2 = _routePoints[i + 1];
      double segmentDistance =
      _calculateDistance(p1.latitude, p1.longitude, p2.latitude, p2.longitude);

      if (distanceSoFar + segmentDistance >= distanceTravelled) {
        // This is the correct segment
        double distanceIntoSegment = distanceTravelled - distanceSoFar;
        double t = distanceIntoSegment / segmentDistance; // Interpolation factor (0.0 to 1.0)

        // Linear interpolation
        final lat = p1.latitude + (p2.latitude - p1.latitude) * t;
        final lng = p1.longitude + (p2.longitude - p1.longitude) * t;
        final bearing =
        _calculateBearing(p1.latitude, p1.longitude, p2.latitude, p2.longitude);

        _broadcastFakeData(LatLng(lat, lng), _simulationSpeedMps, bearing);
        return;
      }
      distanceSoFar += segmentDistance;
    }
  }

  void stopSimulation() {
    _simulationTimer?.cancel();
    _isFaking = false;
    // Don't clear the route info, as requested
    notifyListeners();
  }

  void _broadcastFakeData(LatLng point, double speed, double bearing) {
    final fakeData = LocationData.fromMap({
      'latitude': point.latitude,
      'longitude': point.longitude,
      'accuracy': 5.0,
      'altitude': 0.0,
      'speed': speed,
      'speed_accuracy': 1.0,
      'heading': bearing,
      'time': DateTime.now().millisecondsSinceEpoch.toDouble(),
      'is_mock': 1,
    });
    _fakeLocationController.add(fakeData);
  }

  // --- 5. MATH HELPERS ---

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295; // Math.PI / 180
    var a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a)) * 1000; // 2 * R * 1000 (for meters)
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    final dLon = (lon2 - lon1) * p;
    lat1 = lat1 * p;
    lat2 = lat2 * p;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    double brng = math.atan2(y, x) * (180 / math.pi);
    return (brng + 360) % 360; // Normalize to 0-360
  }

  @override
  void dispose() {
    _fakeLocationController.close();
    _simulationTimer?.cancel();
    super.dispose();
  }
}