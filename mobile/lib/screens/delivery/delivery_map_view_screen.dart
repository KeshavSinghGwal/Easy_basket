import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../../utils/theme.dart';

// Platform-specific imports - same pattern as map_address_picker_screen.dart
// These will only work on mobile, web will show fallback
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DeliveryMapViewScreen extends StatefulWidget {
  final double destinationLat;
  final double destinationLng;
  final String destinationAddress;
  final String? orderId;

  const DeliveryMapViewScreen({
    super.key,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationAddress,
    this.orderId,
  });

  @override
  State<DeliveryMapViewScreen> createState() => _DeliveryMapViewScreenState();
}

class _DeliveryMapViewScreenState extends State<DeliveryMapViewScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _isLoading = true;
  bool _isGettingLocation = false;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
      _error = null;
    });

    if (kIsWeb) {
      setState(() {
        _isLoading = false;
        _isGettingLocation = false;
        _error = 'Location not available on web';
      });
      return;
    }

    // On web, skip location fetching (guarded by kIsWeb check above)
    // This code only runs on mobile
    final status = await Permission.location.request();
    if (!status.isGranted) {
      setState(() {
        _isLoading = false;
        _isGettingLocation = false;
        _error = 'Location permission denied';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required')),
        );
      }
      return;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLoading = false;
          _isGettingLocation = false;
          _error = 'Location services are disabled';
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 15),
      );

      setState(() {
        _currentPosition = position;
        _isLoading = false;
        _isGettingLocation = false;
      });

      _updateMap();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isGettingLocation = false;
        _error = 'Error getting location: $e';
      });
    }
  }

  void _updateMap() {
    if (kIsWeb || _currentPosition == null) return;

    final currentLat = _currentPosition!.latitude;
    final currentLng = _currentPosition!.longitude;
    final destLat = widget.destinationLat;
    final destLng = widget.destinationLng;

    // Create markers (only on mobile, guarded by kIsWeb check above)
    if (!kIsWeb) {
      setState(() {
        _markers = {
          Marker(
            markerId: const MarkerId('current'),
            position: LatLng(currentLat, currentLng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: const InfoWindow(
              title: 'Your Location',
              snippet: 'Delivery agent current location',
            ),
          ),
          Marker(
            markerId: const MarkerId('destination'),
            position: LatLng(destLat, destLng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: 'Delivery Address',
              snippet: widget.destinationAddress,
            ),
          ),
        };

        // Create polyline for route (straight line - for visual representation)
        // Note: For actual turn-by-turn route, use Google Directions API
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: [
              LatLng(currentLat, currentLng),
              LatLng(destLat, destLng),
            ],
            color: AppTheme.primaryGreen,
            width: 4,
            patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          ),
        };
      });
    }

    // Move camera to show both locations (only on mobile)
    if (!kIsWeb && _mapController != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          currentLat < destLat ? currentLat : destLat,
          currentLng < destLng ? currentLng : destLng,
        ),
        northeast: LatLng(
          currentLat > destLat ? currentLat : destLat,
          currentLng > destLng ? currentLng : destLng,
        ),
      );
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          bounds,
          100.0,
        ),
      );
    }
  }

  Future<void> _openGoogleMapsNavigation() async {
    final destLat = widget.destinationLat;
    final destLng = widget.destinationLng;

    // Open Google Maps with turn-by-turn navigation
    // If we have current position, use it as origin, otherwise just show destination
    String urlString;
    if (!kIsWeb && _currentPosition != null) {
      final currentLat = _currentPosition!.latitude;
      final currentLng = _currentPosition!.longitude;
      urlString = 'https://www.google.com/maps/dir/?api=1&origin=$currentLat,$currentLng&destination=$destLat,$destLng&travelmode=driving';
    } else {
      // On web or if location not available, just show destination
      urlString = 'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=driving';
    }

    final uri = Uri.parse(urlString);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Route'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_currentPosition != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _getCurrentLocation,
              tooltip: 'Refresh Location',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : kIsWeb
              ? _buildWebFallback()
              : _error != null
                  ? _buildErrorView()
                  : _buildMapView(),
      bottomNavigationBar: (kIsWeb || _currentPosition != null)
          ? _buildBottomSheet()
          : null,
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Unknown error',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _getCurrentLocation,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebFallback() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 64, color: AppTheme.grey),
            const SizedBox(height: 16),
            const Text(
              'Map view is not available on web.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please use the "Open in Google Maps" button for navigation.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openGoogleMapsNavigation,
              icon: const Icon(Icons.directions),
              label: const Text('Open in Google Maps'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapView() {
    if (_currentPosition == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            ),
            zoom: 14,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
            _updateMap();
          },
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: true,
        ),
        // Refresh location button
        Positioned(
          top: 16,
          right: 16,
          child: FloatingActionButton(
            mini: true,
            onPressed: _getCurrentLocation,
            backgroundColor: AppTheme.white,
            foregroundColor: AppTheme.primaryGreen,
            child: _isGettingLocation
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSheet() {
    // Calculate distance if we have current position (not on web)
    String? distanceKm;
    if (!kIsWeb && _currentPosition != null) {
      final distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        widget.destinationLat,
        widget.destinationLng,
      );
      distanceKm = (distance / 1000).toStringAsFixed(2);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Destination Address
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: AppTheme.primaryGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Delivery Address',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.destinationAddress,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Distance and Action Button
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Distance',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        distanceKm != null ? '$distanceKm km' : 'N/A',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _openGoogleMapsNavigation,
                    icon: const Icon(Icons.directions, size: 20),
                    label: const Text('Start Navigation'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: AppTheme.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

