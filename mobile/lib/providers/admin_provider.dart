  import 'package:flutter/foundation.dart' show ChangeNotifier, kDebugMode;
  import '../services/api_service.dart';
  import '../models/order_model.dart';
  import '../models/user_model.dart';
  import '../models/product_model.dart';
  import '../models/category_model.dart';
  import '../models/product_variant_model.dart';
  import '../models/refund_info.dart';

  class AdminProvider with ChangeNotifier {
    final ApiService apiService;

    Map<String, dynamic>? _stats;
    List<OrderModel> _orders = [];
    List<UserModel> _users = [];
    List<UserModel> _deliveryAgents = [];
    List<ProductModel> _products = [];
    List<CategoryModel> _categories = [];
    bool _isLoading = false;
    bool _isLoadingMore = false;
    String? _error;
    int _currentPage = 1;
    bool _hasMore = true;

    Map<String, dynamic>? get stats => _stats;
    List<OrderModel> get orders => _orders;
    List<UserModel> get users => _users;
    List<UserModel> get deliveryAgents => _deliveryAgents;
    List<ProductModel> get products => _products;
    List<CategoryModel> get categories => _categories;
    bool get isLoading => _isLoading;
    bool get isLoadingMore => _isLoadingMore;
    String? get error => _error;
    bool get hasMore => _hasMore;

    AdminProvider({required this.apiService});

    Future<void> fetchStats({String? token}) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        final response = await apiService.get('/admin/dashboard', token: token);
        _stats = response as Map<String, dynamic>;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        print('Error fetching admin stats: $_error');
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    Future<void> fetchOrders({String? status, String? token, bool loadMore = false}) async {
      if (loadMore) {
        if (!_hasMore || _isLoadingMore) return;
        _isLoadingMore = true;
        _currentPage++;
      } else {
        _isLoading = true;
        _currentPage = 1;
        _orders = [];
        _hasMore = true;
      }
      _error = null;
      notifyListeners();

      try {
        String endpoint = '/admin/orders?page=$_currentPage&limit=20';
        if (status != null && status.isNotEmpty) {
          endpoint += '&status=$status';
        }

        final response = await apiService.get(endpoint, token: token);
        if (response is Map<String, dynamic> && response.containsKey('orders')) {
          final List<dynamic> data = response['orders'] as List? ?? [];
          final pagination = response['pagination'] as Map<String, dynamic>?;
          _hasMore = pagination?['hasMore'] as bool? ?? false;
          
          final newOrders = data.map((json) => OrderModel.fromJson(json as Map<String, dynamic>)).toList();
          if (loadMore) {
            _orders.addAll(newOrders);
          } else {
            _orders = newOrders;
          }
        } else {
          // Fallback for old API format
          final List<dynamic> data = response is List ? response : [];
          final newOrders = data.map((json) => OrderModel.fromJson(json as Map<String, dynamic>)).toList();
          if (loadMore) {
            _orders.addAll(newOrders);
          } else {
            _orders = newOrders;
          }
          _hasMore = false;
        }
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        print('Error fetching admin orders: $_error');
        if (loadMore) _currentPage--;
      } finally {
        _isLoading = false;
        _isLoadingMore = false;
        notifyListeners();
      }
    }

    Future<void> fetchUsers({String? role, String? token, bool loadMore = false}) async {
      if (loadMore) {
        if (!_hasMore || _isLoadingMore) return;
        _isLoadingMore = true;
        _currentPage++;
      } else {
        _isLoading = true;
        _currentPage = 1;
        _users = [];
        _hasMore = true;
      }
      _error = null;
      notifyListeners();

      try {
        String endpoint = '/admin/users?page=$_currentPage&limit=20';
        if (role != null && role.isNotEmpty) {
          endpoint += '&role=$role';
        }

        final response = await apiService.get(endpoint, token: token);
        if (response is Map<String, dynamic> && response.containsKey('users')) {
          final List<dynamic> data = response['users'] as List? ?? [];
          final pagination = response['pagination'] as Map<String, dynamic>?;
          _hasMore = pagination?['hasMore'] as bool? ?? false;
          
          final newUsers = data.map((json) => UserModel.fromJson(json as Map<String, dynamic>)).toList();
          if (loadMore) {
            _users.addAll(newUsers);
          } else {
            _users = newUsers;
          }
        } else {
          // Fallback for old API format
          final List<dynamic> data = response is List ? response : [];
          final newUsers = data.map((json) => UserModel.fromJson(json as Map<String, dynamic>)).toList();
          if (loadMore) {
            _users.addAll(newUsers);
          } else {
            _users = newUsers;
          }
          _hasMore = false;
        }
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        print('Error fetching admin users: $_error');
        if (loadMore) _currentPage--;
      } finally {
        _isLoading = false;
        _isLoadingMore = false;
        notifyListeners();
      }
    }

    Future<bool> updateOrderStatus({
      required String token,
      required int orderId,
      required String status,
      int? deliveryBoyId,
      String? notes,
      String? cancellationReason,
    }) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        final data = <String, dynamic>{'status': status};
        if (deliveryBoyId != null) data['deliveryBoyId'] = deliveryBoyId;
        if (notes != null) data['notes'] = notes;
        if (cancellationReason != null) {
          data['cancellationReason'] = cancellationReason;
        }

        await apiService.put(
          '/admin/orders/$orderId/status',
          data,
          token: token,
        );

        // Update the order in the list if it exists
        final orderIndex = _orders.indexWhere((o) => o.id == orderId);
        if (orderIndex >= 0) {
          // Fetch updated order to refresh the list
          await fetchOrders(token: token);
        } else {
          // If order not in list, just refresh stats
          await fetchStats(token: token);
        }
        return true;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return false;
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    Future<bool> updateUser({
      required String token,
      required int userId,
      String? name,
      String? email,
      String? role,
      bool? isActive,
    }) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        final data = <String, dynamic>{};
        if (name != null) data['name'] = name;
        if (email != null) data['email'] = email;
        if (role != null) data['role'] = role;
        if (isActive != null) data['isActive'] = isActive;

        await apiService.put(
          '/admin/users/$userId',
          data,
          token: token,
        );

        await fetchUsers(token: token);
        return true;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return false;
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    /// Change a user's role via the dedicated, audited endpoint. NOTE: the generic
    /// updateUser (PUT /users/:id) does NOT persist role — role changes must use
    /// this POST /users/:id/role endpoint or they silently no-op.
    Future<bool> changeUserRole({
      required String token,
      required int userId,
      required String role,
    }) async {
      try {
        await apiService.post('/admin/users/$userId/role', {'role': role}, token: token);
        return true;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return false;
      }
    }

    Future<ProductModel?> fetchProductById({required String token, required int productId}) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        final response = await apiService.get('/products/$productId', token: token);
        final product = ProductModel.fromJson(response as Map<String, dynamic>);
        
        // Update product in the list if it exists
        final existingIndex = _products.indexWhere((p) => p.id == productId);
        if (existingIndex >= 0) {
          _products[existingIndex] = product;
        }
        
        _isLoading = false;
        notifyListeners();
        return product;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
        notifyListeners();
        return null;
      }
    }

    Future<void> fetchProducts({String? token, bool loadMore = false, String? search, int? categoryId}) async {
      if (loadMore) {
        if (!_hasMore || _isLoadingMore) return;
        _isLoadingMore = true;
        _currentPage++;
      } else {
        _isLoading = true;
        _currentPage = 1;
        _products = [];
        _hasMore = true;
      }
      _error = null;
      notifyListeners();

      try {
        String endpoint = '/admin/products?page=$_currentPage&limit=20';
        if (search != null && search.isNotEmpty) {
          endpoint += '&search=${Uri.encodeComponent(search)}';
        }
        if (categoryId != null) {
          endpoint += '&categoryId=$categoryId';
        }
        final response = await apiService.get(endpoint, token: token);
        if (response is Map<String, dynamic> && response.containsKey('products')) {
          final List<dynamic> data = response['products'] as List? ?? [];
          final pagination = response['pagination'] as Map<String, dynamic>?;
          _hasMore = pagination?['hasMore'] as bool? ?? false;
          
          final newProducts = data.map((json) => ProductModel.fromJson(json as Map<String, dynamic>)).toList();
          if (loadMore) {
            _products.addAll(newProducts);
          } else {
            _products = newProducts;
          }
        } else {
          // Fallback for old API format
          final List<dynamic> data = response is List ? response : [];
          final newProducts = data.map((json) => ProductModel.fromJson(json as Map<String, dynamic>)).toList();
          if (loadMore) {
            _products.addAll(newProducts);
          } else {
            _products = newProducts;
          }
          _hasMore = false;
        }
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        print('Error fetching admin products: $_error');
        if (loadMore) _currentPage--;
      } finally {
        _isLoading = false;
        _isLoadingMore = false;
        notifyListeners();
      }
    }

    Future<bool> createProduct({
      required String token,
      required String name,
      required double price,
      required int categoryId,
      String? description,
      String? tags,
      String? imageUrl,
      int? stock,
      String? unit,
    }) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        final data = <String, dynamic>{
          'name': name,
          'price': price,
          'categoryId': categoryId,
        };
        if (description != null) data['description'] = description;
        if (tags != null) data['tags'] = tags;
        if (imageUrl != null) data['imageUrl'] = imageUrl;
        if (stock != null) data['stock'] = stock;
        if (unit != null) data['unit'] = unit;

        await apiService.post('/admin/products', data, token: token);
        await fetchProducts(token: token);
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

    Future<bool> updateProduct({
      required String token,
      required int productId,
      String? name,
      String? description,
      String? tags,
      double? price,
      String? imageUrl,
      int? categoryId,
      int? stock,
      String? unit,
      bool? isAvailable,
    }) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        final data = <String, dynamic>{};
        if (name != null) data['name'] = name;
        if (description != null) data['description'] = description;
        if (tags != null) data['tags'] = tags;
        if (price != null) data['price'] = price;
        if (imageUrl != null) data['imageUrl'] = imageUrl;
        if (categoryId != null) data['categoryId'] = categoryId;
        if (stock != null) data['stock'] = stock;
        if (unit != null) data['unit'] = unit;
        if (isAvailable != null) data['isAvailable'] = isAvailable;

        await apiService.put('/admin/products/$productId', data, token: token);
        await fetchProducts(token: token);
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

    Future<bool> deleteProduct({
      required String token,
      required int productId,
    }) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        await apiService.delete('/admin/products/$productId', token: token);
        await fetchProducts(token: token);
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

    Future<void> fetchCategories({String? token, bool loadMore = false}) async {
      if (loadMore) {
        if (!_hasMore || _isLoadingMore) return;
        _isLoadingMore = true;
        _currentPage++;
      } else {
        _isLoading = true;
        _currentPage = 1;
        _categories = [];
        _hasMore = true;
      }
      _error = null;
      notifyListeners();

      try {
        // Include inactive categories for admin dashboard
        final response = await apiService.get('/categories?page=$_currentPage&limit=20&includeInactive=true', token: token);
        if (response is Map<String, dynamic> && response.containsKey('categories')) {
          final List<dynamic> data = response['categories'] as List? ?? [];
          final pagination = response['pagination'] as Map<String, dynamic>?;
          _hasMore = pagination?['hasMore'] as bool? ?? false;
          
          final newCategories = data.map((json) => CategoryModel.fromJson(json as Map<String, dynamic>)).toList();
          if (loadMore) {
            _categories.addAll(newCategories);
          } else {
            _categories = newCategories;
          }
        } else {
          // Fallback for old API format
          final List<dynamic> data = response is List ? response : [];
          final newCategories = data.map((json) => CategoryModel.fromJson(json as Map<String, dynamic>)).toList();
          if (loadMore) {
            _categories.addAll(newCategories);
          } else {
            _categories = newCategories;
          }
          _hasMore = false;
        }
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        print('Error fetching admin categories: $_error');
        if (loadMore) _currentPage--;
      } finally {
        _isLoading = false;
        _isLoadingMore = false;
        notifyListeners();
      }
    }

    Future<bool> createCategory({
      required String token,
      required String name,
      String? description,
      String? imageUrl,
      int? parentCategoryId,
      int? displayOrder,
    }) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        final data = <String, dynamic>{'name': name};
        if (description != null) data['description'] = description;
        if (imageUrl != null) data['imageUrl'] = imageUrl;
        if (parentCategoryId != null) data['parentCategoryId'] = parentCategoryId;
        if (displayOrder != null) data['displayOrder'] = displayOrder;

        await apiService.post('/categories', data, token: token);
        await fetchCategories(token: token);
        return true;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return false;
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    Future<bool> updateCategory({
      required String token,
      required int categoryId,
      String? name,
      String? description,
      String? imageUrl,
      bool? isActive,
      int? parentCategoryId,
      int? displayOrder,
    }) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        final data = <String, dynamic>{};
        if (name != null) data['name'] = name;
        if (description != null) data['description'] = description;
        if (imageUrl != null) data['imageUrl'] = imageUrl;
        if (isActive != null) data['isActive'] = isActive;
        if (parentCategoryId != null) data['parentCategoryId'] = parentCategoryId;
        if (parentCategoryId == null && data.containsKey('parentCategoryId')) {
          // Explicitly set to null to remove parent
          data['parentCategoryId'] = null;
        }
        if (displayOrder != null) data['displayOrder'] = displayOrder;

        await apiService.put('/categories/$categoryId', data, token: token);
        await fetchCategories(token: token);
        return true;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return false;
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    Future<bool> deleteCategory({
      required String token,
      required int categoryId,
    }) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        await apiService.delete('/categories/$categoryId', token: token);
        await fetchCategories(token: token);
        return true;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return false;
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    Future<void> fetchDeliveryAgents({String? token}) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        final response = await apiService.get('/admin/delivery-agents', token: token);
        final List<dynamic> data = response is List ? response : [];
        _deliveryAgents = data.map((json) => UserModel.fromJson(json as Map<String, dynamic>)).toList();
        
        if (kDebugMode) {
          print('✅ Fetched ${_deliveryAgents.length} delivery agents');
          if (_deliveryAgents.isEmpty) {
            print('⚠️ No delivery agents found. Make sure users have role="delivery" and isActive=true');
          }
        }
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        if (kDebugMode) {
          print('❌ Error fetching delivery agents: $_error');
        }
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    // Variant Management Methods
    Future<List<ProductVariantModel>> fetchProductVariants({
      required String token,
      required int productId,
    }) async {
      _error = null;
      try {
        final response = await apiService.get('/products/$productId/variants', token: token);
        if (response is Map<String, dynamic> && response.containsKey('variants')) {
          final List<dynamic> data = response['variants'] as List? ?? [];
          return data.map((json) => ProductVariantModel.fromJson(json as Map<String, dynamic>)).toList();
        }
        return [];
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        print('❌ Error fetching variants: $_error');
        return [];
      }
    }

    Future<bool> createVariant({
      required String token,
      required int productId,
      required double quantity,
      required String unit,
      required String label,
      required double price,
      int? stock,
      bool? isAvailable,
      double? minQuantity,
      double? maxQuantity,
      int? displayOrder,
      bool? isDefault,
    }) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        final data = <String, dynamic>{
          'quantity': quantity,
          'unit': unit,
          'label': label,
          'price': price,
        };
        if (stock != null) data['stock'] = stock;
        if (isAvailable != null) data['isAvailable'] = isAvailable;
        if (minQuantity != null) data['minQuantity'] = minQuantity;
        if (maxQuantity != null) data['maxQuantity'] = maxQuantity;
        if (displayOrder != null) data['displayOrder'] = displayOrder;
        if (isDefault != null) data['isDefault'] = isDefault;

        final response = await apiService.post('/products/$productId/variants', data, token: token);
        
        // Check if response indicates success
        if (response != null) {
          return true;
        }
        return false;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        print('❌ Error creating variant: $_error');
        return false;
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    Future<bool> updateVariant({
      required String token,
      required int variantId,
      double? quantity,
      String? unit,
      String? label,
      double? price,
      int? stock,
      bool? isAvailable,
      double? minQuantity,
      double? maxQuantity,
      int? displayOrder,
      bool? isDefault,
    }) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        final data = <String, dynamic>{};
        if (quantity != null) data['quantity'] = quantity;
        if (unit != null) data['unit'] = unit;
        if (label != null) data['label'] = label;
        if (price != null) data['price'] = price;
        if (stock != null) data['stock'] = stock;
        if (isAvailable != null) data['isAvailable'] = isAvailable;
        if (minQuantity != null) data['minQuantity'] = minQuantity;
        if (maxQuantity != null) data['maxQuantity'] = maxQuantity;
        if (displayOrder != null) data['displayOrder'] = displayOrder;
        if (isDefault != null) data['isDefault'] = isDefault;

        await apiService.put('/variants/$variantId', data, token: token);
        return true;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return false;
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    Future<bool> deleteVariant({
      required String token,
      required int variantId,
    }) async {
      _isLoading = true;
      _error = null;
      notifyListeners();

      try {
        await apiService.delete('/variants/$variantId', token: token);
        return true;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return false;
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    // ════════════════════════════════════════════════════════════════════════
    // Phase 3 — rider management + audit endpoints
    // ════════════════════════════════════════════════════════════════════════

    /// Cached list of riders from `GET /api/admin/riders`. Includes availability,
    /// active-order count, last-seen, vehicle info — everything the admin's
    /// "assign rider" picker needs to make a good call.
    List<Map<String, dynamic>> _riders = [];
    List<Map<String, dynamic>> get riders => _riders;

    /// Fetches ALL riders. Optional `availability` filter (idle|busy|offline).
    Future<void> fetchRiders({String? token, String? availability}) async {
      _isLoading = true;
      _error = null;
      notifyListeners();
      try {
        var endpoint = '/admin/riders';
        if (availability != null && availability.isNotEmpty) {
          endpoint += '?availability=$availability';
        }
        final response = await apiService.get(endpoint, token: token);
        final List<dynamic> data = response is List ? response : [];
        _riders = data.map((j) => Map<String, dynamic>.from(j as Map)).toList();
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    /// Wallet snapshot: cash_in_hand, lifetime totals, pending earnings.
    Future<Map<String, dynamic>?> fetchRiderWallet({
      required String token,
      required int riderId,
    }) async {
      try {
        final response = await apiService.get('/admin/riders/$riderId/wallet', token: token);
        return response is Map<String, dynamic> ? response : null;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return null;
      }
    }

    /// Records cash deposit from rider to hub. Idempotency-Key header is required
    /// by the backend; we generate one from `(riderId, amount, ms-of-the-day)` so
    /// double-taps within ~1s collapse but two intentional deposits a moment apart
    /// don't.
    Future<Map<String, dynamic>?> recordRiderDeposit({
      required String token,
      required int riderId,
      required int amountPaise,
      String? note,
    }) async {
      try {
        final idem =
            'admin-deposit-$riderId-$amountPaise-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
        final response = await apiService.post(
          '/admin/riders/$riderId/deposit',
          {
            'amountPaise': amountPaise,
            if (note != null && note.isNotEmpty) 'note': note,
          },
          token: token,
          extraHeaders: {'Idempotency-Key': idem},
        );
        return response is Map<String, dynamic> ? response : null;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return null;
      }
    }

    /// Assigns a rider to an order. Returns true on success.
    Future<bool> assignRiderToOrder({
      required String token,
      required int orderId,
      required int riderId,
    }) async {
      try {
        await apiService.post(
          '/admin/orders/$orderId/assign-rider',
          {'riderId': riderId},
          token: token,
        );
        return true;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return false;
      }
    }

    /// Marks an RTO complete after the rider physically returns inventory to hub.
    /// Restores stock + auto-refunds prepaid orders.
    Future<bool> completeRto({required String token, required int orderId}) async {
      try {
        await apiService.post('/admin/orders/$orderId/complete-rto', {}, token: token);
        return true;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return false;
      }
    }

    /// Approve a customer's cancellation request → cancels the order and initiates
    /// a full refund if it was prepaid.
    /// Refreshes the local order list so every admin screen (list, dashboard,
    /// detail) reflects the decision immediately — not just after the next poll.
    Future<bool> approveCancellation({required String token, required int orderId}) async {
      try {
        await apiService.post('/admin/orders/$orderId/approve-cancellation', {}, token: token);
        if (_orders.any((o) => o.id == orderId)) {
          await fetchOrders(token: token);
        }
        return true;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        notifyListeners();
        return false;
      }
    }

    /// Fetch refund state for an order — drives the refund card and the
    /// enabled/disabled state of the "Retry refund" button.
    /// Returns null when the order has no refund at all (the common case).
    Future<RefundInfo?> fetchRefundInfo({
      required String token,
      required int orderId,
    }) async {
      try {
        final res = await apiService.get('/admin/orders/$orderId/refund', token: token);
        final data = res is Map<String, dynamic> ? res['refund'] : null;
        if (data is Map<String, dynamic>) return RefundInfo.fromJson(data);
        return null;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return null;
      }
    }

    /// Manually re-attempt a refund whose automatic retries were exhausted.
    ///
    /// One tap = one attempt. The server takes the payment lock and checks with
    /// Razorpay whether a refund already exists for this row before creating
    /// one, so repeated taps cannot refund the customer twice.
    ///
    /// Returns the refreshed state on both success and failure so the caller can
    /// re-render the card either way; `_error` carries the message to surface.
    Future<RefundInfo?> retryRefund({
      required String token,
      required int orderId,
    }) async {
      try {
        final res = await apiService.post(
          '/admin/orders/$orderId/retry-refund',
          {},
          token: token,
        );
        final data = res is Map<String, dynamic> ? res['refund'] : null;
        if (res is Map<String, dynamic> && res['message'] != null) {
          _error = null;
        }
        if (data is Map<String, dynamic>) {
          final info = RefundInfo.fromJson(data);
          if (_orders.any((o) => o.id == orderId)) {
            await fetchOrders(token: token);
          }
          notifyListeners();
          return info;
        }
        return null;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        notifyListeners();
        // Fall back to a plain read so the UI still shows the latest attempt count
        // and failure reason even though this attempt errored.
        return fetchRefundInfo(token: token, orderId: orderId);
      }
    }

    /// Decline a customer's cancellation request — the order stays active.
    /// Refreshes the local order list so the pending-request badge clears
    /// immediately across admin screens.
    Future<bool> rejectCancellation({required String token, required int orderId}) async {
      try {
        await apiService.post('/admin/orders/$orderId/reject-cancellation', {}, token: token);
        if (_orders.any((o) => o.id == orderId)) {
          await fetchOrders(token: token);
        }
        return true;
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        notifyListeners();
        return false;
      }
    }

    /// Pulls the chronological audit log for an order — every state transition
    /// with actor, timestamp, and event payload. Read-only.
    Future<List<Map<String, dynamic>>> fetchOrderEvents({
      required String token,
      required int orderId,
    }) async {
      try {
        final response = await apiService.get('/admin/orders/$orderId/events', token: token);
        final List<dynamic> data = response is List ? response : [];
        return data.map((j) => Map<String, dynamic>.from(j as Map)).toList();
      } catch (e) {
        _error = e.toString().replaceAll('Exception: ', '');
        return [];
      }
    }
  }
