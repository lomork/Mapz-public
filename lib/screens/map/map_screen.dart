import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:mapz/screens/profile/profile_screen.dart';
import 'package:mapz/screens/profile/edit_profile_screen.dart';

import '../../api/google_maps_api_service.dart';
import '../../main.dart';
import '../../models/place.dart';
import '../../models/tts_voice_info.dart';
import '../../services/notification_service.dart';
import '../../services/road_discovery_service.dart';
import '../auth/auth_gate.dart';
import '../../providers/map_provider.dart';
import 'directions_screen.dart';
import '../discovery/road_discovery_screen.dart';
import '../../providers/settings_provider.dart';

class MapScreen extends StatefulWidget {
  final User user;
  const MapScreen({super.key, required this.user});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin{
  late GoogleMapController mapController;
  bool _isMapControllerInitialized = false;
  final LatLng _center = const LatLng(44.6702, -63.5739);
  MapType _currentMapType = MapType.normal;
  bool _isTrafficEnabled = false;
  final Location _locationService = Location();
  final Set<Marker> _markers = {};
  StreamSubscription<LocationData>? _locationSubscription;
  int _currentIndex = 0;

  bool _isProfileMenuVisible = false;
  bool _isAdaptiveDiscoveryEnabled = true;

  AppTheme _currentTheme = AppTheme.automatic;
  String _darkMapStyle = '';
  String _lightMapStyle = '';

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearching = false;
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = [];
  List<SearchHistoryItem> _searchHistory = [];
  List<SavedPlace> _savedPlaces = [];
  String? _sessionToken;
  final Uuid _uuid = const Uuid();

  PlaceDetails? _selectedPlace;

  BitmapDescriptor? _userMarkerIcon;
  final Map<String, BitmapDescriptor> _vehicleMarkers = {};
  String _selectedVehicleKey = 'sedan';

  LatLng? _previousLatLng;
  double _previousRotation = 0.0;
  bool _isFollowingUser = false;

  AnimationController? _markerAnimationController;
  Animation<double>? _rotationAnimation;
  Animation<LatLng>? _positionAnimation;
  LatLng? _currentUserLatLng;
  double _currentUserRotation = 0.0;

  @override
  bool get wantKeepAlive => true;

  late final List<Widget> _screens;
  final FlutterTts _flutterTts = FlutterTts();
  String? _selectedTtsVoice;
  List<TtsVoiceInfo> _availableFriendlyVoices = [];
  final List<TtsVoiceInfo> _friendlyVoices = [
    TtsVoiceInfo(id: 'en-us-x-sfg#male_1-local', displayName: 'American Male'),
    TtsVoiceInfo(id: 'en-us-x-sfg#female_1-local', displayName: 'American Female'),
    TtsVoiceInfo(id: 'en-gb-x-rjs#male_1-local', displayName: 'British Male'),
    TtsVoiceInfo(id: 'en-gb-x-rjs#female_1-local', displayName: 'British Female'),
    TtsVoiceInfo(id: 'en-au-x-afh#male_1-local', displayName: 'Australian Male'),
    TtsVoiceInfo(id: 'fr-fr-x-vlf#female_1-local', displayName: 'French Female'),
    TtsVoiceInfo(id: 'es-es-x-eee#female_1-local', displayName: 'Spanish Female'),
    TtsVoiceInfo(id: 'de-de-x-deb#male_1-local', displayName: 'German Male'),
  ];


  @override
  void initState() {
    super.initState();
    _markerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _initializeMapAndLocation();
    _initTts();
    _searchFocusNode.addListener(_onSearchFocusChange);

  }

  @override
  void dispose() {
    _markerAnimationController?.dispose();
    themeNotifier.removeListener(_updateMapStyle);
    _locationSubscription?.cancel();
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchController.dispose();
    NotificationService().cancelLocationNotification();
    super.dispose();
  }

  // TTS VOICE SELECTION: Method to initialize TTS and get voices
  Future<void> _initTts() async {
    try {
      var voices = await _flutterTts.getVoices;
      if (voices is List) {
        final availableVoiceIds =
        voices.map((v) => (v as Map)['name'].toString()).toSet();

        _availableFriendlyVoices = _friendlyVoices
            .where((friendlyVoice) => availableVoiceIds.contains(friendlyVoice.id))
            .toList();

        final prefs = await SharedPreferences.getInstance();
        _selectedTtsVoice = prefs.getString('selectedTtsVoice');

        if (_selectedTtsVoice == null || !availableVoiceIds.contains(_selectedTtsVoice)) {
          if (_availableFriendlyVoices.isNotEmpty) {
            _selectedTtsVoice = _availableFriendlyVoices.first.id;
            await prefs.setString('selectedTtsVoice', _selectedTtsVoice!);
          }
        }
      }
    } catch (e) {
      debugPrint("Error initializing TTS voices: $e");
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<BitmapDescriptor> _getResizedMarkerIcon(String assetPath, int width) async {
    ByteData data = await rootBundle.load(assetPath);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    final Uint8List resizedBytes = (await fi.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    return BitmapDescriptor.fromBytes(resizedBytes);
  }

  Future<void> _initializeMapAndLocation() async {
    _userMarkerIcon = await _getResizedMarkerIcon('assets/images/UserLocation.png', 150);
    await _loadVehicleMarkers();
    await _loadMapStyles();
    await _initLocationServices();
    themeNotifier.addListener(_updateMapStyle);
    await _loadSearchHistory();
    await _loadSavedPlaces();
  }

  Future<void> _loadVehicleMarkers() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedVehicleKey = prefs.getString('selectedVehicle') ?? 'sedan';

    _vehicleMarkers['sedan'] = await _createVehicleMarkerBitmap(Icons.directions_car);
    _vehicleMarkers['suv'] = await _createVehicleMarkerBitmap(Icons.directions_car_filled);
    _vehicleMarkers['truck'] = await _createVehicleMarkerBitmap(Icons.fire_truck);
    _vehicleMarkers['ev'] = await _createVehicleMarkerBitmap(Icons.electric_car);

    if (mounted) {
      setState(() {});
    }
  }


  Future<void> _initLocationServices() async {
    var locationService = Location();
    bool serviceEnabled = await locationService.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await locationService.requestService();
      if (!serviceEnabled) return;
    }
    PermissionStatus permissionGranted = await locationService.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await locationService.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }
    NotificationService().showLocationActiveNotification();
    _listenToLocationChanges();
  }

  // MARKER ANIMATION: Helper function to update the marker's state on the map
  void _updateUserMarker() {
    if (_currentUserLatLng == null) return;
    final marker = Marker(
      markerId: const MarkerId('userLocation'),
      position: _currentUserLatLng!,
      icon: _userMarkerIcon!,
      rotation: _currentUserRotation,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndex: 2.0,
    );
    _markers.removeWhere((m) => m.markerId.value == 'userLocation');
    _markers.add(marker);
  }

  // In _MapScreenState

  Future<void> _listenToLocationChanges() async {
    final locationService = Location();
    await locationService.changeSettings(
      accuracy: LocationAccuracy.high,
      interval: 1000,
      distanceFilter: 2,
    );
    _locationSubscription =
        locationService.onLocationChanged.listen((LocationData currentLocation) {
          if (!mounted || currentLocation.latitude == null || currentLocation.longitude == null) return;

          final newLatLng = LatLng(currentLocation.latitude!, currentLocation.longitude!);
          final newRotation = currentLocation.heading ?? _previousRotation;

          // If this is the first location update, set the position without animating
          if (_previousLatLng == null) {
            setState(() {
              _currentUserLatLng = newLatLng;
              _currentUserRotation = newRotation;
              _previousLatLng = newLatLng;
              _previousRotation = newRotation;
            });
            return;
          }

          // --- NEW: Animate from the previous position to the new one ---
          _positionAnimation = LatLngTween(begin: _previousLatLng!, end: newLatLng)
              .animate(_markerAnimationController!);

          // Animate rotation for a smoother turn
          _rotationAnimation = Tween<double>(begin: _previousRotation, end: newRotation)
              .animate(_markerAnimationController!);

          _markerAnimationController!.forward(from: 0.0).whenComplete(() {
            // After animation, update the previous values for the next cycle
            _previousLatLng = newLatLng;
            _previousRotation = newRotation;
          });

          final discoveryService = context.read<RoadDiscoveryService>();
          discoveryService.addLocationPoint(newLatLng);

          if (_isFollowingUser) {
            mapController.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                  target: newLatLng,
                  zoom: 17.5,
                  bearing: newRotation,
                  tilt: 50.0),
            ));
          }
        });
  }

  Future<void> _loadMapStyles() async {
    _darkMapStyle = await rootBundle.loadString('assets/map_style_dark.json');
   // _lightMapStyle = await rootBundle.loadString('assets/map_style_light.json');
    _updateMapStyle();
  }

  void _onSearchFocusChange() {
    final mapProvider = context.read<MapProvider>();
    if (_searchFocusNode.hasFocus && !mapProvider.isSearching) {
      mapProvider.startSearch(_searchFocusNode);
    }
  }

  void _onSearchQueryChanged(String query) {
    setState(() {}); // To update the clear button
    context.read<MapProvider>().fetchSuggestions(query, userLocation: _currentUserLatLng);
  }

  void _clearSearch() {
    _searchController.clear();
    context.read<MapProvider>().fetchSuggestions('');
    setState(() {});
  }

  void _closePlaceDetails() {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value != 'userLocation');
      _selectedPlace = null;
    });
  }

  Future<Uint8List> _getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  }

  Future<void> _fetchPlaceSuggestions(String input) async {
    if (_sessionToken == null) return;
    try {
      final apiService = Provider.of<GoogleMapsApiService>(context, listen: false);
      final result = await apiService.getPlaceSuggestions(input, _sessionToken!);
      if (result['status'] == 'OK' && mounted) {
        setState(() {
          _suggestions = (result['predictions'] as List)
              .map((p) => PlaceSuggestion(p['place_id'], p['description']))
              .toList();
        });
      }
    } catch (e) {
      debugPrint("Error fetching suggestions: $e");
    }
  }

  Future<void> _selectPlace(String placeId, String description) async {
    _searchFocusNode.unfocus();
    if (mounted) {
      setState(() {
        _isSearching = false;
        _suggestions = [];
        _searchController.clear();
        _selectedPlace = null;
        _markers.removeWhere((m) => m.markerId.value != 'userLocation');
      });
    }

    _addToSearchHistory(SearchHistoryItem(placeId: placeId, description: description));

    try {
      final apiService = Provider.of<GoogleMapsApiService>(context, listen: false);
      final result = await apiService.getPlaceDetails(placeId, _sessionToken!);

      if (result['status'] == 'OK') {
        final placeJson = result['result'];
        final location = placeJson['geometry']['location'];
        final latLng = LatLng(location['lat'], location['lng']);

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
          final apiKey = Provider.of<GoogleMapsApiService>(context, listen: false).apiKey;
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

        final newPlace = PlaceDetails(
          placeId: placeJson['place_id'],
          name: placeJson['name'],
          address: placeJson['formatted_address'],
          city: city,
          state: state,
          coordinates: latLng,
          photoUrls: photoUrls,
          rating: placeJson['rating']?.toDouble(),
          openingHoursStatus: hoursStatus,
          phoneNumber: placeJson['international_phone_number'],
          website: placeJson['website'],
          editorialSummary: summary,
        );

        setState(() {
          _selectedPlace = newPlace;
          _markers.add(Marker(
              markerId: MarkerId(placeId),
              position: latLng,
              infoWindow: InfoWindow(title: description)));
        });

        mapController.animateCamera(CameraUpdate.newLatLngZoom(latLng, 15));
      }
    } catch (e) {
      debugPrint("Error selecting place: $e");
    } finally {
      if (mounted) {
        _sessionToken = null;
      }
    }
  }

  Future<void> _handleMapTap(LatLng position) async {
    _searchFocusNode.unfocus();
    try {
      final apiService = Provider.of<GoogleMapsApiService>(context, listen: false);
      final result = await apiService.reverseGeocode(position);

      if (result['status'] == 'OK' && result['results'].isNotEmpty) {
        final place = result['results'][0];
        final String placeId = place['place_id'];
        final String description = place['formatted_address'];
        _selectPlace(placeId, description);
      }
    } catch (e) {
      debugPrint("Failed to get place from tap: $e");
    }
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('searchHistory') ?? [];
    if (mounted) {
      setState(() {
        _searchHistory = historyJson
            .map((item) => SearchHistoryItem.fromJson(json.decode(item)))
            .toList();
      });
    }
  }

  Future<void> _addToSearchHistory(SearchHistoryItem item) async {
    _searchHistory.removeWhere((historyItem) => historyItem.description == item.description);
    _searchHistory.insert(0, item);
    if (_searchHistory.length > 10) {
      _searchHistory = _searchHistory.sublist(0, 10);
    }
    final prefs = await SharedPreferences.getInstance();
    final historyJson = _searchHistory.map((item) => json.encode(item.toJson())).toList();
    await prefs.setStringList('searchHistory', historyJson);
    if (mounted) setState(() {});
  }

  Future<void> _loadSavedPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPlacesJson = prefs.getStringList('savedPlaces') ?? [];
    if (mounted) {
      setState(() {
        _savedPlaces = savedPlacesJson
            .map((item) => SavedPlace.fromJson(json.decode(item)))
            .toList();
      });
    }
  }

  Future<void> _savePlace(PlaceDetails place, String name) async {
    final newSavedPlace = SavedPlace(
        placeId: place.placeId,
        name: name,
        address: place.address,
        coordinates: place.coordinates);
    _savedPlaces.removeWhere((p) => p.name.toLowerCase() == name.toLowerCase());
    _savedPlaces.add(newSavedPlace);
    final prefs = await SharedPreferences.getInstance();
    final savedPlacesJson = _savedPlaces.map((p) => json.encode(p.toJson())).toList();
    await prefs.setStringList('savedPlaces', savedPlacesJson);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${place.name}" saved as $name!')));
      setState(() {});
    }
  }

  void _showNameFavoriteDialog(PlaceDetails place) {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Name this Favorite'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: "e.g., John's house"),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  _savePlace(place, nameController.text);
                }
              },
            ),
          ],
        );
      },
    );
  }

// SAVED PLACES: Dialog to choose how to save a place
  void _showSavePlaceDialog(PlaceDetails place) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save Location'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text("Save as Home"),
                onTap: () => _savePlace(place, "Home"),
              ),
              ListTile(
                leading: const Icon(Icons.work),
                title: const Text("Save as Work"),
                onTap: () => _savePlace(place, "Work"),
              ),
              ListTile(
                leading: const Icon(Icons.star),
                title: const Text("Save as Favorite"),
                onTap: () {
                  Navigator.of(context).pop();
                  _showNameFavoriteDialog(place);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    _isMapControllerInitialized = true;
    _updateMapStyle();
  }

  void _updateMapStyle() {
    if (!mounted || !_isMapControllerInitialized) return;

    final isDarkMode = themeNotifier.value == ThemeMode.dark ||
        (themeNotifier.value == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    mapController.setMapStyle(isDarkMode ? _darkMapStyle : null);
  }

  void _toggleProfileMenu() {
    setState(() {
      _isProfileMenuVisible = !_isProfileMenuVisible;
    });
  }

  void _toggleFollowUserMode() {
    setState(() {
      _isFollowingUser = !_isFollowingUser;
    });

    if (_isFollowingUser && _previousLatLng != null) {
      mapController.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _previousLatLng!,
          zoom: 17.5,
          bearing: _previousRotation,
          tilt: 50.0,
        ),
      ));
    }
  }

  void _zoomIn() => mapController.animateCamera(CameraUpdate.zoomIn());
  void _zoomOut() => mapController.animateCamera(CameraUpdate.zoomOut());

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthGate()),
            (route) => false,
      );
    }
  }

  void _showLayerDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Map Layers'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLayerOption(Icons.map, "Normal",
                          _currentMapType == MapType.normal, () {
                            setState(() => _currentMapType = MapType.normal);
                            Navigator.of(context).pop();
                          }),
                      _buildLayerOption(Icons.satellite, "Satellite",
                          _currentMapType == MapType.satellite, () {
                            setState(() => _currentMapType = MapType.satellite);
                            Navigator.of(context).pop();
                          }),
                    ],
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Traffic'),
                    value: _isTrafficEnabled,
                    onChanged: (bool value) {
                      setDialogState(() {
                        _isTrafficEnabled = value;
                      });
                      setState(() {});
                    },
                    secondary: const Icon(Icons.traffic),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    child: const Text('Done'),
                    onPressed: () => Navigator.of(context).pop()),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLayerOption(
      IconData icon, String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.blue : Colors.grey[700]),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: isSelected ? Colors.blue : Colors.grey[700])),
          ],
        ),
      ),
    );
  }

  void _showCountrySelectorDialog() {
    showCountryPicker(
      context: context,
      showPhoneCode: false,
      onSelect: (Country country) {
        context.read<SettingsProvider>().updateCountry(country.name);

        // --- ADD THIS: Show a confirmation message ---
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Switched to ${country.name}"),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  void _showThemeSelectorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppTheme.values.map((theme) {
            return ListTile(
              title:
              Text(theme.name[0].toUpperCase() + theme.name.substring(1)),
              onTap: () {
                setState(() => _currentTheme = theme);
                switch (theme) {
                  case AppTheme.automatic:
                    themeNotifier.value = ThemeMode.system;
                    break;
                  case AppTheme.light:
                    themeNotifier.value = ThemeMode.light;
                    break;
                  case AppTheme.dark:
                    themeNotifier.value = ThemeMode.dark;
                    break;
                }
                _updateMapStyle();
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showSystemTtsSettingsInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Manage Voices"),
        content: const Text(
            "To add or remove TTS voices, you need to go to your phone's system settings.\n\nUsually, this is found under:\nSettings > Accessibility > Text-to-speech output"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // TTS VOICE SELECTION: Method to show the voice selection dialog
  void _showVoiceSelectorDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String? currentSelection = _selectedTtsVoice;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Voice'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_availableFriendlyVoices.isEmpty)
                        const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                  "No alternative voices found on this device."),
                            ))
                      else
                        ..._availableFriendlyVoices.map((voice) {
                          return RadioListTile<String>(
                            title: Text(voice.displayName),
                            value: voice.id,
                            groupValue: currentSelection,
                            onChanged: (String? value) {
                              if (value != null) {
                                setDialogState(() {
                                  currentSelection = value;
                                });
                              }
                            },
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _showSystemTtsSettingsInfo,
                  child: const Text('Add More Voices'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    if (currentSelection != null) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString(
                          'selectedTtsVoice', currentSelection!);
                      if (mounted) {
                        setState(() {
                          _selectedTtsVoice = currentSelection;
                        });
                      }
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<BitmapDescriptor> _createVehicleMarkerBitmap(IconData icon) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final size = 120.0;
    final iconColor = Colors.white;
    final backgroundColor = Colors.blue;

    final backgroundPaint = Paint()..color = backgroundColor;

    // Draw a teardrop shape
    final path = Path()
      ..moveTo(size / 2, size)
      ..arcTo(Rect.fromCircle(center: Offset(size / 2, size / 2), radius: size / 2), pi, -pi, false)
      ..close();

    canvas.drawPath(path, backgroundPaint);

    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.6,
        fontFamily: icon.fontFamily,
        color: iconColor,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2));

    final img = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  void _showMarkerSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Choose Your Vehicle'),
          content: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: _vehicleMarkers.entries.map((entry) {
              final key = entry.key;
              final descriptor = entry.value;
              return GestureDetector(
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('selectedVehicle', key);
                  setState(() {
                    _selectedVehicleKey = key;
                    _userMarkerIcon = descriptor;
                  });
                  Navigator.of(context).pop();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _selectedVehicleKey == key ? Colors.blue.withOpacity(0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedVehicleKey == key ? Colors.blue : Colors.grey,
                          ),
                        ),
                        child: Image.asset('assets/images/${key}_icon.png', width: 48, height: 48, // Placeholder
                          errorBuilder: (context, error, stackTrace) {
                            // In a real app you'd convert the BitmapDescriptor back to a widget
                            // For simplicity, we just show the icon
                            return Icon(
                                key == 'sedan' ? Icons.directions_car :
                                key == 'suv' ? Icons.directions_car_filled :
                                key == 'truck' ? Icons.fire_truck : Icons.electric_car,
                                size: 48,
                                color: Colors.blue
                            );
                          },
                        )
                    ),
                    const SizedBox(height: 4),
                    Text(key[0].toUpperCase() + key.substring(1)),
                  ],
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mapProvider = context.watch<MapProvider>();
    final screenHeight = MediaQuery.of(context).size.height;
    final minSheetSize = 240.0 / screenHeight;
    const midSheetSize = 0.5;
    const maxSheetSize = 0.8;

    return Scaffold(
      body: Stack(
        children: <Widget>[
      AnimatedBuilder(
      animation: _markerAnimationController!,
          builder: (context, _) {
            return GoogleMap(
              onMapCreated: (controller) {
                mapController = controller;
                _isMapControllerInitialized = true;
                _updateMapStyle();
              },
              initialCameraPosition: CameraPosition(
                  target: _center, zoom: 12.0),
              markers: _buildMarkers(mapProvider),
              myLocationButtonEnabled: false,
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              onTap: (position) {
                if (mapProvider.isSearching) {
                  mapProvider.stopSearch(_searchFocusNode, _searchController);
                }
              },
              onLongPress: (pos) => _showMarkerSelectionDialog(),
              mapType: _currentMapType,
              trafficEnabled: _isTrafficEnabled,
            );
          }
      ),

          if (mapProvider.selectedPlace != null)
            DraggableScrollableSheet(
              initialChildSize: minSheetSize,
              minChildSize: minSheetSize,
              maxChildSize: maxSheetSize,
              snap: true,
              snapSizes: const [midSheetSize, maxSheetSize],
              builder: (BuildContext context, ScrollController scrollController) {
                return _buildPlaceDetailsPanel(scrollController, mapProvider.selectedPlace!);
              },
            ),

          if (mapProvider.nearbySearchResults.isNotEmpty && mapProvider.selectedPlace == null)
            _buildNearbySearchResultsPanel(mapProvider),

          if (mapProvider.selectedPlace != null)
            _buildPlaceDetailsTopBar(mapProvider)
          else
            _buildTopSearchBar(mapProvider),

          if (mapProvider.isSearching && mapProvider.nearbySearchResults.isEmpty)
            _buildSearchResultsOverlay(mapProvider),

          if (mapProvider.selectedPlace == null && !mapProvider.isSearching && mapProvider.nearbySearchResults.isEmpty) ...[
            //_buildBottomNavBar(),
            _buildRightSideButtons(),
          ],

          if (_isProfileMenuVisible) _buildProfileMenu(),
        ],
      ),
    );
  }

  Widget _buildNearbySearchResultsPanel(MapProvider mapProvider) {
    final filters = mapProvider.getFiltersForKeyword();

    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.15,
      maxChildSize: 0.7,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
            boxShadow: [BoxShadow(blurRadius: 10.0, color: Colors.black.withOpacity(0.15))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Draggable tab
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              // --- NEW: Title with Close Button ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Results near you", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => context.read<MapProvider>().clearNearbySearch(),
                    ),
                  ],
                ),
              ),

              // Filter Chips
              SizedBox(
                height: 50,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  scrollDirection: Axis.horizontal,
                  itemCount: filters.length,
                  itemBuilder: (context, index) {
                    final filter = filters[index];
                    return FilterChip(
                      label: Text(filter),
                      selected: mapProvider.activeFilter == filter,
                      onSelected: (selected) {
                        mapProvider.applyFilter(filter);
                      },
                    );
                  },
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                ),
              ),

              // The scrollable list
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: mapProvider.filteredNearbyResults.length,
                  itemBuilder: (context, index) {
                    final place = mapProvider.filteredNearbyResults[index];
                    return _buildSearchResultListItem(place, mapProvider);
                  },
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

// This method builds a single item in the list
  Widget _buildSearchResultListItem(Place place, MapProvider mapProvider) {
    return InkWell(
      onTap: () {
        // When tapped, select this place to show its full details
        mapProvider.selectPlace(place.placeId, place.name);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(place.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(place.address, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                if (place.rating != null) ...[
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                  const SizedBox(width: 4),
                  Text(place.rating.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text('•', style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(width: 8),
                ],
                Text(
                  place.isOpenNow == null ? 'Hours unknown' : (place.isOpenNow! ? 'Open' : 'Closed'),
                  style: TextStyle(
                    color: place.isOpenNow == true ? Colors.green.shade700 : Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () {
                    if (_currentUserLatLng != null) {
                      final placeDetails = PlaceDetails(
                          placeId: place.placeId,
                          name: place.name,
                          address: place.address,
                          coordinates: place.coordinates);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => DirectionsScreen(
                          destination: placeDetails,
                          originCoordinates: _currentUserLatLng!,
                        ),
                      ));
                    }
                  },
                  icon: Icon(Icons.directions, color: Theme.of(context).primaryColor),
                  splashRadius: 20,
                ),
                IconButton(
                  onPressed: () {
                    final placeDetails = PlaceDetails(
                        placeId: place.placeId,
                        name: place.name,
                        address: place.address,
                        coordinates: place.coordinates);
                    _showSavePlaceDialog(placeDetails);
                  },
                  icon: const Icon(Icons.bookmark_border),
                  splashRadius: 20,
                ),
                IconButton(
                  onPressed: () {
                    Share.share(
                        'Check out this location: ${place.name}, ${place.address}');
                  },
                  icon: const Icon(Icons.share),
                  splashRadius: 20,
                ),
              ],
            ),
            // REMOVED the Divider from here
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceDetailsTopBar(MapProvider mapProvider) {
    return Positioned(
      top: 50.0,
      left: 15.0,
      right: 15.0,
      child: Material(
        elevation: 4.0,
        borderRadius: BorderRadius.circular(30.0),
        child: Container(
          height: 58.0,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(30.0),
          ),
          child: Row(
            children: [
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => context.read<MapProvider>().closePlaceDetails(),),
              Expanded(
                child: Text(
                  mapProvider.selectedPlace?.address ?? 'Location Details',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceDetailsPanel(ScrollController scrollController, PlaceDetails place) {
    return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
          boxShadow: [
            BoxShadow(
              blurRadius: 10.0,
              color: Colors.black.withOpacity(0.15),
            )
          ],
        ),
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  Text(place.name,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (place.city != null && place.state != null)
                    Text('${place.city}, ${place.state}',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.grey[600])),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildActionButton("directions_fab", Icons.directions, "Directions", () {
                        if (_currentUserLatLng != null) {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => DirectionsScreen(
                              destination: place,
                              originCoordinates: _currentUserLatLng!,
                            ),
                          ));
                        }
                      }),
                      _buildActionButton("save_fab", Icons.bookmark_border, "Save", () {
                        _showSavePlaceDialog(place);
                      }),
                      _buildActionButton("share_fab", Icons.share, "Share", () {
                        Share.share(
                            'Check out this location: ${place.name}, ${place.address}');
                      }),
                    ],
                  ),
                  const Divider(height: 40),
                  if (place.photoUrls.isNotEmpty)
                    _buildPhotoGallery(place.photoUrls),
                  if (place.rating != null) _buildRating(place.rating!),
                  _buildInfoTile(
                      Icons.location_on_outlined, place.address, true),
                  if (place.openingHoursStatus != null && place.openingHoursStatus!.isNotEmpty)
                    _buildInfoTile(
                        Icons.access_time, place.openingHoursStatus!, false),
                  if (place.phoneNumber != null && place.phoneNumber!.isNotEmpty)
                    _buildInfoTile(
                        Icons.phone_outlined, place.phoneNumber!, false, onTap: () async {
                      final url = Uri.parse('tel:${place.phoneNumber}');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url);
                      }
                    }),
                  if (place.website != null && place.website!.isNotEmpty)
                    _buildInfoTile(Icons.public, place.website!, false,
                        onTap: () async {
                          final url = Uri.parse(place.website!);
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        }),
                  _buildAboutSection(place),
                ],
              ),
            ),
          ],
        ));
  }

  Widget _buildPhotoGallery(List<String> photoUrls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Photos", style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: photoUrls.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: Image.network(
                    photoUrls[index],
                    width: 150,
                    height: 120,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      return progress == null
                          ? child
                          : Container(
                          width: 150,
                          height: 120,
                          color: Colors.grey[200],
                          child: const Center(child: CircularProgressIndicator()));
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 150,
                      height: 120,
                      color: Colors.grey[200],
                      child: const Icon(Icons.error_outline),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 30),
      ],
    );
  }

  Widget _buildRating(double rating) {
    List<Widget> stars = [];
    for (int i = 0; i < 5; i++) {
      stars.add(Icon(
        i < rating.round() ? Icons.star : Icons.star_border,
        color: Colors.amber,
        size: 20,
      ));
    }
    return Column(
      children: [
        Row(
          children: [
            ...stars,
            const SizedBox(width: 8),
            Text('$rating from Google',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const Divider(height: 30),
      ],
    );
  }

  Widget _buildInfoTile(IconData icon, String text, bool isAddress,
      {VoidCallback? onTap}) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: Theme.of(context).iconTheme.color),
          title: Text(text),
          trailing: isAddress
              ? IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Address copied!")));
            },
          )
              : null,
          onTap: onTap,
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildAboutSection(PlaceDetails place) {
    // Check if we have a summary to display
    if (place.editorialSummary != null && place.editorialSummary!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text("About", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            place.editorialSummary!,
            style: const TextStyle(color: Colors.grey, height: 1.5),
          ),
        ],
      );
    }

    // If there's no summary, return an empty widget
    return const SizedBox.shrink();
  }

  Widget _buildActionButton(String heroTag, IconData icon, String label, VoidCallback onPressed) {
    return Column(
      children: [
        FloatingActionButton(
          heroTag: heroTag,
          onPressed: onPressed,
          mini: true,
          child: Icon(icon),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTopSearchBar(MapProvider mapProvider) {
    final user = widget.user;
    final userName = user.displayName?.isNotEmpty == true ? user.displayName : (user.email?.split('@')[0] ?? 'Explorer');
    final profileImageUrl = user.photoURL;
    return Positioned(
      top: 50.0,
      left: 15.0,
      right: 15.0,
      child: Material(
        elevation: 4.0,
        borderRadius: BorderRadius.circular(30.0),
        child: Container(
          height: 58.0,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(30.0),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: mapProvider.isSearching ? 0 : 48,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: mapProvider.isSearching ? 0 : 1,
                  child: CircleAvatar(
                    radius: 20,
                    child: ClipOval(child: Image.asset('assets/images/ic_launcher_foreground.png')),
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchQueryChanged,
                  onSubmitted: (String keyword) {
                    if (_currentUserLatLng != null) {
                      context.read<MapProvider>().searchNearby(keyword, _currentUserLatLng!);
                      _addToSearchHistory(SearchHistoryItem(description: keyword));
                      _searchFocusNode.unfocus();
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    border: InputBorder.none,
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: _clearSearch,
                    )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              GestureDetector(
                onTap: () => setState(() => _isProfileMenuVisible = true),
                child: CircleAvatar(
                  radius: 20,
                  backgroundImage: profileImageUrl != null ? NetworkImage(profileImageUrl) : null,
                  child: profileImageUrl == null ? const Icon(Icons.person) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultsOverlay(MapProvider mapProvider) {
    final bool showHistory = _searchController.text.isEmpty;
    final bool showSuggestions = mapProvider.suggestions.isNotEmpty;
    if (!showHistory && !showSuggestions) return const SizedBox.shrink();

    return Positioned(
      top: 115,
      left: 15,
      right: 15,
      child: Material(
        elevation: 4.0,
        borderRadius: BorderRadius.circular(16.0),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: showHistory
              ? _buildHistoryAndSavedPlacesList(mapProvider)
              : ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: mapProvider.suggestions.length,
            itemBuilder: (context, index) {
              final suggestion = mapProvider.suggestions[index];
              return ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(suggestion.description),
                onTap: () {
                  final prov = context.read<MapProvider>();
                  _addToSearchHistory(SearchHistoryItem(placeId: suggestion.placeId, description: suggestion.description));
                  prov.selectPlace(suggestion.placeId, suggestion.description).then((_) {
                    if (prov.selectedPlace != null) {
                      mapController.animateCamera(CameraUpdate.newLatLngZoom(prov.selectedPlace!.coordinates, 15));
                    }
                  });
                  prov.stopSearch(_searchFocusNode, _searchController);
                },
              );
            },
          ),
        ),
      ),
    );
  }


  Widget _buildHistoryAndSavedPlacesList(MapProvider mapProvider) {
    List<Widget> listItems = [];

    if (_savedPlaces.isNotEmpty) {
      listItems.add(const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text("Saved Places", style: TextStyle(fontWeight: FontWeight.bold)),
      ));
      // UI CHANGE: Horizontal scrollable list for saved places
      listItems.add(SizedBox(
        height: 100, // Define a fixed height for the horizontal list
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _savedPlaces.length,
          itemBuilder: (context, index) {
            final place = _savedPlaces[index];
            IconData icon;
            switch (place.name.toLowerCase()) {
              case 'home':
                icon = Icons.home;
                break;
              case 'work':
                icon = Icons.work;
                break;
              default:
                icon = Icons.star;
            }
            return GestureDetector(
              onTap: () => _selectPlace(place.placeId, place.address),
              child: Container(
                width: 100,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      child: Icon(icon),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      place.name,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ));
      listItems.add(const Divider());
    }

    if (_searchHistory.isNotEmpty) {
      listItems.add(const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text("Recent", style: TextStyle(fontWeight: FontWeight.bold)),
      ));
      listItems.addAll(_searchHistory.map((item) {
        bool isPlace = item.placeId != null;
        return ListTile(
          leading: Icon(isPlace ? Icons.history : Icons.search),
          title: Text(item.description),
          onTap: () {
            if (isPlace) {
              // It's a place, select it
              mapProvider.selectPlace(item.placeId!, item.description).then((_){
                // ... animate camera ...
              });
              mapProvider.stopSearch(_searchFocusNode, _searchController);
            } else {
              // It's a keyword, perform a nearby search
              _searchController.text = item.description;
              if (_currentUserLatLng != null) {
                mapProvider.searchNearby(item.description, _currentUserLatLng!);
              }
            }
          },
        );
      }));
    }

    return ListView(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      children: listItems,
    );
  }

  Widget _buildProfileMenu() {
    final user = widget.user;
    final isGuest = user.isAnonymous;
    final userName =
    user.displayName?.isNotEmpty == true ? user.displayName : "Guest Explorer";
    final userEmail = user.email ?? "No email provided";
    return Positioned(
      top: 105,
      right: 15,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16.0),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGuest ? "Guest Mode" : userName!,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        if (!isGuest)
                          Text(userEmail,
                              style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  IconButton(
                      onPressed: _toggleProfileMenu,
                      icon: const Icon(Icons.close))
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.person_outline,
                  color: Theme.of(context).iconTheme.color),
              title: Text('View Profile',
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color)),
              onTap: () {Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const EditProfileScreen()),
              );
              }
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text("SETTINGS",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            SwitchListTile(
              title: Text('Active Road Discovery',
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color)),
              value: _isAdaptiveDiscoveryEnabled,
              onChanged: (val) =>
                  setState(() => _isAdaptiveDiscoveryEnabled = val),
              secondary:
              Icon(Icons.sensors, color: Theme.of(context).iconTheme.color),
            ),
            ListTile(
              leading:
              Icon(Icons.public, color: Theme.of(context).iconTheme.color),
              title: Text('Change country',
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.watch<SettingsProvider>().selectedCountry,
                      style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios,
                      size: 14, color: Colors.grey)
                ],
              ),
              onTap: _showCountrySelectorDialog,
            ),
            ListTile(
              leading: Icon(Icons.palette_outlined,
                  color: Theme.of(context).iconTheme.color),
              title: Text('App Theme',
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      _currentTheme.name[0].toUpperCase() +
                          _currentTheme.name.substring(1),
                      style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios,
                      size: 14, color: Colors.grey)
                ],
              ),
              onTap: _showThemeSelectorDialog,
            ),
            // TTS VOICE SELECTION: Add ListTile for voice selection
            ListTile(
              leading: Icon(Icons.record_voice_over, color: Theme.of(context).iconTheme.color),
              title: Text('Voice', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _availableFriendlyVoices
                        .firstWhere((v) => v.id == _selectedTtsVoice, orElse: () => TtsVoiceInfo(id: '', displayName: 'Default'))
                        .displayName,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                ],
              ),
              onTap: _showVoiceSelectorDialog,
            ),
            const Divider(height: 1),
            if (isGuest)
              ListTile(
                leading: const Icon(Icons.login, color: Colors.blue),
                title: const Text('Login / Sign Up',
                    style: TextStyle(color: Colors.blue)),
                onTap: _logout,
              )
            else
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title:
                const Text('Logout', style: TextStyle(color: Colors.red)),
                onTap: _logout,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightSideButtons() {
    return Positioned(
      bottom: 100,
      right: 15,
      child: Column(
        children: <Widget>[
          FloatingActionButton(
            heroTag: "center_location",
            onPressed: _toggleFollowUserMode,
            backgroundColor:
            _isFollowingUser ? Colors.blue : Theme.of(context).cardColor,
            foregroundColor: _isFollowingUser
                ? Colors.white
                : Theme.of(context).iconTheme.color,
            mini: true,
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "layers",
            onPressed: _showLayerDialog,
            backgroundColor: Theme.of(context).cardColor,
            foregroundColor: Theme.of(context).iconTheme.color,
            mini: true,
            child: const Icon(Icons.layers),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5)
              ],
            ),
            child: Column(
              children: [
                IconButton(icon: const Icon(Icons.add), onPressed: _zoomIn),
                const SizedBox(
                    height: 1,
                    width: 30,
                    child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.grey))),
                IconButton(
                    icon: const Icon(Icons.remove), onPressed: _zoomOut),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Set<Marker> _buildMarkers(MapProvider mapProvider) {
    final Set<Marker> markers = {};

    // --- CHANGED: Wrap the user marker logic in an AnimatedBuilder ---
    if (_markerAnimationController != null && _userMarkerIcon != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('userLocation'),
          position: _positionAnimation?.value ?? _currentUserLatLng ?? _previousLatLng ?? _center,
          icon: _userMarkerIcon!,
          rotation: _rotationAnimation?.value ?? _currentUserRotation,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          zIndex: 2.0,
        ),
      );
    }

    markers.addAll(mapProvider.markers);
    return markers;
  }
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