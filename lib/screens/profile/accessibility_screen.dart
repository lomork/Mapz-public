import 'package:flutter/material.dart';
import '../accessibility/fake_gps_screen.dart'; // We will create this file next

class AccessibilityScreen extends StatelessWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accessibility Features'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(8.0),
        children: [
          ListTile(
            leading: const Icon(Icons.gps_fixed),
            title: const Text('Fake GPS Location'),
            subtitle: const Text('Simulate GPS movement and location.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const FakeGpsScreen(),
                ),
              );
            },
          ),
          // You can add more features here in the future
          // e.g., ListTile(title: Text('Another Feature')),
        ],
      ),
    );
  }
}