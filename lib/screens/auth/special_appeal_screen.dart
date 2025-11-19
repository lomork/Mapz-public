import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SpecialAppealScreen extends StatefulWidget {
  const SpecialAppealScreen({super.key});

  @override
  State<SpecialAppealScreen> createState() => _SpecialAppealScreenState();
}

class _SpecialAppealScreenState extends State<SpecialAppealScreen> {
  final _reasonController = TextEditingController();

  Future<void> _sendEmail() async {
    final reason = _reasonController.text;
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please explain why you are special first.")),
      );
      return;
    }

    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'contactus.mapz@gmail.com',
      query: 'subject=I am Special&body=${Uri.encodeComponent(reason)}',
    );

    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open email app.")),
        );
      }
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Special Appeal"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Explain why you are special",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _reasonController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: "Tell us your story...",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _sendEmail,
              child: const Text("SEND EMAIL"),
            ),
          ],
        ),
      ),
    );
  }
}