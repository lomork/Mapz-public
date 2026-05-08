import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/place.dart';
import '../screens/map/directions_screen.dart';

class PlaceDetailsPanel extends StatelessWidget {
  final ScrollController scrollController;
  final PlaceDetails place;
  final LatLng? currentUserLatLng;
  final Function(PlaceDetails) onSavePlace;

  const PlaceDetailsPanel({
    super.key,
    required this.scrollController,
    required this.place,
    required this.currentUserLatLng,
    required this.onSavePlace,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
          boxShadow: [
            BoxShadow(
              blurRadius: 10.0,
              color: Colors.black.withOpacity(0.15),
            )
          ],
        ),
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  Text(place.name,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (place.city != null && place.state != null)
                    Text('${place.city}, ${place.state}',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.grey[600])),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildActionButton("directions_fab", Icons.directions, "Directions", () {
                        if (currentUserLatLng != null) {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => DirectionsScreen(
                              destination: place,
                              originCoordinates: currentUserLatLng!,
                            ),
                          ));
                        }
                      }),
                      _buildActionButton("save_fab", Icons.bookmark_border, "Save", () {
                        onSavePlace(place);
                      }),
                      _buildActionButton("share_fab", Icons.share, "Share", () {
                        Share.share(
                            'Check out this location: ${place.name}, ${place.address}');
                      }),
                    ],
                  ),
                  const Divider(height: 40),
                  if (place.photoUrls.isNotEmpty) _buildPhotoGallery(context, place.photoUrls),
                  if (place.rating != null) _buildRating(place.rating!),
                  _buildInfoTile(context, Icons.location_on_outlined, place.address, true),
                  if (place.openingHoursStatus != null && place.openingHoursStatus!.isNotEmpty)
                    _buildInfoTile(context, Icons.access_time, place.openingHoursStatus!, false),
                  if (place.phoneNumber != null && place.phoneNumber!.isNotEmpty)
                    _buildInfoTile(context, Icons.phone_outlined, place.phoneNumber!, false, onTap: () async {
                      final url = Uri.parse('tel:${place.phoneNumber}');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url);
                      }
                    }),
                  if (place.website != null && place.website!.isNotEmpty)
                    _buildInfoTile(context, Icons.public, place.website!, false, onTap: () async {
                      final url = Uri.parse(place.website!);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    }),
                  _buildAboutSection(context, place),
                ],
              ),
            ),
          ],
        ));
  }

  Widget _buildPhotoGallery(BuildContext context, List<String> photoUrls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Photos", style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: photoUrls.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: Image.network(
                    photoUrls[index],
                    width: 150,
                    height: 120,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      return progress == null
                          ? child
                          : Container(
                          width: 150,
                          height: 120,
                          color: Colors.grey[200],
                          child: const Center(child: CircularProgressIndicator()));
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 150,
                      height: 120,
                      color: Colors.grey[200],
                      child: const Icon(Icons.error_outline),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 30),
      ],
    );
  }

  Widget _buildRating(double rating) {
    List<Widget> stars = [];
    for (int i = 0; i < 5; i++) {
      stars.add(Icon(
        i < rating.round() ? Icons.star : Icons.star_border,
        color: Colors.amber,
        size: 20,
      ));
    }
    return Column(
      children: [
        Row(
          children: [
            ...stars,
            const SizedBox(width: 8),
            Text('$rating from Google', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const Divider(height: 30),
      ],
    );
  }

  Widget _buildInfoTile(BuildContext context, IconData icon, String text, bool isAddress, {VoidCallback? onTap}) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: Theme.of(context).iconTheme.color),
          title: Text(text),
          trailing: isAddress
              ? IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Address copied!")));
            },
          )
              : null,
          onTap: onTap,
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildAboutSection(BuildContext context, PlaceDetails place) {
    if (place.editorialSummary != null && place.editorialSummary!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text("About", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            place.editorialSummary!,
            style: const TextStyle(color: Colors.grey, height: 1.5),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildActionButton(String heroTag, IconData icon, String label, VoidCallback onPressed) {
    return Column(
      children: [
        FloatingActionButton(
          heroTag: heroTag,
          onPressed: onPressed,
          mini: true,
          child: Icon(icon),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}