import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:location/location.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/fake_location_provider.dart';

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
  String _selectedCountry = '';

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

  GoogleMapController? _sharingMapController;
  final Set<Marker> _friendMarkers = {};
  final List<StreamSubscription> _friendLocationStreams = [];

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
    _loadDiscoveryData();
    _loadMapStyles();
    _loadMarkerIcon();
    _initAtlasLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // We get the new country from the provider
    final newCountry = context.watch<SettingsProvider>().selectedCountry;

    // --- THIS 'IF' STATEMENT IS THE FIX ---
    // If the country has changed, reload the data
    if (_selectedCountry != newCountry) {
      _selectedCountry = newCountry;
      _loadDiscoveryData(); // Reload all data for the new country
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _locationSubscription?.cancel();
    _atlasMapController?.dispose();
    _sharingMapController?.dispose();
    for (var stream in _friendLocationStreams) {
      stream.cancel();
    }
    _friendLocationStreams.clear();
    super.dispose();
  }

  // REPLACE your old _loadDiscoveryData function with this one

  Future<void> _loadDiscoveryData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // Get services and country from providers
    final discoveryService = context.read<RoadDiscoveryService>();
    final leaderboardService = context.read<LeaderboardService>(); // <-- Get this service
    final country = context.read<SettingsProvider>().selectedCountry;
    final currentUser = FirebaseAuth.instance.currentUser; // <-- Get the user

    if (currentUser == null) { // <-- Check for user
      setState(() => _isLoading = false);
      return;
    }

    // 1. Get percentages, leaderboards, and atlas points in parallel
    final results = await Future.wait([
      discoveryService.calculateDiscoveryPercentage(country), // Local
      discoveryService.getCloudDiscoveryPercentage(country),  // Cloud
      leaderboardService.getNationalLeaderboard(country), // <-- Load national
      discoveryService.getAllDiscoveredPoints(), // <-- Load atlas
      leaderboardService.getLocationSharers(), // <-- Load friends
    ]);

    // 2. Process results
    final double localPercentage = results[0] as double;
    final double cloudPercentage = results[1] as double;
    final List<LeaderboardUser> rankings = results[2] as List<LeaderboardUser>;
    final List<LatLng> atlasPoints = results[3] as List<LatLng>;
    _sharingRankings = results[4] as List<LeaderboardUser>;

    // 3. Find the *highest* value to show the user
    final double finalPercentage = max(localPercentage, cloudPercentage);
    final Tier currentTier = TierManager.getTier(finalPercentage);

    // 4. Fix the error from your screenshot (add user to list if not present)
    bool isUserInList = rankings.any((user) => user.uid == currentUser.uid);
    if (!isUserInList) {
      rankings.insert(
        0,
        LeaderboardUser(
          uid: currentUser.uid,
          name: currentUser.displayName ?? 'You',
          photoURL: currentUser.photoURL ?? '',
          percentage: finalPercentage,
          tier: currentTier,
        ),
      );
      // You might want to re-sort or limit to 100 here
    }

    // 5. Get Rivals and Sharers (now that we have the tier)
    final rivals = await leaderboardService.getRivals(currentTier);
    final sharers = await leaderboardService.getLocationSharers();

    // 6. Update Heatmap
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

    // 7. Update the UI
    if (mounted) {
      setState(() {
        _discoveryPercentage = finalPercentage;
        _userTier = currentTier;
        _nationalRankings = rankings; // <-- Set the list
        _rivalsRankings = rivals;   // <-- Set the list
        _sharingRankings = sharers; // <-- Set the list
        _isLoading = false;
      });
    }
    _listenToFriendLocations();

    // 8. (Separately) Try to sync the local value up
    await discoveryService.updateCloudPercentage(localPercentage, country);
  }

  void _listenToFriendLocations() {
    // Clear out any old listeners
    for (var stream in _friendLocationStreams) {
      stream.cancel();
    }
    _friendLocationStreams.clear();
    _friendMarkers.clear();

    // Get the photo for the current user to add to the map
    final currentUser = _auth.currentUser;
    String myPhotoUrl = currentUser?.photoURL ?? '';

    // Loop through each friend and create a listener
    for (final friend in _sharingRankings) {
      final stream = _db
          .collection('users')
          .doc(friend.uid)
          .snapshots()
          .listen((doc) {
        _updateFriendMarker(doc, myPhotoUrl);
      });
      _friendLocationStreams.add(stream);
    }

    // Also listen to *my own* location to show on the friend map
    if (currentUser != null) {
      final myStream = _db
          .collection('users')
          .doc(currentUser.uid)
          .snapshots()
          .listen((doc) {
        _updateFriendMarker(doc, myPhotoUrl, isCurrentUser: true);
      });
      _friendLocationStreams.add(myStream);
    }
  }

  // --- NEW: Callback for when a friend's location changes ---
  Future<void> _updateFriendMarker(DocumentSnapshot doc, String myPhotoUrl, {bool isCurrentUser = false}) async {
    if (!doc.exists || doc.data() == null) return;

    final data = doc.data() as Map<String, dynamic>;
    final geoPoint = data['live_location'] as GeoPoint?;
    final lastUpdated = data['location_last_updated'] as Timestamp?;

    // If no location or location is old, remove marker and return
    if (geoPoint == null || lastUpdated == null || DateTime.now().difference(lastUpdated.toDate()).inMinutes > 30) {
      if (mounted) {
        setState(() {
          _friendMarkers.removeWhere((m) => m.markerId.value == doc.id);
        });
      }
      return;
    }

    final latLng = LatLng(geoPoint.latitude, geoPoint.longitude);
    final String name = data['displayName'] ?? 'Friend';
    final String photoUrl = isCurrentUser ? myPhotoUrl : (data['photoURL'] ?? '');

    // Create a custom marker with their profile picture
    final BitmapDescriptor icon = await _createCustomMarkerBitmap(
      photoUrl,
      name,
      isCurrentUser: isCurrentUser,
    );

    final marker = Marker(
      markerId: MarkerId(doc.id),
      position: latLng,
      icon: icon,
      anchor: const Offset(0.5, 0.5), // Center the icon
      infoWindow: InfoWindow(
        title: name,
        snippet: 'Last seen: ${lastUpdated.toDate().toLocal()}',
      ),
    );

    if (mounted) {
      setState(() {
        _friendMarkers.removeWhere((m) => m.markerId.value == doc.id); // Remove old
        _friendMarkers.add(marker); // Add new
      });
    }
  }

  // --- NEW: Helper to create a custom marker from a URL ---
  Future<BitmapDescriptor> _createCustomMarkerBitmap(String? imageUrl, String name, {bool isCurrentUser = false}) async {
    // ... (This is a complex canvas operation, simplified for now)
    // In a real app, you'd load the image, draw it on a canvas, and add a border
    // For now, let's use a colored pin

    final double hue = isCurrentUser ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueGreen;

    return BitmapDescriptor.defaultMarkerWithHue(hue);

    // TODO: Implement a real custom marker painter if you want profile pics
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = FirebaseAuth.instance.currentUser;
    final selectedCountry = context.watch<SettingsProvider>().selectedCountry;

    final fakeGps = context.watch<FakeLocationProvider>();
    final bool isPaused = fakeGps.isFaking && !fakeGps.isAdmin;

    if (user?.isAnonymous ?? true) {
      return const GuestDiscoveryPromptScreen();
    }
    if (_isLoading || _discoveryPercentage == null) {
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
                  _PausedOverlayWrapper(
                    isPaused: isPaused,
                    child: TieredProgressCircle(
                      percentage: _discoveryPercentage!,
                      tier: _userTier!,
                      country: selectedCountry,
                    ),
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

          _buildCurrentTab(isPaused),

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
              child: _PausedOverlayWrapper(
                isPaused: isPaused,
                child: SizedBox(
                  height: 300,
                  child: _buildAtlasMap(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTab(bool isPaused) {
    switch (_tabController.index) {
      case 0: // NATIONAL
        return _buildSliverList(_nationalRankings, "Be the First!", "You're the first to explore this country. Your name will appear here.", Icons.flag_outlined);
      case 1: // RIVALS
        return _buildSliverList(_rivalsRankings, "No Rivals Found", "Users in your tier will appear here once they join.", Icons.people_outline);
      case 2: // SHARING
      // If paused, show the overlay
        if (isPaused) {
          return SliverToBoxAdapter(
            child: _PausedOverlayWrapper(
              isPaused: true,
              child: Container(height: 400), // Placeholder height
            ),
          );
        }
        // If no friends, show empty state
        if (_sharingRankings.isEmpty) {
          return SliverToBoxAdapter(
            child: _buildEmptyState("Add Friends to Share", "Go to your profile to add friends. Their location will appear here if they are sharing.", Icons.person_add_alt_1),
          );
        }
        // Otherwise, show the map
        return SliverToBoxAdapter(
          child: SizedBox(
            height: 400, // Define a height for the map
            child: _buildSharingMap(),
          ),
        );
      default:
        return _buildSliverList([], "Error", "Something went wrong", Icons.error);
    }
  }

  // --- NEW: Extracted the SliverList builder ---
  Widget _buildSliverList(List<LeaderboardUser> list, String emptyTitle, String emptyMessage, IconData emptyIcon) {
    if (list.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildEmptyState(emptyTitle, emptyMessage, emptyIcon),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          final user = list[index];
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
        childCount: list.length,
      ),
    );
  }

  // --- NEW: The map for the "SHARING" tab ---
  Widget _buildSharingMap() {
    return GoogleMap(
      onMapCreated: (controller) {
        _sharingMapController = controller;
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        _sharingMapController?.setMapStyle(
          isDarkMode ? _darkMapStyle : _lightMapStyle,
        );
      },
      initialCameraPosition: CameraPosition(
        target: _currentUserLocation ?? const LatLng(44.6488, -63.5752), // Center on user or default
        zoom: 12,
      ),
      markers: _friendMarkers,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
      },
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

class _PausedOverlayWrapper extends StatelessWidget {
  final Widget child;
  final bool isPaused;

  const _PausedOverlayWrapper({
    required this.child,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    // If not paused, just return the original widget
    if (!isPaused) {
      return child;
    }

    // If paused, stack the blur and text on top of the child
    return Stack(
      alignment: Alignment.center,
      children: [
        // 1. The blurred child content
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
          child: child,
        ),
        // 2. The "Paused" overlay text
        // We use a container to provide a slight dark overlay, making
        // the white text more readable against any background.
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.1),
            // This makes the overlay match the map's rounded corners
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Paused",
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 4.0,
                        color: Colors.black.withOpacity(0.5),
                        offset: const Offset(2.0, 2.0),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Due to Fake GPS location ON",
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 4.0,
                        color: Colors.black.withOpacity(0.5),
                        offset: const Offset(1.0, 1.0),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
