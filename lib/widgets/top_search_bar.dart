import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/map_provider.dart';
import '../models/place.dart'; // Make sure this path is correct
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TopSearchBar extends StatelessWidget {
  final User user;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onProfileTap;
  final LatLng? currentUserLatLng;
  final Function(SearchHistoryItem) addToSearchHistory;
  final VoidCallback clearSearch;

  const TopSearchBar({
    super.key,
    required this.user,
    required this.searchController,
    required this.searchFocusNode,
    required this.onProfileTap,
    required this.currentUserLatLng,
    required this.addToSearchHistory,
    required this.clearSearch,
  });

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapProvider>();
    final profileImageUrl = user.photoURL;

    return Material(
      elevation: 4.0,
      borderRadius: BorderRadius.circular(30.0),
      child: Container(
        height: 58.0,
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(30.0),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: mapProvider.isSearching ? 0 : 48,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: mapProvider.isSearching ? 0 : 1,
                  child: CircleAvatar(
                    radius: 20,
                    child: ClipOval(child: Image.asset('assets/images/ic_launcher_foreground.png')),
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: TextField(
                  controller: searchController,
                  focusNode: searchFocusNode,
                  onChanged: (query) => context.read<MapProvider>().fetchSuggestions(query, userLocation: currentUserLatLng),
                  onSubmitted: (String keyword) {
                    if (currentUserLatLng != null) {
                      context.read<MapProvider>().searchNearby(keyword, currentUserLatLng!);
                      addToSearchHistory(SearchHistoryItem(description: keyword));
                      searchFocusNode.unfocus();
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    border: InputBorder.none,
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: clearSearch,
                    )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              GestureDetector(
                onTap: onProfileTap,
                child: CircleAvatar(
                  radius: 20,
                  backgroundImage: profileImageUrl != null ? NetworkImage(profileImageUrl) : null,
                  child: profileImageUrl == null ? const Icon(Icons.person) : null,
                ),
              ),
            ],
          ),
        ),
      );
  }
}