import 'dart:async';
import 'dart:convert';
//import 'dart:io';
import 'dart:math' show cos, sqrt, asin, atan2, sin, pi, min, max, pow;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
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

enum StepTravelMode { walking, transit, driving, bicycling }

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
  final String? vehicleType;
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

  late FlutterTts _flutterTts;
  bool _navigationStarted = false;
  int? _currentSpeedLimit;
  Timer? _speedLimitTimer;
  final Stopwatch _navigationStopwatch = Stopwatch();
  double _currentSpeed = 0.0;
  double _currentZoom = 18.0;
  double _currentUserRotation = 0.0;

  int _fastestRouteIndex = 0;
  int _scenicRouteIndex = 0;

  bool _isRecalculating = false;

  AnimationController? _progressAnimationController;
  Animation<double>? _progressAnimation;

  int _offRouteStrikeCount = 0;
  static const int _requiredStrikesForReroute = 3;
  bool _isCameraLocked = true;

  String _getDirectionAbbreviation(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('northwest') || lower.contains('north-west')) return 'NW';
    if (lower.contains('northeast') || lower.contains('north-east')) return 'NE';
    if (lower.contains('southwest') || lower.contains('south-west')) return 'SW';
    if (lower.contains('southeast') || lower.contains('south-east')) return 'SE';
    if (lower.contains('north')) return 'N';
    if (lower.contains('south')) return 'S';
    if (lower.contains('east')) return 'E';
    if (lower.contains('west')) return 'W';
    return '';
  }

  @override
  void initState() {
    super.initState();
    _destination = widget.destination;
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _initializeDirections();
    _createStopIcons();
    _loadMutePreference();
    _initTts();
    themeNotifier.addListener(_updateMapStyle);
  }

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

  Future<void> _speak(String text) async {
    if (!_isMuted && text.isNotEmpty) {
      await _flutterTts.speak(text.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' '));
    }
  }

  void _updateMapStyle() {
    if (!_isMapControllerInitialized || !mounted) return;
    final themeMode = themeNotifier.value;
    final isDarkMode = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    if (isDarkMode) {
      rootBundle.loadString('assets/map_style_dark.json').then((style) {
        if (mounted) mapController.setMapStyle(style);
      });
    } else {
      mapController.setMapStyle(null);
    }
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      LoadingOverlay.show(context);

      try {
        final originLatLng = widget.originCoordinates;
        _lastLocation = originLatLng;

        final originAddress = await _reverseGeocode(originLatLng);

        if (!mounted) {
          LoadingOverlay.hide();
          return;
        }

        setState(() {
          _origin = PlaceDetails(
            placeId: 'user_location',
            name: "Current Location",
            address: originAddress,
            coordinates: originLatLng,
          );
        });

        await _getDirections();

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

        if (_travelMode == TravelMode.transit) {
          final List<FullTransitRoute> parsedTransitRoutes = [];
          for (var route in data['routes']) {
            final leg = route['legs'][0];
            final List<RouteStep> steps = [];

            for (var step in leg['steps']) {
              final String mode = step['travel_mode'];
              StepTravelMode stepMode = StepTravelMode.walking;
              String? line;
              String? vehicle;

              if (mode == 'TRANSIT') {
                stepMode = StepTravelMode.transit;
                if (step['transit_details'] != null) {
                  line = step['transit_details']['line']['short_name'] ??
                      step['transit_details']['line']['name'];
                  vehicle = step['transit_details']['line']['vehicle']['type'];
                }
              }

              steps.add(RouteStep(
                instruction: _stripHtmlIfNeeded(step['html_instructions']),
                distance: step['distance']['text'],
                duration: step['duration']['text'],
                travelMode: stepMode,
                lineName: line,
                vehicleType: vehicle,
                polylinePoints: PolylinePoints()
                    .decodePolyline(step['polyline']['points'])
                    .map((p) => LatLng(p.latitude, p.longitude))
                    .toList(),
              ));
            }

            parsedTransitRoutes.add(FullTransitRoute(
                duration: leg['duration']['text'],
                distance: leg['distance']['text'],
                steps: steps
            ));
          }
          _transitRoutes = parsedTransitRoutes;
        }

        if (mounted) {
          setState(() {
            _routes = fetchedRoutes;
            _processRoutes();
            if (_travelMode != TravelMode.transit) {
              _transitRoutes = [];
            }
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
        if(mounted) {
          setState(() {
            _routes = [];
            _transitRoutes = [];
          });
        }
      }
      _updateMarkersAndPolylines();
    } catch (e) {
      debugPrint("Error fetching directions: $e");
      if(mounted) {
        setState(() {
          _routes = [];
          _transitRoutes = [];
        });
      }
    } finally {
      LoadingOverlay.hide();
      if (mounted) {
        _isRecalculating = false;
        _updateRouteDifferenceMarkers();
      }
    }
  }

  void _processRoutes() {
    if (_routes.isEmpty) return;
    _fastestRouteIndex = 0;
    _scenicRouteIndex = 0;
    double maxCurviness = 0;
    for (int i = 0; i < _routes.length; i++) {
      if (_routes[i].curviness > maxCurviness) {
        maxCurviness = _routes[i].curviness;
        _scenicRouteIndex = i;
      }
    }
    _selectedRouteIndex = _routeType == RouteType.fastest ? _fastestRouteIndex : _scenicRouteIndex;
  }

  Set<Polyline> _createTrafficPolylines(List<dynamic> steps) {
    final Set<Polyline> polylines = {};
    if (steps.isEmpty) return polylines;

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color baseColor = isDarkMode ? Colors.greenAccent : Colors.blueAccent;

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final duration = step['duration']['value'];
      final durationInTraffic = step['duration_in_traffic']?['value'] ?? duration;
      final delay = durationInTraffic - duration;

      Color color = baseColor;

      if (delay > 120) {
        color = Colors.red.shade800;
      } else if (delay > 30) {
        color = Colors.orange.shade700;
      }

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
        bearingChange = 360 - bearingChange;
      }
      totalBearingChange += bearingChange;
    }
    return totalBearingChange;
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final double startLat = start.latitude * pi / 180;
    final double startLng = start.longitude * pi / 180;
    final double endLat = end.latitude * pi / 180;
    final double endLng = end.longitude * pi / 180;

    double dLng = endLng - startLng;
    double y = sin(dLng) * cos(endLat);
    double x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(dLng);

    double bearing = atan2(y, x) * 180 / pi;
    return (bearing + 360) % 360;
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

  void _updateMarkersAndPolylines() {
    if (!mounted || _origin == null || _destination == null) return;

    final bool isTransit = _travelMode == TravelMode.transit;

    final newMarkers = <Marker>{
      Marker(markerId: const MarkerId('origin'), position: _origin!.coordinates, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
      Marker(markerId: const MarkerId('destination'), position: _destination!.coordinates),
    };
    Set<Polyline> newPolylines = {};

    final bool hasRoutes = (_travelMode != TravelMode.transit && _routes.isNotEmpty) ||
        (_travelMode == TravelMode.transit && _transitRoutes.isNotEmpty);

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color routeColor = isDarkMode ? Colors.greenAccent : Colors.blueAccent;

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
            color: routeColor,
            width: 6,
            patterns: [PatternItem.dot, PatternItem.gap(10)],
          ));
          break;
        case TravelMode.bicycling:
          newPolylines.add(Polyline(
            polylineId: const PolylineId('route_cycling'),
            points: points,
            color: routeColor,
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
                color: step.travelMode == StepTravelMode.walking ? Colors.grey : routeColor,
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
    _updateMapStyle();
  }

  List<Widget> _buildNavigationUI() {
    return [
      _buildFuturisticTopCard(),
      _buildFuturisticBottomPanel(),
      _buildSpeedLimitIndicator(),

      Positioned(
        bottom: 150,
        right: 15,
        child: FloatingActionButton(
          mini: true,
          onPressed: _recenterCamera,
          child: const Icon(Icons.my_location),
        ),
      )
    ];
  }

  Set<Marker> _buildMarkers() {
    if (!_isNavigating) {
      return _markers.union(_routeDifferenceMarkers);
    }

    Set<Marker> displayMarkers = Set.from(_routeDifferenceMarkers);

    displayMarkers.addAll(_markers.where((m) => m.markerId.value != 'origin'));
    displayMarkers.addAll(_navigationMarkers);

    return displayMarkers;
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
              _currentZoom = position.zoom;
            },
            onCameraIdle: () {
              _updateNavigationMarkerIcon();
            },
            polylines: _polylines,
            markers: _buildMarkers(),
            onCameraMoveStarted: () {
              if (_isCameraLocked) {
                setState(() {
                  _isCameraLocked = false;
                });
              }
            },
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

  Future<void> _updateNavigationMarkerIcon() async {
    final double newSize = 110 + (_currentZoom - 12) * 20;
    final double clampedSize = newSize.clamp(110.0, 300.0);

    // Always use the dynamic arrow bitmap
    _navigationMarkerIcon = await _createDynamicMarkerBitmap(clampedSize);
    _updateNavigationMarkers();
  }

  Future<BitmapDescriptor> _createTransparentMarker() async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final ui.Image image = await recorder.endRecording().toImage(1, 1);
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  void _updateNavigationMarkers() {
    if (!mounted || _lastLocation == null || _navigationMarkerIcon == null) return;

    final Offset anchor = const Offset(0.5, 0.5);

    final marker = Marker(
      markerId: const MarkerId('navigation_user'),
      position: _lastLocation!,
      icon: _navigationMarkerIcon!,
      rotation: _currentUserRotation,
      anchor: anchor,
      flat: true,
      zIndex: 2.0,
    );

    setState(() {
      _navigationMarkers.clear();
      _navigationMarkers.add(marker);
    });
  }

  Widget _buildFuturisticTopCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String directionAbbr = _getDirectionAbbreviation(_navInstruction);

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 15,
      right: 15,
      child: GlassmorphicContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                          _navManeuverIcon,
                          color: Colors.white,
                          size: 42
                      ),
                    ),
                    if (directionAbbr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        directionAbbr,
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ]
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _navInstruction,
                        textAlign: TextAlign.left,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                          _distanceToNextManeuver,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 18,
                              fontWeight: FontWeight.w500
                          )
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AnimatedBuilder(
                animation: _progressAnimationController!,
                builder: (context, child) {
                  return LinearProgressIndicator(
                    value: _progressAnimation?.value ?? _progressToNextManeuver,
                    minHeight: 6,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFuturisticBottomPanel() {
    final arrivalTime = DateTime.now().add(Duration(seconds: _routes[_selectedRouteIndex].durationValue));
    final timeFormat = DateFormat.jm();

    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 20,
      left: 15,
      right: 15,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
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
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          Text(
                            _navEta,
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            " · $_navDistance",
                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                    onPressed: () {
                      setState(() => _isMuted = !_isMuted);
                      _saveMutePreference(_isMuted);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          GestureDetector(
            onTap: _stopNavigation,
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.close, color: Colors.white, size: 28),
                  Text("EXIT", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransitRouteOption(int index) {
    final route = _transitRoutes[index];
    final isSelected = _selectedRouteIndex == index;

    return GestureDetector(
      onTap: () => _onRouteTapped(index),
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.1) : Theme.of(context).cardColor,
          border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey.withOpacity(0.3),
              width: isSelected ? 2 : 1
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              route.duration,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: route.steps.map((step) {
                  return Row(
                    children: [
                      _buildStepPill(step),
                      if (step != route.steps.last)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepPill(RouteStep step) {
    if (step.travelMode == StepTravelMode.walking) {
      return const Icon(Icons.directions_walk, size: 32, color: Colors.grey);
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(getTransitIcon(step.vehicleType), size: 32, color: Colors.blue.shade800),
            if (step.lineName != null) ...[
              const SizedBox(width: 8),
              Text(
                step.lineName!,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                  fontSize: 16,
                ),
              ),
            ],
          ],
        ),
      );
    }
  }

  Widget _buildTransitPanel() {
    if (_transitRoutes.isEmpty) return const Center(child: Text("No transit routes found."));

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _transitRoutes.length,
      separatorBuilder: (ctx, i) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildTransitRouteOption(index);
      },
    );
  }

  Widget _buildRouteDetailsContent(ScrollController scrollController, FullTransitRoute route) {
    return ListView.builder(
      controller: scrollController,
      itemCount: route.steps.length,
      itemBuilder: (context, index) {
        final step = route.steps[index];
        final isFirst = index == 0;
        final isLast = index == route.steps.length - 1;
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
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(12))),
          ),
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
              Text("Start: ${timeFormat.format(now)}"),
              Text("Arrival: ${timeFormat.format(arrivalTime)}"),
            ],
          ),
          const SizedBox(height: 8),
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

  Future<BitmapDescriptor> _createCircleStopMarkerBitmap() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(pictureRecorder);
    final ui.Paint paint = ui.Paint()..color = Colors.white;
    final ui.Paint borderPaint = ui.Paint()
      ..color = Colors.grey.shade600
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke;
    final ui.Paint innerPaint = ui.Paint()..color = Colors.grey.shade400;

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
    WakelockPlus.enable();
    setState(() {
      _isNavigating = true;
      _navigationStarted = true;
    });
    _navigationStopwatch.start();
    _speak(_navInstruction);
    _listenToLocationForNavigation();

    _speedLimitTimer?.cancel();
    _speedLimitTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_lastLocation != null) {
        _getSpeedLimit(_lastLocation!);
      }
    });
  }

  void _stopNavigation() {
    WakelockPlus.disable();
    _navigationLocationSubscription?.cancel();
    _speedLimitTimer?.cancel();
    NotificationService().cancelNavigationNotification();
    _navigationStopwatch.stop();
    _navigationStopwatch.reset();
    setState(() {
      _isNavigating = false;
      _navigationStarted = false;
      _currentSpeedLimit = null;
    });
    _updateMarkersAndPolylines();
  }

  void _recenterCamera() {
    setState(() {
      _isCameraLocked = true; // Lock the camera again
    });

    if (_lastLocation != null && _isMapControllerInitialized) {
      mapController.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _lastLocation!,
          zoom: 18,
          tilt: 50.0,
          bearing: _currentUserRotation,
        ),
      ));
    }
  }

  double _calculateDistanceAlongPolyline(LatLng userLoc, String encodedPolyline) {
    List<LatLng> polyline = PolylinePoints()
        .decodePolyline(encodedPolyline)
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    if (polyline.isEmpty) return 0.0;

    int closestIndex = 0;
    double minDistance = double.infinity;

    for(int i=0; i<polyline.length; i++) {
      double d = _calculateDistance(userLoc.latitude, userLoc.longitude, polyline[i].latitude, polyline[i].longitude);
      if(d < minDistance) {
        minDistance = d;
        closestIndex = i;
      }
    }

    double distanceRemaining = 0.0;
    for(int i=closestIndex; i<polyline.length-1; i++) {
      distanceRemaining += _calculateDistance(
          polyline[i].latitude, polyline[i].longitude,
          polyline[i+1].latitude, polyline[i+1].longitude
      );
    }
    return distanceRemaining;
  }

  void _listenToLocationForNavigation() {
    final locationService = Location();
    _navigationLocationSubscription =
        locationService.onLocationChanged.listen((LocationData currentLocation) async{
          if (!mounted || !_isNavigating) return;

          final newLatLng =
          LatLng(currentLocation.latitude!, currentLocation.longitude!);
          _lastLocation = newLatLng;
          final newRotation = currentLocation.heading ?? 0.0;
          _currentUserRotation = newRotation;

          if (_isCameraLocked && !_isRecalculating) {
            mapController.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                target: newLatLng,
                zoom: 18,
                tilt: 50.0,
                bearing: newRotation,
              ),
            ));
          }

          if (!_isRecalculating) {
            bool isCurrentlyOffRoute = _isOffRoute(
                newLatLng, _routes[_selectedRouteIndex].polylinePoints);
            if (isCurrentlyOffRoute) {
              _offRouteStrikeCount++;
            } else {
              _offRouteStrikeCount = 0;
            }

            if (_offRouteStrikeCount >= _requiredStrikesForReroute) {
              _offRouteStrikeCount = 0;
              _recalculateRoute(newLatLng);
              return;
            }
          }
          _updateNavigationMarkers();

          if (!_isRecalculating) {
            _updateNavigationState(newLatLng);
          }
        });
  }

  Future<BitmapDescriptor> _createDynamicMarkerBitmap(double size) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final double halfSize = size / 2;

    // 1. Draw the "Glow" (Shadow)
    final Paint glowPaint = Paint()
      ..color = Colors.blue.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);

    canvas.drawCircle(Offset(halfSize, halfSize), size / 3, glowPaint);

    // 2. Draw the Arrow (Path)
    final Paint arrowPaint = Paint()
      ..color = Colors.blue.shade700
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path();
    // Tip of the arrow (Top Center)
    path.moveTo(halfSize, size * 0.1);
    // Bottom Right
    path.lineTo(size * 0.85, size * 0.85);
    // Bottom Center (Indent to make it a chevron)
    path.lineTo(halfSize, size * 0.7);
    // Bottom Left
    path.lineTo(size * 0.15, size * 0.85);
    path.close();

    canvas.drawPath(path, arrowPaint);
    canvas.drawPath(path, borderPaint);

    final img = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

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

  double _distanceToLineSegment(LatLng p, LatLng v, LatLng w) {
    double l2 = _calculateDistance(v.latitude, v.longitude, w.latitude, w.longitude);
    l2 = l2 * l2;
    if (l2 == 0.0) return _calculateDistance(p.latitude, p.longitude, v.latitude, v.longitude);
    double t = ((p.latitude - v.latitude) * (w.latitude - v.latitude) + (p.longitude - v.longitude) * (w.longitude - v.longitude)) / l2;
    t = max(0, min(1, t));
    return _calculateDistance(p.latitude, p.longitude, v.latitude + t * (w.latitude - v.latitude), v.longitude + t * (w.longitude - v.longitude));
  }

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
    final totalStepDistance = currentStep['distance']['value'].toDouble();

    // --- FIX: Use projected distance along path instead of air distance ---
    final distanceInMeters = _calculateDistanceAlongPolyline(
        currentUserPosition,
        currentStep['polyline']['points']
    );

    if (distanceInMeters < 30 && _currentStepIndex < _navSteps.length - 1) {
      setState(() {
        _currentStepIndex++;
        _updateNavInstruction();
      });
    }

    final newProgress = (totalStepDistance - distanceInMeters) / totalStepDistance;
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(_navManeuverIcon, color: Colors.white, size: 48),
              const SizedBox(height: 8),
              Text(
                _navInstruction,
                textAlign: TextAlign.center,
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
                        : getTransitIcon(step.vehicleType),
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