import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mapz/screens/auth/auth_gate.dart';
import 'package:mapz/models/Discovery/tier.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {

  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isLoading = false;

  Timer? _debounce;
  String? _usernameErrorText;
  bool _isUsernameAvailable = false;
  bool _isCheckingUsername = false;

  @override
  void initState() {
    super.initState();
    // --- FEATURE: Listen to username changes ---
    _usernameController.addListener(_onUsernameChanged);
  }
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.removeListener(_onUsernameChanged); // --- FEATURE
    _usernameController.dispose();
    _debounce?.cancel(); // --- FEATURE
    super.dispose();
  }

  void _onUsernameChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    setState(() {
      _isCheckingUsername = true;
      _usernameErrorText = null;
    });

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final String username = _usernameController.text.trim();
      if (username.length < 3) {
        setState(() {
          _usernameErrorText = 'Username must be at least 3 characters';
          _isUsernameAvailable = false;
          _isCheckingUsername = false;
        });
        return;
      }

      final isTaken = await _isUsernameTaken(username);
      if (mounted) {
        setState(() {
          if (isTaken) {
            _usernameErrorText = 'This username is already taken';
            _isUsernameAvailable = false;
          } else {
            _usernameErrorText = null;
            _isUsernameAvailable = true;
          }
          _isCheckingUsername = false;
        });
      }
    });
  }

  Future<bool> _isUsernameTaken(String username) async {

    final String normalizedUsername = username.toLowerCase();

    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('username_lowercase', isEqualTo: normalizedUsername)
        .limit(1)
        .get();

    return query.docs.isNotEmpty;
  }

  void _signUp() async {
    // --- FEATURE: Use the form key ---
    if (!_formKey.currentState!.validate()) {
      return; // Stop if form is invalid (e.g., empty email/password)
    }

    // --- FEATURE: Check our real-time validation state ---
    if (_isCheckingUsername) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait, checking username...')),
      );
      return;
    }

    if (!_isUsernameAvailable || _usernameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid, available username.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Passwords do not match.")));
      return;
    }

    setState(() => _isLoading = true);

    final String username = _usernameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    try {
      // --- All checks passed, now create the user ---
      UserCredential userCredential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update the user's profile display name
      await userCredential.user?.updateDisplayName(username);

      final defaultTier = TierManager.getTier(0.0);
      final defaultTierString = defaultTier.name;

      // Save user data to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'uid': userCredential.user!.uid,
        'email': email,
        'displayName': username,
        'username_lowercase': username.toLowerCase(),
        'photoURL': null,
        'tier': defaultTierString,
        'discovery': {},
      });

      // --- FIX: Added 'if (mounted)' check ---
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthGate()),
        );
      }
    } on FirebaseAuthException catch (e) {
      // --- FIX: Added 'if (mounted)' check ---
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'An error occurred.')),
        );
      }
    } finally {
      // --- FIX: Added 'if (mounted)' check ---
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        // --- FEATURE: Use Form ---
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // --- FEATURE: Updated username field ---
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: const Icon(Icons.person),
                  errorText: _usernameErrorText,
                  suffixIcon: _isCheckingUsername
                      ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                      : (_isUsernameAvailable &&
                      !_isCheckingUsername &&
                      _usernameController.text.isNotEmpty)
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                ),
                // We don't use the validator for async, just empty check
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an email';
                  }
                  if (!value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (value) {
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                ElevatedButton(
                  onPressed: _signUp,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Create Account'),
                ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Already have an account? Login'),
              )
            ],
          ),
        ),
      ),
    );
  }
}