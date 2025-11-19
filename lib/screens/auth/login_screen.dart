import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mapz/screens/main_screen.dart';
import 'package:mapz/screens/auth/special_appeal_screen.dart';

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

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => MainScreen(user: FirebaseAuth.instance.currentUser!)),
        );
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Login failed")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
                  decoration: const InputDecoration(labelText: 'Email',prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),),
                keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: "Password",
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              //if (_isLoading) const CircularProgressIndicator(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("LOGIN"),
                ),
              ),
                const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account?"),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SignUpScreen()),
                      );
                    },
                    child: const Text("Sign Up"),
                  ),
                ],
              ),
              const Divider(height: 32),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => _signInAsGuest(context),
                  child: const Text('Enter as Guest'),
                ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SpecialAppealScreen()),
                  );
                },
                child: const Text(
                  "You think you are special huh",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ]
          ),
        ),
      ),
    );
  }
  Future<void> _signInAsGuest(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int guestNumber = (prefs.getInt('guestCounter') ?? 0) + 1;
      await prefs.setInt('guestCounter', guestNumber);

      UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
      User? user = userCredential.user;

      if (user != null) {
        String guestName = "Traveller #$guestNumber";
        await user.updateDisplayName(guestName);
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