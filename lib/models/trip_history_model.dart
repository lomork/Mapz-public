import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TripHistory {
  final int? id;
  final String startAddress;
  final String endAddress;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;
  final String distanceText;
  final List<LatLng> routePath; // The full path taken

  TripHistory({
    this.id,
    required this.startAddress,
    required this.endAddress,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.distanceText,
    required this.routePath,
  });

  Map<String, dynamic> toMap() {
    // Convert List<LatLng> to JSON String for storage
    List<Map<String, double>> pathMap = routePath.map((p) => {
      'lat': p.latitude,
      'lng': p.longitude
    }).toList();

    return {
      'id': id,
      'startAddress': startAddress,
      'endAddress': endAddress,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'durationSeconds': durationSeconds,
      'distanceText': distanceText,
      'routePathJson': jsonEncode(pathMap),
    };
  }

  factory TripHistory.fromMap(Map<String, dynamic> map) {
    // Convert JSON String back to List<LatLng>
    List<dynamic> decodedPath = jsonDecode(map['routePathJson']);
    List<LatLng> path = decodedPath.map((p) => LatLng(p['lat'], p['lng'])).toList();

    return TripHistory(
      id: map['id'],
      startAddress: map['startAddress'] ?? 'Unknown Start',
      endAddress: map['endAddress'] ?? 'Unknown End',
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime']),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['endTime']),
      durationSeconds: map['durationSeconds'] ?? 0,
      distanceText: map['distanceText'] ?? '',
      routePath: path,
    );
  }
}