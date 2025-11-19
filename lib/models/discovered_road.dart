// lib/models/discovered_road.dart
class DiscoveredRoad {
  final int? id; // This is the local SQLite ID
  final String placeId;
  final double latitude;
  final double longitude;
  final String country;

  DiscoveredRoad({
    this.id,
    required this.placeId,
    required this.latitude,
    required this.longitude,
    required this.country,
  });

  // Convert a DiscoveredRoad into a Map.
  // The keys must correspond to the column names in database_service.dart.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'placeId': placeId,
      'latitude': latitude,
      'longitude': longitude,
      'country': country,
    };
  }

  // A factory constructor to create a DiscoveredRoad from a map
  factory DiscoveredRoad.fromMap(Map<String, dynamic> map) {
    return DiscoveredRoad(
      id: map['id'],
      placeId: map['placeId'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      country: map['country'] ?? 'Unknown',
    );
  }

  @override
  String toString() {
    return 'DiscoveredRoad(id: $id, placeId: $placeId, lat: $latitude, lng: $longitude)';
  }
}