import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class GoogleMapsApiService {
  final String _apiKey = dotenv.env['GOOGLE_API_KEY'] ?? 'NO_API_KEY';
  final String _cloudProxyUrl = dotenv.env['CLOUD_PROXY_URL'] ?? 'NO_PROXY_URL';

  String get apiKey => _apiKey;

  Future<Map<String, dynamic>> _getRequest(String googleApiUrl) async {
    final String finalUrl = kIsWeb
        ? '$_cloudProxyUrl?url=${Uri.encodeComponent(googleApiUrl)}'
        : googleApiUrl;

    try {
      final response = await http.get(Uri.parse(finalUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load data from Google Maps API');
      }
    } catch (e) {
      print('API Service Error: $e'); // For debugging
      throw Exception('Failed to connect to the API service: $e');
    }
  }

  Future<Map<String, dynamic>> getPlaceSuggestions(String input, String sessionToken, {LatLng? location}) {
    String url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(input)}&key=$_apiKey&sessiontoken=$sessionToken';

    if (location != null) {
      url += '&location=${location.latitude}%2C${location.longitude}&radius=10000';
    }

    return _getRequest(url);
  }

  Future<Map<String, dynamic>> getPlaceDetails(String placeId, String sessionToken) {
    final String fields =
        'place_id,name,formatted_address,geometry,photo,rating,opening_hours,international_phone_number,website,address_components,editorial_summary';
    final String url =
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_apiKey&sessiontoken=$sessionToken&fields=$fields';
    return _getRequest(url);
  }

  Future<Map<String, dynamic>> getDirections({
    required LatLng origin,
    required LatLng destination,
    required String travelMode,
    String avoidances = '',
  }) {
    final String url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&mode=$travelMode&alternatives=true&key=$_apiKey$avoidances&departure_time=now';
    return _getRequest(url);
  }

  Future<Map<String, dynamic>> reverseGeocode(LatLng coordinates) {
    final String url =
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${coordinates.latitude},${coordinates.longitude}&key=$_apiKey';
    return _getRequest(url);
  }

  Future<Map<String, dynamic>> getSpeedLimit(LatLng point) {
    final String url =
        'https://roads.googleapis.com/v1/speedLimits?path=${point.latitude},${point.longitude}&key=$_apiKey';
    return _getRequest(url);
  }

  Future<Map<String, dynamic>> nearbySearch({
    required LatLng location,
    required String keyword,
  }) {

    const int radius = 5000;
    final String url =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${location.latitude},${location.longitude}&radius=$radius&keyword=${Uri.encodeComponent(keyword)}&key=$_apiKey';
    return _getRequest(url);
  }
  Future<Map<String, dynamic>> snapToRoads(List<LatLng> path) {
    // The path needs to be formatted as lat,lng|lat,lng|...
    final String pathString = path.map((p) => '${p.latitude},${p.longitude}').join('|');
    final String url =
        'https://roads.googleapis.com/v1/snapToRoads?path=$pathString&interpolate=true&key=$_apiKey';
    return _getRequest(url);
  }

  Future<Map<String, dynamic>> geocode(String address) async {
    final encodedAddress = Uri.encodeComponent(address);
    final String url =
        'https://maps.googleapis.com/maps/api/geocode/json?address=$encodedAddress&key=$_apiKey';
    return _getRequest(url);
  }

}