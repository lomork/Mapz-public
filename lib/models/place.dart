import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlaceSuggestion {
  final String placeId;
  final String description;
  PlaceSuggestion(this.placeId, this.description);
}

class PlaceDetails {
  final String placeId;
  final String name;
  final String address;
  final String? city;
  final String? state;
  final LatLng coordinates;
  final List<String> photoUrls;
  final double? rating;
  final String? openingHoursStatus;
  final String? phoneNumber;
  final String? website;
  final String? editorialSummary;

  PlaceDetails({
    required this.placeId,
    required this.name,
    required this.address,
    this.city,
    this.state,
    required this.coordinates,
    this.photoUrls = const [],
    this.rating,
    this.openingHoursStatus,
    this.phoneNumber,
    this.website,
    this.editorialSummary,
  });
}

class SearchHistoryItem {
  final String? placeId;
  final String description;

  SearchHistoryItem({this.placeId, required this.description});

  Map<String, dynamic> toJson() =>
      {'placeId': placeId, 'description': description};

  factory SearchHistoryItem.fromJson(Map<String, dynamic> json) =>
      SearchHistoryItem(
        placeId: json['placeId'],
        description: json['description'],
      );
}

class SavedPlace {
  final String placeId;
  final String name;
  final String address;
  final LatLng coordinates;

  SavedPlace(
      {required this.placeId,
        required this.name,
        required this.address,
        required this.coordinates});

  Map<String, dynamic> toJson() => {
    'placeId': placeId,
    'name': name,
    'address': address,
    'latitude': coordinates.latitude,
    'longitude': coordinates.longitude,
  };

  factory SavedPlace.fromJson(Map<String, dynamic> json) => SavedPlace(
    placeId: json['placeId'],
    name: json['name'],
    address: json['address'],
    coordinates: LatLng(json['latitude'], json['longitude']),
  );
}

class Place {
  final String placeId;
  final String name;
  final String address;
  final LatLng coordinates;
  final double? rating;
  final bool? isOpenNow;
  final List<String> types;

  Place({
    required this.placeId,
    required this.name,
    required this.address,
    required this.coordinates,
    this.rating,
    this.isOpenNow,
    this.types = const [],
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      placeId: json['place_id'],
      name: json['name'],
      address: json['vicinity'] ?? 'Address not available',
      coordinates: LatLng(
        json['geometry']['location']['lat'],
        json['geometry']['location']['lng'],
      ),
      rating: json['rating']?.toDouble(),
      isOpenNow: json['opening_hours']?['open_now'],
      types: (json['types'] as List<dynamic>).map((e) => e.toString()).toList(),
    );
  }
}

