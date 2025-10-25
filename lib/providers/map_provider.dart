import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';

import '../api/google_maps_api_service.dart';
import '../models/place.dart';

class MapProvider with ChangeNotifier {
  final GoogleMapsApiService _apiService;
  final Uuid _uuid = const Uuid();
  String? _sessionToken;
  Timer? _debounce;

  MapProvider(this._apiService);

  // --- STATE VARIABLES ---
  PlaceDetails? _selectedPlace;
  bool _isSearching = false;
  List<PlaceSuggestion> _suggestions = [];
  final Set<Marker> _markers = {};
  List<Place> _nearbySearchResults = [];
  String _activeFilter = 'All';
  String _currentSearchKeyword = '';

  // --- GETTERS ---
  // UI widgets will use these getters to access the current state.
  PlaceDetails? get selectedPlace => _selectedPlace;
  bool get isSearching => _isSearching;
  List<PlaceSuggestion> get suggestions => _suggestions;
  Set<Marker> get markers => _markers;
  List<Place> get nearbySearchResults => _nearbySearchResults;
  String get activeFilter => _activeFilter;

  List<Place> get filteredNearbyResults {
    switch (_activeFilter) {
      case 'Open Now':
        return _nearbySearchResults.where((p) => p.isOpenNow == true).toList();
      case 'Top Rated':
      // Create a mutable copy before sorting
        var sortedList = List<Place>.from(_nearbySearchResults);
        sortedList.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
        return sortedList;
      default: // 'All'
        return _nearbySearchResults;
    }
  }

  // --- LOGIC METHODS ---
  // These methods contain the logic to change the state.

  void startSearch(FocusNode searchFocusNode) {
    // Clear previous nearby results when starting a new search
    _nearbySearchResults.clear();
    _markers.clear();

    searchFocusNode.requestFocus();
    _isSearching = true;
    _sessionToken = _uuid.v4();
    notifyListeners();
  }

  void clearNearbySearch() {
    _nearbySearchResults.clear();
    _markers.clear();
    _currentSearchKeyword = '';
    notifyListeners();
  }

  void stopSearch(FocusNode searchFocusNode, TextEditingController searchController) {
    searchFocusNode.unfocus();
    searchController.clear();
    _isSearching = false;
    _suggestions = [];
    _sessionToken = null;
    notifyListeners();
  }

  void applyFilter(String filter) {
    _activeFilter = filter;
    notifyListeners();
  }

  List<String> getFiltersForKeyword() {
    // This can be expanded with more logic for different keywords
    if (_currentSearchKeyword.toLowerCase().contains('restaurant')) {
      return ['All', 'Top Rated', 'Open Now']; // Example for restaurants
    }
    // Default filters
    return ['All', 'Top Rated', 'Open Now'];
  }

  void fetchSuggestions(String input, {LatLng? userLocation}) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (input.isNotEmpty && _sessionToken != null) {
        try {
          // Pass the user's location to the API service
          final result = await _apiService.getPlaceSuggestions(input, _sessionToken!, location: userLocation);

          if (result['status'] == 'OK') {
            _suggestions = (result['predictions'] as List)
                .map((p) => PlaceSuggestion(p['place_id'], p['description']))
                .toList();
          }
        } catch (e) {
          print("Error fetching suggestions: $e");
          _suggestions = [];
        }
      } else {
        _suggestions = [];
      }
      notifyListeners();
    });
  }

  Future<void> selectPlace(String placeId, String description) async {
    // Clear previous selection and notify UI to show a loading state if needed
    _selectedPlace = null;
    _markers.clear();
    notifyListeners();

    try {
      final result = await _apiService.getPlaceDetails(placeId, _sessionToken ?? '');
      if (result['status'] == 'OK') {
        final placeJson = result['result'];
        final location = placeJson['geometry']['location'];
        final latLng = LatLng(location['lat'], location['lng']);

        // --- FULL PARSING LOGIC FROM YOUR OLD METHOD ---
        String? city;
        String? state;
        if (placeJson['address_components'] != null) {
          final components = placeJson['address_components'] as List;
          for (var component in components) {
            final types = component['types'] as List;
            if (types.contains('locality')) city = component['long_name'];
            if (types.contains('administrative_area_level_1')) state = component['long_name'];
          }
        }

        List<String> photoUrls = [];
        if (placeJson['photos'] != null) {
          final apiKey = _apiService.apiKey; // Get the API key from the service
          for (var photo in placeJson['photos']) {
            final photoReference = photo['photo_reference'];
            final url =
                'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=$photoReference&key=$apiKey';
            photoUrls.add(url);
          }
        }

        final openingHours = placeJson['opening_hours'];
        String? hoursStatus;
        if (openingHours != null) {
          hoursStatus = openingHours['open_now'] ?? false ? 'Open now' : 'Closed';
        }

        final editorialSummaryJson = placeJson['editorial_summary'];
        String? summary;
        if (editorialSummaryJson != null) {
          summary = editorialSummaryJson['overview'];
        }
        // --- END OF FULL PARSING LOGIC ---

        _selectedPlace = PlaceDetails(
          placeId: placeJson['place_id'],
          name: placeJson['name'],
          address: placeJson['formatted_address'],
          coordinates: latLng,
          // Add all the newly parsed details
          city: city,
          state: state,
          photoUrls: photoUrls,
          rating: placeJson['rating']?.toDouble(),
          openingHoursStatus: hoursStatus,
          phoneNumber: placeJson['international_phone_number'],
          website: placeJson['website'],
          editorialSummary: summary,
        );

        _markers.add(
          Marker(
            markerId: MarkerId(placeId),
            position: latLng,
            infoWindow: InfoWindow(title: description),
          ),
        );
      }
    } catch (e) {
      print("Error selecting place: $e");
    } finally {
      // Clean up search state and notify the UI of the final result
      _sessionToken = null;
      _isSearching = false;
      _suggestions = [];
      notifyListeners();
    }
  }

  Future<void> searchNearby(String keyword, LatLng userLocation) async {
    _currentSearchKeyword = keyword;
    _activeFilter = 'All';
    _nearbySearchResults = [];
    _markers.clear();
    notifyListeners();

    try {
      final result = await _apiService.nearbySearch(location: userLocation, keyword: keyword);

      if (result['status'] == 'OK') {
        final List<dynamic> results = result['results'];

        List<Place> places = [];
        for (var placeJson in results) {
          places.add(Place.fromJson(placeJson));
        }
        _nearbySearchResults = places;

        // Now, create custom markers for each result
        for (var place in _nearbySearchResults) {
          final icon = await _createCustomMarker(
              place.name,
              place.isOpenNow == true ? 'Open' : 'Closed',
              Icons.local_library // Example icon, you can make this dynamic
          );
          _markers.add(
            Marker(
              markerId: MarkerId(place.placeId),
              position: place.coordinates,
              icon: icon,
              onTap: () {
                // When a map marker is tapped, select that place
                selectPlace(place.placeId, place.name);
              },
            ),
          );
        }
      }
    } catch (e) {
      print("Error during nearby search: $e");
    }
    notifyListeners(); // Notify UI with the final list and markers
  }

  // Helper method to create custom markers with text
  Future<BitmapDescriptor> _createCustomMarker(String title, String status, IconData iconData) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Size size = const Size(300, 120); // The size of our marker bitmap

    // Draw the background
    final Paint backgroundPaint = Paint()..color = Colors.blue.shade800;
    final RRect rrect = RRect.fromLTRBAndCorners(0, 0, size.width, size.height - 20,
        topLeft: const Radius.circular(20),
        topRight: const Radius.circular(20),
        bottomLeft: const Radius.circular(20),
        bottomRight: const Radius.circular(20));
    canvas.drawRRect(rrect, backgroundPaint);

    // Draw the pin shape at the bottom
    final Path pinPath = Path();
    pinPath.moveTo(size.width / 2 - 20, size.height - 20);
    pinPath.lineTo(size.width / 2, size.height);
    pinPath.lineTo(size.width / 2 + 20, size.height - 20);
    pinPath.close();
    canvas.drawPath(pinPath, backgroundPaint);

    // Draw the icon
    TextPainter iconPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    iconPainter.text = TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(fontSize: 50, color: Colors.white, fontFamily: iconData.fontFamily));
    iconPainter.layout();
    iconPainter.paint(canvas, const Offset(20, 15));

    // Draw the title
    TextPainter titlePainter = TextPainter(
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...');
    titlePainter.text = TextSpan(
        text: title, style: const TextStyle(fontSize: 30, color: Colors.white, fontWeight: FontWeight.bold));
    titlePainter.layout(maxWidth: size.width - 90);
    titlePainter.paint(canvas, const Offset(80, 15));

    // Draw the status
    TextPainter statusPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    statusPainter.text = TextSpan(
        text: status, style: TextStyle(fontSize: 24, color: Colors.grey.shade300));
    statusPainter.layout();
    statusPainter.paint(canvas, const Offset(80, 55));

    // Convert to image
    final img = await pictureRecorder.endRecording().toImage(size.width.toInt(), size.height.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  void closePlaceDetails() {
    _selectedPlace = null;
    _markers.clear();
    notifyListeners();
  }
}