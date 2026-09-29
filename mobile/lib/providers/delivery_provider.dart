import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../models/order_model.dart';

class DeliveryProvider with ChangeNotifier {
  final ApiService apiService;

  List<OrderModel> _orders = [];
  List<OrderModel> _availableOrders = [];
  Map<String, dynamic>? _stats;
  bool _isLoading = false;
  String? _error;

  List<OrderModel> get orders => _orders;
  List<OrderModel> get availableOrders => _availableOrders;
  Map<String, dynamic>? get stats => _stats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  DeliveryProvider({required this.apiService});

  Future<void> fetchOrders({String? status, String? token}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      String endpoint = '/delivery/orders';
      if (status != null && status.isNotEmpty) {
        endpoint += '?status=$status';
      }

      final response = await apiService.get(endpoint, token: token);
      final List<dynamic> data = response is List ? response : [];
      _orders = data.map((json) => OrderModel.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchStats({String? token}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiService.get('/delivery/stats', token: token);
      _stats = response as Map<String, dynamic>;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateOrderStatus({
    required String token,
    required int orderId,
    required String status,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await apiService.put(
        '/delivery/orders/$orderId/status',
        {'status': status},
        token: token,
      );

      // Refresh orders after status update
      await fetchOrders(token: token);
      await fetchStats(token: token);
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<OrderModel?> getOrderDetails(int orderId, {String? token}) async {
    try {
      final response = await apiService.get('/delivery/orders/$orderId', token: token);
      return OrderModel.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      return null;
    }
  }

  Future<void> fetchAvailableOrders({String? status, String? token}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      String endpoint = '/delivery/orders/available';
      if (status != null && status.isNotEmpty) {
        endpoint += '?status=$status';
      }

      final response = await apiService.get(endpoint, token: token);
      final List<dynamic> data = response is List ? response : [];
      _availableOrders = data.map((json) => OrderModel.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> acceptOrder({
    required String token,
    required int orderId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await apiService.post(
        '/delivery/orders/$orderId/accept',
        {},
        token: token,
      );

      // Refresh available orders and assigned orders
      await fetchAvailableOrders(token: token);
      await fetchOrders(token: token);
      await fetchStats(token: token);
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Phase 1 state-machine endpoints
  //
  // These call the new backend routes (/api/delivery/orders/:id/<verb>) and
  // return the parsed JSON map for callers that need extra fields (e.g.
  // collect-cash returns the rider wallet, start-delivery returns otpDev in
  // non-production).
  //
  // None of them auto-refresh the orders list — callers refresh on the screen
  // they're navigating to (saves a wasted API call when going to detail/COD).
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> _postTransition({
    required String token,
    required int orderId,
    required String verb,
    Map<String, dynamic> body = const {},
  }) async {
    final response = await apiService.post(
      '/delivery/orders/$orderId/$verb',
      body,
      token: token,
    );
    return response is Map<String, dynamic> ? response : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> arrivedAtStore({required String token, required int orderId}) =>
      _postTransition(token: token, orderId: orderId, verb: 'arrived-at-store');

  Future<Map<String, dynamic>> pickedOrder({required String token, required int orderId}) =>
      _postTransition(token: token, orderId: orderId, verb: 'picked');

  /// Returns `{ deliveryStatus, otpDev? }`. `otpDev` is only present in non-production.
  Future<Map<String, dynamic>> startDelivery({required String token, required int orderId}) =>
      _postTransition(token: token, orderId: orderId, verb: 'start-delivery');

  Future<Map<String, dynamic>> arrivedAtCustomer({
    required String token,
    required int orderId,
    double? lat,
    double? lng,
  }) {
    final body = <String, dynamic>{};
    if (lat != null && lng != null) {
      body['lat'] = lat;
      body['lng'] = lng;
    }
    return _postTransition(token: token, orderId: orderId, verb: 'arrived', body: body);
  }

  /// Collect cash + verify OTP. Returns `{ deliveryStatus, cashCollectedPaise, wallet }`.
  Future<Map<String, dynamic>> collectCash({
    required String token,
    required int orderId,
    required int amountPaise,
    required String otp,
    double? lat,
    double? lng,
  }) {
    final body = <String, dynamic>{
      'amountPaise': amountPaise,
      'otp': otp,
    };
    if (lat != null && lng != null) {
      body['lat'] = lat;
      body['lng'] = lng;
    }
    return _postTransition(token: token, orderId: orderId, verb: 'collect-cash', body: body);
  }

  /// Mark a PREPAID order delivered after verifying the customer's OTP.
  /// Returns `{ deliveryStatus }`. No wallet credit (no cash exchanged).
  Future<Map<String, dynamic>> markPrepaidDelivered({
    required String token,
    required int orderId,
    required String otp,
    double? lat,
    double? lng,
  }) {
    final body = <String, dynamic>{'otp': otp};
    if (lat != null && lng != null) {
      body['lat'] = lat;
      body['lng'] = lng;
    }
    return _postTransition(
        token: token, orderId: orderId, verb: 'mark-prepaid-delivered', body: body);
  }

  /// Generate a fresh Razorpay order at the door so the customer can pay UPI/QR
  /// instead of cash. Returns `{ razorpayOrderId, amountPaise, key }`.
  Future<Map<String, dynamic>> switchToUpi({required String token, required int orderId}) =>
      _postTransition(token: token, orderId: orderId, verb: 'switch-to-upi');

  /// Reasons: customer_refused | not_reachable | wrong_address | damaged | other
  Future<Map<String, dynamic>> reportIssue({
    required String token,
    required int orderId,
    required String reason,
    String? note,
  }) {
    final body = <String, dynamic>{'reason': reason};
    if (note != null && note.isNotEmpty) body['note'] = note;
    return _postTransition(token: token, orderId: orderId, verb: 'report-issue', body: body);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Wallet + availability
  // ═══════════════════════════════════════════════════════════════════════

  Map<String, dynamic>? _wallet;
  Map<String, dynamic>? get wallet => _wallet;

  /// Fetch the rider's cash-in-hand + lifetime totals.
  /// Returns the wallet map and caches it on the provider for UI display.
  Future<Map<String, dynamic>?> fetchWallet({required String token}) async {
    try {
      final response = await apiService.get('/delivery/wallet', token: token);
      _wallet = response is Map<String, dynamic> ? response : null;
      notifyListeners();
      return _wallet;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      return null;
    }
  }

  /// Set the rider's availability. Backend values: offline | idle | busy.
  Future<bool> setAvailability({required String token, required String availability}) async {
    try {
      await apiService.post('/delivery/availability', {'availability': availability}, token: token);
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      return false;
    }
  }

  /// Lightweight ping for admin-side rider tracking. Best-effort, swallows errors
  /// since failures here shouldn't block the UI.
  Future<void> pingLocation({
    required String token,
    required double lat,
    required double lng,
  }) async {
    try {
      await apiService.post('/delivery/location', {'lat': lat, 'lng': lng}, token: token);
    } catch (_) {
      // ignore — location ping is fire-and-forget
    }
  }
}

