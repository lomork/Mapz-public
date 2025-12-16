// lib/models/discovered_road.dart
class DiscoveredRoad {
  final int? id; // This is the local SQLite ID
  final String placeId;
  final double latitude;
  final double longitude;
  final String country;
  final String city;
  final String state;

  DiscoveredRoad({
    this.id,
    required this.placeId,
    required this.latitude,
    required this.longitude,
    this.country = 'Unknown',
    this.city = 'Unknown',
    this.state = 'Unknown',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'placeId': placeId,
      'latitude': latitude,
      'longitude': longitude,
      'country': country,
      'city': city,
      'state': state,
    };
  }

  factory DiscoveredRoad.fromMap(Map<String, dynamic> map) {
    return DiscoveredRoad(
      id: map['id'],
      placeId: map['placeId'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      country: map['country'] ?? 'Unknown',
      city: map['city'] ?? 'Unknown',
      state: map['state'] ?? 'Unknown',
    );
  }

  @override
  String toString() {
    return 'DiscoveredRoad(id: $id, placeId: $placeId, lat: $latitude, lng: $longitude)';
  }
}