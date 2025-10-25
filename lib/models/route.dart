import 'package:google_maps_flutter/google_maps_flutter.dart';

// Enums should be defined first
enum RouteType { fastest, scenic }

enum StepTravelMode { walking, transit }

// Data classes
class RouteInfo {
  final String duration;
  final int durationValue;
  final String distance;
  final List<LatLng> polylinePoints;
  double curviness;
  final List<dynamic> steps;

  RouteInfo({
    required this.duration,
    required this.durationValue,
    required this.distance,
    required this.polylinePoints,
    this.curviness = 0.0,
    required this.steps,
  });
}

class TransitInfo {
  final String vehicleName;
  final String headsign;
  final String departureStop;
  final LatLng? departureStopCoordinates;
  final String arrivalStop;
  final LatLng? arrivalStopCoordinates;
  final String departureTime;
  final String arrivalTime;
  final int numStops;

  TransitInfo({
    required this.vehicleName,
    required this.headsign,
    required this.departureStop,
    this.departureStopCoordinates,
    required this.arrivalStop,
    this.arrivalStopCoordinates,
    required this.departureTime,
    required this.arrivalTime,
    required this.numStops,
  });
}

class RouteStep {
  final StepTravelMode travelMode;
  final List<LatLng> polylinePoints;
  final int durationValue;
  final String? walkingDuration;
  final String? walkingDistance;
  final TransitInfo? transitInfo;

  RouteStep({
    required this.travelMode,
    required this.polylinePoints,
    required this.durationValue,
    this.walkingDuration,
    this.walkingDistance,
    this.transitInfo,
  });
}

class FullTransitRoute {
  final String totalDuration;
  final String departureTime;
  final String arrivalTime;
  final String totalWalkingDuration;
  final String totalWalkingDistance;
  final List<RouteStep> steps;

  FullTransitRoute({
    required this.totalDuration,
    required this.departureTime,
    required this.arrivalTime,
    required this.totalWalkingDuration,
    required this.totalWalkingDistance,
    required this.steps,
  });

  TransitInfo? get primaryTransitStep {
    try {
      return steps.firstWhere((s) => s.travelMode == StepTravelMode.transit).transitInfo;
    } catch (e) {
      return null;
    }
  }

  String get routeSequence {
    if (steps.isEmpty) return "N/A";
    return steps
        .where((s) => s.travelMode == StepTravelMode.transit)
        .map((s) => s.transitInfo!.vehicleName)
        .join(' > ');
  }
}