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
import '../../models/trip_history_model.dart';
import '../../services/database_service.dart';
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

  bool _show3DCar = false;
  double _carScreenX = 0;
  double _carScreenY = 0;
  String _selectedVehicleAsset = 'arrow';
  String? _selectedVehicleModel;
  final Map<String, String> _localModelPaths = {};

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

  AnimationController? _markerAnimationController;
  Animation<LatLng>? _positionAnimation;
  Animation<double>? _rotationAnimation;
  LatLng? _previousLocation;
  double _previousRotation = 0.0;
  double _lastCameraBearing = 0.0;
  bool _isMovingCameraProgrammatically = false;

  int _fastestRouteIndex = 0;
  int _scenicRouteIndex = 0;

  bool _isRecalculating = false;

  AnimationController? _progressAnimationController;
  Animation<double>? _progressAnimation;

  int _offRouteStrikeCount = 0;
  static const int _requiredStrikesForReroute = 3;
  bool _isCameraLocked = true;

  DateTime? _tripStartTime;
  List<LatLng> _tripPathRecorded = [];
  Timer? _offRouteCheckTimer;

  int _browsingStepIndex = -1;

  bool _isArrived = false;
  Timer? _arrivalTimer;
  int _arrivalCountdown = 10;
  DateTime? _actualTripStartTime;
  String _originalEtaText = ""; // To compare with actual
  double _totalDistanceTraveledMeters = 0.0; // Track actual distance driven
  final List<double> _speedSamples = []; // To calc average speed
  Timer? _autoCompleteTimer;

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
    _lastLocation = widget.originCoordinates;
    _previousLocation = widget.originCoordinates;
    _markerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _markerAnimationController?.addListener(() {
      if (mounted) setState(() {});
    });
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
    _arrivalTimer?.cancel();
    _autoCompleteTimer?.cancel();
    _offRouteCheckTimer?.cancel();
    _navigationLocationSubscription?.cancel();
    _flutterTts.stop();
    _speedLimitTimer?.cancel();
    _progressAnimationController?.dispose();
    _markerAnimationController?.dispose();
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

    if (_origin!.placeId == 'user_location') {
      try {
        final location = Location();
        final hasPermission = await location.hasPermission();
        if (hasPermission == PermissionStatus.granted) {
          final locData = await location.getLocation();
          if (locData.latitude != null && locData.longitude != null) {
            final currentLatLng = LatLng(locData.latitude!, locData.longitude!);
            // Quietly update the origin coordinate
            _origin = PlaceDetails(
                placeId: 'user_location',
                name: "Current Location",
                address: "Your Location", // Or reverse geocode again if you want
                coordinates: currentLatLng
            );
            _lastLocation = currentLatLng; // Sync tracking
          }
        }
      } catch (e) {
        debugPrint("Could not refresh live location: $e");
      }
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
    final Color baseColor =
    isDarkMode ? Colors.greenAccent : Colors.blueAccent;

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final duration = step['duration']['value'];
      final durationInTraffic =
          step['duration_in_traffic']?['value'] ?? duration;
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
        color: color, // Use the traffic color determined above
        width: 19, // Width of polyline.
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 1, // IMPORTANT: Ensure this is above the grey alternative routes
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
      Marker(
          markerId: const MarkerId('origin'),
          position: _origin!.coordinates,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
      Marker(
          markerId: const MarkerId('destination'),
          position: _destination!.coordinates),
    };

    if (_markerAnimationController != null) {
      LatLng pos = _positionAnimation?.value ?? _lastLocation ?? widget.originCoordinates;
      double rot = _rotationAnimation?.value ?? _currentUserRotation;

      // Normalize rotation for display (0-360)
      rot = (rot % 360 + 360) % 360;

      _markers.add(Marker(
        markerId: const MarkerId('user_navigation_marker'),
        position: pos,
        rotation: rot,
        icon: _navigationMarkerIcon ?? BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        zIndex: 100,
      ));
    }

    Set<Polyline> newPolylines = {};

    final bool hasRoutes =
        (_travelMode != TravelMode.transit && _routes.isNotEmpty) ||
            (_travelMode == TravelMode.transit && _transitRoutes.isNotEmpty);

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color routeColor =
    isDarkMode ? Colors.greenAccent : Colors.blueAccent;
    final Color alternativeRouteColor = Colors.grey;

    if (hasRoutes) {
      if (!isTransit) {
        for (int i = 0; i < _routes.length; i++) {
          if (i == _selectedRouteIndex) continue;

          newPolylines.add(Polyline(
            polylineId: PolylineId('route_alt_$i'),
            points: _routes[i].polylinePoints,
            color: alternativeRouteColor,
            width: 9,
            zIndex: 0,
            consumeTapEvents: true,
            onTap: () => _onRouteTapped(i),
          ));
        }

        List<LatLng> points = _routes[_selectedRouteIndex].polylinePoints;
        switch (_travelMode) {
          case TravelMode.driving:
            newPolylines.addAll(
                _createTrafficPolylines(_routes[_selectedRouteIndex].steps));
            break;
          case TravelMode.walking:
            newPolylines.add(Polyline(
              polylineId: const PolylineId('route_walking'),
              points: points,
              color: routeColor,
              width: 6,
              zIndex: 1, // Draw on top
              patterns: [PatternItem.dot, PatternItem.gap(10)],
            ));
            break;
          case TravelMode.bicycling:
            newPolylines.add(Polyline(
              polylineId: const PolylineId('route_cycling'),
              points: points,
              color: routeColor,
              width: 6,
              zIndex: 1, // Draw on top
              patterns: [PatternItem.dash(20), PatternItem.gap(15)],
            ));
            break;
          default:
            break;
        }
      } else {
        for (int i = 0; i < _transitRoutes.length; i++) {
          if (i == _selectedRouteIndex) continue;
          for (var step in _transitRoutes[i].steps) {
            newPolylines.add(Polyline(
              polylineId: PolylineId('transit_alt_${i}_step_${step.hashCode}'),
              points: step.polylinePoints,
              color: alternativeRouteColor.withOpacity(0.7),
              width: 5,
              zIndex: 0,
              consumeTapEvents: true,
              onTap: () => _onRouteTapped(i),
            ));
          }
        }
        if (_detailedRoute != null) {
          for (var step in _detailedRoute!.steps) {
            newPolylines.add(Polyline(
              polylineId: PolylineId('transit_step_${step.hashCode}'),
              points: step.polylinePoints,
              color: step.travelMode == StepTravelMode.walking
                  ? Colors.grey
                  : routeColor,
              width: 6,
              zIndex: 1, // On top
              patterns: step.travelMode == StepTravelMode.walking
                  ? [PatternItem.dot, PatternItem.gap(10)]
                  : [],
            ));
          }
        }
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
          ? _transitRoutes[_selectedRouteIndex]
          .steps
          .expand((s) => s.polylinePoints)
          .toList()
          : _routes[_selectedRouteIndex].polylinePoints;

      if (fullRouteForBounds.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final bounds = _boundsFromLatLngList(fullRouteForBounds);
            mapController
                .animateCamera(CameraUpdate.newLatLngBounds(bounds, 80.0));
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
      // Top Card - Animate Opacity to hide when arrived
      AnimatedOpacity(
        opacity: _isArrived ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 500),
        child: IgnorePointer(
          ignoring: _isArrived, // Disable touches when hidden
          child: _buildFuturisticTopCard(),
        ),
      ),

      // Bottom Panel - Hide standard bottom panel when arrived
      if (!_isArrived) _buildFuturisticBottomPanel(),

      if (!_isArrived) _buildSpeedLimitIndicator(),

      // Camera Lock Button - Hide when arrived
      if (!_isArrived)
        Positioned(
          bottom: 150,
          right: 15,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: _isCameraLocked ? Colors.blue : Colors.white,
            foregroundColor: _isCameraLocked ? Colors.white : Colors.grey,
            onPressed: _toggleCameraLock,
            child: Icon(_isCameraLocked ? Icons.navigation : Icons.my_location),
          ),
        ),

      // --- NEW: Arrival Summary Panel ---
      if (_isArrived) _buildArrivalSummaryPanel(),
    ];
  }

  Widget _buildArrivalSummaryPanel() {
    final now = DateTime.now();
    final duration = _navigationStopwatch.elapsed;
    String timeTaken = "${duration.inMinutes} min ${duration.inSeconds % 60} sec";

    // Calculate Average Speed
    String avgSpeedText = "N/A";
    if (_speedSamples.isNotEmpty) {
      double sumSpeed = _speedSamples.reduce((a, b) => a + b);
      double avgMps = sumSpeed / _speedSamples.length;
      double avgKmph = avgMps * 3.6; // Convert m/s to km/h
      avgSpeedText = "${avgKmph.toStringAsFixed(1)} km/h";
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              spreadRadius: 5,
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Trip Completed", style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.green)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber)
                  ),
                  child: Text("Auto-closing in ${_arrivalCountdown}s", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                )
              ],
            ),
            const SizedBox(height: 20),

            // Time Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("ACTUAL TIME", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    Text(timeTaken, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("ESTIMATED", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    Text(_originalEtaText, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Clock Times
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Started: ${DateFormat.jm().format(_actualTripStartTime ?? now)}", style: const TextStyle(fontWeight: FontWeight.w500)),
                Text("Arrived: ${DateFormat.jm().format(now)}", style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 16),

            // Speed Stat
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.speed, color: Colors.blue),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Average Speed", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      Text(avgSpeedText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Complete Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _finalizeTrip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("COMPLETE TRIP", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Set<Marker> _buildMarkers() {
    if (!_isNavigating) {
      return _markers.union(_routeDifferenceMarkers);
    }

    Set<Marker> displayMarkers = Set.from(_routeDifferenceMarkers);
    displayMarkers.addAll(_markers.where((m) => m.markerId.value != 'origin'));

    if (_navigationMarkerIcon != null) {
      final LatLng markerPosition = _positionAnimation?.value ?? _lastLocation ?? const LatLng(0,0);
      final double markerRotation = _rotationAnimation?.value ?? _currentUserRotation;

      displayMarkers.add(
        Marker(
          markerId: const MarkerId('navigation_user'),
          position: markerPosition,
          icon: _navigationMarkerIcon!,
          rotation: markerRotation,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          zIndex: 2.0,
        ),
      );
    }

    return displayMarkers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Wrap GoogleMap in AnimatedBuilder to rebuild on every animation frame
          AnimatedBuilder(
              animation: _markerAnimationController!,
              builder: (context, child) {
                return GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(target: widget.destination.coordinates, zoom: 12),
                  onCameraMove: (CameraPosition position) {
                    _currentZoom = position.zoom;
                  },
                  // --- MODIFIED: Logic to ignore programmatic moves ---
                  onCameraMoveStarted: () {
                    if (!_isMovingCameraProgrammatically) {
                      setState(() {
                        _isCameraLocked = false;
                      });
                    }
                  },
                  // ----------------------------------------------------
                  onCameraIdle: () {
                    _updateNavigationMarkerIcon();
                  },
                  polylines: _polylines,
                  markers: _buildMarkers(), // This now returns interpolated position
                  zoomControlsEnabled: false,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  padding: EdgeInsets.only(
                      top: _isNavigating ? 150 : 120,
                      bottom: _isNavigating ? 100 : MediaQuery.of(context).size.height * 0.2
                  ),
                );
              }
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

    _navigationMarkerIcon = await _createDynamicMarkerBitmap(clampedSize);
  }

  Future<BitmapDescriptor> _createTransparentMarker() async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final ui.Image image = await recorder.endRecording().toImage(1, 1);
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  void _toggleCameraLock() {
    setState(() {
      _isCameraLocked = !_isCameraLocked;
    });
    if (_isCameraLocked && _lastLocation != null) {
      _isMovingCameraProgrammatically = true;
      mapController.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _lastLocation!,
          zoom: 18,
          tilt: 50.0,
          bearing: _currentUserRotation,
        ),
      )).then((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _isMovingCameraProgrammatically = false;
        });
      });
    }
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
    // 1. Determine which step to show (Live vs Browsing)
    final int displayIndex =
    _browsingStepIndex != -1 ? _browsingStepIndex : _currentStepIndex;

    // Safety Check
    if (_navSteps.isEmpty || displayIndex >= _navSteps.length) {
      return const SizedBox.shrink();
    }

    final currentStep = _navSteps[displayIndex];

    // 2. Parse Instruction Text (Simplified) based on the specific step
    String fullInstruction =
    _stripHtmlIfNeeded(currentStep['html_instructions']);
    String simplifiedInstruction = fullInstruction;
    RegExp exp = RegExp(r'\b(on|onto)\s+(.*)', caseSensitive: false);
    Match? match = exp.firstMatch(fullInstruction);
    if (match != null && match.groupCount >= 2) {
      simplifiedInstruction = match.group(2) ?? fullInstruction;
    }

    // 3. Get Icon & Abbreviation
    final IconData icon = _getManeuverIcon(currentStep['maneuver']);
    final String directionAbbr =
    _getDirectionAbbreviation(simplifiedInstruction);

    // 4. Get Distance
    // If viewing the current live step, show remaining distance.
    // If browsing other steps, show the total distance of that step.
    String displayDistance;
    if (displayIndex == _currentStepIndex) {
      displayDistance = _distanceToNextManeuver;
    } else {
      displayDistance = currentStep['distance']['text'];
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 15,
      right: 15,
      child: GestureDetector(
        // --- SWIPE GESTURES ---
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! < 0) {
            // Swipe Left -> Next Turn
            _cycleStep(1);
          } else if (details.primaryVelocity! > 0) {
            // Swipe Right -> Previous Turn
            _cycleStep(-1);
          }
        },
        // --- TAP TO RESET ---
        onTap: () {
          setState(() {
            _browsingStepIndex = -1; // Reset to live tracking
          });
          _recenterCamera(); // Snap camera back to user
        },
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
                        child:
                        Icon(icon, color: Colors.white, size: 42),
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
                        // Browsing Indicator (Optional, helpful context)
                        if (_browsingStepIndex != -1)
                          Text(
                            "PREVIEWING STEP ${displayIndex + 1} OF ${_navSteps.length}",
                            style: TextStyle(
                                color: Colors.amber.withOpacity(0.8),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0),
                          ),
                        Text(
                          simplifiedInstruction,
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
                        Text(displayDistance,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 18,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Only show progress bar if we are on the current live step
              if (displayIndex == _currentStepIndex)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedBuilder(
                    animation: _progressAnimationController!,
                    builder: (context, child) {
                      return LinearProgressIndicator(
                        value: _progressAnimation?.value ??
                            _progressToNextManeuver,
                        minHeight: 6,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _cycleStep(int delta) {
    setState(() {
      // If we are currently "live" (index -1), start browsing from the current step
      if (_browsingStepIndex == -1) {
        _browsingStepIndex = _currentStepIndex;
      }

      int newIndex = _browsingStepIndex + delta;

      // Clamp to bounds
      if (newIndex < 0) newIndex = 0;
      if (newIndex >= _navSteps.length) newIndex = _navSteps.length - 1;

      _browsingStepIndex = newIndex;
    });
  }
  Widget _buildFuturisticBottomPanel() {
    // FIX: Calculate Arrival Time based on Remaining Time (not total trip time)
    final totalDurationSeconds = _routes[_selectedRouteIndex].durationValue;
    final elapsedSeconds = _navigationStopwatch.elapsed.inSeconds;
    final remainingSeconds = max(0, totalDurationSeconds - elapsedSeconds);

    // Add REMAINING time to current time
    final arrivalTime = DateTime.now().add(Duration(seconds: remainingSeconds));
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
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          Text(
                            _navEta,
                            style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            " · $_navDistance",
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 16),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white),
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
                  ]),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.close, color: Colors.white, size: 28),
                  Text("EXIT",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold))
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

  void _startNavigation() async {
    if (_routes.isEmpty) return;
    await _updateNavigationMarkerIcon();
    WakelockPlus.enable();

    _tripStartTime = DateTime.now();
    _actualTripStartTime = DateTime.now(); // Ensure this is set
    _tripPathRecorded = [];
    _speedSamples.clear();
    _totalDistanceTraveledMeters = 0.0;
    _originalEtaText = _routes[_selectedRouteIndex].duration; // Capture original estimate
    _offRouteStrikeCount = 0;
    _isArrived = false; // Reset arrival state
    _arrivalCountdown = 10; // Reset timer

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

    _startOffRouteChecker();
  }

  void _startOffRouteChecker() {
    _offRouteCheckTimer?.cancel();
    _offRouteCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_isNavigating && !_isRecalculating && _lastLocation != null) {
        _checkIfOffRoute(_lastLocation!);
      }
    });
  }

  void _stopNavigation() async {
    // Cancel the new timer
    _arrivalTimer?.cancel();
    _arrivalCountdown = 10;

    WakelockPlus.disable();
    _navigationLocationSubscription?.cancel();
    _speedLimitTimer?.cancel();
    _offRouteCheckTimer?.cancel();
    NotificationService().cancelNavigationNotification();
    _navigationStopwatch.stop();
    _navigationStopwatch.reset();

    // Note: The saving logic was moved to _finalizeTrip, so we just clean up UI here

    if (mounted) {
      setState(() {
        _isNavigating = false;
        _navigationStarted = false;
        _currentSpeedLimit = null;
        _isArrived = false; // Reset
      });
      _updateMarkersAndPolylines();
    }
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
        locationService.onLocationChanged.listen((LocationData currentLocation) async {
          if (!mounted || !_isNavigating) return;

          final newLatLng = LatLng(currentLocation.latitude!, currentLocation.longitude!);

          if (_lastLocation != null) {
            double dist = _calculateDistance(_lastLocation!.latitude, _lastLocation!.longitude, newLatLng.latitude, newLatLng.longitude);
            if (dist < 100) {
              _totalDistanceTraveledMeters += dist;
              _tripPathRecorded.add(newLatLng);
            }
          }
          if (currentLocation.speed != null && currentLocation.speed! > 0) {
            _speedSamples.add(currentLocation.speed!);
          }
          _lastLocation = newLatLng;
          final newRotation = currentLocation.heading ?? 0.0;
          _currentUserRotation = newRotation;

          if (_destination != null) {
            double distToDest = _calculateDistance(
                newLatLng.latitude, newLatLng.longitude,
                _destination!.coordinates.latitude, _destination!.coordinates.longitude
            );

            // Trigger Arrival if < 16 meters
            if (distToDest < 16.0 && !_isArrived) {
              _onArrivalDetected();
            }
            // Go back to navigation if user moves away (> 25 meters hysteresis)
            else if (distToDest > 25.0 && _isArrived) {
              _resumeNavigationFromArrival();
            }
          }

          if (!_isRecalculating) {
            double targetZoom = 17.5;
            double targetTilt = 50.0;
            double lookAheadDistance = 0.0005; // Roughly 50m ahead (in degrees) to keep car at bottom

            if (_navSteps.isNotEmpty && _currentStepIndex < _navSteps.length) {
              final currentStep = _navSteps[_currentStepIndex];
              double distToTurn = _calculateDistanceAlongPolyline(newLatLng, currentStep['polyline']['points']);

              if (distToTurn < 100) {
                double ratio = (100 - distToTurn) / 100; // 0.0 to 1.0
                targetZoom = 18.0 + (2.0 * ratio); // Max zoom 20.0

                targetTilt = 50.0 - (20.0 * ratio); // Tilts down to 30.0 at the turn

                lookAheadDistance = 0.0005 * (1 - ratio);
              }
            }
            double headingRad = newRotation * (pi / 180.0);
            double targetLat = newLatLng.latitude + (lookAheadDistance * cos(headingRad));
            double targetLng = newLatLng.longitude + (lookAheadDistance * sin(headingRad));

            mapController.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(targetLat, targetLng), // Look ahead point
                zoom: targetZoom,                     // Dynamic Zoom
                tilt: targetTilt,                     // Dynamic Tilt
                bearing: newRotation,
              ),
            ));
            if (_show3DCar && _isMapControllerInitialized) {
              try {
                ScreenCoordinate screenPos = await mapController.getScreenCoordinate(newLatLng);
                setState(() {
                  _carScreenX = screenPos.x.toDouble();
                  _carScreenY = screenPos.y.toDouble();
                });
              } catch (e) {
                print("Error projecting car: $e");
              }
            }

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
            _updateNavigationState(newLatLng, newRotation);
          }
        });
  }
  void _checkIfOffRoute(LatLng userPosition) {
    // Use a looser threshold (e.g., 60-80 meters)
    bool isCurrentlyOffRoute = _isOffRoute(userPosition, _routes[_selectedRouteIndex].polylinePoints);

    if (isCurrentlyOffRoute) {
      _offRouteStrikeCount++;
      print("Off route strike: $_offRouteStrikeCount");
    } else {
      _offRouteStrikeCount = 0;
    }

    if (_offRouteStrikeCount >= _requiredStrikesForReroute) {
      _offRouteStrikeCount = 0;
      print("REROUTING NOW...");
      _recalculateRoute(userPosition);
    }
  }

  void _onArrivalDetected() {
    setState(() {
      _isArrived = true;
      _arrivalCountdown = 10;
    });

    // Speak completion message
    _speak("You have arrived at your destination.");

    // Start Auto-Complete Timer
    _arrivalTimer?.cancel();
    _arrivalTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _arrivalCountdown--;
      });

      if (_arrivalCountdown <= 0) {
        timer.cancel();
        _finalizeTrip(); // Auto-complete
      }
    });
  }

  void _resumeNavigationFromArrival() {
    // User moved away from destination without finishing
    _arrivalTimer?.cancel();
    setState(() {
      _isArrived = false;
      _arrivalCountdown = 10;
    });
    _speak("Resuming navigation.");
  }

  Future<void> _finalizeTrip() async {
    _arrivalTimer?.cancel();
    final endTime = DateTime.now();
    final durationSecs = _navigationStopwatch.elapsed.inSeconds;

    // Save to DB
    if (_origin != null && _destination != null) {
      // Calculate formatted distance driven
      String actualDistText;
      if (_totalDistanceTraveledMeters < 1000) {
        actualDistText = "${_totalDistanceTraveledMeters.toStringAsFixed(0)} m";
      } else {
        actualDistText = "${(_totalDistanceTraveledMeters / 1000).toStringAsFixed(1)} km";
      }

      final trip = TripHistory(
        startAddress: _origin!.address,
        endAddress: _destination!.address,
        startTime: _actualTripStartTime ?? DateTime.now(),
        endTime: endTime,
        durationSeconds: durationSecs,
        distanceText: actualDistText, // Use actual driven distance
        routePath: List.from(_tripPathRecorded),
      );

      await DatabaseService().insertTrip(trip);
      debugPrint("Trip Auto-Completed and Saved");
    }

    _stopNavigation();

    // Optional: Show a quick snackbar or dialog confirming save before popping
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Trip saved to history!")),
      );
      Navigator.of(context).pop(); // Exit Directions Screen
    }
  }

  Future<BitmapDescriptor> _createDynamicMarkerBitmap(double size) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double halfSize = size / 2;

    final Paint glowPaint = Paint()
      ..color = Colors.blue.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawCircle(Offset(halfSize, halfSize), size / 3, glowPaint);

    final Paint arrowPaint = Paint()
      ..color = Colors.blue.shade700
      ..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path();
    path.moveTo(halfSize, size * 0.1);
    path.lineTo(size * 0.85, size * 0.85);
    path.lineTo(halfSize, size * 0.7);
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
    double l2 = (w.latitude - v.latitude) * (w.latitude - v.latitude) +
        (w.longitude - v.longitude) * (w.longitude - v.longitude);
    if (l2 == 0.0) return _calculateDistance(p.latitude, p.longitude, v.latitude, v.longitude);
    double t = ((p.latitude - v.latitude) * (w.latitude - v.latitude) +
        (p.longitude - v.longitude) * (w.longitude - v.longitude)) / l2;
    t = max(0, min(1, t));

    double projectionLat = v.latitude + t * (w.latitude - v.latitude);
    double projectionLng = v.longitude + t * (w.longitude - v.longitude);
    return _calculateDistance(p.latitude, p.longitude, projectionLat, projectionLng);
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

  void _updateNavigationState(LatLng currentUserPosition, double heading) {
    if (_navSteps.isEmpty) return;

    if (_previousLocation == null) {
      setState(() {
        _lastLocation = currentUserPosition;
        _currentUserRotation = heading;
        _previousLocation = currentUserPosition;
        _previousRotation = heading;
      });
    } else {
      _markerAnimationController?.reset();

      // Animate Position
      _positionAnimation = LatLngTween(
          begin: _previousLocation!,
          end: currentUserPosition
      ).animate(CurvedAnimation(
        parent: _markerAnimationController!,
        curve: Curves.linear,
      ));

      double startRotation = _previousRotation;
      double endRotation = heading;

      double diff = endRotation - startRotation;
      if (diff > 180) endRotation -= 360;
      if (diff < -180) endRotation += 360;

      _rotationAnimation = Tween<double>(
          begin: startRotation,
          end: endRotation
      ).animate(CurvedAnimation(
        parent: _markerAnimationController!,
        curve: Curves.easeInOut,
      ));

      _markerAnimationController?.forward();

      _previousLocation = currentUserPosition;
      _previousRotation = heading;
    }

    if (_isCameraLocked && _isMapControllerInitialized) {
      double bearingToUse = _lastCameraBearing;

      double diff = (heading - _lastCameraBearing).abs();
      if (diff > 180) diff = 360 - diff;
      bool shouldUpdateBearing = diff > 10.0;

      if (_travelMode == TravelMode.driving) {
        shouldUpdateBearing = diff > 15.0;
      }

      if (shouldUpdateBearing) {
        bearingToUse = heading;
        _lastCameraBearing = heading;
      }

      mapController.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: currentUserPosition,
          zoom: _currentZoom,
          bearing: bearingToUse,
          tilt: _travelMode == TravelMode.driving ? 50.0 : 0.0,
        ),
      ));
    }

    final currentStep = _navSteps[_currentStepIndex];
    final totalStepDistance = currentStep['distance']['value'].toDouble();

    final distanceInMeters = _calculateDistanceAlongPolyline(
        currentUserPosition, currentStep['polyline']['points']);

    if (distanceInMeters < 30 && _currentStepIndex < _navSteps.length - 1) {
      setState(() {
        _currentStepIndex++;
        _updateNavInstruction();
      });
    }

    final newProgress =
        (totalStepDistance - distanceInMeters) / totalStepDistance;
    _progressAnimation = Tween<double>(
        begin: _progressToNextManeuver, end: newProgress.clamp(0.0, 1.0))
        .animate(_progressAnimationController!);
    _progressAnimationController!.forward(from: 0.0);

    double futureDistance = 0.0;
    for (int i = _currentStepIndex + 1; i < _navSteps.length; i++) {
      futureDistance += _navSteps[i]['distance']['value'];
    }
    double totalRemainingDistance = distanceInMeters + futureDistance;

    String newDistanceString = totalRemainingDistance < 1000
        ? "${totalRemainingDistance.toStringAsFixed(0)} m"
        : "${(totalRemainingDistance / 1000).toStringAsFixed(1)} km";

    final totalDurationSeconds = _routes[_selectedRouteIndex].durationValue;
    final elapsedSeconds = _navigationStopwatch.elapsed.inSeconds;
    final remainingSeconds = max(0, totalDurationSeconds - elapsedSeconds);
    final remainingDuration = Duration(seconds: remainingSeconds);

    String newEtaString = remainingDuration.inHours > 0
        ? "${remainingDuration.inHours} hr ${remainingDuration.inMinutes % 60} min"
        : "${remainingDuration.inMinutes} min";

    setState(() {
      _distanceToNextManeuver = distanceInMeters < 1000
          ? "${distanceInMeters.toStringAsFixed(0)} m"
          : "${(distanceInMeters / 1000).toStringAsFixed(1)} km";
      _progressToNextManeuver = newProgress.clamp(0.0, 1.0);

      _navDistance = newDistanceString;
      _navEta = newEtaString;
    });

    final fullRoute = _routes[_selectedRouteIndex].polylinePoints;
    int closestIndex = _findClosestPointIndex(currentUserPosition, fullRoute);

    if (closestIndex != -1) {
      List<LatLng> travelledPoints = fullRoute.sublist(0, closestIndex + 1);
      List<LatLng> remainingPoints = fullRoute.sublist(closestIndex);

      Set<Polyline> updatedPolylines = {};

      updatedPolylines.add(Polyline(
        polylineId: const PolylineId('travelled_path'),
        points: travelledPoints,
        color: Colors.grey,
        width: 8,
        zIndex: 1,
      ));

      updatedPolylines.add(Polyline(
        polylineId: const PolylineId('remaining_path'),
        points: remainingPoints,
        color: Colors.blueAccent,
        width: 8,
        zIndex: 2,
      ));

      setState(() {
        _polylines.clear();
        _polylines.addAll(updatedPolylines);
      });
    }

    NotificationService().showNavigationNotification(
        destination: _destination?.name ?? 'your destination',
        eta: _navEta,
        timeRemaining: newEtaString,
        nextTurn: _navInstruction,
        maneuverIcon: _navManeuverIcon);
  }

  int _findClosestPointIndex(LatLng userPos, List<LatLng> path) {
    int minIndex = -1;
    double minDst = double.infinity;

    for (int i = 0; i < path.length; i++) {
      double dst = _calculateDistance(userPos.latitude, userPos.longitude, path[i].latitude, path[i].longitude);
      if (dst < minDst) {
        minDst = dst;
        minIndex = i;
      }
    }
    return minIndex;
  }

  void _updateNavInstruction() {
    if (_navSteps.isEmpty || _currentStepIndex >= _navSteps.length) return;
    final currentStep = _navSteps[_currentStepIndex];

    String fullInstruction =
    _stripHtmlIfNeeded(currentStep['html_instructions']);
    String simplifiedInstruction = fullInstruction;

    RegExp exp = RegExp(r'\b(on|onto)\s+(.*)', caseSensitive: false);
    Match? match = exp.firstMatch(fullInstruction);
    if (match != null && match.groupCount >= 2) {
      // Use the captured text after the preposition
      simplifiedInstruction = match.group(2) ?? fullInstruction;
    }

    setState(() {
      _navInstruction = simplifiedInstruction; // Show simplified text on screen
      _navManeuverIcon = _getManeuverIcon(currentStep['maneuver']);
    });

    if (_navigationStarted) {
      // Speak the FULL instruction so the user hears "Turn left..."
      _speak(fullInstruction);
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

class LatLngTween extends Tween<LatLng> {
  LatLngTween({required LatLng begin, required LatLng end})
      : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) {
    return LatLng(
      begin!.latitude + (end!.latitude - begin!.latitude) * t,
      begin!.longitude + (end!.longitude - begin!.longitude) * t,
    );
  }
}