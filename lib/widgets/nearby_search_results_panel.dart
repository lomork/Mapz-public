import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/map_provider.dart';
import '../models/place.dart';
import '../screens/map/directions_screen.dart';

class NearbySearchResultsPanel extends StatelessWidget {
  final LatLng? currentUserLatLng;
  final Function(PlaceDetails) onSavePlace;

  const NearbySearchResultsPanel({
    super.key,
    required this.currentUserLatLng,
    required this.onSavePlace,
  });

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapProvider>();
    final filters = mapProvider.getFiltersForKeyword();

    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.15,
      maxChildSize: 0.7,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
            boxShadow: [BoxShadow(blurRadius: 10.0, color: Colors.black.withOpacity(0.15))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Results near you", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => context.read<MapProvider>().clearNearbySearch(),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 50,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  scrollDirection: Axis.horizontal,
                  itemCount: filters.length,
                  itemBuilder: (context, index) {
                    final filter = filters[index];
                    return FilterChip(
                      label: Text(filter),
                      selected: mapProvider.activeFilter == filter,
                      onSelected: (selected) {
                        mapProvider.applyFilter(filter);
                      },
                    );
                  },
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: mapProvider.filteredNearbyResults.length,
                  itemBuilder: (context, index) {
                    final place = mapProvider.filteredNearbyResults[index];
                    return _buildSearchResultListItem(context, place, mapProvider);
                  },
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchResultListItem(BuildContext context, Place place, MapProvider mapProvider) {
    return InkWell(
      onTap: () {
        mapProvider.selectPlace(place.placeId, place.name);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(place.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(place.address, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                if (place.rating != null) ...[
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                  const SizedBox(width: 4),
                  Text(place.rating.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text('•', style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(width: 8),
                ],
                Text(
                  place.isOpenNow == null ? 'Hours unknown' : (place.isOpenNow! ? 'Open' : 'Closed'),
                  style: TextStyle(
                    color: place.isOpenNow == true ? Colors.green.shade700 : Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () {
                    if (currentUserLatLng != null) {
                      final placeDetails = PlaceDetails(
                          placeId: place.placeId,
                          name: place.name,
                          address: place.address,
                          coordinates: place.coordinates);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => DirectionsScreen(
                          destination: placeDetails,
                          originCoordinates: currentUserLatLng!,
                        ),
                      ));
                    }
                  },
                  icon: Icon(Icons.directions, color: Theme.of(context).primaryColor),
                  splashRadius: 20,
                ),
                IconButton(
                  onPressed: () {
                    final placeDetails = PlaceDetails(
                        placeId: place.placeId,
                        name: place.name,
                        address: place.address,
                        coordinates: place.coordinates);
                    onSavePlace(placeDetails);
                  },
                  icon: const Icon(Icons.bookmark_border),
                  splashRadius: 20,
                ),
                IconButton(
                  onPressed: () {
                    Share.share('Check out this location: ${place.name}, ${place.address}');
                  },
                  icon: const Icon(Icons.share),
                  splashRadius: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}