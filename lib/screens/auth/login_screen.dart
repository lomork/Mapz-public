import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mapz/screens/main_screen.dart';

import 'sign_up_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                  radius: 40,
                  child:
                  Image.asset('assets/images/ic_launcher_foreground.png')),
              const SizedBox(height: 20),
              const Text("Welcome to Mapz",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 10),
              TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password')),
              const SizedBox(height: 30),
              if (_isLoading) const CircularProgressIndicator(),
              if (!_isLoading) ...[
                ElevatedButton(
                  onPressed: () async {
                    setState(() => _isLoading = true);
                    try {
                      await FirebaseAuth.instance.signInWithEmailAndPassword(
                          email: _emailController.text.trim(),
                          password: _passwordController.text.trim());
                    } on FirebaseAuthException catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(e.message ?? "Login failed.")));
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _isLoading = false);
                      }
                    }
                  },
                  child: const Text('Login'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const SignUpScreen()));
                  },
                  child: const Text('Sign Up'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => _signInAsGuest(context),
                  child: const Text('Enter as Guest'),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
  Future<void> _signInAsGuest(BuildContext context) async {
    try {
      // 1. Get the latest guest number from local storage
      final prefs = await SharedPreferences.getInstance();
      int guestNumber = (prefs.getInt('guestCounter') ?? 0) + 1;
      await prefs.setInt('guestCounter', guestNumber);

      // 2. Sign in anonymously with Firebase
      UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
      User? user = userCredential.user;

      // 3. Update the new guest's profile with a generated name
      if (user != null) {
        String guestName = "Traveller #$guestNumber";
        await user.updateDisplayName(guestName);
        // We reload the user to make sure the new display name is applied
        await user.reload();
        user = FirebaseAuth.instance.currentUser;

        if (context.mounted && user != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => MainScreen(user: user!)),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not sign in as guest: $e")),
      );
    }
  }
}