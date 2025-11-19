import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  final User? _user = FirebaseAuth.instance.currentUser;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  File? _imageFile;
  String? _networkImageUrl;
  bool _isLoading = false;

  Timer? _debounce;
  String? _usernameErrorText;
  bool _isUsernameAvailable = true; // Default to true (for unchanged name)
  bool _isCheckingUsername = false;
  late String _originalUsername;

  bool _isCompressing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _user?.displayName ?? '');
    _networkImageUrl = _user?.photoURL;
    _originalUsername = _user?.displayName?.toLowerCase() ?? '';
    _nameController.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onUsernameChanged);
    _nameController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<File?> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    // Create a new path with a 'jpg' extension, regardless of original
    final targetPath = p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg');

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 80, // Compress to 80% quality
      minWidth: 1080, // Resize to max 1080px wide
      minHeight: 1080, // Resize to max 1080px high
      format: CompressFormat.jpeg,
    );

    if (result == null) return null;

    return File(result.path);
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _isCompressing = true;
        _imageFile = File(pickedFile.path);
      });
      try {
        final File? compressedFile = await _compressImage(File(pickedFile.path));

        if (compressedFile != null) {
          setState(() {
            _imageFile = compressedFile;
          });
        }
      } catch (e) {
        // Handle compression error
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to process image: $e")));
      } finally {
        setState(() {
          _isCompressing = false; // Stop compression loading
        });
      }
    }
  }

  void _onUsernameChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    final String newUsername = _nameController.text.trim().toLowerCase();

    // If the name is the same as the original, it's valid.
    if (newUsername == _originalUsername) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = true;
        _usernameErrorText = null;
      });
      return;
    }

    // If it's a new name, start checking
    setState(() {
      _isCheckingUsername = true;
      _usernameErrorText = null;
    });

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final String username = _nameController.text.trim();
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

  Future<String?> _uploadProfilePicture(File image, String userId) async {
    try {
      final storageRef = FirebaseStorage.instance.ref().child('profile_pictures/$userId/profile.jpg');

      final uploadTask = storageRef.putFile(image);
      final snapshot = await uploadTask.whenComplete(() {});
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to upload image: $e")));
      return null;
    }
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

  Future<void> _saveProfile() async {
    if (_user == null) return;
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      String? newPhotoUrl = _networkImageUrl;

      if (_isCheckingUsername) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please wait, checking username...')),
        );
        setState(() => _isLoading = false);
        return;
      }

      final String newUsername = _nameController.text.trim();
      final User? user = _auth.currentUser;

      // 1. Upload new image if one was selected
      if (_imageFile != null) {
        newPhotoUrl = await _uploadProfilePicture(_imageFile!, _user!.uid);

        if (newPhotoUrl == null) {
          setState(() => _isLoading = false);
          return;
        }
      }

      // 2. Update Firebase Auth profile
      try {
        if (newUsername.toLowerCase() != user!.displayName?.toLowerCase()) {
          final bool isTaken = await _isUsernameTaken(newUsername);
          if (isTaken) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('This username is already taken. Please try another.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            setState(() => _isLoading = false);
            return; // Stop the save process
          }
        }
        await user.updateDisplayName(newUsername);

        await _firestore.collection('users').doc(user.uid).update({
          'displayName': newUsername,
          'username_lowercase': newUsername.toLowerCase(), // <-- SAVE THE LOWERCASE FIELD
        });

        if (newPhotoUrl != _networkImageUrl) {
          await user.updatePhotoURL(newPhotoUrl);
          await _firestore.collection('users').doc(user.uid).update({'photoURL': newPhotoUrl});
        }

        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Profile updated successfully!")));
          Navigator.of(context).pop();
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to update profile: $e")));
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Profile"),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isLoading ? null : _saveProfile,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: _imageFile != null
                        ? FileImage(_imageFile!)
                        : (_networkImageUrl != null ? NetworkImage(_networkImageUrl!) : null) as ImageProvider?,
                    child: _imageFile == null && _networkImageUrl == null ? const Icon(Icons.person, size: 60) : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 20,
                      child: IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: _pickImage,
                      ),
                    ),
                  ),
                  if (_isCompressing)
                    const CircularProgressIndicator(),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "Display Name",
                border: const OutlineInputBorder(),
                errorText: _usernameErrorText,
                suffixIcon: _isCheckingUsername
                    ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                    : (_isUsernameAvailable &&
                    !_isCheckingUsername &&
                    _nameController.text.isNotEmpty &&
                    _nameController.text.trim().toLowerCase() != _originalUsername)
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a display name';
                }
                if (value.trim().length < 3) {
                  return 'Username must be at least 3 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _user?.email ?? 'No email associated',
              decoration: const InputDecoration(
                labelText: "Email Address",
                border: OutlineInputBorder(),
                filled: true,
              ),
              readOnly: true, // User cannot edit email
            ),
          ],
        ),
      ),
    );
  }
}