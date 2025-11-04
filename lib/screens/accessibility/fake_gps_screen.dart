import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:mapz/api/google_maps_api_service.dart';
import 'package:mapz/providers/fake_location_provider.dart';
import 'package:provider/provider.dart';


class FakeGpsScreen extends StatefulWidget {
  const FakeGpsScreen({super.key});

  @override
  State<FakeGpsScreen> createState() => _FakeGpsScreenState();
}

class _FakeGpsScreenState extends State<FakeGpsScreen> {
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _durationController =
  TextEditingController(text: '10');
  final TextEditingController _speedController =
  TextEditingController(text: '50');

  bool _showRouteOptions = false;
  GoogleMapController? _mapController;
  final Location _location = Location();
  Timer? _debounce;
  bool _isMapMoving = false;

  LatLng? _fromLatLng;
  LatLng? _toLatLng;


  @override
  void initState() {
    super.initState();
    _fromController.addListener(() {
      if (mounted) {
        setState(() {
          _showRouteOptions = _fromController.text.isNotEmpty;
        });
      }
    });
  }

    @override
    void dispose() {
      _fromController.dispose();
      _toController.dispose();
      _durationController.dispose();
      _speedController.dispose();
      _debounce?.cancel();
      super.dispose();
    }

    void _centerOnUser() async {
      try {
        var userLocation = await _location.getLocation();
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(userLocation.latitude!, userLocation.longitude!),
            16.0,
          ),
        );
      } catch (e) {
        // Handle error (e.g., location permission denied)
      }
    }

    void _onCameraIdle() async {
      if (!_isMapMoving || _mapController == null) return; // Don't run on init

      _isMapMoving = false;
      final LatLng center = await _mapController!.getLatLng(
        ScreenCoordinate(
          x: MediaQuery.of(context).size.width ~/ 2,
          y: (MediaQuery.of(context).size.height * 0.5) ~/ 2, // Center of the map view
        ),
      );

      _toLatLng = center;
      // Get the human-readable address
      final apiService = context.read<GoogleMapsApiService>();
      try {
        final result = await apiService.reverseGeocode(center);
        if (result['status'] == 'OK' && result['results'].isNotEmpty) {
          _toController.text = result['results'][0]['formatted_address'];
        }
      } catch (e) {
        _toController.text = 'Lat: ${center.latitude}, Lng: ${center.longitude}';
      }
    }

    void _geocodeAddress(String address, {bool isFrom = false}) {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 700), () async {
        if (address.isEmpty) return;

        final apiService = context.read<GoogleMapsApiService>();
        try {
          final result = await apiService.geocode(address);
          if (result['status'] == 'OK' && result['results'].isNotEmpty) {
            final loc = result['results'][0]['geometry']['location'];
            final latLng = LatLng(loc['lat'], loc['lng']);

            if (isFrom) {
              _fromLatLng = latLng;
            } else {
              _toLatLng = latLng;
              _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16.0));
            }
          }
        } catch (e) {
          // Handle geocoding error
        }
      });
    }

  void _startSimulation() async {
    final fakeGps = context.read<FakeLocationProvider>();
    final apiService = context.read<GoogleMapsApiService>();

    // --- FIX: Capture context-dependent variables before await ---
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Ensure we have a "To" location (the map center)
    _toLatLng ??= await _mapController?.getLatLng(
      ScreenCoordinate(
        x: MediaQuery.of(context).size.width ~/ 2,
        y: (MediaQuery.of(context).size.height * 0.5) ~/ 2,
      ),
    );

    if (_toLatLng == null) return;

    // Case 1: "To" location only. Set a static fake location.
    if (_fromLatLng == null) {
      // --- FIX: Removed 'await' ---
      fakeGps.setManualFakeLocation(_toLatLng!);

      // --- FIX: Use captured variable ---
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Set fake location to: ${_toController.text}')),
      );
      // --- FIX: Use captured variable ---
      navigator.pop(); // Close the screen
      return;
    }

    // Case 2: "From" and "To" locations. Simulate a route.
    try {
      final directions = await apiService.getDirections(
        origin: _fromLatLng!,
        destination: _toLatLng!,
        travelMode: 'driving',
      );

      if (directions['status'] == 'OK') {
        final polyline = directions['routes'][0]['overview_polyline']['points'];
        final List<LatLng> points = _decodePolyline(polyline);
        final double speed = double.tryParse(_speedController.text) ?? 50.0;

        // --- FIX: Removed 'await' ---
        fakeGps.startRouteSimulation(points, speed);

        // --- FIX: Use captured variable ---
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Starting fake route simulation...')),
        );
        // --- FIX: Use captured variable ---
        navigator.pop();
      }
    } catch (e) {
      // --- FIX: Use captured variable ---
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to get route: $e')),
      );
    }
  }
    void _updateNumberField(TextEditingController controller, int step) {
      int currentValue = int.tryParse(controller.text) ?? 0;
      currentValue += step;
      if (currentValue < 1) currentValue = 1; // Don't allow 0 or negative
      controller.text = currentValue.toString();
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Fake GPS Location'),
        ),
        body: Column(
          children: [
            // --- 1. The Mini Map ---
            Expanded(
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(44.6702, -63.5739), // Default
                      zoom: 12,
                    ),
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _centerOnUser(); // Move to user's location on start
                    },
                    onCameraMoveStarted: () => _isMapMoving = true,
                    onCameraIdle: _onCameraIdle,
                    myLocationButtonEnabled: false,
                    myLocationEnabled: true,
                    zoomControlsEnabled: false,
                  ),
                  // The blue dot in the middle
                  const Center(
                    child: Icon(
                      Icons.location_pin,
                      color: Colors.blue,
                      size: 40,
                    ),
                  ),
                  // "Show Live Location" Button
                  Positioned(
                    top: 10,
                    right: 10,
                    child: FloatingActionButton(
                      mini: true,
                      onPressed: _centerOnUser,
                      child: const Icon(Icons.my_location),
                    ),
                  )
                ],
              ),
            ),

            // --- 2. The Controls Panel ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _fromController,
                      decoration: const InputDecoration(
                        labelText: 'From',
                        prefixIcon: Icon(Icons.trip_origin),
                      ),
                      onChanged: (value) => _geocodeAddress(value, isFrom: true),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _toController,
                      decoration: const InputDecoration(
                        labelText: 'To',
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      onChanged: (value) => _geocodeAddress(value, isFrom: false),
                    ),

                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: _showRouteOptions
                          ? _buildRouteOptions()
                          : const SizedBox(width: double.infinity),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _startSimulation,
                        child: const Text('Start Fake Location'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

  // Helper widget for the Speed/Duration controls
  Widget _buildRouteOptions() {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0),
      child: Row(
        children: [
          // Duration
          Expanded(
            child: _buildControlColumn(
              label: 'Duration (min)',
              controller: _durationController,
              onDecrement: () => _updateNumberField(_durationController, -1),
              onIncrement: () => _updateNumberField(_durationController, 1),
            ),
          ),
          const SizedBox(width: 16),
          // Speed
          Expanded(
            child: _buildControlColumn(
              label: 'Speed (km/h)',
              controller: _speedController,
              onDecrement: () => _updateNumberField(_speedController, -5),
              onIncrement: () => _updateNumberField(_speedController, 5),
            ),
          ),
        ],
      ),
    );
  }

  // Helper for the individual control
  Widget _buildControlColumn({
    required String label,
    required TextEditingController controller,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(icon: const Icon(Icons.remove), onPressed: onDecrement),
            Expanded(
              child: TextField(
                controller: controller,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(8),
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.add), onPressed: onIncrement),
          ],
        ),
      ],
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }
}