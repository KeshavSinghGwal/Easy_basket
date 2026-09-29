import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class ServiceAreaProvider with ChangeNotifier {
  /// Injected so this provider shares the one wired ApiService instead of
  /// creating an unwired one of its own — see AddressProvider for why that
  /// mattered.
  final ApiService apiService;

  ServiceAreaProvider({ApiService? apiService})
      : apiService = apiService ?? ApiService();

  bool _isChecking = false;
  bool? _isServiceAvailable;
  String? _error;
  Map<String, dynamic>? _serviceAreaInfo;

  bool get isChecking => _isChecking;
  bool? get isServiceAvailable => _isServiceAvailable;
  String? get error => _error;
  Map<String, dynamic>? get serviceAreaInfo => _serviceAreaInfo;

  /// Check if service is available for a location.
  ///
  /// Prefers GPS coordinates (latitude/longitude) — the backend decides via a
  /// distance-from-store radius check. Falls back to `pincode` when coordinates
  /// aren't provided (e.g. GPS denied). Callers that already have address/GPS
  /// coordinates should pass them for an accurate, radius-based result.
  Future<bool> checkServiceAvailability({
    String? pincode,
    double? latitude,
    double? longitude,
    String country = 'India',
  }) async {
    // CRITICAL: Always reset state before checking to prevent stale results
    _isChecking = true;
    _error = null;
    _isServiceAvailable = null;
    _serviceAreaInfo = null;
    notifyListeners();

    try {
      final hasCoords = latitude != null && longitude != null;
      final cleanPincode = (pincode ?? '').trim().replaceAll(' ', '');
      final pincodeQuery =
          '&pincode=$cleanPincode&country=${Uri.encodeComponent(country)}';
      final String queryString;
      if (hasCoords) {
        // Send the pincode ALONGSIDE the coordinates. The backend prefers the
        // radius check and only reads the pincode if the store radius isn't
        // configured — so this keeps pincode as a pure fallback. Omitting it
        // meant that fallback had nothing to fall back to: the server would
        // reach its pincode branch with no pincode and return 400, which this
        // provider's catch turns into "not serviceable".
        queryString = '?lat=$latitude&lng=$longitude'
            '${cleanPincode.isEmpty ? '' : pincodeQuery}';
        if (kDebugMode) {
          print('🌐 [API CALL] Checking service for coords: $latitude,$longitude'
              '${cleanPincode.isEmpty ? '' : ' (pincode fallback: $cleanPincode)'}');
        }
      } else {
        queryString = '?pincode=$cleanPincode&country=${Uri.encodeComponent(country)}';
        if (kDebugMode) {
          print('🌐 [API CALL] Checking service for pincode: $cleanPincode, country: $country');
        }
      }

      final response = await apiService.get(
        '/service-area/check$queryString',
      );

      _isServiceAvailable = response['available'] as bool? ?? false;
      if (_isServiceAvailable == true && response['serviceArea'] != null) {
        _serviceAreaInfo = response['serviceArea'] as Map<String, dynamic>;
      }

      _isChecking = false;
      notifyListeners();
      
      if (kDebugMode) {
        final where = (latitude != null && longitude != null)
            ? '$latitude,$longitude'
            : (pincode ?? '');
        print('🌐 [API RESULT] $where: ${(_isServiceAvailable == true) ? "AVAILABLE" : "NOT AVAILABLE"}');
      }
      
      return _isServiceAvailable ?? false;
    } catch (e) {
      // FAIL OPEN. This used to set _isServiceAvailable = false, which made a
      // timeout, DNS blip or brief 5xx indistinguishable from a real "we don't
      // deliver here" — and a serviceable customer on a flaky connection was
      // turned away at the top of the funnel with no reason to try again.
      //
      // null means "we genuinely do not know", not "no". The server is the real
      // gate: POST /api/orders re-checks and returns OUT_OF_SERVICE_AREA if the
      // address really is out of range. Same reasoning StoreStatusProvider
      // already documents for the store-open check.
      _error = e.toString().replaceAll('Exception: ', '');
      _isServiceAvailable = null;
      _isChecking = false;
      notifyListeners();
      if (kDebugMode) {
        print('⚠️ [API ERROR] Service availability unknown for pincode $pincode (proceeding optimistically): ${_error ?? "Unknown error"}');
      }
      return true;
    }
  }

  /// Reset state
  void reset() {
    _isChecking = false;
    _isServiceAvailable = null;
    _error = null;
    _serviceAreaInfo = null;
    notifyListeners();
  }
}

