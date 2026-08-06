import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../utils/theme.dart';

class MapAddressPickerScreen extends StatefulWidget {
  final Function(double lat, double lng, String address) onLocationSelected;

  const MapAddressPickerScreen({
    super.key,
    required this.onLocationSelected,
  });

  @override
  State<MapAddressPickerScreen> createState() => _MapAddressPickerScreenState();
}

class _MapAddressPickerScreenState extends State<MapAddressPickerScreen> {
  GoogleMapController? _mapController;
  double _currentLat = 28.7041; // Default: Delhi
  double _currentLng = 77.1025;
  double _selectedLat = 28.7041;
  double _selectedLng = 77.1025;
  String _selectedAddress = 'Loading location...';
  bool _isLoading = true;
  bool _isGettingAddress = false;
  Set<Marker> _markers = {};
  bool _isMapReady = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);

    // Check permission status first (don't request if already granted - Blinkit style)
    PermissionStatus status = await Permission.location.status;
    if (status.isDenied) {
      // Only request if denied (not permanently denied)
      status = await Permission.location.request();
    }
    
    if (!status.isGranted) {
      setState(() {
        _isLoading = false;
        _selectedAddress = 'Location permission denied';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required')),
        );
      }
      return;
    }

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLoading = false;
          _selectedAddress = 'Location services are disabled';
        });
        return;
      }

      // Blinkit-style: Get last known position first (instant)
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ No last known position: $e');
        }
      }

      // If no cached position, get fresh one (fast, low accuracy first)
      if (position == null) {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low, // Fast initial fix
          timeLimit: const Duration(seconds: 10),
        );
      }

      // Ensure we have a valid position
      if (position == null) {
        setState(() {
          _isLoading = false;
          _selectedAddress = 'Unable to get location';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to get your location. Please try again.')),
          );
        }
        return;
      }

      // At this point, position is guaranteed to be non-null
      final validPosition = position;
      setState(() {
        _currentLat = validPosition.latitude;
        _currentLng = validPosition.longitude;
        _selectedLat = validPosition.latitude;
        _selectedLng = validPosition.longitude;
        _isLoading = false;
      });

      // Move map to current location
      final mapController = _mapController;
      if (mapController != null) {
        await mapController.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(_selectedLat, _selectedLng),
            17.0, // Zoom level for street view
          ),
        );
      }

      await _getAddressFromCoordinates(_selectedLat, _selectedLng);
      _updateMarker();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _selectedAddress = 'Error getting location: $e';
      });
    }
  }

  // Store parsed address components
  Placemark? _currentPlacemark;

  Future<void> _getAddressFromCoordinates(double lat, double lng) async {
    setState(() => _isGettingAddress = true);

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final place = placemarks[0];
        _currentPlacemark = place; // Store for later use
        final address = _formatAddress(place);
        setState(() {
          _selectedAddress = address;
          _isGettingAddress = false;
        });
      } else {
        setState(() {
          _selectedAddress = 'Address not found';
          _isGettingAddress = false;
          _currentPlacemark = null;
        });
      }
    } catch (e) {
      setState(() {
        _selectedAddress = 'Error getting address: $e';
        _isGettingAddress = false;
        _currentPlacemark = null;
      });
    }
  }

  String _formatAddress(Placemark place) {
    final parts = <String>[];
    if (place.street != null && place.street!.isNotEmpty) {
      parts.add(place.street!);
    }
    if (place.subLocality != null && place.subLocality!.isNotEmpty) {
      parts.add(place.subLocality!);
    }
    if (place.locality != null && place.locality!.isNotEmpty) {
      parts.add(place.locality!);
    }
    if (place.postalCode != null && place.postalCode!.isNotEmpty) {
      parts.add(place.postalCode!);
    }
    if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
      parts.add(place.administrativeArea!);
    }
    return parts.join(', ');
  }

  // Extract structured address components from Placemark
  // Optimized for Indian addresses
  Map<String, String?> _extractAddressComponents(Placemark place) {
    // Address Line 1: House/Building number and street
    // Priority: subThoroughfare (house number) + thoroughfare (street) > thoroughfare > street > subLocality
    String? addressLine1;
    final houseNumber = place.subThoroughfare?.trim();
    final streetName = place.thoroughfare?.trim();
    final street = place.street?.trim();
    
    if (houseNumber != null && houseNumber.isNotEmpty) {
      if (streetName != null && streetName.isNotEmpty) {
        addressLine1 = '$houseNumber, $streetName';
      } else if (street != null && street.isNotEmpty) {
        addressLine1 = '$houseNumber, $street';
      } else {
        addressLine1 = houseNumber;
      }
    } else if (streetName != null && streetName.isNotEmpty) {
      addressLine1 = streetName;
    } else if (street != null && street.isNotEmpty) {
      addressLine1 = street;
    } else {
      // Last resort: use subLocality or locality
      addressLine1 = place.subLocality?.trim() ?? place.locality?.trim() ?? 'Address';
    }

    // Address Line 2: Area/Locality/Sub-locality
    // For Indian addresses, subLocality often contains the area/colony name
    String? addressLine2;
    final subLocality = place.subLocality?.trim();
    final locality = place.locality?.trim();
    
    // Only set addressLine2 if it's different from what we used in addressLine1
    if (subLocality != null && 
        subLocality.isNotEmpty && 
        subLocality != addressLine1 &&
        subLocality != locality) {
      addressLine2 = subLocality;
    } else if (locality != null && 
               locality.isNotEmpty && 
               locality != addressLine1 &&
               locality != place.administrativeArea?.trim()) {
      // Only use locality if it's not the same as city/state
      addressLine2 = locality;
    }

    // City: Priority: locality > subAdministrativeArea > subLocality
    // For Indian addresses, locality is usually the city
    String? city = locality ?? 
                   place.subAdministrativeArea?.trim() ?? 
                   subLocality;

    // State: Use administrativeArea (usually state in India)
    String? state = place.administrativeArea?.trim();

    // Pincode: Use postalCode (6-digit pincode in India)
    String? pincode = place.postalCode?.trim();
    
    // Validate pincode format (should be 6 digits for India)
    if (pincode != null && pincode.isNotEmpty) {
      // Remove any non-digit characters
      pincode = pincode.replaceAll(RegExp(r'[^0-9]'), '');
      // If it's not 6 digits, might be invalid
      if (pincode.length != 6) {
        // Still return it, but log a warning
        print('⚠️ Pincode format might be invalid: $pincode (expected 6 digits)');
      }
    }

    return {
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'pincode': pincode,
    };
  }

  void _updateMarker() {
    // No markers needed - we use a centered pin overlay instead
    // This gives better UX like Zomato/Blinkit
    setState(() {
      _markers = {};
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    setState(() {
      _isMapReady = true;
    });
    
    // Update marker after map is ready
    _updateMarker();
    
    // Move to current location if available
    if (_selectedLat != 0 && _selectedLng != 0) {
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_selectedLat, _selectedLng),
          17.0,
        ),
      );
    }
  }

  void _onCameraMove(CameraPosition position) {
    // Update selected location as user pans the map
    setState(() {
      _selectedLat = position.target.latitude;
      _selectedLng = position.target.longitude;
    });
    _updateMarker();
  }

  void _onCameraIdle() {
    // Get address when user stops moving the map
    _getAddressFromCoordinates(_selectedLat, _selectedLng);
  }

  Future<void> _moveToCurrentLocation() async {
    await _getCurrentLocation();
  }

  void _confirmSelection() {
    if (!mounted) return;
    
    // Validate we have valid coordinates
    if (_selectedLat == 0 || _selectedLng == 0 || _selectedAddress.isEmpty || _selectedAddress == 'Loading location...') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for location to load or select a valid location'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Extract structured address components
    Map<String, String?> addressComponents = {};
    if (_currentPlacemark != null) {
      addressComponents = _extractAddressComponents(_currentPlacemark!);
    } else {
      // Fallback: try to get address again if placemark is missing
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for address to load completely'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Debug log
    print('✅ Confirming location: $_selectedLat, $_selectedLng');
    print('✅ Address: $_selectedAddress');
    print('✅ Components: $addressComponents');
    
    // Return data to the previous screen with structured components
    final result = {
      'latitude': _selectedLat,
      'longitude': _selectedLng,
      'address': _selectedAddress, // Full formatted address for display
      'addressLine1': addressComponents['addressLine1'],
      'addressLine2': addressComponents['addressLine2'],
      'city': addressComponents['city'],
      'state': addressComponents['state'],
      'pincode': addressComponents['pincode'],
    };
    
    // Call the callback first (for any side effects)
    widget.onLocationSelected(
      _selectedLat,
      _selectedLng,
      _selectedAddress,
    );
    
    // Then pop with data
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _moveToCurrentLocation,
            tooltip: 'Current Location',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Google Map
          if (kIsWeb)
            _buildWebFallback()
          else
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
                    onMapCreated: _onMapCreated,
                    initialCameraPosition: CameraPosition(
                      target: LatLng(_selectedLat, _selectedLng),
                      zoom: 17.0,
                    ),
                    markers: _markers,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    onCameraMove: _onCameraMove,
                    onCameraIdle: _onCameraIdle,
                    mapType: MapType.normal,
                  ),

          // Centered Pin (always visible in center)
          if (!kIsWeb && !_isLoading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Pin Icon
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.location_on,
                      color: AppTheme.primaryGreen,
                      size: 40,
                    ),
                  ),
                  // Pin Point
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Address Card at Bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
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
                    // Address Display
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
                              if (_isGettingAddress)
                                const LinearProgressIndicator()
                              else
                                Text(
                                  _selectedAddress,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (_selectedLat != 0 && _selectedLng != 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${_selectedLat.toStringAsFixed(6)}, ${_selectedLng.toStringAsFixed(6)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.grey,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Confirm Button
                    SizedBox(
                      width: double.infinity,
                      child: AppTheme.gradientButton(
                        onPressed: (_isGettingAddress || _selectedAddress.isEmpty || _selectedAddress == 'Loading location...')
                            ? null
                            : _confirmSelection,
                        height: 52,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _isGettingAddress
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.check_circle, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(_isGettingAddress ? 'Loading address...' : 'Confirm Location',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Current Location Button (Floating)
          if (!kIsWeb && !_isLoading)
            Positioned(
              right: 16,
              top: 80,
              child: FloatingActionButton(
                mini: true,
                onPressed: _moveToCurrentLocation,
                backgroundColor: AppTheme.white,
                child: Icon(
                  Icons.my_location,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebFallback() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.map_outlined,
              size: 100,
              color: AppTheme.primaryGreen,
            ),
            const SizedBox(height: 24),
            const Text(
              'Map View Available on Mobile',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'For the best experience with interactive map and draggable pin, please use the mobile app.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.grey,
              ),
            ),
            const SizedBox(height: 32),
            AppTheme.gradientButton(
              onPressed: _getCurrentLocation,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              height: 52,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.my_location, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Use Current Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ),
            ),
            if (_selectedAddress != 'Loading location...' && _selectedAddress != 'Location permission denied') ...[
              const SizedBox(height: 24),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selected Location:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(_selectedAddress),
                      const SizedBox(height: 8),
                      Text(
                        'Coordinates: ${_selectedLat.toStringAsFixed(6)}, ${_selectedLng.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
