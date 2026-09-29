import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/cart_service.dart';
import '../models/product_model.dart';
import '../models/product_variant_model.dart';

class CartProvider with ChangeNotifier {
  final CartService _cartService = CartService();
  final Set<int> _addingItems = {}; // Track items being added
  SharedPreferences? _prefs;
  bool _isLoading = false;

  List<CartItem> get items => _cartService.items;
  int get itemCount => _cartService.itemCount;
  int get unitCount => _cartService.unitCount;
  double get totalAmount => _cartService.totalAmount;
  bool isAddingItem(int productId) => _addingItems.contains(productId);
  bool get isLoading => _isLoading;

  CartProvider();

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadCart();
  }

  Future<void> _loadCart() async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
    }
    
    _isLoading = true;
    notifyListeners();

    try {
      final cartJson = _prefs!.getString('cart_items');
      if (cartJson != null && cartJson.isNotEmpty) {
        final List<dynamic> cartData = jsonDecode(cartJson);
        
        for (var itemData in cartData) {
          try {
            final productJson = itemData['product'] as Map<String, dynamic>;
            final product = ProductModel.fromJson(productJson);
            final quantity = itemData['quantity'] as int;
            ProductVariantModel? variant;
            
            // Load variant if present
            if (itemData['variant'] != null) {
              variant = ProductVariantModel.fromJson(itemData['variant'] as Map<String, dynamic>);
            }
            
            // Add item with quantity and variant
            for (int i = 0; i < quantity; i++) {
              _cartService.addItem(product, variant: variant);
            }
            // Adjust quantity if needed (in case it was > 1)
            if (quantity > 1) {
              _cartService.updateQuantity(product.id, quantity, variantId: variant?.id);
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error loading cart item: $e');
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading cart: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveCart() async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
    }

    try {
      final cartData = _cartService.items.map((item) => {
        'product': item.product.toJson(),
        'quantity': item.quantity,
        if (item.variant != null) 'variant': item.variant!.toJson(),
      }).toList();

      final cartJson = jsonEncode(cartData);
      await _prefs!.setString('cart_items', cartJson);
    } catch (e) {
      if (kDebugMode) {
        print('Error saving cart: $e');
      }
    }
  }

  Future<void> addItem(ProductModel product, {ProductVariantModel? variant}) async {
    _addingItems.add(product.id);
    notifyListeners();
    
    // Instant update for better UX (like Blinkit)
    _cartService.addItem(product, variant: variant);
    _addingItems.remove(product.id);
    await _saveCart();
    notifyListeners();
  }

  Future<void> removeItem(int productId, {int? variantId}) async {
    _cartService.removeItem(productId, variantId: variantId);
    await _saveCart();
    notifyListeners();
  }

  Future<void> updateQuantity(int productId, int quantity, {int? variantId}) async {
    // Instant update for smooth UX (like Blinkit)
    _cartService.updateQuantity(productId, quantity, variantId: variantId);
    await _saveCart();
    notifyListeners();
  }

  Future<void> clear() async {
    _cartService.clear();
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
    }
    await _prefs!.remove('cart_items');
    notifyListeners();
  }

  bool contains(int productId, {int? variantId}) {
    return _cartService.contains(productId, variantId: variantId);
  }

  int getQuantity(int productId, {int? variantId}) {
    return _cartService.getQuantity(productId, variantId: variantId);
  }
}

