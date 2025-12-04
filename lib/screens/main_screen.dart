import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:mapz/screens/discovery/road_discovery_screen.dart';
import 'package:mapz/screens/map/map_screen.dart';

import '../widgets/floating_nav_bar.dart';
import 'package:provider/provider.dart';
import '../../services/road_discovery_service.dart';
import '../../screens/profile/profile_screen.dart';
import '../../providers/settings_provider.dart';
import '../../providers/map_provider.dart';


class MainScreen extends StatefulWidget {
  final User user;
  const MainScreen({super.key, required this.user});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  late final List<Widget> _screens;
  bool _isPermissionChecked = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _initAppPermissions();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPermissionChecked) { // Removed null check on _screens as it's late initialized
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 1. Check if Keyboard is Open
    final bool isKeyboardOpen = MediaQuery
        .of(context)
        .viewInsets
        .bottom > 0;

    // 2. Check if Place Details are Open (Watch the MapProvider)
    final mapProvider = context.watch<MapProvider>();
    final bool isPlaceDetailsOpen = mapProvider.selectedPlace != null;

    // 3. Determine Dock Visibility
    // Hide if keyboard is open OR if we are looking at place details
    final bool isDockVisible = !isKeyboardOpen && !isPlaceDetailsOpen;

    return Scaffold(
      // Resize to avoid bottom inset allows the map to extend behind the keyboard area
      // preventing the whole UI from crunching up when keyboard opens.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: _screens,
          ),

          // --- ANIMATED DOCK ---
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            // If visible, sit at bottom: 30. If hidden, slide down off-screen (-100).
            bottom: isDockVisible ? 30 : -150,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingNavBar(
                currentIndex: _currentIndex,
                onTap: _onTabTapped,
              ),
            ),
          ),
        ],
      ),
    );
  }

    Future<void> _initAppPermissions() async {
    final location = Location();

    // 1. Check/Request Service
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
    }

    // 2. Check/Request Permission (Only ask once here!)
    PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
    }

    // 3. Initialize Screens ONLY after permission is settled
    if (mounted) {
      setState(() {
        _screens = [
          MapScreen(user: widget.user),
          const RoadDiscoveryScreen(),
          const ProfileScreen(),
        ];
        _isPermissionChecked = true;
      });

      // 4. Start Discovery Service safely
      final settings = context.read<SettingsProvider>();
      if (settings.isDiscoveryOn && permissionGranted == PermissionStatus.granted) {
        context.read<RoadDiscoveryService>().startDiscovery();
      }
    }
  }
}