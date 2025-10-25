import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:location/location.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/discovery/achievement.dart';
import '../../models/discovery/leaderboard_user.dart';
import '../../models/discovery/tier.dart';
import '../../services/leaderboard_service.dart';
import '../../services/road_discovery_service.dart';
import '../../providers/settings_provider.dart';

class RoadDiscoveryScreen extends StatefulWidget {
  const RoadDiscoveryScreen({super.key});

  @override
  State<RoadDiscoveryScreen> createState() => _RoadDiscoveryScreenState();
}

class _RoadDiscoveryScreenState extends State<RoadDiscoveryScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin{
  // --- State Variables ---
  double? _discoveryPercentage;
  Tier? _userTier;
  List<LeaderboardUser> _nationalRankings = [];
  final Set<Heatmap> _heatmaps = {};
  bool _isLoading = true; // To show a loading indicator
  List<LeaderboardUser> _rivalsRankings = [];
  List<LeaderboardUser> _sharingRankings = [];
  double _currentUserRotation = 0.0;
  String? _currentCountry;

  GoogleMapController? _atlasMapController;
  StreamSubscription<LocationData>? _locationSubscription;
  LatLng? _currentUserLocation;
  String _darkMapStyle = '';
  String _lightMapStyle = '';
  BitmapDescriptor? _userMarkerIcon; // For custom marker
  final Set<Marker> _markers = {};

  late TabController _tabController;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _loadMapStyles();
    _loadMarkerIcon();
    _initAtlasLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get the latest country from the provider
    final newCountry = context.watch<SettingsProvider>().selectedCountry;

    // If the country has changed (or it's the first time loading), fetch all new data
    if (_currentCountry != newCountry) {
      _currentCountry = newCountry;
      _loadAllData();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final discoveryService = context.read<RoadDiscoveryService>();
    final leaderboardService = context.read<LeaderboardService>();
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null || _currentCountry == null) {
      setState(() => _isLoading = false);
      return;
    }

    final results = await Future.wait([
      discoveryService.calculateDiscoveryPercentage(_currentCountry!),
      leaderboardService.getNationalLeaderboard(_currentCountry!),
      discoveryService.getAllDiscoveredPoints(),
    ]);

    final percentage = results[0] as double;
    final rankings = results[1] as List<LeaderboardUser>;
    final atlasPoints = results[2] as List<LatLng>;
    final userTier = TierManager.getTier(percentage);

    bool isUserInList = rankings.any(
      (user) => user.name == (currentUser.displayName ?? 'You'),
    );
    if (!isUserInList) {
      rankings.insert(
        0,
        LeaderboardUser(
          name: currentUser.displayName ?? 'You',
          percentage: percentage,
          tier: userTier,
        ),
      );
      // In a real app, you might want to sort the list again here.
    }

    final rivals = await leaderboardService.getRivals(userTier);
    final sharers = await leaderboardService.getLocationSharers();

    if (atlasPoints.isNotEmpty) {
      final heatmap = Heatmap(
        heatmapId: const HeatmapId('discovery_heatmap'),
        data: atlasPoints.map((point) => WeightedLatLng(point)).toList(),
        radius: HeatmapRadius.fromPixels(40),
        opacity: 0.8,
      );
      _heatmaps.clear();
      _heatmaps.add(heatmap);
    }

    setState(() {
      _discoveryPercentage = percentage;
      _userTier = userTier;
      _nationalRankings = rankings;
      _rivalsRankings = rivals;
      _sharingRankings = sharers;
      _isLoading = false;
    });

    if (_currentCountry != null) {
      await discoveryService.updateCloudPercentage(percentage, _currentCountry!);
    }
  }



  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final selectedCountry = context.watch<SettingsProvider>().selectedCountry;
    super.build(context);

    if (user?.isAnonymous ?? true) {
      return const GuestDiscoveryPromptScreen();
    }
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text("Road Discovery"),
            elevation: 0,
            backgroundColor: Colors.transparent,
            pinned: true,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TieredProgressCircle(
                    percentage: _discoveryPercentage!,
                    tier: _userTier!,
                    country: selectedCountry,
                  ),
                  const SizedBox(height: 24),
                  _buildRankCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            delegate: _SliverAppBarDelegate(
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: "NATIONAL"),
                  Tab(text: "RIVALS"),
                  Tab(text: "SHARING"),
                ],
              ),
            ),
            pinned: true,
          ),
          // This SliverToBoxAdapter will now be flexible
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                // Determine which list to show based on the active tab
                final List<LeaderboardUser> currentList;
                switch (_tabController.index) {
                  case 1:
                    currentList = _rivalsRankings;
                    break;
                  case 2:
                    currentList = _sharingRankings;
                    break;
                  default:
                    currentList = _nationalRankings;
                }
                if (currentList.isEmpty) {
                  switch (_tabController.index) {
                    case 1:
                      return _buildEmptyState("No Rivals Found", "Users in your tier will appear here once they join.", Icons.people_outline);
                    case 2:
                      return _buildEmptyState("Nobody is Sharing", "Friends who share their location will appear here.", Icons.location_off_outlined);
                    default:
                      return _buildEmptyState("Be the First!", "You're the first to explore this country. Your name will appear here.", Icons.flag_outlined);
                  }                }
                final user = currentList[index];
                return ListTile(
                  leading: Text(
                    "${index + 1}",
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  title: Text(
                    user.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Text(
                    "${user.percentage.toStringAsFixed(4)}%",
                    style: TextStyle(
                      color: TierManager.getColor(user.tier),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
              // Determine the number of items in the current list
              childCount: () {
                switch (_tabController.index) {
                  case 1:
                    return _rivalsRankings.isEmpty ? 1 : _rivalsRankings.length;
                  case 2:
                    return _sharingRankings.isEmpty ? 1 : _sharingRankings.length;
                  default:
                    return _nationalRankings.isEmpty ? 1 : _nationalRankings.length;
                }
              }(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle("Achievements"),
                  const SizedBox(height: 8),
                  _buildAchievements(),
                  const SizedBox(height: 24),
                  _buildSectionTitle("My Atlas"),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              // The map itself needs a constrained height
              child: SizedBox(
                height: 300, // Explicitly give the map a height
                child: _buildAtlasMap(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String message, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  // --- BUILDER METHODS ---

  Widget _buildRankCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Your National Rank:", style: TextStyle(fontSize: 16)),
            Chip(
              avatar: Icon(
                Icons.shield,
                color: TierManager.getColor(_userTier!),
              ),
              label: Text(
                TierManager.getName(_userTier!),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: TierManager.getColor(
                _userTier!,
              ).withOpacity(0.2),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadMarkerIcon() async {
    _userMarkerIcon = await _getResizedMarkerIcon(
      'assets/images/UserLocation.png',
      120,
    );
    if (_currentUserLocation != null) _updateUserMarker();
  }

  Future<BitmapDescriptor> _getResizedMarkerIcon(
    String assetPath,
    int width,
  ) async {
    ByteData data = await rootBundle.load(assetPath);
    ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    ui.FrameInfo fi = await codec.getNextFrame();
    final Uint8List resizedBytes = (await fi.image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    return BitmapDescriptor.fromBytes(resizedBytes);
  }

  void _updateUserMarker() {
    if (_currentUserLocation == null || _userMarkerIcon == null) return;
    final marker = Marker(
      markerId: const MarkerId('atlasUserLocation'),
      position: _currentUserLocation!,
      icon: _userMarkerIcon!,
      rotation: _currentUserRotation,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndex: 2.0,
    );
    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.add(marker);
      });
    }
  }

  Widget _buildLeaderboardList(List<LeaderboardUser> users) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return ListTile(
          leading: Text(
            "${index + 1}",
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          title: Text(
            user.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          trailing: Text(
            "${user.percentage.toStringAsFixed(4)}%",
            style: TextStyle(
              color: TierManager.getColor(user.tier),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildAchievements() {
    return Wrap(
      spacing: 8.0,
      children: const [
        Chip(avatar: Icon(Icons.location_city), label: Text("City Explorer")),
        Chip(avatar: Icon(Icons.waves), label: Text("Coastal Cruiser")),
      ],
    );
  }

  Widget _buildAtlasMap() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.0),
      child: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onAtlasMapCreated,
            initialCameraPosition: const CameraPosition(
              target: LatLng(44.6488, -63.5752),
              zoom: 8,
            ),
            heatmaps: _heatmaps,
            markers: _markers,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
            },
          ),
          Positioned(
            top: 10,
            right: 10,
            child: FloatingActionButton(
              heroTag: 'recenter_atlas_button',
              onPressed: _recenterAtlas,
              mini: true,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMapStyles() async {
    _darkMapStyle = await rootBundle.loadString('assets/map_style_dark.json');
    _lightMapStyle = await rootBundle.loadString('assets/map_style_light.json');
  }

  void _onAtlasMapCreated(GoogleMapController controller) {
    _atlasMapController = controller;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    _atlasMapController?.setMapStyle(
      isDarkMode ? _darkMapStyle : _lightMapStyle,
    );
  }

  void _initAtlasLocation() async {
    final locationService = Location();
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

    // Get the first location to initially center the map
    try {
      final initialLocation = await locationService.getLocation();
      if (mounted) {
        setState(() {
          _currentUserLocation = LatLng(
            initialLocation.latitude!,
            initialLocation.longitude!,
          );
          _recenterAtlas();
        });
      }
    } catch (e) {
      debugPrint("Could not get initial location: $e");
    }

    // Start listening for subsequent location changes
    _locationSubscription = locationService.onLocationChanged.listen((
        locationData,
        ) {
      if (mounted && locationData.latitude != null && locationData.longitude != null) {
        _currentUserLocation = LatLng(
          locationData.latitude!,
          locationData.longitude!,
        );
        _currentUserRotation = locationData.heading ?? _currentUserRotation;
        _updateUserMarker();
      }
    });
  }

  void _recenterAtlas() {
    if (_atlasMapController != null && _currentUserLocation != null) {
      _atlasMapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _currentUserLocation!, zoom: 14),
        ),
      );
    }
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  _SliverAppBarDelegate(this._tabBar);
  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

// --- CUSTOM WIDGET for the Progress Circle ---

class TieredProgressCircle extends StatelessWidget {
  final double percentage;
  final Tier tier;
  final String country;
  const TieredProgressCircle({
    super.key,
    required this.percentage,
    required this.tier,
    required this.country,
  });

  @override
  Widget build(BuildContext context) {
    final color = TierManager.getColor(tier);
    // Convert percentage (0-100) to progress (0.0-1.0)
    final progress = percentage / 100;

    return AspectRatio(
      aspectRatio: 1.5,
      child: CustomPaint(
        painter: _CirclePainter(progress: progress, color: color),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "${percentage.toStringAsFixed(4)}%",
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text("of $country", style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  final double progress;
  final Color color;

  _CirclePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2);
    const strokeWidth = 12.0;

    // Background track
    final backgroundPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, backgroundPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const startAngle = -pi / 2; // Start at the top
    final sweepAngle = 2 * pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CirclePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

// Add this widget to the bottom of road_discovery_screen.dart
class GuestDiscoveryPromptScreen extends StatelessWidget {
  const GuestDiscoveryPromptScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.explore_off_outlined, size: 80, color: Colors.grey),
              const SizedBox(height: 24),
              Text(
                "Unlock Road Discovery",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                "Create a free account to map your journeys, compete on leaderboards, and earn achievements.",
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  // TODO: This should navigate to the Edit Profile screen to add an email
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Account creation coming soon!"),
                    ),
                  );
                },
                child: const Text("Create Account to Continue"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
