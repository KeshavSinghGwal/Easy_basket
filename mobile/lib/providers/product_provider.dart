import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';

class ProductProvider with ChangeNotifier {
  final ApiService apiService;

  List<ProductModel> _products = [];

  /// Products fetched individually by id (product detail, deep links) that are
  /// NOT part of the current list query. Kept apart from [_products] so a detail
  /// view can never inject a foreign product into the category or search grid.
  final Map<int, ProductModel> _productsById = {};

  List<CategoryModel> _categories = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;  // Infinite scroll ke liye — next page load ho raha hai
  bool _hasMore = true;          // Aur products hain ya nahi
  int _currentPage = 1;          // Current page number
  int? _currentCategoryId;       // Current category filter (pagination mein reuse)
  String? _currentSearch;        // Current search filter (pagination mein reuse)
  String? _error;

  List<ProductModel> get products => _products;
  List<CategoryModel> get categories => _categories;
  List<Map<String, dynamic>> get suggestions => _suggestions;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;

  /// A product we already hold, whether it came from the current list query or
  /// from an individual fetch. Lets a detail screen render instantly without
  /// pushing that product into the grid. Null when we have never loaded it.
  ProductModel? productById(int id) {
    final cached = _productsById[id];
    if (cached != null) return cached;
    final i = _products.indexWhere((p) => p.id == id);
    return i >= 0 ? _products[i] : null;
  }

  ProductProvider({required this.apiService});

  Future<void> fetchSuggestions(String query) async {
    if (query.length < 2) {
      _suggestions = [];
      notifyListeners();
      return;
    }

    try {
      // Encoded, not interpolated. A '#' in the term used to truncate the query
      // into a fragment ("Kurkure #1" searched for "Kurkure "), '&' split it into
      // a bogus extra parameter, and non-ASCII input — which Hindi/Punjabi voice
      // search feeds straight into this field — risked a FormatException from
      // Uri.parse that surfaced as a network error.
      final response = await apiService
          .get('/products/suggestions?search=${Uri.encodeQueryComponent(query)}');
      if (response is List) {
        _suggestions = response.map((item) => item as Map<String, dynamic>).toList();
      } else {
        _suggestions = [];
      }
      notifyListeners();
    } catch (e) {
      print('Error fetching suggestions: $e');
      _suggestions = [];
      notifyListeners();
    }
  }

  void clearSuggestions() {
    _suggestions = [];
    notifyListeners();
  }

  Future<void> fetchCategories() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiService.get('/categories');
      // Handle both paginated and non-paginated responses
      if (response is Map<String, dynamic> && response.containsKey('categories')) {
        final List<dynamic> data = response['categories'] as List? ?? [];
        _categories = data.map((json) => CategoryModel.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        // Fallback for old API format (direct array)
        final List<dynamic> data = response is List ? response : [];
        _categories = data.map((json) => CategoryModel.fromJson(json as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchProducts({int? categoryId, String? search, int? limit, int? page}) async {
    _isLoading = true;
    _error = null;

    // Store current filters for loadMore to reuse
    _currentCategoryId = categoryId;
    _currentSearch = search;
    _currentPage = 1;
    _hasMore = true;

    notifyListeners();

    try {
      // Build endpoint with query params
      final params = <String>[];
      if (categoryId != null) params.add('categoryId=$categoryId');
      if (search != null && search.isNotEmpty) {
        params.add('search=${Uri.encodeQueryComponent(search)}');
      }
      // Default limit=20 for paginated screens, custom limit for home
      final useLimit = limit ?? 20;
      params.add('limit=$useLimit');
      params.add('page=1');
      final query = '?${params.join('&')}';
      String endpoint = '/products$query';

      final response = await apiService.get(endpoint);
      final List<dynamic> data = response is List ? response : [];

      // Fresh fetch — replace products list
      _products = data.map((json) {
        try {
          return ProductModel.fromJson(json as Map<String, dynamic>);
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing product: $e');
          }
          rethrow;
        }
      }).toList();

      // Agar returned products < limit → aur products nahi hain
      _hasMore = data.length >= useLimit;

      // Sort: in-stock first, out-of-stock bottom
      _sortProducts();

      if (kDebugMode) {
        print('Fetched ${_products.length} products (page 1, limit $useLimit, hasMore: $_hasMore)');
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      if (kDebugMode) {
        print('Error fetching products: $_error');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Infinite scroll — next page load karo aur existing list mein append karo
  /// Kyun: User scroll kare toh aur products dikhao bina purani list replace kiye
  Future<void> loadMoreProducts() async {
    // Agar already loading hai ya aur products nahi hain → skip
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      _currentPage++;
      final params = <String>[];
      if (_currentCategoryId != null) params.add('categoryId=$_currentCategoryId');
      if (_currentSearch != null && _currentSearch!.isNotEmpty) {
        params.add('search=${Uri.encodeQueryComponent(_currentSearch!)}');
      }
      params.add('limit=20');
      params.add('page=$_currentPage');
      final endpoint = '/products?${params.join('&')}';

      final response = await apiService.get(endpoint);
      final List<dynamic> data = response is List ? response : [];

      final newProducts = data.map((json) {
        try {
          return ProductModel.fromJson(json as Map<String, dynamic>);
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing product: $e');
          }
          rethrow;
        }
      }).toList();

      // Append — purani list mein naye products jodo
      _products.addAll(newProducts);

      // Agar returned < 20 → aur nahi hain
      _hasMore = newProducts.length >= 20;

      _sortProducts();

      if (kDebugMode) {
        print('Loaded page $_currentPage: ${newProducts.length} products (total: ${_products.length}, hasMore: $_hasMore)');
      }
    } catch (e) {
      _currentPage--; // Revert page number on failure
      if (kDebugMode) {
        print('Error loading more products: $e');
      }
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Sort: in-stock products first, out-of-stock at bottom
  void _sortProducts() {
    _products.sort((a, b) {
      final aOutOfStock = !a.isAvailable ||
          ((a.hasVariants && a.variants != null && !a.variants!.any((v) => v.isAvailable && v.stock > 0)) ||
           (!a.hasVariants && a.stock <= 0));
      final bOutOfStock = !b.isAvailable ||
          ((b.hasVariants && b.variants != null && !b.variants!.any((v) => v.isAvailable && v.stock > 0)) ||
           (!b.hasVariants && b.stock <= 0));
      if (!aOutOfStock && bOutOfStock) return -1;
      if (aOutOfStock && !bOutOfStock) return 1;
      return 0;
    });
  }

  Future<ProductModel?> fetchProductById(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final response = await apiService.get('/products/$id');
      final product = ProductModel.fromJson(response as Map<String, dynamic>);

      // Refresh this product where the CURRENT list already contains it, but never
      // append it. _products backs the category grid and search results; adding a
      // product fetched by id (from search, or a deep link) made a foreign product
      // appear in an unrelated category, and inflated the count loadMoreProducts
      // uses as its paging offset, so the next page could skip or duplicate a row.
      final existingIndex = _products.indexWhere((p) => p.id == id);
      if (existingIndex >= 0) {
        _products[existingIndex] = product;
      } else {
        _productsById[id] = product;
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
}

