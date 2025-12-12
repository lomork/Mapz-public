import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../models/trip_history_model.dart';
import '../../services/database_service.dart';

class TravelHistoryScreen extends StatefulWidget {
  const TravelHistoryScreen({super.key});

  @override
  State<TravelHistoryScreen> createState() => _TravelHistoryScreenState();
}

class _TravelHistoryScreenState extends State<TravelHistoryScreen> {
  List<TripHistory> _trips = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    final trips = await DatabaseService().getAllTrips();
    setState(() {
      _trips = trips;
      _isLoading = false;
    });
  }

  Future<void> _confirmDelete(int tripId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Trip?"),
        content: const Text("Are you sure you want to delete this trip from your history? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Delete", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService().deleteTrip(tripId);
      _loadTrips(); // Refresh list
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Travel History")),
      body: _trips.isEmpty
          ? const Center(child: Text("No trips recorded yet."))
          : ListView.builder(
        itemCount: _trips.length,
        itemBuilder: (ctx, i) {
          final trip = _trips[i];
          final duration = Duration(seconds: trip.durationSeconds);
          final durationString = "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                // Map Snapshot (Non-interactive)
                SizedBox(
                  height: 150,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: trip.routePath.first,
                      zoom: 10, // You might want to calculate bounds here
                    ),
                    markers: {
                      Marker(markerId: const MarkerId('start'), position: trip.routePath.first, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
                      Marker(markerId: const MarkerId('end'), position: trip.routePath.last, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
                    },
                    polylines: {
                      Polyline(
                        polylineId: const PolylineId('path'),
                        points: trip.routePath,
                        color: Colors.blue,
                        width: 4,
                      )
                    },
                    zoomControlsEnabled: false,
                    scrollGesturesEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    zoomGesturesEnabled: false,
                    myLocationButtonEnabled: false,
                    onMapCreated: (controller) {
                      // Fit bounds to show whole route
                      if (trip.routePath.isNotEmpty) {
                        // Calculate bounds...
                        // controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.circle, size: 12, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(child: Text(trip.startAddress, style: const TextStyle(fontWeight: FontWeight.bold))),
                        ],
                      ),
                      Container(
                          margin: const EdgeInsets.only(left: 5),
                          height: 20,
                        decoration: const BoxDecoration(
                          border: Border(left: BorderSide(color: Colors.grey)),
                        ),                      ),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 12, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(child: Text(trip.endAddress, style: const TextStyle(fontWeight: FontWeight.bold))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(DateFormat.yMMMd().add_jm().format(trip.startTime)),
                          Text(durationString),
                        ],
                      ),
                      const Divider(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          label: const Text("Delete", style: TextStyle(color: Colors.red)),
                          onPressed: () => _confirmDelete(trip.id!),
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}