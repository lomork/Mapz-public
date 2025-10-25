import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main_screen.dart';

class TermsCheckWrapper extends StatelessWidget {
  final User user;
  const TermsCheckWrapper({super.key, required this.user});
  Future<bool> _hasAcceptedTerms() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('termsAcceptedDate');
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasAcceptedTerms(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == true) {
          return MainScreen(user: user);
        }
        return TermsScreen(user: user);
      },
    );
  }
}

class TermsScreen extends StatelessWidget {
  final User user;
  const TermsScreen({super.key, required this.user});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Terms & Conditions")),
      body: Column(
        children: [
          const Expanded(
              child: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      "Terms and Conditions for Mapz...\n\nEffective Date: September 1, 2025...\n\n1. Agreement to Terms\nWelcome to Mapz! These Terms and Conditions ( Terms ) govern your use of the Mapz mobile application (the  Service ) provided by Mapz ( we,   us,  or  our ). By downloading, accessing, or using our Service, you agree to be bound by these Terms and our Privacy Policy. If you do not agree to these Terms, do not use the Service.\n\n2. Description of Service\nMapz is a mobile navigation application designed for exploration and driving enthusiasts. The Service includes: -Real-time GPS navigation and route selection. -A  Road Discovery  feature that tracks your driven paths to calculate the percentage of roads you have explored in a given country. -Community-sourced  Road Tags  that allow users to share real-time road information, such as scenic views, points of interest, or road hazards. -User profiles and search history.\n\n2.5 License to Use the Service\nSubject to your compliance with these Terms, Mapz grants you a limited, non-exclusive, non-transferable, non-sublicensable, revocable license to download, install, and use a copy of the Mapz application on a single mobile device that you own or control, solely for your own personal, non-commercial purposes.\n\n3. Location-Based Services\nTo provide our core features, Mapz collects and processes your device's precise location data. -Navigation: Your location is used to provide turn-by-turn directions and display your position on the map. -Road Discovery: This feature requires the collection of location data while the app is running in the background to accurately track the roads you have traveled. You can enable or disable background location tracking at any time in the app's settings menu. Disabling it will prevent the Road Discovery feature from updating your progress.\n\n4. User-Generated Content\nOur  Road Tags  feature allows you to submit content, including text and location data ( User Content ). -You are solely responsible for the User Content you submit. You agree not to submit any content that is illegal, defamatory, obscene, or infringes on the rights of others. -By submitting User Content, you grant Mapz a worldwide, non-exclusive, royalty-free, transferable license to use, display, reproduce, and distribute your content in connection with the Service. -We reserve the right, but not the obligation, to monitor and remove any User Content that we, in our sole discretion, deem to be in violation of these Terms or otherwise inappropriate.\n\n5. Third-Party Services\nThe Mapz application relies heavily on data and services provided by third parties, primarily the Google Maps Platform (including Google Maps, Places API, Directions API, and Roads API). Your use of these features is also subject to the applicable Google Terms of Service. We do not guarantee the accuracy, availability, or completeness of data from these third parties, including but not limited to map data, directions, business information, and speed limits.\n\n6. Disclaimers and Safe Driving Practices\nUse the Service at Your Own Risk. The information provided by Mapz is for informational and planning purposes only. -All data, including navigation routes, speed limits, road conditions, and user-generated  Road Tags,  may be inaccurate, incomplete, or outdated. -Always prioritize safety. Obey all traffic laws, posted road signs, and official instructions. Use your judgment and drive attentively according to current road and weather conditions. -Mapz is not a substitute for safe, responsible driving and should never distract you from operating your vehicle safely.\n\n7. Limitation of Liability\nTo the fullest extent permitted by applicable law, [Your Company Name] shall not be liable for any indirect, incidental, special, consequential, or punitive damages, or any loss of profits or revenues, whether incurred directly or indirectly, or any loss of data, use, goodwill, or other intangible losses, resulting from (a) your use of the Service; (b) any errors, inaccuracies, or omissions in the Service's content; or (c) any personal injury or property damage resulting from your use of the Service.\n\n8. Termination\nWe may terminate or suspend your access to the Service immediately, without prior notice or liability, for any reason whatsoever, including without limitation if you breach the Terms.\n\n9. Governing Law\nThese Terms shall be governed and construed in accordance with the laws of the Province of Nova Scotia, Canada, without regard to its conflict of law provisions.\n\n10. Changes to Terms\nWe reserve the right to modify or replace these Terms at any time. We will provide notice of any significant changes. By continuing to access or use our Service after those revisions become effective, you agree to be bound by the revised terms.\n\n11. Contact Us\nIf you have any questions about these Terms, please contact us at: contactus.mapz@gmail.com"))),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(
                    'termsAcceptedDate', DateTime.now().toIso8601String());
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                        builder: (_) => MainScreen(user: user)),
                  );
                }
              },
              child: const Text("Accept and Continue"),
            ),
          ),
        ],
      ),
    );
  }
}