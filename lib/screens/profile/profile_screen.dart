import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mapz/screens/profile/edit_profile_screen.dart';

import '../../models/discovery/leaderboard_user.dart';
import '../../models/discovery/tier.dart';
import '../../services/leaderboard_service.dart';
import '../../services/road_discovery_service.dart';
import '../auth/auth_gate.dart';
import '../../providers/settings_provider.dart';
import '../profile/friends/friends_screen.dart';

import 'accessibility_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text("Not logged in."));
    } else if (user.isAnonymous) {
      return const GuestProfileScreen();
    } else {
      return LoggedInProfileScreen(user: user);
    }
  }
}

// --- UI for a fully logged-in user ---
class LoggedInProfileScreen extends StatefulWidget {
  final User user;
  const LoggedInProfileScreen({super.key, required this.user});

  @override
  State<LoggedInProfileScreen> createState() => _LoggedInProfileScreenState();
}

class _LoggedInProfileScreenState extends State<LoggedInProfileScreen> with AutomaticKeepAliveClientMixin{
  // --- STATE VARIABLES ---
  bool _isLoading = true;
  double? _discoveryPercent;
  int? _nationalRank;
  //bool _isDiscoveryOn = true;
  final _feedbackController = TextEditingController();
  String? _currentCountry;

  bool _isSyncing = false;

  bool _hasSpecialOffer = false;

  @override
  bool get wantKeepAlive => true;

  bool _isSharingLocation = false;
  bool _isLoadingSharingToggle = true;
  StreamSubscription? _userSharingSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToSharingSetting();
  }

  void _subscribeToSharingSetting() {
    _userSharingSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .snapshots()
        .listen((doc) {
      if (mounted) {
        setState(() {
          _isSharingLocation = doc.data()?['isSharingLocation'] ?? false;
          _isLoadingSharingToggle = false;
        });
      }
    }, onError: (e) {
      if (mounted) {
        setState(() {
          _isSharingLocation = false;
          _isLoadingSharingToggle = false;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get the latest country from the central provider
    final newCountry = context.watch<SettingsProvider>().selectedCountry;

    // If the country has changed (or it's the first time), reload all data
    if (_currentCountry != newCountry) {
      _currentCountry = newCountry;
      _loadProfileData();
    }
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    _userSharingSubscription?.cancel();
    super.dispose();
  }

  Future<void> _updateSharingPreference(bool isSharing) async {
    setState(() => _isSharingLocation = isSharing);
    try {
      final service = context.read<LeaderboardService>();
      await service.updateSharingPreference(isSharing);
    } catch (e) {
      // Revert on error
      setState(() => _isSharingLocation = !isSharing);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update setting: $e')),
      );
    }
  }

  Future<void> _loadProfileData() async {

    if (!mounted) return;
    setState(() => _isLoading = true);

    if (_currentCountry == null) {
      _currentCountry = context.read<SettingsProvider>().selectedCountry;
    }
    final discoveryService = context.read<RoadDiscoveryService>();
    final leaderboardService = context.read<LeaderboardService>();

    final userDocFuture = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .get();

    final localPercentageFuture = discoveryService.calculateDiscoveryPercentage(_currentCountry!);
    final cloudPercentageFuture = discoveryService.getCloudDiscoveryPercentage(_currentCountry!);
    final rankingsFuture =
    leaderboardService.getNationalLeaderboard(_currentCountry!);

    final results = await Future.wait([
      localPercentageFuture,
      cloudPercentageFuture,
      rankingsFuture,
      userDocFuture,
    ]);

    final localPercentage = results[0] as double;
    final cloudPercentage = results[1] as double;
    final rankings = results[1] as List<LeaderboardUser>;
    final userDoc = results[2] as DocumentSnapshot<Map<String, dynamic>>;

    final percentage = max(localPercentage, cloudPercentage);

    int? rank;
    final userIndex = rankings.indexWhere((u) => u.name == widget.user.displayName);
    if (userIndex != -1) {
      rank = userIndex + 1;
    }

    bool offerFlag = false;
    if (userDoc.exists && userDoc.data() != null) {
      final data = userDoc.data()!;
      if (data.containsKey('has_special_offer') &&
          data['has_special_offer'] == true) {
        offerFlag = true;
      }
    }

    if (mounted) {
      setState(() {
        _discoveryPercent = percentage;
        _nationalRank = rank;
        _hasSpecialOffer = offerFlag;
        _isLoading = false;
      });
    }
  }

  Future<void> _forceSync() async {
    setState(() => _isSyncing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Syncing pending road data...")),
    );

    try {
      final discoveryService = context.read<RoadDiscoveryService>();
      final settingsProvider = context.read<SettingsProvider>();
      final country = settingsProvider.selectedCountry;

      // 1. Force the service to process any locations in its buffer
      await discoveryService.forceProcessBuffer();

      // 2. Recalculate the percentage with the newly saved data
      final percentage = await discoveryService.calculateDiscoveryPercentage(country);

      // 3. Update Firestore with the new percentage
      await discoveryService.updateCloudPercentage(percentage, country);

      // 4. Reload the profile stats to show the updated numbers
      await _loadProfileData();

      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sync complete!"), backgroundColor: Colors.green),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Sync failed: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  void _sendFeedback() async {
    final feedback = _feedbackController.text;
    if (feedback.isEmpty) {
      // Don't do anything if the feedback box is empty
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your feedback first.")),
      );
      return;
    }

    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'contactus.mapz@gmail.com',
      query: 'subject=Mapz Feedback&body=${Uri.encodeComponent(feedback)}',
    );

    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open email app. Is one installed?")),
      );
    }

    _feedbackController.clear();
    FocusManager.instance.primaryFocus?.unfocus(); // Close keyboard
  }

  void _showLegalDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final acceptedDate = prefs.getString('termsAcceptedDate') ?? 'Not recorded';
    const termsText =
        "Terms and Conditions for Mapz...\n\nEffective Date: September 1, 2025...\n\n1. Agreement to Terms\nWelcome to Mapz! These Terms and Conditions ( Terms ) govern your use of the Mapz mobile application (the  Service ) provided by Mapz ( we,   us,  or  our ). By downloading, accessing, or using our Service, you agree to be bound by these Terms and our Privacy Policy. If you do not agree to these Terms, do not use the Service.\n\n2. Description of Service\nMapz is a mobile navigation application designed for exploration and driving enthusiasts. The Service includes: -Real-time GPS navigation and route selection. -A  Road Discovery  feature that tracks your driven paths to calculate the percentage of roads you have explored in a given country. -Community-sourced  Road Tags  that allow users to share real-time road information, such as scenic views, points of interest, or road hazards. -User profiles and search history.\n\n2.5 License to Use the Service\nSubject to your compliance with these Terms, Mapz grants you a limited, non-exclusive, non-transferable, non-sublicensable, revocable license to download, install, and use a copy of the Mapz application on a single mobile device that you own or control, solely for your own personal, non-commercial purposes.\n\n3. Location-Based Services\nTo provide our core features, Mapz collects and processes your device's precise location data. -Navigation: Your location is used to provide turn-by-turn directions and display your position on the map. -Road Discovery: This feature requires the collection of location data while the app is running in the background to accurately track the roads you have traveled. You can enable or disable background location tracking at any time in the app's settings menu. Disabling it will prevent the Road Discovery feature from updating your progress.\n\n4. User-Generated Content\nOur  Road Tags  feature allows you to submit content, including text and location data ( User Content ). -You are solely responsible for the User Content you submit. You agree not to submit any content that is illegal, defamatory, obscene, or infringes on the rights of others. -By submitting User Content, you grant Mapz a worldwide, non-exclusive, royalty-free, transferable license to use, display, reproduce, and distribute your content in connection with the Service. -We reserve the right, but not the obligation, to monitor and remove any User Content that we, in our sole discretion, deem to be in violation of these Terms or otherwise inappropriate.\n\n5. Third-Party Services\nThe Mapz application relies heavily on data and services provided by third parties, primarily the Google Maps Platform (including Google Maps, Places API, Directions API, and Roads API). Your use of these features is also subject to the applicable Google Terms of Service. We do not guarantee the accuracy, availability, or completeness of data from these third parties, including but not limited to map data, directions, business information, and speed limits.\n\n6. Disclaimers and Safe Driving Practices\nUse the Service at Your Own Risk. The information provided by Mapz is for informational and planning purposes only. -All data, including navigation routes, speed limits, road conditions, and user-generated  Road Tags,  may be inaccurate, incomplete, or outdated. -Always prioritize safety. Obey all traffic laws, posted road signs, and official instructions. Use your judgment and drive attentively according to current road and weather conditions. -Mapz is not a substitute for safe, responsible driving and should never distract you from operating your vehicle safely.\n\n7. Limitation of Liability\nTo the fullest extent permitted by applicable law, [Your Company Name] shall not be liable for any indirect, incidental, special, consequential, or punitive damages, or any loss of profits or revenues, whether incurred directly or indirectly, or any loss of data, use, goodwill, or other intangible losses, resulting from (a) your use of the Service; (b) any errors, inaccuracies, or omissions in the Service's content; or (c) any personal injury or property damage resulting from your use of the Service.\n\n8. Termination\nWe may terminate or suspend your access to the Service immediately, without prior notice or liability, for any reason whatsoever, including without limitation if you breach the Terms.\n\n9. Governing Law\nThese Terms shall be governed and construed in accordance with the laws of the Province of Nova Scotia, Canada, without regard to its conflict of law provisions.\n\n10. Changes to Terms\nWe reserve the right to modify or replace these Terms at any time. We will provide notice of any significant changes. By continuing to access or use our Service after those revisions become effective, you agree to be bound by the revised terms.\n\n11. Contact Us\nIf you have any questions about these Terms, please contact us at: contactus.mapz@gmail.com";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Legal"),
        content: SingleChildScrollView(
          child: Text("$termsText \n\nAccepted on: $acceptedDate"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final name = widget.user.displayName ?? "Explorer";
    final profileImageUrl = widget.user.photoURL;
    final settingsProvider = context.watch<SettingsProvider>();
    final user = widget.user;
    final discoveryService = context.watch<RoadDiscoveryService>();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 100,
        title: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundImage: profileImageUrl != null
                  ? NetworkImage(profileImageUrl)
                  : null,
              child: profileImageUrl == null
                  ? const Icon(Icons.person, size: 30)
                  : null,
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Welcome back,",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const EditProfileScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: "Discovery %",
                        value:
                            "${_discoveryPercent?.toStringAsFixed(4) ?? '...'}%",
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _StatCard(
                        title: "National Rank",
                        value: _nationalRank != null
                            ? "#$_nationalRank"
                            : "N/A",
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                    ).copyWith(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Settings",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text("Country"),
                          subtitle: Text(settingsProvider.selectedCountry),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            showCountryPicker(
                              context: context,
                              showPhoneCode: false, // We don't need phone codes
                              onSelect: (Country country) {
                                // Update the provider when a country is selected
                                context.read<SettingsProvider>().updateCountry(country.name);
                              },
                            );
                          },
                        ),

                        SwitchListTile(
                          title: const Text(
                            "Adaptive Background Road Discovery",
                          ),
                          value: settingsProvider.isDiscoveryOn,
                          onChanged: (val) {
                            context.read<SettingsProvider>().updateDiscovery(val);
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 16),
                    Center(
                      child: _isSyncing
                          ? const CircularProgressIndicator()
                          : OutlinedButton.icon(
                        onPressed: _forceSync,
                        icon: const Icon(Icons.sync),
                        label: const Text("Force Sync Data"),
                      ),
                    ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    leading: const Icon(Icons.people_outline),
                    title: const Text("Manage Friends"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const FriendsScreen(),
                      ));
                    },
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _isLoadingSharingToggle
                    ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                )
                    : SwitchListTile(
                  title: const Text("Share My Location"),
                  subtitle: const Text("Visible to friends only"),
                  value: _isSharingLocation,
                  onChanged: _updateSharingPreference,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Send Feedback",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _feedbackController,
                          decoration: const InputDecoration(
                            hintText: "Tell us what you think...",
                          ),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _sendFeedback,
                            child: const Text("SEND"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: _showLegalDialog,
                  child: const Text("LEGAL"),
                ),
                const SizedBox(height: 8),
                if (_hasSpecialOffer)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const AccessibilityScreen(),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue)),
                      child: const Text("ACCESSIBILITY"),
                    ),
                  ),

                OutlinedButton(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => const AuthGate(),
                        ),
                        (route) => false,
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text("SIGN OUT"),
                ),
              ],
            ),
    );
  }
}

// --- UI for a GUEST user ---
class GuestProfileScreen extends StatelessWidget {
  const GuestProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "This is a guest account.",
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                "To save your road discovery progress and compete on leaderboards, add an email to your account.",
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  // TODO: Navigate to EditProfileScreen to add email
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Edit Profile screen coming soon!"),
                    ),
                  );
                },
                child: const Text("Add Email & Save Progress"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper widget for the stat cards
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  const _StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
