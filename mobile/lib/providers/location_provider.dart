import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:location/location.dart' as loc;
import '../models/partial_address_model.dart';

/// LocationProvider — Manages GPS location and permission state
///
/// This is the "Radio Station" for location data.
/// It detects GPS, converts to address, and broadcasts to all listeners.
///
/// Responsibilities:
/// 1. Check & request GPS permission
/// 2. Get current GPS coordinates (lat/lng)
/// 3. Convert coordinates to partial address (reverse geocode)
/// 4. Track permission status for UI decisions
///
/// Used by:
/// - Home screen (on app open — detect location)
/// - Permission screen (request permission)
/// - ProximityProvider (needs GPS to compare with saved addresses)
class LocationProvider extends ChangeNotifier {

  // ══════════════════════════════════════════════════
  // STATE — Data this provider holds
  // ══════════════════════════════════════════════════

  /// Current GPS position (lat/lng)
  /// null until GPS detection completes
  Position? _currentPosition;

  /// Partial address from GPS reverse geocode
  /// Contains: area, city, state, pincode (NO house/street)
  PartialAddress? _detectedAddress;

  /// Is GPS detection currently running?
  /// true while waiting for GPS/geocode — show shimmer in UI
  bool _isDetecting = false;

  /// Error message if something went wrong
  String? _error;

  /// GPS permission status
  /// Tracks: granted, denied, deniedForever, etc.
  LocationPermission _permissionStatus = LocationPermission.denied;

  /// Has detection been done at least once in this session?
  /// Prevents repeated detection on every rebuild
  bool _hasDetected = false;

  // ══════════════════════════════════════════════════
  // GETTERS — Read-only access for UI
  // ══════════════════════════════════════════════════

  /// Get current GPS position
  Position? get currentPosition => _currentPosition;

  /// Get detected partial address
  PartialAddress? get detectedAddress => _detectedAddress;

  /// Is detection in progress?
  bool get isDetecting => _isDetecting;

  /// Get error message (if any)
  String? get error => _error;

  /// Get permission status
  LocationPermission get permissionStatus => _permissionStatus;

  /// Has detection happened this session?
  bool get hasDetected => _hasDetected;

  /// Is GPS permission granted?
  bool get isPermissionGranted =>
      _permissionStatus == LocationPermission.always ||
      _permissionStatus == LocationPermission.whileInUse;

  /// Is GPS permission permanently denied?
  /// If yes, we can't show system dialog — must open app settings
  bool get isPermissionPermanentlyDenied =>
      _permissionStatus == LocationPermission.deniedForever;

  /// Is GPS permission denied (but can ask again)?
  bool get isPermissionDenied =>
      _permissionStatus == LocationPermission.denied;

  // ══════════════════════════════════════════════════
  // METHOD 1: Check current permission status
  // ══════════════════════════════════════════════════

  /// Check what the current GPS permission status is
  /// Does NOT request permission — just checks
  ///
  /// Why separate from request?
  /// Because we need to know status BEFORE deciding
  /// whether to show permission screen or detect directly
  Future<void> checkPermission() async {
    try {
      // First check: Is GPS turned on in phone settings?
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _permissionStatus = LocationPermission.denied;
        _error = 'Location services are turned off';
        notifyListeners();
        return;
      }

      // Second check: Does our app have permission?
      _permissionStatus = await Geolocator.checkPermission();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to check location permission';
      debugPrint('❌ [Location] Permission check failed: $e');
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════
  // METHOD 2: Request GPS permission from user
  // ══════════════════════════════════════════════════

  /// Show system dialog asking user for GPS permission
  /// Returns true if granted, false if denied
  ///
  /// Flow:
  /// - If never asked → System dialog appears
  /// - If denied once → System dialog appears again
  /// - If permanently denied → Can't show dialog, returns false
  ///   (caller should use openAppSettings instead)
  Future<bool> requestPermission() async {
    try {
      // Check if GPS service is enabled first
      var serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        // Try the in-app Google Play Services resolution dialog before sending
        // the user out to phone settings. On Android with Play Services this
        // shows a one-tap "OK" overlay that flips the OS toggle without
        // leaving the app. On iOS / Android-without-Play-Services it returns
        // false and the caller falls back to openLocationSettings().
        try {
          final accepted = await loc.Location().requestService();
          if (accepted) {
            serviceEnabled = true;
            debugPrint('📍 [Location] In-app service dialog: enabled');
          } else {
            debugPrint('📍 [Location] In-app service dialog: declined or unavailable');
          }
        } catch (e) {
          debugPrint('⚠️ [Location] requestService threw — falling back: $e');
        }

        if (!serviceEnabled) {
          _error = 'Please turn on location in phone settings';
          debugPrint('⚠️ [Location] Service still disabled — caller will show settings link');
          notifyListeners();
          return false;
        }
      }

      // If permanently denied, can't request — need app settings
      if (_permissionStatus == LocationPermission.deniedForever) {
        _error = 'Location permanently denied. Please enable in Settings.';
        notifyListeners();
        return false;
      }

      // Request permission — system dialog will appear
      _permissionStatus = await Geolocator.requestPermission();
      debugPrint('📍 [Location] requestPermission returned: $_permissionStatus');

      // Some Android devices return `unableToDetermine` or a stale `denied` value
      // immediately after the user dismisses the dialog. A fresh checkPermission
      // call gives the OS a moment to settle and returns the actual state.
      if (_permissionStatus == LocationPermission.unableToDetermine ||
          _permissionStatus == LocationPermission.denied) {
        final settled = await Geolocator.checkPermission();
        debugPrint('📍 [Location] re-check after dialog: $settled');
        _permissionStatus = settled;
      }

      notifyListeners();
      return isPermissionGranted;
    } catch (e) {
      _error = 'Failed to request location permission';
      debugPrint('❌ [Location] Permission request failed: $e');
      notifyListeners();
      return false;
    }
  }

  // ══════════════════════════════════════════════════
  // METHOD 3: Open phone's app settings
  // ══════════════════════════════════════════════════

  /// Open phone's Settings → Apps → Easy Basket → Permissions
  /// Used when permission is permanently denied
  /// User can manually enable location from there
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Open phone's location settings (turn on GPS)
  /// Used when location service is disabled
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  // ══════════════════════════════════════════════════
  // METHOD 4: Detect current location (Main method)
  // ══════════════════════════════════════════════════

  /// Get GPS coordinates + reverse geocode to partial address
  ///
  /// This is the main method — called when app opens
  ///
  /// Flow:
  /// 1. Check permission → if not granted, stop
  /// 2. Try last known position (instant, cached)
  /// 3. If no cache, get fresh position (2-3 sec)
  /// 4. Reverse geocode lat/lng → address components
  /// 5. Create PartialAddress → notify listeners
  ///
  /// After this completes:
  /// - _currentPosition has lat/lng
  /// - _detectedAddress has city/area/pincode
  /// - ProximityProvider can now compare with saved addresses
  /// Force parameter — if true, detect even if already done
  /// Default false for normal use, true when user explicitly asks
  Future<void> detectLocation({bool force = false}) async {
    // Don't detect if already in progress
    if (_isDetecting) return;

    // Skip if already done this session (unless forced)
    if (!force && _hasDetected && _detectedAddress != null) return;

    _isDetecting = true;
    _error = null;
    notifyListeners(); // UI shows shimmer/loading

    try {
      // Step 1: Check permission
      await checkPermission();
      if (!isPermissionGranted) {
        _isDetecting = false;
        _hasDetected = true;
        notifyListeners();
        return;
      }

      // Step 2: Try last known position first (instant — no GPS wait)
      // Why? Last known position is cached by the OS
      // It's available immediately, no 2-3 sec GPS wait
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
        debugPrint('📍 [Location] Last known position: ${position?.latitude}, ${position?.longitude}');
      } catch (e) {
        debugPrint('⚠️ [Location] No last known position: $e');
      }

      // Step 3: If no cached position, get fresh GPS reading
      // This takes 2-3 seconds — GPS chip talks to satellites
      if (position == null) {
        try {
          // First try: Low accuracy (faster, 5 sec timeout)
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 5),
          );
        } catch (_) {
          // Fallback: Medium accuracy (slightly slower, 10 sec timeout)
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
        }
        debugPrint('📍 [Location] Fresh position: ${position.latitude}, ${position.longitude}');
      }

      _currentPosition = position;

      // Step 4: Reverse geocode — convert lat/lng to address
      // Sends coordinates to device's geocoder (Google Play Services)
      // Returns: street, area, city, state, pincode
      List<Placemark> placemarks = [];
      try {
        placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 6));
      } catch (_) {
        // Retry without timeout
        try {
          placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );
        } catch (e) {
          debugPrint('❌ [Location] Geocode failed: $e');
        }
      }

      // Step 5: Extract address components from placemark
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        // City: Try locality first, then sub-administrative area
        String? city = place.locality?.trim();
        if (city == null || city.isEmpty) {
          city = place.subAdministrativeArea?.trim();
        }

        // Area: Sub-locality (neighborhood/sector)
        String? area = place.subLocality?.trim();
        // If area same as city, don't use it (redundant)
        if (area != null && area == city) area = null;

        // State: Administrative area
        String? state = place.administrativeArea?.trim();

        // Pincode: Postal code — clean non-digits
        String? pincode = place.postalCode?.trim();
        if (pincode != null && pincode.isNotEmpty) {
          pincode = pincode.replaceAll(RegExp(r'[^0-9]'), '');
        }
        // Validate: Indian pincode = exactly 6 digits
        if (pincode != null && pincode.length != 6) {
          pincode = null;
        }

        // Create PartialAddress
        _detectedAddress = PartialAddress(
          area: area,
          city: city,
          state: state,
          pincode: pincode,
          latitude: position.latitude,
          longitude: position.longitude,
        );

        debugPrint('📍 [Location] Detected: ${_detectedAddress!.displayName}');
        debugPrint('📍 [Location] Full: ${_detectedAddress!.fullDisplay}');
      } else {
        // Geocode returned nothing — still have coordinates
        _detectedAddress = PartialAddress(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        debugPrint('⚠️ [Location] Geocode empty — using coordinates only');
      }

      _hasDetected = true;
      _isDetecting = false;
      _error = null;
      notifyListeners(); // UI updates with detected address

    } catch (e) {
      _error = 'Could not detect location';
      _isDetecting = false;
      _hasDetected = true;
      debugPrint('❌ [Location] Detection failed: $e');
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════
  // METHOD 5: Reset (for re-detection)
  // ══════════════════════════════════════════════════

  /// Reset all state — forces fresh detection next time
  /// Used when: user changes permission in settings and comes back
  void reset() {
    _currentPosition = null;
    _detectedAddress = null;
    _isDetecting = false;
    _error = null;
    _hasDetected = false;
    notifyListeners();
  }
}
