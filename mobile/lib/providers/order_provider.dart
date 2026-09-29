import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../models/order_model.dart';
import '../models/active_order_model.dart';
import '../models/address_model.dart';

class OrderProvider with ChangeNotifier {
  final ApiService apiService;

  List<OrderModel> _orders = [];
  List<ActiveOrderModel> _activeOrders = [];  // Lightweight — sirf home screen ke liye
  List<AddressModel> _addresses = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMoreOrders = true;
  int _ordersTotal = 0;
  String? _error;

  /// Page size for My Orders (must match backend default expectations).
  static const int ordersPageSize = 15;

  List<OrderModel> get orders => _orders;
  List<ActiveOrderModel> get activeOrders => _activeOrders;
  List<AddressModel> get addresses => _addresses;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreOrders => _hasMoreOrders;
  int get ordersTotal => _ordersTotal;
  String? get error => _error;

  /// Drop every piece of user-scoped state this provider holds.
  ///
  /// Called on logout via core/session.dart. Without it, `_orders` survived a
  /// logout in memory, so the next person to sign in on the same device saw the
  /// previous user's order list — names, phone numbers and full delivery
  /// addresses — until the first refetch replaced it.
  void reset() {
    _orders = [];
    _activeOrders = [];
    _addresses = [];
    _isLoading = false;
    _isLoadingMore = false;
    _hasMoreOrders = true;
    _ordersTotal = 0;
    _error = null;
    notifyListeners();
  }

  /// Sync addresses from AddressProvider — no extra API call
  /// Used by home screen to keep OrderProvider in sync
  void syncAddresses(List<AddressModel> addresses) {
    _addresses = addresses;
    notifyListeners();
  }

  OrderProvider({required this.apiService});

  /// Parse a page of order rows, dropping any single row we cannot read.
  ///
  /// OrderModel.fromJson hard-casts `user` and `deliveryAddress` to non-null
  /// while parsing every other field defensively. One row missing either — a
  /// relation some endpoint does not join, or an address removed by a manual
  /// cleanup — threw inside .map() and took the ENTIRE page with it, so the
  /// customer saw an empty Orders tab instead of the orders that parsed fine.
  ///
  /// Losing one row visibly beats losing all of them silently.
  List<OrderModel> _parseOrders(List<dynamic> data) {
    final parsed = <OrderModel>[];
    for (final row in data) {
      try {
        parsed.add(OrderModel.fromJson(row as Map<String, dynamic>));
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Skipped an unreadable order row: $e');
          print('Row: $row');
        }
      }
    }
    return parsed;
  }

  /// Fetches orders. Use [paginated] for My Orders list (15 per page + infinite scroll).
  /// Without [paginated], behavior is unchanged: full list, replaces [_orders].
  Future<void> fetchOrders(
    String token, {
    String? Function()? getUpdatedToken,
    String? status,
    String? fields,
    bool paginated = false,
    bool append = false,
  }) async {
    if (paginated) {
      if (append) {
        if (_isLoadingMore || !_hasMoreOrders || _isLoading) return;
        _isLoadingMore = true;
      } else {
        _isLoading = true;
        _hasMoreOrders = true;
      }
    } else {
      _isLoading = true;
    }
    _error = null;
    notifyListeners();

    try {
      final params = <String>[];
      if (status != null) params.add('status=$status');
      if (fields != null) params.add('fields=$fields');
      if (paginated) {
        final offset = append ? _orders.length : 0;
        params.add('limit=$ordersPageSize');
        params.add('offset=$offset');
      }
      final query = params.isNotEmpty ? '?${params.join('&')}' : '';
      final endpoint = '/orders$query';

      if (kDebugMode) {
        print(
          '🔄 Fetching orders... (status: ${status ?? 'all'}, paginated: $paginated, append: $append)',
        );
      }

      final response = await apiService.get(
        endpoint,
        token: token,
        getUpdatedToken: getUpdatedToken,
      );

      if (paginated && response is Map<String, dynamic>) {
        final rawList = response['orders'];
        final total = (response['total'] as num?)?.toInt() ?? 0;
        final List<dynamic> data = rawList is List ? rawList : [];
        final page = _parseOrders(data);

        if (append) {
          _orders = [..._orders, ...page];
        } else {
          _orders = page;
        }
        _ordersTotal = total;
        _hasMoreOrders = _orders.length < total;
        if (kDebugMode) {
          print('✅ Orders page: ${page.length} items, total=$total, hasMore=$_hasMoreOrders');
        }
      } else {
        final List<dynamic> data = response is List ? response : [];
        _orders = _parseOrders(data);
        if (!paginated) {
          _hasMoreOrders = false;
          _ordersTotal = _orders.length;
        }
        if (kDebugMode) {
          print('✅ Fetched ${_orders.length} orders successfully');
        }
      }
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      _error = errorMessage;
      if (kDebugMode) {
        print('❌ Error fetching orders: $errorMessage');
        print('Full error: $e');
      }
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Lightweight fetch — sirf active orders ke liye (home screen)
  /// Kyun: Full OrderModel mein 6 JOINs hote hain — heavy
  /// ActiveOrderModel mein 0 JOINs, sirf 4 fields — ~90% faster
  Future<void> fetchActiveOrders(String token, {String? Function()? getUpdatedToken}) async {
    try {
      if (kDebugMode) {
        print('🔄 Fetching active orders (light)...');
      }

      final response = await apiService.get(
        '/orders?status=active&fields=light',
        token: token,
        getUpdatedToken: getUpdatedToken,
      );

      final List<dynamic> data = response is List ? response : [];
      _activeOrders = data.map((json) {
        try {
          return ActiveOrderModel.fromJson(json as Map<String, dynamic>);
        } catch (e) {
          if (kDebugMode) {
            print('❌ Error parsing active order: $e');
            print('Order data: $json');
          }
          rethrow;
        }
      }).toList();

      if (kDebugMode) {
        print('✅ Fetched ${_activeOrders.length} active orders');
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error fetching active orders: $e');
      }
    }
  }

  /// Active orders list ko full order data se sync karo
  /// Kyun: Tracking screen pe polling se naya status aata hai (full OrderModel)
  /// Wo status _activeOrders mein bhi reflect hona chahiye (home screen ke liye)
  ///
  /// 3 cases:
  /// 1. Order active hai aur _activeOrders mein hai → status update karo
  /// 2. Order active hai but _activeOrders mein nahi → add karo
  /// 3. Order delivered/cancelled ho gaya → _activeOrders se hatao
  void _syncActiveOrder(OrderModel order) {
    final isTerminal = order.status == 'delivered' || order.status == 'cancelled';
    final activeIndex = _activeOrders.indexWhere((a) => a.id == order.id);

    if (isTerminal) {
      // Order khatam — active list se hatao
      if (activeIndex >= 0) {
        _activeOrders.removeAt(activeIndex);
      }
    } else {
      // Order abhi active hai
      final updatedActive = ActiveOrderModel(
        id: order.id,
        status: order.status,
        totalAmount: order.totalAmount,
        createdAt: order.createdAt,
      );

      if (activeIndex >= 0) {
        // Already hai — update karo
        _activeOrders[activeIndex] = updatedActive;
      } else {
        // Nahi hai — add karo
        _activeOrders.insert(0, updatedActive);
      }
    }
  }

  Future<OrderModel?> fetchOrderById(int id, String token) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiService.get('/orders/$id', token: token);
      final order = OrderModel.fromJson(response as Map<String, dynamic>);
      
      // Add or update the order in the list to prevent glitches during navigation
      final existingIndex = _orders.indexWhere((o) => o.id == id);
      if (existingIndex >= 0) {
        _orders[existingIndex] = order;
      } else {
        _orders.insert(0, order);
      }

      // Sync active orders list — taki home screen pe bhi latest status dikhe
      // Kyun: _activeOrders alag list hai (lightweight). Jab full order ka status
      // change ho toh activeOrders mein bhi reflect hona chahiye.
      _syncActiveOrder(order);

      _isLoading = false;
      notifyListeners();
      
      return order;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Raise a cancellation/refund request (only valid before packing). On success
  /// the order moves to cancelRequestStatus='requested' awaiting admin approval.
  Future<bool> requestCancellation(int orderId, String token, {String? reason}) async {
    try {
      await apiService.post(
        '/orders/$orderId/request-cancellation',
        {if (reason != null && reason.isNotEmpty) 'reason': reason},
        token: token,
      );
      await fetchOrderById(orderId, token);
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Cancel an order directly (after packing — NO refund). For pending/accepted
  /// orders the backend rejects this and directs to requestCancellation.
  Future<bool> cancelOrder(int orderId, String token) async {
    try {
      await apiService.put('/orders/$orderId/cancel', {}, token: token);
      await fetchOrderById(orderId, token);
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<OrderModel?> createOrder({
    required String token,
    required List<Map<String, dynamic>> items,
    required int addressId,
    required String paymentMethod,
    String? notes,
    String? idempotencyKey,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiService.post(
        '/orders',
        {
          'items': items,
          'addressId': addressId,
          'paymentMethod': paymentMethod,
          if (notes != null) 'notes': notes,
        },
        token: token,
        // Idempotency-Key makes a retry (timeout, double-tap) reuse the same order
        // instead of creating a duplicate + double-decrementing stock. Stable per
        // checkout attempt — the caller passes one key and reuses it on retry.
        extraHeaders:
            idempotencyKey != null ? {'Idempotency-Key': idempotencyKey} : null,
      );
      // Backend returns { order: {...}, paymentOrder: {...} }
      // Extract the order from the response
      final responseMap = response as Map<String, dynamic>;
      OrderModel? createdOrder;
      if (responseMap.containsKey('order')) {
        createdOrder = OrderModel.fromJson(responseMap['order'] as Map<String, dynamic>);
      } else {
        // Fallback: if response is directly the order object
        createdOrder = OrderModel.fromJson(responseMap);
      }
      
      // Add the order to the list immediately (optimistic update)
      if (createdOrder != null) {
        _orders.insert(0, createdOrder); // Add at the beginning (newest first)
        if (kDebugMode) {
          print('✅ Added order ${createdOrder.id} to list. Total orders: ${_orders.length}');
        }
      }
      
      _isLoading = false;
      notifyListeners();
      
      return createdOrder;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }


  Future<void> fetchAddresses(String token) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiService.get('/addresses', token: token);
      // Backend returns array directly: res.json(addresses)
      final List<dynamic> data = response is List ? response : [];
      _addresses = data.map((json) => AddressModel.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

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
      // Check for duplicate addresses on frontend first (quick check)
      if (latitude != null && longitude != null) {
        final existingAddresses = _addresses.where((addr) {
          if (addr.latitude != null && addr.longitude != null) {
            // Calculate distance (simple approximation)
            final lat1 = double.tryParse(latitude);
            final lng1 = double.tryParse(longitude);
            final lat2 = double.tryParse(addr.latitude!);
            final lng2 = double.tryParse(addr.longitude!);
            
            if (lat1 != null && lng1 != null && lat2 != null && lng2 != null) {
              // Simple distance check (within ~50 meters)
              final latDiff = (lat1 - lat2).abs();
              final lngDiff = (lng1 - lng2).abs();
              // Approximate: 0.0005 degrees ≈ 50 meters
              if (latDiff < 0.0005 && lngDiff < 0.0005) {
                return true; // Very close, likely duplicate
              }
            }
          }
          // Also check by pincode and address similarity
          if (addr.pincode == pincode) {
            final addr1Lower = addressLine1.toLowerCase().trim();
            final addr2Lower = addr.addressLine1.toLowerCase().trim();
            // Simple similarity check
            if (addr1Lower == addr2Lower || 
                addr1Lower.contains(addr2Lower) || 
                addr2Lower.contains(addr1Lower)) {
              return true; // Similar address
            }
          }
          return false;
        }).toList();
        
        if (existingAddresses.isNotEmpty) {
          // Duplicate found - update existing instead
          final existing = existingAddresses.first;
          final success = await updateAddress(
            token: token,
            addressId: existing.id,
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
      
      // No duplicate found, create new address
      final response = await apiService.post(
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
      await fetchAddresses(token);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // Provide more specific error message
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      _error = errorMessage;
      if (kDebugMode) {
        print('❌ Error creating address: $errorMessage');
      }
      _isLoading = false;
      notifyListeners();
      // Re-throw to allow caller to handle token expiration
      if (errorMessage.contains('Invalid token') || 
          errorMessage.contains('Authentication required') ||
          errorMessage.contains('TokenExpiredException')) {
        rethrow;
      }
      return false;
    }
  }

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

      await apiService.put(
        '/addresses/$addressId',
        data,
        token: token,
      );
      await fetchAddresses(token);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      _error = errorMessage;
      if (kDebugMode) {
        print('❌ Error updating address: $errorMessage');
      }
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}

