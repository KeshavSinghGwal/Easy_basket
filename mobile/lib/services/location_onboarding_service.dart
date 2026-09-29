import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/order_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/service_area_provider.dart';

/// Service to handle seamless location onboarding
/// Auto-detects location in background and only shows screens if needed
class LocationOnboardingService {
  /// Auto-detect and save location for new users
  /// Returns: true if location was saved, false if error or not serviceable
  static Future<Map<String, dynamic>> autoDetectAndSaveLocation({
    required OrderProvider orderProvider,
    required AuthProvider authProvider,
    required ServiceAreaProvider serviceAreaProvider,
  }) async {
    if (kIsWeb) {
      return {
        'success': false,
        'error': 'Location detection not available on web',
        'showScreen': false,
      };
    }

    try {
      // Check current permission status first
      final currentStatus = await Permission.location.status;
      
      // Request location permission with permanently denied handling
      PermissionStatus status;
      if (currentStatus.isDenied) {
        status = await Permission.location.request();
      } else {
        status = currentStatus;
      }
      
      if (!status.isGranted) {
        final isPermanentlyDenied = status.isPermanentlyDenied || await Permission.location.isPermanentlyDenied;
        return {
          'success': false,
          'error': 'Location permission denied',
          'showScreen': true, // Show permission explanation screen
          'permissionDenied': true,
          'permissionPermanentlyDenied': isPermanentlyDenied,
        };
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return {
          'success': false,
          'error': 'Location services disabled',
          'showScreen': false,
        };
      }

      // Get last known position first (instant)
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ No last known position: $e');
        }
      }

      // If no last known position, get fresh one (fast, low accuracy) with fallback
      if (position == null) {
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 5),
          );
        } catch (_) {
          // Fallback: medium accuracy with slightly longer timeout
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
        }
      }

      // Get address from coordinates with timeout and graceful fallback
      List<Placemark> placemarks = [];
      try {
        placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 6));
      } catch (_) {
        placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
      }

      if (placemarks.isEmpty) {
        return {
          'success': false,
          'error': 'Could not get address from location',
          'showScreen': false,
        };
      }

      final place = placemarks.first;

      // Extract address components
      String? city = place.locality?.trim() ?? 
                     place.subAdministrativeArea?.trim() ?? 
                     place.subLocality?.trim();
      
      String? state = place.administrativeArea?.trim();
      String? pincode = place.postalCode?.trim();
      
      // Clean pincode
      if (pincode != null && pincode.isNotEmpty) {
        pincode = pincode.replaceAll(RegExp(r'[^0-9]'), '');
      }

      if (pincode == null || pincode.isEmpty) {
        return {
          'success': false,
          'error': 'Could not detect pincode',
          'showScreen': false,
        };
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

      // Check service availability
      // Coordinates first — radius check decides; pincode stays a fallback.
      final isAvailable = await serviceAreaProvider.checkServiceAvailability(
        latitude: position.latitude,
        longitude: position.longitude,
        pincode: pincode,
        country: 'India',
      );

      // If not serviceable, return info to show service not available screen
      if (!isAvailable) {
        return {
          'success': false,
          'error': 'Service not available',
          'showScreen': true, // Show service not available screen
          'pincode': pincode,
          'city': city,
          'state': state,
          'country': 'India',
        };
      }

      // Service is available - return address data for user to review/edit (Blinkit-style)
      if (authProvider.token == null) {
        return {
          'success': false,
          'error': 'Not authenticated',
          'showScreen': false,
        };
      }

      // Return address data instead of saving directly - let user review/edit first
      return {
        'success': true,
        'showScreen': true, // Show edit screen for user to review/edit
        'addressData': {
          'addressLine1': addressLine1,
          'city': city ?? '',
          'state': state ?? '',
          'pincode': pincode,
          'latitude': position.latitude.toString(),
          'longitude': position.longitude.toString(),
          'selectedAddressText': addressLine1,
          'tag': 'home',
          'isDefault': true,
          'skipToDetails': true, // Skip location step, go to details
        },
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in auto location detection: $e');
      }
      return {
        'success': false,
        'error': e.toString(),
        'showScreen': false,
      };
    }
  }
}
