import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/address_model.dart';
import '../models/partial_address_model.dart';
import '../models/proximity_result.dart';
import 'location_provider.dart';
import 'address_provider.dart';

/// ProximityProvider — The Decision Engine
///
/// This is the brain of the address system.
/// It takes two inputs:
///   1. GPS location (from LocationProvider)
///   2. Saved addresses (from AddressProvider)
/// And produces one output:
///   → ProximityResult (what should the app do)
///
/// Think of it like a traffic signal:
///   🟢 Green (autoSelect) = Go ahead, address is nearby
///   🟡 Yellow (warn) = Careful, you're somewhat far
///   🔴 Red (forceNew) = Stop, you're in a different city
///   ⚫ Off (noGps) = GPS not available, use default
///
/// Used by:
/// - Home screen: Which header to show, show warning?, show mismatch?
/// - Checkout: Need address completion form?
class ProximityProvider extends ChangeNotifier {

  // ══════════════════════════════════════════════════
  // CONSTANTS — Distance thresholds
  // ══════════════════════════════════════════════════

  /// Distance under which we auto-select the saved address
  /// User is clearly near this address — no need to ask
  /// Example: User at home, Home address auto-selected
  static const double _autoSelectRadiusKm = 5.0;

  /// Distance under which we select but show warning
  /// User is somewhat far — might want to use current location instead
  /// Example: User 15km from home, visiting nearby town
  static const double _warnRadiusKm = 20.0;

  /// Beyond _warnRadiusKm = forceNew
  /// User is in completely different city
  /// Example: User in Mohali, saved address in Bareilly (500km)

  /// Distance under which two locations are "same place"
  /// Used for matching GPS with saved address (200 meters)
  static const double _exactMatchRadiusMeters = 200.0;

  /// Digits-only pincode for comparison (India: first 6 digits).
  static String? _normalizePincode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return null;
    if (d.length >= 6) return d.substring(0, 6);
    return d;
  }

  /// When GPS pincode matches saved address pincode, prefer that full saved address (km drift OK).
  static AddressModel _pickBestSamePincodeAddress(
    Position gps,
    List<AddressModel> candidates,
  ) {
    for (final a in candidates) {
      if (a.isDefault) return a;
    }
    AddressModel? best;
    var bestKm = double.infinity;
    for (final a in candidates) {
      if (a.latitude == null || a.longitude == null) continue;
      final alat = double.tryParse(a.latitude!);
      final alng = double.tryParse(a.longitude!);
      if (alat == null || alng == null) continue;
      final km = Geolocator.distanceBetween(gps.latitude, gps.longitude, alat, alng) / 1000.0;
      if (km < bestKm) {
        bestKm = km;
        best = a;
      }
    }
    return best ?? candidates.first;
  }

  // ══════════════════════════════════════════════════
  // STATE
  // ══════════════════════════════════════════════════

  /// The decision result — contains everything UI needs
  ProximityResult? _result;

  /// GPS partial address seeded directly from [LocationProvider], for flows that
  /// never run a full proximity check (guests, pre-login). Lets every consumer
  /// read [partialAddress] uniformly instead of each call site falling back to
  /// LocationProvider itself. A real proximity [_result] always takes precedence.
  PartialAddress? _seededPartial;

  /// Is proximity check in progress?
  bool _isChecking = false;

  /// Has check been done this session?
  bool _hasChecked = false;

  // ══════════════════════════════════════════════════
  // GETTERS
  // ══════════════════════════════════════════════════

  /// The proximity result — UI reads this to decide what to show
  ProximityResult? get result => _result;

  /// Is check in progress?
  bool get isChecking => _isChecking;

  /// Has check happened this session?
  bool get hasChecked => _hasChecked;

  /// Quick access: Should we show warning banner?
  bool get showWarning => _result?.showWarning ?? false;

  /// Quick access: Should we show mismatch screen?
  bool get showMismatchScreen => _result?.showMismatchScreen ?? false;

  /// Quick access: Should we show "enable location" banner?
  bool get showEnableLocationBanner => _result?.showEnableLocationBanner ?? false;

  /// Quick access: Does checkout need address completion form?
  bool get needsAddressCompletion => _result?.needsAddressCompletion ?? false;

  /// Quick access: Warning text for banner
  String get warningText => _result?.warningText ?? '';

  /// Quick access: Detected partial address.
  /// Prefers a real proximity result; falls back to the GPS partial seeded via
  /// [seedPartial] so guest / pre-login flows expose the detected location too.
  PartialAddress? get partialAddress => _result?.partialAddress ?? _seededPartial;

  /// Seed the GPS partial address from [LocationProvider] for flows that don't
  /// run [checkProximity] (e.g. guests). Idempotent-ish: only notifies when the
  /// value actually changes, and never clears an existing partial with null.
  void seedPartial(PartialAddress? partial) {
    if (partial == null || partial == _seededPartial) return;
    _seededPartial = partial;
    notifyListeners();
  }

  /// Quick access: Nearest saved address
  AddressModel? get nearestAddress => _result?.nearestAddress;

  // ══════════════════════════════════════════════════
  // MAIN METHOD: Check proximity
  // ══════════════════════════════════════════════════

  /// Compare GPS location with all saved addresses and decide what to do
  ///
  /// This is the main method — called from home screen after
  /// both LocationProvider and AddressProvider have data.
  ///
  /// Flow:
  /// 1. Get GPS position from LocationProvider
  /// 2. Get saved addresses from AddressProvider
  /// 3. Calculate distance from GPS to each saved address
  /// 4. Find nearest saved address
  /// 5. Apply decision rules (< 5km, 5-20km, > 20km)
  /// 6. Create ProximityResult → notify listeners → UI updates
  /// Force parameter — re-check even if already done
  void checkProximity({
    required LocationProvider locationProvider,
    required AddressProvider addressProvider,
    bool force = false,
  }) {
    // Don't check again if already done (unless forced)
    if (!force && _hasChecked) return;

    _isChecking = true;
    notifyListeners();

    // ── Case: GPS not available ──
    // Permission denied or GPS detection failed
    if (!locationProvider.isPermissionGranted ||
        locationProvider.currentPosition == null) {
      _result = ProximityResult(
        decision: ProximityDecision.noGps,
        nearestAddress: addressProvider.defaultAddress,
        isWithinExactMatch: false,
      );
      _isChecking = false;
      _hasChecked = true;
      debugPrint('📍 [Proximity] No GPS → using default address');
      notifyListeners();
      return;
    }

    final gps = locationProvider.currentPosition!;
    final detectedAddress = locationProvider.detectedAddress;
    final savedAddresses = addressProvider.addresses;

    // ── Case: No saved addresses ──
    // New user or all addresses deleted
    if (savedAddresses.isEmpty) {
      _result = ProximityResult(
        decision: ProximityDecision.forceNew,
        partialAddress: detectedAddress,
        isWithinExactMatch: false,
      );
      _isChecking = false;
      _hasChecked = true;
      debugPrint('📍 [Proximity] No saved addresses → force new address');
      notifyListeners();
      return;
    }

    // ── Same pincode as GPS partial → full saved address (distance in km can be large; OK per product) ──
    final gpsPin = _normalizePincode(detectedAddress?.pincode);
    if (gpsPin != null) {
      final samePin = savedAddresses
          .where((a) => _normalizePincode(a.pincode) == gpsPin)
          .toList();
      if (samePin.isNotEmpty) {
        final picked = _pickBestSamePincodeAddress(gps, samePin);
        var distanceKm = 0.0;
        var exact = false;
        if (picked.latitude != null && picked.longitude != null) {
          final alat = double.tryParse(picked.latitude!);
          final alng = double.tryParse(picked.longitude!);
          if (alat != null && alng != null) {
            final m = Geolocator.distanceBetween(
              gps.latitude,
              gps.longitude,
              alat,
              alng,
            );
            distanceKm = m / 1000.0;
            exact = m <= _exactMatchRadiusMeters;
          }
        }
        _result = ProximityResult(
          decision: ProximityDecision.autoSelect,
          distanceKm: distanceKm,
          nearestAddress: picked,
          partialAddress: detectedAddress,
          isWithinExactMatch: exact,
        );
        _isChecking = false;
        _hasChecked = true;
        debugPrint(
          '📍 [Proximity] Same GPS pin $gpsPin as saved (#${picked.id}) — full address (${distanceKm.toStringAsFixed(1)}km)',
        );
        notifyListeners();
        return;
      }
    }

    // ── Find nearest saved address ──
    AddressModel? nearest;
    double nearestDistanceKm = double.infinity;

    for (final addr in savedAddresses) {
      // Skip addresses without coordinates
      if (addr.latitude == null || addr.longitude == null) continue;

      final addrLat = double.tryParse(addr.latitude!);
      final addrLng = double.tryParse(addr.longitude!);
      if (addrLat == null || addrLng == null) continue;

      // Calculate distance using Haversine formula (built into Geolocator)
      // Returns distance in meters
      final distanceMeters = Geolocator.distanceBetween(
        gps.latitude,
        gps.longitude,
        addrLat,
        addrLng,
      );

      final distanceKm = distanceMeters / 1000;

      if (distanceKm < nearestDistanceKm) {
        nearestDistanceKm = distanceKm;
        nearest = addr;
      }
    }

    // ── No address with coordinates found ──
    if (nearest == null) {
      _result = ProximityResult(
        decision: ProximityDecision.forceNew,
        partialAddress: detectedAddress,
        nearestAddress: addressProvider.defaultAddress,
        isWithinExactMatch: false,
      );
      _isChecking = false;
      _hasChecked = true;
      debugPrint('📍 [Proximity] No address with coordinates → force new');
      notifyListeners();
      return;
    }

    // ══════════════════════════════════════════════════
    // DECISION ENGINE — Apply distance rules
    // ══════════════════════════════════════════════════

    ProximityDecision decision;
    final distanceMeters = nearestDistanceKm * 1000;
    final isWithinExactMatch = distanceMeters <= _exactMatchRadiusMeters;

    if (nearestDistanceKm <= _autoSelectRadiusKm) {
      // 🟢 < 5km — User is near a saved address (Case A <200m or Case B <5km)
      decision = ProximityDecision.autoSelect;
      debugPrint('📍 [Proximity] Auto-select: ${nearest.tag} (${nearestDistanceKm.toStringAsFixed(1)}km, exact=$isWithinExactMatch)');
    } else if (nearestDistanceKm <= _warnRadiusKm) {
      // 🟡 5-20km — User is somewhat far
      // Select nearest but show warning banner
      decision = ProximityDecision.warn;
      debugPrint('📍 [Proximity] Warning: ${nearestDistanceKm.toStringAsFixed(1)}km from ${nearest.tag}');
    } else {
      // 🔴 > 20km — User is in different city
      // Don't auto-select, show mismatch screen
      decision = ProximityDecision.forceNew;
      debugPrint('📍 [Proximity] Force new: ${nearestDistanceKm.toStringAsFixed(1)}km from ${nearest.tag}');
    }

    // ── Create result ──
    _result = ProximityResult(
      decision: decision,
      distanceKm: nearestDistanceKm,
      nearestAddress: nearest,
      partialAddress: detectedAddress,
      isWithinExactMatch:
          decision == ProximityDecision.autoSelect && isWithinExactMatch,
    );

    _isChecking = false;
    _hasChecked = true;
    notifyListeners(); // UI updates based on decision
  }

  // ══════════════════════════════════════════════════
  // HELPER: Check if GPS matches a saved address exactly
  // ══════════════════════════════════════════════════

  /// Check if current GPS is within 200m of a specific address
  /// Used by checkout to determine if saved address is "current location"
  ///
  /// Why 200m and not exact match?
  /// GPS has 5-30m accuracy. Two readings from same building
  /// can differ by 10-50m. 200m gives comfortable margin.
  bool isAtAddress(Position gps, AddressModel address) {
    if (address.latitude == null || address.longitude == null) return false;

    final addrLat = double.tryParse(address.latitude!);
    final addrLng = double.tryParse(address.longitude!);
    if (addrLat == null || addrLng == null) return false;

    final distanceMeters = Geolocator.distanceBetween(
      gps.latitude,
      gps.longitude,
      addrLat,
      addrLng,
    );

    return distanceMeters <= _exactMatchRadiusMeters;
  }

  // ══════════════════════════════════════════════════
  // HELPER: Get distance between GPS and a specific address
  // ══════════════════════════════════════════════════

  /// Get distance in km between current GPS and a saved address
  /// Used by address list screen to show "2.3 km" badge
  double? getDistanceKm(Position gps, AddressModel address) {
    if (address.latitude == null || address.longitude == null) return null;

    final addrLat = double.tryParse(address.latitude!);
    final addrLng = double.tryParse(address.longitude!);
    if (addrLat == null || addrLng == null) return null;

    final distanceMeters = Geolocator.distanceBetween(
      gps.latitude,
      gps.longitude,
      addrLat,
      addrLng,
    );

    return distanceMeters / 1000;
  }

  // ══════════════════════════════════════════════════
  // RESET
  // ══════════════════════════════════════════════════

  /// Clear all state — forces fresh check next time
  /// Used when: user adds/changes address, or comes back from settings
  void reset() {
    _result = null;
    _isChecking = false;
    _hasChecked = false;
    notifyListeners();
  }

  /// Dismiss warning banner — user tapped "Continue Anyway"
  /// Changes decision from warn to autoSelect (keeps same address)
  void dismissWarning() {
    if (_result != null && _result!.decision == ProximityDecision.warn) {
      _result = ProximityResult(
        decision: ProximityDecision.autoSelect,
        distanceKm: _result!.distanceKm,
        nearestAddress: _result!.nearestAddress,
        partialAddress: _result!.partialAddress,
        isWithinExactMatch: _result!.isWithinExactMatch,
      );
      notifyListeners();
    }
  }
}
