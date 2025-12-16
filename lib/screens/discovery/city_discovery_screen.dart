import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../services/road_discovery_service.dart';
import '../../services/database_service.dart';
import '../../models/discovered_road.dart';

// --- MAIN ENTRY SCREEN (COUNTRIES) ---
class RoadDiscoveriezScreen extends StatefulWidget {
  const RoadDiscoveriezScreen({super.key});

  @override
  State<RoadDiscoveriezScreen> createState() => _RoadDiscoveriezScreenState();
}

class _RoadDiscoveriezScreenState extends State<RoadDiscoveriezScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    final service = context.read<RoadDiscoveryService>();
    final data = await service.getVisitedCountries();
    if (mounted) setState(() { _items = data; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return _DiscoveryListScaffold(
      title: "Countries Visited",
      isLoading: _isLoading,
      items: _items,
      onTapItem: (item) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _StateListScreen(country: item['name']),
        ));
      },
    );
  }
}

// --- LEVEL 2: STATES ---
class _StateListScreen extends StatefulWidget {
  final String country;
  const _StateListScreen({required this.country});

  @override
  State<_StateListScreen> createState() => _StateListScreenState();
}

class _StateListScreenState extends State<_StateListScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStates();
  }

  Future<void> _loadStates() async {
    final service = context.read<RoadDiscoveryService>();
    final data = await service.getVisitedStates(widget.country);
    if (mounted) setState(() { _items = data; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return _DiscoveryListScaffold(
      title: "States in ${widget.country}",
      isLoading: _isLoading,
      items: _items,
      onTapItem: (item) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _CityListScreen(country: widget.country, state: item['name']),
        ));
      },
    );
  }
}

// --- LEVEL 3: CITIES ---
class _CityListScreen extends StatefulWidget {
  final String country;
  final String state;
  const _CityListScreen({required this.country, required this.state});

  @override
  State<_CityListScreen> createState() => _CityListScreenState();
}

class _CityListScreenState extends State<_CityListScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  Future<void> _loadCities() async {
    final service = context.read<RoadDiscoveryService>();
    final data = await service.getVisitedCities(widget.country, widget.state);
    if (mounted) setState(() { _items = data; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return _DiscoveryListScaffold(
      title: "Cities in ${widget.state}",
      isLoading: _isLoading,
      items: _items,
      onTapItem: (item) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => CityHeatmapView(
            country: widget.country,
            state: widget.state,
            city: item['name'],
          ),
        ));
      },
    );
  }
}

// --- SHARED SCAFFOLD ---
class _DiscoveryListScaffold extends StatelessWidget {
  final String title;
  final bool isLoading;
  final List<Map<String, dynamic>> items;
  final Function(Map<String, dynamic>) onTapItem;

  const _DiscoveryListScaffold({
    required this.title,
    required this.isLoading,
    required this.items,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade900, Colors.black],
          ),
        ),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
            ? const Center(child: Text("No discoveries here yet!", style: TextStyle(color: Colors.white)))
            : ListView.builder(
          padding: const EdgeInsets.only(top: 100, bottom: 20),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final double pct = item['percentage'];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                onTap: () => onTapItem(item),
                title: Text(
                  item['name'],
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "${(pct * 100).toStringAsFixed(2)}%",
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      "${item['count']} segments",
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
                leading: CircularProgressIndicator(
                  value: pct,
                  backgroundColor: Colors.grey.withOpacity(0.3),
                  color: Colors.greenAccent,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// --- LEVEL 4: HEATMAP ---
class CityHeatmapView extends StatefulWidget {
  final String country;
  final String state;
  final String city;

  const CityHeatmapView({super.key, required this.country, required this.state, required this.city});

  @override
  State<CityHeatmapView> createState() => _CityHeatmapViewState();
}

class _CityHeatmapViewState extends State<CityHeatmapView> {
  final Set<Polyline> _polylines = {};
  late GoogleMapController _controller;
  bool _loading = true;
  LatLngBounds? _cityBounds;

  @override
  void initState() {
    super.initState();
    _loadCityRoads();
  }

  Future<void> _loadCityRoads() async {
    final roads = await DatabaseService().getRoadsByCity(widget.country, widget.state, widget.city);

    if (roads.isNotEmpty) {
      double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;

      for (var road in roads) {
        // Calculate bounds
        if (road.latitude < minLat) minLat = road.latitude;
        if (road.latitude > maxLat) maxLat = road.latitude;
        if (road.longitude < minLng) minLng = road.longitude;
        if (road.longitude > maxLng) maxLng = road.longitude;

        _polylines.add(Polyline(
          polylineId: PolylineId("road_${road.placeId}"),
          points: [
            LatLng(road.latitude, road.longitude),
            LatLng(road.latitude + 0.00005, road.longitude + 0.00005)
          ],
          color: Colors.greenAccent.withOpacity(0.6),
          width: 5,
        ));
      }

      _cityBounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.city)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
        initialCameraPosition: const CameraPosition(target: LatLng(0, 0), zoom: 2),
        onMapCreated: (controller) async {
          _controller = controller;
          if (_cityBounds != null) {
            // Wait a moment for map to init
            Future.delayed(const Duration(milliseconds: 300), () {
              controller.moveCamera(CameraUpdate.newLatLngBounds(_cityBounds!, 50));
            });
          }
        },
        // Lock camera to city bounds
        cameraTargetBounds: _cityBounds != null
            ? CameraTargetBounds(_cityBounds!)
            : CameraTargetBounds.unbounded,
        minMaxZoomPreference: const MinMaxZoomPreference(10, 20), // Prevent zooming out too far
        polylines: _polylines,
        mapType: MapType.normal,
        myLocationEnabled: false,
        myLocationButtonEnabled: false,
      ),
    );
  }
}