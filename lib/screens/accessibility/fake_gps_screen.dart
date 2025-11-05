import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mapz/models/place.dart';
import 'package:mapz/providers/fake_location_provider.dart';
import 'package:provider/provider.dart';

class FakeGpsScreen extends StatefulWidget {
  const FakeGpsScreen({super.key});

  @override
  State<FakeGpsScreen> createState() => _FakeGpsScreenState();
}

class _FakeGpsScreenState extends State<FakeGpsScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _fromController = TextEditingController();
  final FocusNode _toFocus = FocusNode();
  final FocusNode _fromFocus = FocusNode();

  // --- NEW: State for speed slider ---
  double _selectedSpeedKmph = 50.0;

  @override
  void initState() {
    super.initState();
    final provider = context.read<FakeLocationProvider>();

    // Generate a new session token only if not already faking
    if (!provider.isFaking) {
      provider.generateSessionToken();
    }

    // Add listeners to fetch suggestions
    _toController.addListener(() => _onSearchChanged(true));
    _fromController.addListener(() => _onSearchChanged(false));

    _toFocus.addListener(() => _onFocusChanged(true));
    _fromFocus.addListener(() => _onFocusChanged(false));

    // Pre-fill text fields from provider state
    _toController.text = provider.toPlace?.name ?? '';
    _fromController.text = provider.fromPlace?.name ?? '';
  }

  void _onSearchChanged(bool isToField) {
    // Only fetch suggestions if the text field has focus
    if (isToField) {
      if (_toFocus.hasFocus) {
        context
            .read<FakeLocationProvider>()
            .fetchSuggestions(_toController.text, isFromField: false);
      }
    } else {
      if (_fromFocus.hasFocus) {
        context
            .read<FakeLocationProvider>()
            .fetchSuggestions(_fromController.text, isFromField: true);
      }
    }
  }

  void _onFocusChanged(bool isToField) {
    final provider = context.read<FakeLocationProvider>();
    // When focusing, generate a token if it's null (e.g., first run)
    if (_toFocus.hasFocus || _fromFocus.hasFocus) {
      provider.generateSessionToken();
    }

    // Clear suggestions for the *other* field when this one gains focus
    if (isToField) {
      if (_toFocus.hasFocus) {
        provider.clearSuggestions(true); // Clear 'from'
      }
    } else {
      if (_fromFocus.hasFocus) {
        provider.clearSuggestions(false); // Clear 'to'
      }
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _toController.dispose();
    _fromController.dispose();
    _toFocus.dispose();
    _fromFocus.dispose();

    // --- FIX: REMOVED THE LINE THAT CAUSED THE CRASH ---
    // DO NOT call context.read() in dispose.
    // We will clear the token from the provider itself if needed.

    super.dispose();
  }

  void _onPlaceSelected(PlaceSuggestion suggestion, bool isToField) {
    final provider = context.read<FakeLocationProvider>();
    provider.setPlace(suggestion: suggestion, isFromField: !isToField).then((_) {
      // After setting, update text controllers from provider
      _toController.text = provider.toPlace?.name ?? '';
      _fromController.text = provider.fromPlace?.name ?? '';
      _toFocus.unfocus();
      _fromFocus.unfocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use Consumer to react to provider changes
    return Consumer<FakeLocationProvider>(
      builder: (context, provider, child) {
        // Animate map to new route bounds when they change
        if (provider.routeBounds != null && _mapController != null) {
          // Check if map is already at bounds to prevent loop
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(
              provider.routeBounds!,
              50.0, // Padding
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Fake GPS Location'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                // Manually clear token when user presses back
                provider.clearSessionToken();
                Navigator.of(context).pop();
              },
            ),
          ),
          body: WillPopScope(
            // Also clear token on system back button
            onWillPop: () async {
              provider.clearSessionToken();
              return true;
            },
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildLocationInputs(provider),
                    _buildEtaDisplay(provider),
                    Expanded(
                      child: GoogleMap(
                        onMapCreated: (controller) => _mapController = controller,
                        initialCameraPosition: const CameraPosition(
                          target: LatLng(44.6702, -63.5739), // Default
                          zoom: 12.0,
                        ),
                        polylines: provider.polylines,
                        myLocationButtonEnabled: false,
                        myLocationEnabled: false,
                      ),
                    ),
                    _buildBottomBar(provider),
                  ],
                ),
                // --- Suggestions Overlay ---
                if (provider.toSuggestions.isNotEmpty)
                  _buildSuggestionsOverlay(provider.toSuggestions, true),
                if (provider.fromSuggestions.isNotEmpty)
                  _buildSuggestionsOverlay(provider.fromSuggestions, false),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Swapped UI (To/From) ---
  Widget _buildLocationInputs(FakeLocationProvider provider) {
    bool isReadOnly = provider.isFaking;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _toController,
                  focusNode: _toFocus,
                  readOnly: isReadOnly,
                  decoration: const InputDecoration(
                    hintText: 'To: Choose destination',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          const Divider(),
          Row(
            children: [
              const Icon(Icons.my_location, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _fromController,
                  focusNode: _fromFocus,
                  readOnly: isReadOnly,
                  decoration: const InputDecoration(
                    hintText: 'From: Your location',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.swap_vert),
                onPressed:
                isReadOnly ? null : () {
                  provider.swapFromAndTo();
                  // Update controllers after swap
                  _toController.text = provider.toPlace?.name ?? '';
                  _fromController.text = provider.fromPlace?.name ?? '';
                },
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }

  // --- ETA Display ---
  Widget _buildEtaDisplay(FakeLocationProvider provider) {
    if (provider.routeEta == null || provider.isFaking) {
      return const SizedBox.shrink(); // Hide if no ETA or if faking
    }
    return Container(
      width: double.infinity,
      color: Theme.of(context).canvasColor,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
        'ETA: ${provider.routeEta} (${provider.routeDistance})',
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
        textAlign: TextAlign.center,
      ),
    );
  }

  // --- State-Managed Button & NEW SLIDER ---
  Widget _buildBottomBar(FakeLocationProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- NEW: Speed Slider ---
          if (!provider.isFaking) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  const Icon(Icons.speed_outlined, color: Colors.grey),
                  Expanded(
                    child: Slider(
                      value: _selectedSpeedKmph,
                      min: 10,  // Min 10 km/h
                      max: 200, // Max 200 km/h
                      divisions: 19,
                      label: '${_selectedSpeedKmph.round()} km/h',
                      onChanged: (double value) {
                        setState(() {
                          _selectedSpeedKmph = value;
                        });
                      },
                    ),
                  ),
                  Text('${_selectedSpeedKmph.round()} km/h', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          // --- END: Speed Slider ---

          SizedBox(
            width: double.infinity,
            child: provider.isFaking
                ? ElevatedButton(
              onPressed: () {
                provider.stopSimulation();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Stop Fake Location',
                  style: TextStyle(color: Colors.white)),
            )
                : ElevatedButton(
              onPressed: (provider.fromPlace != null &&
                  provider.toPlace != null)
                  ? () {
                // Use the speed from the slider
                provider.startRouteSimulation(_selectedSpeedKmph);
              }
                  : null, // Disabled if no route
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Start Fake Location'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsOverlay(
      List<PlaceSuggestion> suggestions, bool isToField) {
    // Position the overlay below the correct text field
    final topPosition = isToField ? 120.0 : 180.0;
    return Positioned(
      top: topPosition,
      left: 16,
      right: 16,
      child: Material(
        elevation: 4.0,
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(suggestion.description),
                onTap: () => _onPlaceSelected(suggestion, isToField),
              );
            },
          ),
        ),
      ),
    );
  }
}