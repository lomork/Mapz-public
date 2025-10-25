import 'dart:async';
import 'dart:convert';
import 'dart:math' show cos, sqrt, asin, atan2, sin, pi, min, max;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart';
import '../../api/google_maps_api_service.dart';
import '../../models/place.dart';
import '../../models/route.dart';
import '../../services/notification_service.dart';
import '../../widgets/animated_route_line.dart';
import '../../widgets/pulsing_start_button.dart';
import '../../utils/loading_overlay.dart';
import '../../providers/settings_provider.dart';

class FullTransitRoute {
  final String duration;
  final String distance;
  final List<RouteStep> steps;
  FullTransitRoute({required this.duration, required this.distance, required this.steps});
}

class RouteStep {
  final String instruction;
  final String distance;
  final String duration;
  final StepTravelMode travelMode;
  final String? lineName;
  final String? vehicleType; // e.g., 'BUS', 'SUBWAY'
  final List<LatLng> polylinePoints;

  RouteStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.travelMode,
    this.lineName,
    this.vehicleType,
    required this.polylinePoints,
  });
}

class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  const GlassmorphicContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24.0),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.25),
            borderRadius: BorderRadius.circular(24.0),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: child,
        ),
      ),
    );
  }
}

IconData getTransitIcon(String? vehicleType) {
  switch (vehicleType) {
    case 'BUS': return Icons.directions_bus;
    case 'SUBWAY': return Icons.subway;
    case 'TRAIN': return Icons.train;
    case 'TRAM': return Icons.tram;
    default: return Icons.transit_enterexit;
  }
}

class DirectionsScreen extends StatefulWidget {
  final PlaceDetails destination;
  final LatLng originCoordinates;

  const DirectionsScreen({super.key, required this.destination, required this.originCoordinates,});
  @override
  State<DirectionsScreen> createState() => _DirectionsScreenState();
}

class _DirectionsScreenState extends State<DirectionsScreen> with TickerProviderStateMixin {
  late GoogleMapController mapController;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  final Set<Marker> _routeDifferenceMarkers = {};

  List<FullTransitRoute> _transitRoutes = [];
  int _selectedRouteIndex = 0;
  TravelMode _travelMode = TravelMode.driving;
  PlaceDetails? _origin;
  PlaceDetails? _destination;
  FullTransitRoute? _detailedRoute;
  BitmapDescriptor? _circleStopIcon;
  final Map<String, BitmapDescriptor> _busNumberIcons = {};
  bool _avoidTolls = false;
  bool _avoidHighways = false;
  bool _avoidFerries = false;
  List<RouteInfo> _routes = [];
  RouteType _routeType = RouteType.fastest;

  late bool _isMapControllerInitialized = false;

  bool _isNavigating = false;
  StreamSubscription<LocationData>? _navigationLocationSubscription;
  List<dynamic> _navSteps = [];
  int _currentStepIndex = 0;
  String _distanceToNextManeuver = '';
  String _navEta = '';
  String _navDistance = '';
  String _navInstruction = '';
  IconData _navManeuverIcon = Icons.straight;
  LatLng? _lastLocation;
  double _progressToNextManeuver = 0.0;
  bool _isMuted = false;
  BitmapDescriptor? _navigationMarkerIcon;
  final Set<Marker> _navigationMarkers = {};

  // TTS FEATURE: TTS instance
  late FlutterTts _flutterTts;
  bool _navigationStarted = false; // TTS FIX: Flag to control initial speech
  // SPEED LIMIT FEATURE: State variables
  int? _currentSpeedLimit;
  Timer? _speedLimitTimer;
  final Stopwatch _navigationStopwatch = Stopwatch();
  double _currentSpeed = 0.0;
  double _currentZoom = 18.0;
  double _currentUserRotation = 0.0;

  // SCENIC ROUTE: State variables

  int _fastestRouteIndex = 0;
  int _scenicRouteIndex = 0;

  // REROUTE: State variables
  bool _isRecalculating = false;


  // ANIMATION: Controller for the progress bar
  AnimationController? _progressAnimationController;
  Animation<double>? _progressAnimation;


  @override
  void initState() {
    super.initState();
    _destination = widget.destination;
    // ANIMATION: Initialize progress bar controller
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500), // Quick animation for progress
      vsync: this,
    );
    _initializeDirections();
    _createStopIcons();
    _loadMutePreference();
    _initTts(); // TTS VOICE SELECTION & INIT
    themeNotifier.addListener(_updateMapStyle);

  }

  // TTS VOICE SELECTION & INIT: Method to setup TTS with selected voice
  Future<void> _initTts() async {
    _flutterTts = FlutterTts();
    final prefs = await SharedPreferences.getInstance();
    final voiceName = prefs.getString('selectedTtsVoice');
    if (voiceName != null) {
      try {
        final voices = await _flutterTts.getVoices;
        final selectedVoice = (voices as List).firstWhere(
              (v) => (v as Map)['name'] == voiceName,
          orElse: () => null,
        );
        if (selectedVoice != null) {
          await _flutterTts.setVoice(selectedVoice);
        }
      } catch (e) {
        debugPrint("Error setting TTS voice: $e");
      }
    }
  }

  @override
  void dispose() {
    _navigationLocationSubscription?.cancel();
    _flutterTts.stop();
    _speedLimitTimer?.cancel();
    _progressAnimationController?.dispose();
    WakelockPlus.disable();
    NotificationService().cancelNavigationNotification();
    _navigationStopwatch.stop();
    themeNotifier.removeListener(_updateMapStyle);
    super.dispose();
  }

  // TTS FEATURE: Method to speak text
  Future<void> _speak(String text) async {
    if (!_isMuted && text.isNotEmpty) {
      await _flutterTts.speak(text.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' '));
    }
  }

  void _updateMapStyle() {
    if (!_isMapControllerInitialized || !mounted) return;

    // Check the app's current theme mode (light, dark, or system)
    final themeMode = themeNotifier.value;
    final isDarkMode = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    if (isDarkMode) {
      // If it's dark mode, load and apply your custom dark style
      rootBundle.loadString('assets/map_style_dark.json').then((style) {
        if (mounted) mapController.setMapStyle(style);
      });
    } else {
      // If it's light mode, pass null to use the default Google Maps style
      mapController.setMapStyle(null);
    }
  }

  // SPEED LIMIT FEATURE: Method to fetch speed limit
  Future<void> _getSpeedLimit(LatLng point) async {
    try {
      final apiService = Provider.of<GoogleMapsApiService>(context, listen: false);
      final data = await apiService.getSpeedLimit(point);
      final speedLimits = data['speedLimits'];
      if (speedLimits != null && speedLimits.isNotEmpty) {
        final limit = speedLimits[0]['speedLimit'];
        if (mounted) {
          setState(() {
            _currentSpeedLimit = limit.round();
          });
        }
      }
    } catch (e) {
      debugPrint("Failed to get speed limit: $e");
    }
  }


  Future<void> _loadMutePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isMuted = prefs.getBool('isMuted') ?? false;
    });
  }

  Future<void> _saveMutePreference(bool isMuted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isMuted', isMuted);
  }


  Future<void> _createStopIcons() async {
    _circleStopIcon = await _createCircleStopMarkerBitmap();
    setState(() {});
  }

  Future<void> _initializeDirections() async {
    // Show the loading overlay immediately at the very start.
    // Use a post-frame callback to ensure the first build is complete.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      LoadingOverlay.show(context);

      try {
        print("--- DirectionsScreen: Initializing ---");

        // STEP 1: Get Origin Coords
        final originLatLng = widget.originCoordinates;
        _lastLocation = originLatLng;
        print("1. Got user location from MapScreen: $originLatLng");

        // STEP 2: Get Origin Address
        final originAddress = await _reverseGeocode(originLatLng);
        print("2. Got origin address: '$originAddress'");

        if (!mounted) {
          LoadingOverlay.hide();
          return;
        }

        // STEP 3: Set initial state in one go
        setState(() {
          _origin = PlaceDetails(
            placeId: 'user_location',
            name: "Current Location",
            address: originAddress,
            coordinates: originLatLng,
          );
        });

        // STEP 4: Now get the directions.
        // The _getDirections method will handle hiding the overlay in its `finally` block.
        await _getDirections();
        print("3. Get directions finished.");

      } catch (e) {
        print("CRITICAL ERROR during initialization: $e");
        if (mounted) LoadingOverlay.hide();
      }
    });
  }

  Future<String> _reverseGeocode(LatLng coordinates) async {
    try {
      final apiService = Provider.of<GoogleMapsApiService>(context, listen: false);
      final data = await apiService.reverseGeocode(coordinates);
      if (data['status'] == 'OK' && data['results'].isNotEmpty) {
        return data['results'][0]['formatted_address'];
      }
    } catch (e) {
      debugPrint("Reverse geocoding failed: $e");
    }
    return "Your Location";
  }

  Future<void> _getDirections() async {
    if (_origin == null || _destination == null) {
      return;
    }

    // Show the overlay directly at the start. No setState needed.
    LoadingOverlay.show(context);
    _routeDifferenceMarkers.clear();

    String travelModeStr = _travelMode.toString().split('.').last;
    List<String> avoidances = [];
    if (_avoidTolls) avoidances.add('tolls');
    if (_avoidHighways) avoidances.add('highways');
    if (_avoidFerries) avoidances.add('ferries');
    String avoidStr = avoidances.isNotEmpty ? '&avoid=${avoidances.join('|')}' : '';

    try {
      final apiService = Provider.of<GoogleMapsApiService>(context, listen: false);
      final data = await apiService.getDirections(
        origin: _origin!.coordinates,
        destination: _destination!.coordinates,
        travelMode: travelModeStr,
        avoidances: avoidStr,
      );

      if (data['status'] == 'OK') {
        final List<RouteInfo> fetchedRoutes = [];
        for (var route in data['routes']) {
          final leg = route['legs'][0];
          List<LatLng> polylinePoints = PolylinePoints()
              .decodePolyline(route['overview_polyline']['points'])
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList();
          final durationText = leg['duration_in_traffic']?['text'] ?? leg['duration']['text'];
          final durationValue = leg['duration_in_traffic']?['value'] ?? leg['duration']['value'];
          fetchedRoutes.add(RouteInfo(
            duration: durationText,
            durationValue: durationValue,
            distance: leg['distance']['text'],
            polylinePoints: polylinePoints,
            curviness: _calculateCurviness(polylinePoints),
            steps: leg['steps'],
          ));
        }

        // This setState is CORRECT because it's updating the UI with the new route data.
        if (mounted) {
          setState(() {
            _routes = fetchedRoutes;
            _processRoutes();
            _transitRoutes = []; // Clear transit routes when fetching driving routes
            _detailedRoute = null;

            if (_routes.isNotEmpty) {
              _navSteps = data['routes'][_selectedRouteIndex]['legs'][0]['steps'];
              _navEta = _routes[_selectedRouteIndex].duration;
              _navDistance = _routes[_selectedRouteIndex].distance;
              _updateNavInstruction();
            }
          });
        }
      } else {
        // If status is not OK, make sure the routes list is empty
        if(mounted) {
          setState(() {
            _routes = [];
          });
        }
      }

      _updateMarkersAndPolylines();
    } catch (e) {
      debugPrint("Error fetching directions: $e");
      if(mounted) { // Also clear routes on error
        setState(() {
          _routes = [];
        });
      }
    } finally {
      // Always hide the overlay when the process is finished, success or fail.
      LoadingOverlay.hide();
      if (mounted) {
        _updateRouteDifferenceMarkers();
      }
    }
  }

  // SCENIC ROUTE: Method to process and rank routes
  void _processRoutes() {
    if (_routes.isEmpty) return;
    _fastestRouteIndex = 0; // Google API's first route is usually the fastest
    _scenicRouteIndex = 0;
    double maxCurviness = 0;
    for (int i = 0; i < _routes.length; i++) {
      if (_routes[i].curviness > maxCurviness) {
        maxCurviness = _routes[i].curviness;
        _scenicRouteIndex = i;
      }
    }
    // Set the initial selected route based on the chosen type
    _selectedRouteIndex = _routeType == RouteType.fastest ? _fastestRouteIndex : _scenicRouteIndex;
  }

  // lib/screens/map/directions_screen.dart

  Set<Polyline> _createTrafficPolylines(List<dynamic> steps) {
    final Set<Polyline> polylines = {};
    if (steps.isEmpty) return polylines;

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final duration = step['duration']['value'];
      // duration_in_traffic may not exist if there's no traffic, so default to the base duration
      final durationInTraffic = step['duration_in_traffic']?['value'] ?? duration;

      // Calculate the delay in seconds
      final delay = durationInTraffic - duration;

      // Assign color based on delay
      Color color = Colors.green.shade600; // No traffic
      if (delay > 120) { // Over 2 minutes of delay
        color = Colors.red.shade800;
      } else if (delay > 30) { // Over 30 seconds of delay
        color = Colors.orange.shade700;
      }

      // Decode the polyline for this specific step
      final points = PolylinePoints()
          .decodePolyline(step['polyline']['points'])
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();

      polylines.add(Polyline(
        polylineId: PolylineId('route_traffic_segment_$i'),
        points: points,
        color: color,
        width: 8,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ));
    }
    return polylines;
  }

// SCENIC ROUTE: Helper to calculate the "curviness" of a route
  double _calculateCurviness(List<LatLng> polyline) {
    if (polyline.length < 3) return 0.0;
    double totalBearingChange = 0.0;
    for (int i = 0; i < polyline.length - 2; i++) {
      final p1 = polyline[i];
      final p2 = polyline[i + 1];
      final p3 = polyline[i + 2];

      final bearing1 = _calculateBearing(p1, p2);
      final bearing2 = _calculateBearing(p2, p3);

      double bearingChange = (bearing2 - bearing1).abs();
      if (bearingChange > 180) {
        bearingChange = 360 - bearingChange; // Handle wrapping around 360 degrees
      }
      totalBearingChange += bearingChange;
    }
    return totalBearingChange;
  }

// SCENIC ROUTE: Helper to calculate bearing between two points
  double _calculateBearing(LatLng start, LatLng end) {
    final double startLat = start.latitude * pi / 180;
    final double startLng = start.longitude * pi / 180;
    final double endLat = end.latitude * pi / 180;
    final double endLng = end.longitude * pi / 180;

    double dLng = endLng - startLng;
    double y = sin(dLng) * cos(endLat);
    double x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(dLng);

    double bearing = atan2(y, x) * 180 / pi;
    return (bearing + 360) % 360; // Normalize to 0-360
  }

  Future<BitmapDescriptor> _createTimeDifferenceMarkerBitmap(String text) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 32,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();

    final double padding = 16.0;
    final double borderRadius = 30.0;
    final Rect rect = Rect.fromLTWH(
        0, 0, textPainter.width + padding * 2, textPainter.height + padding);
    final RRect rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    final Paint backgroundPaint = Paint()..color = Colors.black.withOpacity(0.7);
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawRRect(rrect, backgroundPaint);
    canvas.drawRRect(rrect, borderPaint);

    textPainter.paint(canvas, Offset(padding, padding / 2));

    final img = await pictureRecorder
        .endRecording()
        .toImage(rect.width.toInt(), rect.height.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  Future<void> _updateRouteDifferenceMarkers() async {
    if (_routes.length <= 1 || _travelMode != TravelMode.driving) {
      return;
    }

    final fastestDuration = _routes.map((r) => r.durationValue).reduce(min);
    final newMarkers = <Marker>{};

    for (final route in _routes) {
      if (route.durationValue > fastestDuration) {
        final differenceInSeconds = route.durationValue - fastestDuration;
        final differenceInMinutes = (differenceInSeconds / 60).ceil();
        final labelText = '+$differenceInMinutes min';

        if (route.polylinePoints.isNotEmpty) {
          final markerPosition = route.polylinePoints[route.polylinePoints.length ~/ 2];
          final icon = await _createTimeDifferenceMarkerBitmap(labelText);

          newMarkers.add(
            Marker(
              markerId: MarkerId('route_diff_${route.hashCode}'),
              position: markerPosition,
              icon: icon,
              anchor: const Offset(0.5, 1.2),
            ),
          );
        }
      }
    }

    if (mounted) {
      setState(() {
        _routeDifferenceMarkers.clear();
        _routeDifferenceMarkers.addAll(newMarkers);
      });
    }
  }

// Replace your entire _updateMarkersAndPolylines method with this one.

  void _updateMarkersAndPolylines() {
    if (!mounted || _origin == null || _destination == null) return;

    // --- FIX 1: The 'isTransit' variable is now correctly defined ---
    final bool isTransit = _travelMode == TravelMode.transit;

    final newMarkers = <Marker>{
      Marker(markerId: const MarkerId('origin'), position: _origin!.coordinates, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
      Marker(markerId: const MarkerId('destination'), position: _destination!.coordinates),
    };
    Set<Polyline> newPolylines = {};

    final bool hasRoutes = (_travelMode != TravelMode.transit && _routes.isNotEmpty) ||
        (_travelMode == TravelMode.transit && _transitRoutes.isNotEmpty);

    if (hasRoutes) {
      List<LatLng> points = [];
      if (!isTransit) {
        points = _routes[_selectedRouteIndex].polylinePoints;
      }

      switch (_travelMode) {
        case TravelMode.driving:
          newPolylines = _createTrafficPolylines(_routes[_selectedRouteIndex].steps);
          break;
        case TravelMode.walking:
          newPolylines.add(Polyline(
            polylineId: const PolylineId('route_walking'),
            points: points,
            color: Colors.blueAccent,
            width: 6,
            patterns: [PatternItem.dot, PatternItem.gap(10)],
          ));
          break;
        case TravelMode.bicycling:
          newPolylines.add(Polyline(
            polylineId: const PolylineId('route_cycling'),
            points: points,
            color: Colors.green,
            width: 6,
            patterns: [PatternItem.dash(20), PatternItem.gap(15)],
          ));
          break;
        case TravelMode.transit:
          if (_detailedRoute != null) {
            for (var step in _detailedRoute!.steps) {
              newPolylines.add(Polyline(
                polylineId: PolylineId('transit_step_${step.hashCode}'),
                points: step.polylinePoints,
                color: step.travelMode == StepTravelMode.walking ? Colors.grey : Colors.blue,
                width: 6,
                patterns: step.travelMode == StepTravelMode.walking ? [PatternItem.dot, PatternItem.gap(10)] : [],
              ));
            }
          }
          break;
      }
    }

    setState(() {
      _markers.clear();
      _markers.addAll(newMarkers);
      _polylines.clear();
      _polylines.addAll(newPolylines);
    });

    // --- FIX 2: This logic now correctly runs when a route IS found ---
    if (hasRoutes && _isMapControllerInitialized && !_isNavigating) {
      List<LatLng> fullRouteForBounds = isTransit
          ? _transitRoutes[_selectedRouteIndex].steps.expand((s) => s.polylinePoints).toList()
          : _routes[_selectedRouteIndex].polylinePoints;

      if (fullRouteForBounds.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final bounds = _boundsFromLatLngList(fullRouteForBounds);
            mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80.0));
          }
        });
      }
    }
  }

  void _onRouteTapped(int index) {
    setState(() {
      _selectedRouteIndex = index;
      if (_travelMode == TravelMode.transit && _transitRoutes.length > index) {
        _detailedRoute = _transitRoutes[index];
      }
      _updateMarkersAndPolylines();
    });
  }
  void _swapDirections() {
    setState(() {
      _isNavigating = false;
      final temp = _origin;
      _origin = _destination;
      _destination = temp;
    });
    _getDirections();
  }
  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    _isMapControllerInitialized = true;
    final isDarkMode = MediaQuery.of(context).platformBrightness == Brightness.dark;

    // --- CHANGED: Conditionally load the dark style or pass null for default light style ---
    _updateMapStyle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(target: widget.destination.coordinates, zoom: 12),
            onCameraMove: (CameraPosition position) {
              // Continuously update the zoom level as the user moves the map
              _currentZoom = position.zoom;
            },
            onCameraIdle: () {
              // When the user stops moving the map, trigger the marker resize
              _updateNavigationMarkerIcon();
            },
            polylines: _polylines,
            markers: _isNavigating
                ? _navigationMarkers.union(_routeDifferenceMarkers)
                : _markers.union(_routeDifferenceMarkers),
            zoomControlsEnabled: false,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            padding: EdgeInsets.only(
                top: _isNavigating ? 150 : 120,
                bottom: _isNavigating ? 100 : MediaQuery.of(context).size.height * 0.2
            ),
          ),
          if (_isRecalculating)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Recalculating route...", style: TextStyle(color: Colors.white, fontSize: 18)),
                  ],
                ),
              ),
            ),
          // FIX: Call the list-returning function with a spread operator
          if (!_isRecalculating)
            if (_isNavigating)
              ..._buildNavigationUI()
            else
              ...[
                _buildDirectionsHeader(),
                _buildDraggableRoutePanel(),
              ]
        ],
      ),
    );
  }

  List<Widget> _buildFuturisticNavigationUI() {
    return [
      _buildFuturisticTopCard(),
      _buildFuturisticBottomPanel(),
      // You can keep other FloatingActionButtons like recenter, speed limit, etc.
      // ...
    ];
  }

  Future<void> _updateNavigationMarkerIcon() async {
    // The sizing formula remains the same
    final double newSize = 80 + (_currentZoom - 12) * 15;
    final double clampedSize = newSize.clamp(80.0, 220.0);

    // --- CHANGED: Call the new drawing method instead of _getResizedMarkerIcon ---
    _navigationMarkerIcon = await _createDynamicMarkerBitmap(clampedSize);

    // Trigger a UI update to show the new marker
    _updateNavigationMarkers();
  }

  // This helper method updates the state with the new marker
  void _updateNavigationMarkers() {
    if (!mounted || _lastLocation == null || _navigationMarkerIcon == null) return;

    final marker = Marker(
      markerId: const MarkerId('navigation_user'),
      position: _lastLocation!,
      icon: _navigationMarkerIcon!,
      rotation: _currentUserRotation,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndex: 2.0,
    );

    setState(() {
      _navigationMarkers.clear();
      _navigationMarkers.add(marker);
    });
  }

  // --- DESIGN OVERHAUL: New "glass" top card ---
  Widget _buildFuturisticTopCard() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 15,
      right: 15,
      child: GlassmorphicContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_navManeuverIcon, color: Colors.white, size: 48),
            const SizedBox(height: 8),
            Text(
              _navInstruction,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progressToNextManeuver,
                      minHeight: 10,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(_distanceToNextManeuver,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            )
          ],
        ),
      ),
    );
  }

  // --- DESIGN OVERHAUL: New "glass" bottom panel ---
  Widget _buildFuturisticBottomPanel() {
    final arrivalTime = DateTime.now().add(Duration(seconds: _routes[_selectedRouteIndex].durationValue));
    final timeFormat = DateFormat.jm();

    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 10,
      left: 15,
      right: 15,
      child: GlassmorphicContainer(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeFormat.format(arrivalTime),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  "${_navDistance} · ${_navEta}",
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
                ),
              ],
            ),
            Row(
              children: [
                // Mute Button
                Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.3)),
                  child: IconButton(
                    icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                    onPressed: () { /* Mute logic */ },
                  ),
                ),
                const SizedBox(width: 16),
                // End Button
                Container(
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _stopNavigation,
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // --- NEW TRANSIT UI: A new panel for displaying transit routes ---
  Widget _buildTransitPanel() {
    if (_transitRoutes.isEmpty) return const Center(child: Text("No transit routes found."));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _transitRoutes.length,
      itemBuilder: (context, index) {
        // This is a simplified card. Tapping it would show the full timeline.
        final route = _transitRoutes[index];
        final isSelected = _selectedRouteIndex == index;
        return Card(
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
          child: ListTile(
            onTap: () => _onRouteTapped(index),
            title: Text("Option ${index + 1}: ${route.duration} (${route.distance})"),
            subtitle: Row(
              children: route.steps.where((s) => s.travelMode == StepTravelMode.transit).map((step) {
                return Padding(
                  padding: const EdgeInsets.only(right: 4.0),
                  child: Icon(getTransitIcon(step.vehicleType), size: 16),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // --- NEW TRANSIT UI: The detailed vertical timeline view ---
  Widget _buildRouteDetailsContent(ScrollController scrollController, FullTransitRoute route) {
    return ListView.builder(
      controller: scrollController,
      itemCount: route.steps.length,
      itemBuilder: (context, index) {
        final step = route.steps[index];
        final isFirst = index == 0;
        final isLast = index == route.steps.length - 1;
        // This is a custom widget you would build to display each step
        return _TransitStepWidget(step: step, isFirst: isFirst, isLast: isLast);
      },
    );
  }

  Widget _buildDirectionsHeader() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 5,
      left: 15,
      right: 15,
      child: Material(
        elevation: 4.0,
        borderRadius: BorderRadius.circular(16.0),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Row(
            children: [
              // TTS BUG FIX: Stop TTS when back button is pressed
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  _flutterTts.stop();
                  Navigator.of(context).pop();
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("From: ${_origin?.address ?? 'Loading...'}",
                        overflow: TextOverflow.ellipsis),
                    const Divider(),
                    Text("To: ${_destination?.address ?? ''}",
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.swap_vert),
                onPressed: _swapDirections,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDraggableRoutePanel() {
    final minSize = 0.25;
    final initialSize = 0.4;
    final maxSize = 0.9;

    return DraggableScrollableSheet(
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      builder: (context, scrollController) {
        Widget panelContent;
        if (_travelMode == TravelMode.transit && _detailedRoute != null) {
          panelContent = _buildRouteDetailsContent(scrollController, _detailedRoute!);
        } else {
          panelContent = _buildRouteSelectionContent();
        }
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 5,
              )
            ],
          ),
          child: panelContent,
        );
      },
    );
  }

  Widget _buildRouteSelectionContent() {
    if ((_travelMode == TravelMode.transit && _transitRoutes.isEmpty) ||
        (_travelMode != TravelMode.transit && _routes.isEmpty)) {
      return const Center(child: Text("No route found for the selected options."));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              _travelMode.name[0].toUpperCase() + _travelMode.name.substring(1),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTravelModeIcon(
                  TravelMode.driving, Icons.directions_car, "Car"),
              _buildTravelModeIcon(
                  TravelMode.transit, Icons.directions_bus, "Transit"),
              _buildTravelModeIcon(
                  TravelMode.walking, Icons.directions_walk, "Walk"),
              _buildTravelModeIcon(
                  TravelMode.bicycling, Icons.directions_bike, "Cycle"),
            ],
          ),
          const Divider(height: 24),
          if (_travelMode == TravelMode.transit)
            _buildTransitPanel()
          else
            _buildDrivingPanel(),
        ],
      ),
    );
  }

  Widget _buildDrivingPanel() {
    if (_routes.isEmpty) return const SizedBox.shrink();
    final route = _routes[_selectedRouteIndex];
    final now = DateTime.now();
    final arrivalTime = now.add(Duration(seconds: route.durationValue));
    final timeFormat = DateFormat.jm();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_travelMode == TravelMode.driving)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Center(
                child: SegmentedButton<RouteType>(
                  segments: const <ButtonSegment<RouteType>>[
                    ButtonSegment<RouteType>(
                        value: RouteType.fastest,
                        label: Text('Fastest'),
                        icon: Icon(Icons.timer)),
                    ButtonSegment<RouteType>(
                        value: RouteType.scenic,
                        label: Text('Scenic'),
                        icon: Icon(Icons.park)),
                  ],
                  selected: <RouteType>{_routeType},
                  onSelectionChanged: (Set<RouteType> newSelection) {
                    setState(() {
                      _routeType = newSelection.first;
                      _selectedRouteIndex = _routeType == RouteType.fastest
                          ? _fastestRouteIndex
                          : _scenicRouteIndex;
                      _updateMarkersAndPolylines();
                    });
                  },
                ),
              ),
            ),
          Text("ETA: ${route.duration} (${route.distance})",
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildOptionChip("Avoid Tolls", _avoidTolls, (val) {
                setState(() => _avoidTolls = val);
                _getDirections();
              }),
              _buildOptionChip("Avoid Highways", _avoidHighways, (val) {
                setState(() => _avoidHighways = val);
                _getDirections();
              }),
              _buildOptionChip("Avoid Ferries", _avoidFerries, (val) {
                setState(() => _avoidFerries = val);
                _getDirections();
              }),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Start time: ${timeFormat.format(now)}"),
              Text("Reaching time: ${timeFormat.format(arrivalTime)}"),
            ],
          ),
          const SizedBox(height: 8),
          // THIS IS THE CORRECTED ROW
          Row(
            children: [
              const Icon(Icons.directions_car, color: Colors.blue),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: AnimatedRouteLine(),
                ),
              ),
              const Icon(Icons.flag, color: Colors.redAccent),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: PulsingStartButton(onPressed: _startNavigation)),
              const SizedBox(width: 16),
              OutlinedButton(onPressed: () {}, child: const Icon(Icons.add)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTravelModeIcon(TravelMode mode, IconData icon, String label) {
    final isSelected = _travelMode == mode;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color unselectedColor =
    isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final Color color = isSelected ? Colors.green : unselectedColor;
    return GestureDetector(
      onTap: () {
        if (_travelMode != mode) {
          setState(() {
            _travelMode = mode;
            _detailedRoute = null;
          });
          _getDirections();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
            BoxShadow(
                color: Colors.green.withOpacity(0.4),
                blurRadius: 10,
                spreadRadius: 1)
          ]
              : [],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal))
          ],
        ),
      ),
    );
  }
  Widget _buildOptionChip(
      String label, bool isSelected, Function(bool) onSelected) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      showCheckmark: false,
      backgroundColor: Theme.of(context).dividerColor.withOpacity(0.1),
      selectedColor: Colors.green,
      labelStyle: TextStyle(
        color:
        isSelected ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
        fontWeight: FontWeight.bold,
      ),
      side: BorderSide(
          color: isSelected
              ? Colors.green.shade700
              : Theme.of(context).dividerColor),
    );
  }
  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double? x0, x1, y0, y1;
    for (LatLng latLng in list) {
      if (x0 == null) {
        x0 = x1 = latLng.latitude;
        y0 = y1 = latLng.longitude;
      } else {
        if (latLng.latitude > x1!) x1 = latLng.latitude;
        if (latLng.latitude < x0) x0 = latLng.latitude;
        if (latLng.longitude > y1!) y1 = latLng.longitude;
        if (latLng.longitude < y0!) y0 = latLng.longitude;
      }
    }
    return LatLngBounds(northeast: LatLng(x1!, y1!), southwest: LatLng(x0!, y0!));
  }

  Future<BitmapDescriptor> _createBusNumberMarkerBitmap(String text) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(pictureRecorder);
    final ui.Paint paint1 = ui.Paint()..color = Colors.blueAccent;
    const int size = 100;

    canvas.drawRect(ui.Rect.fromLTWH(0.0, 0.0, size.toDouble(), size.toDouble() / 2), paint1);

    final TextPainter painter = TextPainter(textDirection: ui.TextDirection.ltr); // FIX: Added ui. prefix
    painter.text = TextSpan(
      text: text,
      style: const TextStyle(
          fontSize: 40.0, color: Colors.white, fontWeight: FontWeight.bold),
    );
    painter.layout();
    painter.paint(
      canvas,
      Offset((size * 0.5) - (painter.width * 0.5), (size * 0.25) - (painter.height * 0.5)),
    );

    final img = await pictureRecorder.endRecording().toImage(size, (size / 2).toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createCircleStopMarkerBitmap() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(pictureRecorder);
    final ui.Paint paint = ui.Paint()..color = Colors.white; // FIX: Added ui. prefix
    final ui.Paint borderPaint = ui.Paint() // FIX: Added ui. prefix
      ..color = Colors.grey.shade600
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke;
    final ui.Paint innerPaint = ui.Paint()..color = Colors.grey.shade400; // FIX: Added ui. prefix

    const double size = 100.0;

    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, paint);
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, borderPaint);
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 5, innerPaint);

    final img = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  void _startNavigation() async{
    if (_routes.isEmpty) return;
    await _updateNavigationMarkerIcon();
    WakelockPlus.enable(); // WAKELOCK: Keep screen on
    setState(() {
      _isNavigating = true;
      _navigationStarted = true; // TTS FIX: Flag to control initial speech
    });
    _navigationStopwatch.start();
    // TTS FIX: Speak the first instruction only when navigation starts
    _speak(_navInstruction);
    _listenToLocationForNavigation();

    // SPEED LIMIT: Start the timer when navigation begins
    _speedLimitTimer?.cancel();
    _speedLimitTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_lastLocation != null) {
        _getSpeedLimit(_lastLocation!);
      }
    });
  }

  void _stopNavigation() {
    WakelockPlus.disable(); // WAKELOCK: Allow screen to turn off
    _navigationLocationSubscription?.cancel();
    _speedLimitTimer?.cancel(); // SPEED LIMIT: Stop the timer
    NotificationService().cancelNavigationNotification();
    _navigationStopwatch.stop();
    _navigationStopwatch.reset();
    setState(() {
      _isNavigating = false;
      _navigationStarted = false; // TTS FIX: Reset flag
      _currentSpeedLimit = null; // Clear speed limit from view
    });
    _updateMarkersAndPolylines();
  }

  void _recenterCamera() {
    if (_lastLocation != null && _isMapControllerInitialized) {
      mapController.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _lastLocation!,
          zoom: 18,
          tilt: 50.0,
          bearing: 0.0,
        ),
      ));
    }
  }

  void _listenToLocationForNavigation() {
    final locationService = Location();
    _navigationLocationSubscription =
        locationService.onLocationChanged.listen((LocationData currentLocation) {
          if (!mounted || !_isNavigating) return;

          final newLatLng = LatLng(currentLocation.latitude!, currentLocation.longitude!);
          _lastLocation = newLatLng;
          final newRotation = currentLocation.heading ?? 0.0;
          _currentUserRotation = newRotation;
          // REROUTE: Check if the user is off-route
          if (!_isRecalculating && _isOffRoute(newLatLng, _routes[_selectedRouteIndex].polylinePoints)) {
            _recalculateRoute(newLatLng);
            return; // Skip the rest of the update while recalculating
          }
          _updateNavigationMarkers();
          mapController.animateCamera(CameraUpdate.newCameraPosition(
            CameraPosition(
              target: newLatLng,
              zoom: 18,
              tilt: 50.0,
              bearing: newRotation,
            ),
          ));
          _updateNavigationState(newLatLng);
        });
  }

  Future<BitmapDescriptor> _createDynamicMarkerBitmap(double size) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint paint = Paint()..color = Colors.blue.shade700;
    final Paint glowPaint = Paint()..color = Colors.blue.withOpacity(0.3);

    // The outer "glow" circle
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, glowPaint);
    // The inner solid circle
    canvas.drawCircle(Offset(size / 2, size / 2), size / 3.5, paint);

    final img = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  // REROUTE: New method to check if user is off-route
  bool _isOffRoute(LatLng userPosition, List<LatLng> polyline) {
    const double offRouteThreshold = 50.0; // meters
    double minDistance = double.infinity;

    for (int i = 0; i < polyline.length - 1; i++) {
      final p1 = polyline[i];
      final p2 = polyline[i + 1];
      final distance = _distanceToLineSegment(userPosition, p1, p2);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance > offRouteThreshold;
  }

// REROUTE: Helper for distance calculation
  double _distanceToLineSegment(LatLng p, LatLng v, LatLng w) {
    double l2 = _calculateDistance(v.latitude, v.longitude, w.latitude, w.longitude);
    l2 = l2 * l2;
    if (l2 == 0.0) return _calculateDistance(p.latitude, p.longitude, v.latitude, v.longitude);
    double t = ((p.latitude - v.latitude) * (w.latitude - v.latitude) + (p.longitude - v.longitude) * (w.longitude - v.longitude)) / l2;
    t = max(0, min(1, t));
    return _calculateDistance(p.latitude, p.longitude, v.latitude + t * (w.latitude - v.latitude), v.longitude + t * (w.longitude - v.longitude));
  }

// REROUTE: New method to trigger recalculation
  Future<void> _recalculateRoute(LatLng newOrigin) async {
    if (!mounted) return;
    setState(() {
      _isRecalculating = true;
      _origin = PlaceDetails(
          placeId: 'recalc_origin',
          name: 'Current Location',
          address: 'Recalculating...',
          coordinates: newOrigin
      );
    });
    await _getDirections();
  }

  void _updateNavigationState(LatLng currentUserPosition) {
    if (_navSteps.isEmpty) return;

    final currentStep = _navSteps[_currentStepIndex];
    final endLocation = LatLng(
        currentStep['end_location']['lat'],
        currentStep['end_location']['lng']
    );
    final totalStepDistance = currentStep['distance']['value'].toDouble();


    final distanceInMeters = _calculateDistance(
        currentUserPosition.latitude,
        currentUserPosition.longitude,
        endLocation.latitude,
        endLocation.longitude
    );

    if (distanceInMeters < 30 && _currentStepIndex < _navSteps.length - 1) {
      setState(() {
        _currentStepIndex++;
        _updateNavInstruction();
      });
    }

    final newProgress = (totalStepDistance - distanceInMeters) / totalStepDistance;
    // ANIMATION: Animate the progress bar value
    _progressAnimation = Tween<double>(begin: _progressToNextManeuver, end: newProgress.clamp(0.0, 1.0))
        .animate(_progressAnimationController!);
    _progressAnimationController!.forward(from: 0.0);

    final totalDuration = Duration(seconds: _routes[_selectedRouteIndex].durationValue);
    final remainingDuration = totalDuration - _navigationStopwatch.elapsed;
    final timeRemainingStr = remainingDuration.inMinutes > 0
        ? "${remainingDuration.inMinutes} min"
        : "${remainingDuration.inSeconds} sec";


    setState(() {
      _distanceToNextManeuver = distanceInMeters < 1000
          ? "${distanceInMeters.toStringAsFixed(0)} m"
          : "${(distanceInMeters / 1000).toStringAsFixed(1)} km";
      _progressToNextManeuver = newProgress.clamp(0.0, 1.0);
    });

    NotificationService().showNavigationNotification(
        destination: _destination?.name ?? 'your destination',
        eta: _navEta,
        timeRemaining: timeRemainingStr,
        nextTurn: _navInstruction,
        maneuverIcon: _navManeuverIcon);

  }

  void _updateNavInstruction() {
    if (_navSteps.isEmpty || _currentStepIndex >= _navSteps.length) return;
    final currentStep = _navSteps[_currentStepIndex];
    final instruction = _stripHtmlIfNeeded(currentStep['html_instructions']);
    setState(() {
      _navInstruction = instruction;
      _navManeuverIcon = _getManeuverIcon(currentStep['maneuver']);
    });
    // TTS FIX: Only speak subsequent instructions
    if (_navigationStarted) {
      _speak(_navInstruction);
    }
  }

  String _stripHtmlIfNeeded(String htmlString) {
    return htmlString.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ');
  }

  IconData _getManeuverIcon(String? maneuver) {
    if (maneuver == null) return Icons.straight;
    switch (maneuver) {
      case 'turn-sharp-left': return Icons.turn_sharp_left;
      case 'turn-left': return Icons.turn_left;
      case 'turn-slight-left': return Icons.turn_slight_left;
      case 'turn-sharp-right': return Icons.turn_sharp_right;
      case 'turn-right': return Icons.turn_right;
      case 'turn-slight-right': return Icons.turn_slight_right;
      case 'uturn-left': return Icons.u_turn_left;
      case 'uturn-right': return Icons.u_turn_right;
      case 'roundabout-left': return Icons.roundabout_left;
      case 'roundabout-right': return Icons.roundabout_right;
      default: return Icons.straight;
    }
  }

  double _calculateDistance(lat1, lon1, lat2, lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)) * 1000;
  }

  // FIX: Return a list of widgets instead of a Stack
  List<Widget> _buildNavigationUI() {
    return [
      _buildTopInstructionCard(),
      _buildBottomEtaCard(),
      _buildSpeedLimitIndicator(),
      Positioned(
        bottom: 120,
        right: 15,
        child: FloatingActionButton(
          mini: true,
          onPressed: _recenterCamera,
          child: const Icon(Icons.my_location),
        ),
      )
    ];
  }

  // SPEED LIMIT FEATURE: New widget to show the speed limit
  Widget _buildSpeedLimitIndicator() {
    if (_currentSpeedLimit == null) return const SizedBox.shrink();

    return Positioned(
      bottom: 120,
      left: 15,
      child: Material(
        elevation: 4,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 60,
          height: 60,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 4),
          ),
          child: FittedBox(
            child: Text(
              '$_currentSpeedLimit',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopInstructionCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 5,
      left: 15,
      right: 15,
      child: Material(
        color: isDark ? Colors.grey[900] : Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          // UI ALIGNMENT FIX: Center the instruction content
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center, // Center horizontally
            children: [
              Icon(_navManeuverIcon, color: Colors.white, size: 48),
              const SizedBox(height: 8),
              Text(
                _navInstruction,
                textAlign: TextAlign.center, // Center text
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        // ANIMATION: Use AnimatedBuilder for smooth progress
                        child: AnimatedBuilder(
                          animation: _progressAnimationController!,
                          builder: (context, child) {
                            return LinearProgressIndicator(
                              value: _progressAnimation?.value ?? _progressToNextManeuver,
                              minHeight: 10,
                              backgroundColor: Colors.grey[700],
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            );
                          },
                        )
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(_distanceToNextManeuver,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomEtaCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final arrivalTime = now.add(Duration(seconds: _routes[_selectedRouteIndex].durationValue));
    final timeFormat = DateFormat.jm();

    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 10,
      left: 15,
      right: 15,
      child: Material(
        color: isDark ? Colors.grey[900] : Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeFormat.format(arrivalTime),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "${_navDistance} · ${_navEta}",
                    style: TextStyle(color: Colors.grey[400], fontSize: 16),
                  ),
                ],
              ),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.grey[800],
                    child: IconButton(
                      icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _isMuted = !_isMuted;
                          if (_isMuted) {
                            _flutterTts.stop();
                          }
                        });
                        _saveMutePreference(_isMuted);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  CircleAvatar(
                    backgroundColor: Colors.red,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _stopNavigation,
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _TransitStepWidget extends StatelessWidget {
  final RouteStep step;
  final bool isFirst;
  final bool isLast;

  const _TransitStepWidget({required this.step, this.isFirst = false, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 70,
            child: CustomPaint(
              painter: _TimelinePainter(
                mode: step.travelMode,
                isFirst: isFirst,
                isLast: isLast,
              ),
              child: Center(
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: step.travelMode == StepTravelMode.walking
                      ? Colors.grey
                      : Theme.of(context).primaryColor,
                  child: Icon(
                    step.travelMode == StepTravelMode.walking
                        ? Icons.directions_walk
                        : getTransitIcon(step.vehicleType), // <-- USES CLEANED-UP FUNCTION
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.instruction, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  if (step.lineName != null)
                    Text("Line: ${step.lineName}", style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text("${step.duration} (${step.distance})", style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final StepTravelMode mode;
  final bool isFirst;
  final bool isLast;

  _TimelinePainter({required this.mode, this.isFirst = false, this.isLast = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 3;
    final centerX = size.width / 2;

    // Determine start and end points for the line
    final double startY = isFirst ? size.height / 2 : 0;
    final double endY = isLast ? size.height / 2 : size.height;

    // Draw line based on travel mode
    if (mode == StepTravelMode.walking) {
      paint.color = Colors.grey;
      const double dashHeight = 5;
      const double dashSpace = 4;
      double currentY = startY;
      while (currentY < endY) {
        canvas.drawLine(Offset(centerX, currentY), Offset(centerX, currentY + dashHeight), paint);
        currentY += dashHeight + dashSpace;
      }
    } else { // Transit mode
      paint.color = Colors.blue;
      canvas.drawLine(Offset(centerX, startY), Offset(centerX, endY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) => false;
}

class _ConnectingTimelinePainter extends CustomPainter {
  final StepTravelMode mode;
  _ConnectingTimelinePainter({required this.mode});

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final paint = Paint()..strokeWidth = 3;
    final dotRadius = 2.5;

    if (mode == StepTravelMode.transit) {
      paint.color = Colors.blueAccent;
      canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint);
    } else { // Walking mode
      paint.color = Colors.grey;
      const double dotSpacing = 12.0;
      double currentY = 0;
      while (currentY < size.height) {
        if (currentY + dotRadius < size.height) {
          canvas.drawCircle(Offset(size.width / 2, currentY + dotRadius), dotRadius, paint);
        }
        currentY += dotSpacing;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}