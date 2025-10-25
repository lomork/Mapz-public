import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  final User? _user = FirebaseAuth.instance.currentUser;

  File? _imageFile;
  String? _networkImageUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _user?.displayName ?? '');
    _networkImageUrl = _user?.photoURL;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadProfilePicture(File image, String userId) async {
    try {
      final storageRef = FirebaseStorage.instance.ref().child('profile_pictures/$userId.jpg');
      final uploadTask = storageRef.putFile(image);
      final snapshot = await uploadTask.whenComplete(() {});
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to upload image: $e")));
      return null;
    }
  }

  Future<void> _saveProfile() async {
    if (_user == null) return;
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      String? newPhotoUrl = _networkImageUrl;

      // 1. Upload new image if one was selected
      if (_imageFile != null) {
        newPhotoUrl = await _uploadProfilePicture(_imageFile!, _user!.uid);
      }

      // 2. Update Firebase Auth profile
      try {
        await _user!.updateDisplayName(_nameController.text);
        if (newPhotoUrl != null) {
          await _user!.updatePhotoURL(newPhotoUrl);
        }

        // 3. Update Firestore document (to keep leaderboards in sync)
        await FirebaseFirestore.instance.collection('users').doc(_user!.uid).set({
          'displayName': _nameController.text,
          'photoURL': newPhotoUrl,
        }, SetOptions(merge: true));

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated successfully!")));
        Navigator.of(context).pop();

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
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Display Name",
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a display name';
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