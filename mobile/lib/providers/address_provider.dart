import 'package:flutter/foundation.dart';
import '../models/address_model.dart';
import '../services/api_service.dart';

/// AddressProvider — Manages all saved addresses
///
/// Think of it as a "Contacts app" for addresses.
/// It stores, creates, updates, deletes addresses
/// and tracks which one is currently selected.
///
/// Why separate from OrderProvider?
/// OrderProvider was handling orders AND addresses — too many responsibilities.
/// Separating makes code cleaner and easier to maintain.
/// Each provider should have ONE job (Single Responsibility Principle).
///
/// Responsibilities:
/// 1. Fetch all saved addresses from backend
/// 2. Create new address (with duplicate detection)
/// 3. Update existing address
/// 4. Delete address
/// 5. Set default address
/// 6. Track currently selected address
///
/// Used by:
/// - Home screen (show selected address in header)
/// - Address list screen (show all addresses)
/// - Add/Edit address screens (CRUD operations)
/// - Checkout/Payment (verify address is complete)
/// - ProximityProvider (compare GPS with saved addresses)
class AddressProvider extends ChangeNotifier {

  // ══════════════════════════════════════════════════
  // DEPENDENCIES
  // ══════════════════════════════════════════════════

  /// API service — handles all HTTP calls to backend.
  ///
  /// Injected. This used to be a bare `ApiService()` created here, and because
  /// AddressProvider was registered as a plain ChangeNotifierProvider rather
  /// than a proxy, it never received the onTokenExpired / getCurrentToken
  /// wiring the other providers get. Every address call therefore threw
  /// TokenExpiredException with no refresh attempt once the 15-minute access
  /// token lapsed — and addresses are needed on the home screen and required at
  /// checkout, so ordering broke until some other provider happened to refresh
  /// first. That made it look intermittent.
  final ApiService _apiService;

  AddressProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  // ══════════════════════════════════════════════════
  // STATE
  // ══════════════════════════════════════════════════

  /// All saved addresses for this user
  /// Fetched from: GET /api/addresses
  List<AddressModel> _addresses = [];

  /// Currently selected address for delivery
  /// This is what shows in home screen header
  /// Can be different from default — user might select temporarily
  AddressModel? _selectedAddress;

  /// True ONLY when the user explicitly picked an address (tapped a card,
  /// completed the address sheet, etc). False when the smart-flow auto-selected
  /// it based on GPS proximity, default address, etc.
  ///
  /// Why we need this:
  ///   The home-screen smart flow (`_initSmartAddressFlow`) re-runs on every
  ///   home init and can decide "user is far from any saved address" → wipe the
  ///   selection. That's the right call on first load (user might have travelled),
  ///   but WRONG after the user has just manually picked. This flag lets the
  ///   smart flow back off when the user has already taken a stand.
  ///
  /// Cleared by:
  ///   - `clearSelection()` — explicit unset
  ///   - `reset()` — logout / nuke all state
  ///   - `deleteAddress()` if the deleted one was the selected
  bool _manuallySelected = false;

  /// Loading state — show shimmer while fetching
  bool _isLoading = false;

  /// Error message from last operation
  String? _error;

  // ══════════════════════════════════════════════════
  // GETTERS — Read-only access for UI
  // ══════════════════════════════════════════════════

  /// All saved addresses
  List<AddressModel> get addresses => _addresses;

  /// Currently selected address
  AddressModel? get selectedAddress => _selectedAddress;

  /// True only when the user has explicitly picked the current selection.
  /// The home-screen smart flow uses this to back off and not overwrite a manual choice.
  bool get manuallySelected => _manuallySelected;

  /// Is any operation in progress?
  bool get isLoading => _isLoading;

  /// Error message (if any)
  String? get error => _error;

  /// Does user have any saved addresses?
  bool get hasAddresses => _addresses.isNotEmpty;

  /// Get the default address (marked as default in backend)
  /// Returns null if no default set
  AddressModel? get defaultAddress {
    try {
      return _addresses.firstWhere((addr) => addr.isDefault);
    } catch (_) {
      // No default found — return first address if available
      return _addresses.isNotEmpty ? _addresses.first : null;
    }
  }

  // ══════════════════════════════════════════════════
  // METHOD 1: Fetch all addresses from backend
  // ══════════════════════════════════════════════════

  /// Fetch all saved addresses for logged-in user
  ///
  /// API: GET /api/addresses
  /// Backend returns: Array of address objects
  ///
  /// Called when:
  /// - App opens (home screen initState)
  /// - After creating/updating/deleting an address
  /// - After login
  Future<void> fetchAddresses(String token) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.get('/addresses', token: token);

      // Backend returns array directly: res.json(addresses)
      final List<dynamic> data = response is List ? response : [];

      // Convert each JSON object to AddressModel
      _addresses = data
          .map((json) => AddressModel.fromJson(json as Map<String, dynamic>))
          .toList();

      // If no address is selected yet, auto-select default
      if (_selectedAddress == null && _addresses.isNotEmpty) {
        _selectedAddress = defaultAddress;
      }

      // If selected address was deleted, reset to default
      if (_selectedAddress != null &&
          !_addresses.any((addr) => addr.id == _selectedAddress!.id)) {
        _selectedAddress = defaultAddress;
      }

      debugPrint('📍 [Address] Fetched ${_addresses.length} addresses');
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      debugPrint('❌ [Address] Fetch failed: $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════
  // METHOD 2: Select an address (for delivery)
  // ══════════════════════════════════════════════════

  /// User-driven selection — call this from address-list tap, address-completion-sheet
  /// save, etc. Sets `_manuallySelected = true` so the home-screen smart flow won't
  /// overwrite this on its next pass.
  ///
  /// Note: This does NOT change the default address in backend.
  /// It's a temporary selection for this session.
  /// To change default, use setDefault() method.
  void selectAddress(AddressModel address) {
    _selectedAddress = address;
    _manuallySelected = true;
    debugPrint('📍 [Address] Selected (manual): ${address.tag} - ${address.addressLine1}');
    notifyListeners(); // Home screen header updates instantly
  }

  /// Smart-flow selection — call this from `_initSmartAddressFlow` and similar
  /// auto-pick code paths. Does NOT touch `_manuallySelected`, so a previous
  /// manual pick keeps its sticky status.
  void autoSelectAddress(AddressModel address) {
    _selectedAddress = address;
    debugPrint('📍 [Address] Selected (auto): ${address.tag} - ${address.addressLine1}');
    notifyListeners();
  }

  /// Clear session selection so UI can show GPS partial only (e.g. >20km from saved).
  /// Also clears the manual-pick flag — caller is asserting "go back to auto".
  void clearSelection() {
    _selectedAddress = null;
    _manuallySelected = false;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════
  // METHOD 3: Create new address
  // ══════════════════════════════════════════════════

  /// Create a new address with duplicate detection
  ///
  /// API: POST /api/addresses
  ///
  /// Duplicate detection (before creating):
  /// 1. Check GPS distance — if within 50 meters of existing, it's duplicate
  /// 2. Check pincode + address text similarity
  /// If duplicate found → update existing instead of creating new
  ///
  /// Why duplicate detection?
  /// User might add same address twice (from GPS).
  /// Without detection, they'd have 5 copies of "Home".
  Future<bool> createAddress({
    required String token,
    required String addressLine1,
    String? addressLine2,
    required String city,
    required String state,
    required String pincode,
    String? landmark,
    bool isDefault = false,
    String? latitude,
    String? longitude,
    String? tag,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // ── Duplicate detection ──
      if (latitude != null && longitude != null) {
        final duplicate = _findDuplicate(
          latitude: latitude,
          longitude: longitude,
          pincode: pincode,
          addressLine1: addressLine1,
        );

        if (duplicate != null) {
          // Duplicate found — update existing instead of creating new
          debugPrint('📍 [Address] Duplicate found (id=${duplicate.id}), updating instead');
          final success = await updateAddress(
            token: token,
            addressId: duplicate.id,
            addressLine1: addressLine1,
            addressLine2: addressLine2,
            city: city,
            state: state,
            pincode: pincode,
            landmark: landmark,
            isDefault: isDefault,
            latitude: latitude,
            longitude: longitude,
            tag: tag,
          );
          _isLoading = false;
          notifyListeners();
          return success;
        }
      }

      // ── No duplicate — create new address ──
      await _apiService.post(
        '/addresses',
        {
          'addressLine1': addressLine1,
          if (addressLine2 != null) 'addressLine2': addressLine2,
          'city': city,
          'state': state,
          'pincode': pincode,
          if (landmark != null) 'landmark': landmark,
          'isDefault': isDefault,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (tag != null) 'tag': tag,
        },
        token: token,
      );

      // Refresh address list from backend
      await fetchAddresses(token);

      debugPrint('✅ [Address] Created successfully');
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      _error = errorMessage;
      debugPrint('❌ [Address] Create failed: $errorMessage');
      _isLoading = false;
      notifyListeners();

      // Re-throw auth errors so caller can handle token refresh
      if (errorMessage.contains('Invalid token') ||
          errorMessage.contains('Authentication required') ||
          errorMessage.contains('TokenExpiredException')) {
        rethrow;
      }
      return false;
    }
  }

  // ══════════════════════════════════════════════════
  // METHOD 4: Update existing address
  // ══════════════════════════════════════════════════

  /// Update an existing address
  ///
  /// API: PUT /api/addresses/:id
  /// Only sends fields that changed (partial update)
  Future<bool> updateAddress({
    required String token,
    required int addressId,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? pincode,
    String? landmark,
    bool? isDefault,
    String? latitude,
    String? longitude,
    String? tag,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Build update data — only include non-null fields
      final data = <String, dynamic>{};
      if (addressLine1 != null) data['addressLine1'] = addressLine1;
      if (addressLine2 != null) data['addressLine2'] = addressLine2;
      if (city != null) data['city'] = city;
      if (state != null) data['state'] = state;
      if (pincode != null) data['pincode'] = pincode;
      if (landmark != null) data['landmark'] = landmark;
      if (isDefault != null) data['isDefault'] = isDefault;
      if (latitude != null) data['latitude'] = latitude;
      if (longitude != null) data['longitude'] = longitude;
      if (tag != null) data['tag'] = tag;

      await _apiService.put(
        '/addresses/$addressId',
        data,
        token: token,
      );

      // Refresh address list from backend
      await fetchAddresses(token);

      debugPrint('✅ [Address] Updated id=$addressId');
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      debugPrint('❌ [Address] Update failed: $_error');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ══════════════════════════════════════════════════
  // METHOD 5: Delete address
  // ══════════════════════════════════════════════════

  /// Delete an address
  ///
  /// API: DELETE /api/addresses/:id
  ///
  /// After deletion:
  /// - If deleted address was selected → select default
  /// - Refresh list from backend
  Future<bool> deleteAddress({
    required String token,
    required int addressId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.delete(
        '/addresses/$addressId',
        token: token,
      );

      // If deleted address was the selected one, reset selection.
      // Also clear the manual-pick flag — the user no longer has a sticky choice.
      if (_selectedAddress?.id == addressId) {
        _selectedAddress = null;
        _manuallySelected = false;
      }

      // Refresh from backend
      await fetchAddresses(token);

      debugPrint('✅ [Address] Deleted id=$addressId');
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      debugPrint('❌ [Address] Delete failed: $_error');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ══════════════════════════════════════════════════
  // METHOD 6: Set default address
  // ══════════════════════════════════════════════════

  /// Mark an address as the default delivery address
  ///
  /// Backend will automatically unset all other defaults
  /// So only ONE address is default at a time
  Future<bool> setDefault({
    required String token,
    required int addressId,
  }) async {
    return await updateAddress(
      token: token,
      addressId: addressId,
      isDefault: true,
    );
  }

  // ══════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ══════════════════════════════════════════════════

  /// Find duplicate address by GPS proximity or text similarity
  ///
  /// Check 1: GPS distance — within 50 meters = duplicate
  ///   Why 50m? Two GPS readings of same building can differ by 10-30m
  ///
  /// Check 2: Same pincode + similar address text = duplicate
  ///   Why text check? Sometimes GPS is slightly off but address is same
  AddressModel? _findDuplicate({
    required String latitude,
    required String longitude,
    required String pincode,
    required String addressLine1,
  }) {
    for (final addr in _addresses) {
      // Check 1: GPS proximity (within ~50 meters)
      if (addr.latitude != null && addr.longitude != null) {
        final lat1 = double.tryParse(latitude);
        final lng1 = double.tryParse(longitude);
        final lat2 = double.tryParse(addr.latitude!);
        final lng2 = double.tryParse(addr.longitude!);

        if (lat1 != null && lng1 != null && lat2 != null && lng2 != null) {
          final latDiff = (lat1 - lat2).abs();
          final lngDiff = (lng1 - lng2).abs();
          // 0.0005 degrees ≈ 50 meters
          if (latDiff < 0.0005 && lngDiff < 0.0005) {
            return addr; // Very close — likely same place
          }
        }
      }

      // Check 2: Same pincode + similar text
      if (addr.pincode == pincode) {
        final newText = addressLine1.toLowerCase().trim();
        final existingText = addr.addressLine1.toLowerCase().trim();
        if (newText == existingText ||
            newText.contains(existingText) ||
            existingText.contains(newText)) {
          return addr; // Similar address text
        }
      }
    }

    return null; // No duplicate found
  }

  // ══════════════════════════════════════════════════
  // RESET
  // ══════════════════════════════════════════════════

  /// Clear all state — used on logout
  void reset() {
    _addresses = [];
    _selectedAddress = null;
    _manuallySelected = false;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
