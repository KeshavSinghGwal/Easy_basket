import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_area_provider.dart';
import '../../utils/theme.dart';
import '../../l10n/app_localizations.dart';

/// Screen shown to new users to automatically detect their location
/// Similar to Blinkit/Zomato onboarding flow
class LocationDetectionScreen extends StatefulWidget {
  const LocationDetectionScreen({super.key});

  @override
  State<LocationDetectionScreen> createState() => _LocationDetectionScreenState();
}

class _LocationDetectionScreenState extends State<LocationDetectionScreen> {
  bool _isDetecting = true;
  bool _isRefining = false; // Track if we're refining location in background
  bool _hasError = false;
  String? _errorMessage;
  String? _detectedCity;
  String? _detectedState;
  String? _detectedPincode;
  double? _latitude;
  double? _longitude;
  String? _addressLine1;

  @override
  void initState() {
    super.initState();
    _detectLocation();
  }

  /// Optimized location detection - like Blinkit (fast and smooth)
  /// Strategy:
  /// 1. Use last known position first (instant)
  /// 2. Show location immediately
  /// 3. Refine in background with better accuracy
  /// 4. Check service availability in parallel (non-blocking)
  Future<void> _detectLocation() async {
    setState(() {
      _isDetecting = true;
      _hasError = false;
      _errorMessage = null;
    });

    if (kIsWeb) {
      setState(() {
        _isDetecting = false;
        _hasError = true;
        _errorMessage = 'Location detection is not available on web. Please add address manually.';
      });
      return;
    }

    try {
      // Request location permission
      final status = await Permission.location.request();
      if (!status.isGranted) {
        setState(() {
          _isDetecting = false;
          _hasError = true;
          _errorMessage = 'Location permission is required to detect your delivery area.';
        });
        return;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isDetecting = false;
          _hasError = true;
          _errorMessage = 'Please enable location services in your device settings.';
        });
        return;
      }

      // STEP 1: Get last known position FIRST (instant, no waiting)
      // This gives us immediate location to show user
      Position? lastPosition;
      try {
        lastPosition = await Geolocator.getLastKnownPosition();
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ No last known position: $e');
        }
      }

      // STEP 2: If we have last known position, show it immediately
      if (lastPosition != null) {
        _latitude = lastPosition.latitude;
        _longitude = lastPosition.longitude;
        
        // Get address from last known position (fast, shows immediately)
        _processLocationData(lastPosition.latitude, lastPosition.longitude, isInitial: true);
        
        // STEP 3: Refine location in background (non-blocking)
        // Use lower accuracy for speed, then refine if needed
        _refineLocationInBackground();
      } else {
        // No last known position, get fresh location
        // Use LOW accuracy first for speed (like Blinkit)
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low, // Fast, good enough for initial detection
          timeLimit: const Duration(seconds: 5), // Shorter timeout
        );

        _latitude = position.latitude;
        _longitude = position.longitude;
        
        // Process and show immediately
        await _processLocationData(position.latitude, position.longitude, isInitial: true);
        
        // Refine in background if needed
        _refineLocationInBackground();
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error detecting location: $e');
      }
      setState(() {
        _isDetecting = false;
        _hasError = true;
        _errorMessage = 'Error detecting location. Please try again or add address manually.';
      });
    }
  }

  /// Process location data and update UI immediately
  Future<void> _processLocationData(double lat, double lng, {bool isInitial = false}) async {
    try {
      // Get address from coordinates (this is the slow part, but we show loading)
      List<Placemark> placemarks = await placemarkFromCoordinates(
        lat,
        lng,
      );

      if (placemarks.isEmpty) {
        if (isInitial) {
          setState(() {
            _isDetecting = false;
            _hasError = true;
            _errorMessage = 'Could not detect your location. Please add address manually.';
          });
        }
        return;
      }

      final place = placemarks.first;

      // Extract address components (India-specific)
      String? city = place.locality?.trim() ?? 
                     place.subAdministrativeArea?.trim() ?? 
                     place.subLocality?.trim();
      
      String? state = place.administrativeArea?.trim();
      String? pincode = place.postalCode?.trim();
      
      // Clean pincode (remove non-digits)
      if (pincode != null && pincode.isNotEmpty) {
        pincode = pincode.replaceAll(RegExp(r'[^0-9]'), '');
      }

      // Build address line 1
      final addressParts = <String>[];
      if (place.street != null && place.street!.isNotEmpty) {
        addressParts.add(place.street!);
      }
      if (place.subThoroughfare != null && place.subThoroughfare!.isNotEmpty) {
        addressParts.add(place.subThoroughfare!);
      }
      if (place.thoroughfare != null && place.thoroughfare!.isNotEmpty) {
        addressParts.add(place.thoroughfare!);
      }
      final addressLine1 = addressParts.isNotEmpty 
          ? addressParts.join(', ')
          : (city ?? 'Your Location');

      // Update UI immediately (user sees location right away)
      setState(() {
        _detectedCity = city;
        _detectedState = state;
        _detectedPincode = pincode;
        _addressLine1 = addressLine1;
        _latitude = lat;
        _longitude = lng;
        _isDetecting = false;
      });

      // Check service availability in background (non-blocking)
      if (pincode != null && pincode.isNotEmpty && mounted) {
        final serviceAreaProvider = Provider.of<ServiceAreaProvider>(context, listen: false);
        // Don't await - let it run in background
        serviceAreaProvider.checkServiceAvailability(
          latitude: lat,
          longitude: lng,
          pincode: pincode,
          country: 'India',
        ).catchError((e) {
          if (kDebugMode) {
            print('⚠️ Service check error (non-blocking): $e');
          }
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error processing location: $e');
      }
      if (isInitial) {
        setState(() {
          _isDetecting = false;
          _hasError = true;
          _errorMessage = 'Error processing location. Please try again.';
        });
      }
    }
  }

  /// Refine location in background with better accuracy (non-blocking)
  void _refineLocationInBackground() {
    if (!mounted) return;
    
    setState(() => _isRefining = true);
    
    // Run in background without blocking UI
    Future.delayed(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      
      try {
        // Get more accurate position in background
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium, // Better accuracy, but still fast
          timeLimit: const Duration(seconds: 8),
        );

        // Only update if significantly different (avoid unnecessary updates)
        if (_latitude != null && _longitude != null) {
          final distance = Geolocator.distanceBetween(
            _latitude!,
            _longitude!,
            position.latitude,
            position.longitude,
          );
          
          // Only update if moved more than 100 meters (significant change)
          if (distance > 100) {
            await _processLocationData(position.latitude, position.longitude, isInitial: false);
          }
        } else {
          await _processLocationData(position.latitude, position.longitude, isInitial: false);
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Background refinement failed (non-critical): $e');
        }
        // Don't show error - initial location is good enough
      } finally {
        if (mounted) {
          setState(() => _isRefining = false);
        }
      }
    });
  }

  Future<void> _confirmAndSave() async {
    if (_latitude == null || _longitude == null || _detectedPincode == null) {
      return;
    }

    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final serviceAreaProvider = Provider.of<ServiceAreaProvider>(context, listen: false);

    if (authProvider.token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(AppLocalizations.of(context).commonLoginFirst)),
        );
      }
      return;
    }

    // Check service availability one more time.
    // `?? true`, not `?? false`: null means the check could not complete (network
    // failure), not that we are out of area. Blocking onboarding on an unknown
    // would turn away a serviceable customer over a dropped request — and the
    // server re-checks at order time anyway. See ServiceAreaProvider's catch.
    final isAvailable = serviceAreaProvider.isServiceAvailable ?? true;
    if (!isAvailable) {
      if (mounted) {
        context.push('/service-not-available', extra: {
          'pincode': _detectedPincode,
          'city': _detectedCity,
          'state': _detectedState,
          'country': 'India',
        });
      }
      return;
    }

    // Show loading
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      // Save the detected address as default
      final success = await orderProvider.createAddress(
        token: authProvider.token!,
        addressLine1: _addressLine1 ?? 'Your Location',
        city: _detectedCity ?? '',
        state: _detectedState ?? '',
        pincode: _detectedPincode!,
        isDefault: true,
        latitude: _latitude!.toString(),
        longitude: _longitude!.toString(),
        tag: 'home',
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        if (success) {
          // Navigate to home
          context.go('/home');
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text(AppLocalizations.of(context).locationSaved),
                ],
              ),
              backgroundColor: AppTheme.primaryGreen,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(orderProvider.error ?? 'Failed to save location'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).commonError(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              
              // Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isDetecting ? Icons.my_location : Icons.location_on,
                  size: 64,
                  color: AppTheme.primaryGreen,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Title
              Text(
                _isDetecting 
                    ? AppLocalizations.of(context).locationDetecting
                    : _hasError
                        ? 'Location Detection'
                        : 'We found your location!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.black,
                    ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 16),
              
              // Loading or Error or Success
              if (_isDetecting)
                Column(
                  children: [
                    // Smooth, non-jumpy loading indicator
                    const SizedBox(
                      width: 50,
                      height: 50,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context).locationDetecting,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.grey,
                            fontSize: 14,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              else if (_hasError)
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage ?? 'Unknown error',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.black,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: AppTheme.gradientButton(
                        onPressed: _detectLocation,
                        height: 52,
                        child:  Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(AppLocalizations.of(context).commonTryAgain, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/address/add'),
                        icon: const Icon(Icons.add_location),
                        label:  Text(AppLocalizations.of(context).locationAddManually),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryGreen,
                          side: const BorderSide(color: AppTheme.primaryGreen),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                // Success - Show detected location
                Column(
                  children: [
                    // Location Card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryGreen.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
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
                                      Text(
                                        _addressLine1 ?? 'Your Location',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      if (_detectedCity != null || _detectedState != null)
                                        Text(
                                          [
                                            _detectedCity,
                                            _detectedState,
                                            _detectedPincode,
                                          ].where((e) => e != null && e.isNotEmpty).join(', '),
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                color: AppTheme.grey,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                // Show subtle indicator if refining in background
                                if (_isRefining)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Action Buttons
                    SizedBox(
                      width: double.infinity,
                      child: AppTheme.gradientButton(
                        onPressed: _confirmAndSave,
                        height: 54,
                        child:  Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, color: Colors.white, size: 22),
                            SizedBox(width: 8),
                            Text(AppLocalizations.of(context).locationConfirmContinue, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/address/add'),
                        icon: const Icon(Icons.edit_location),
                        label:  Text(AppLocalizations.of(context).locationRefine),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryGreen,
                          side: const BorderSide(color: AppTheme.primaryGreen, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 18),
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
      ),
    );
  }
}

