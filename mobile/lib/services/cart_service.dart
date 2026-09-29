import '../models/product_model.dart';
import '../models/product_variant_model.dart';

class CartItem {
  final ProductModel product;
  final ProductVariantModel? variant;
  int quantity;

  CartItem({
    required this.product,
    this.variant,
    this.quantity = 1,
  });

  double get total {
    final price = variant?.price ?? product.price;
    return price * quantity;
  }
  
  String get displayLabel {
    if (variant != null) {
      return '${quantity} × ${variant!.label}';
    }
    return '$quantity × ${product.name}';
  }
  
  // Unique key for cart items (product + variant combination)
  String get key {
    if (variant != null) {
      return '${product.id}_${variant!.id}';
    }
    return '${product.id}_null';
  }
}

class CartService {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  /// Number of distinct product/variant LINES in the cart.
  int get itemCount => _items.length;

  /// Total number of units across all lines — six of one product is 6, not 1.
  /// Split out because `itemCount` reads as "items" beside a total that folds
  /// over quantity, so a badge showing "1 item" next to a six-unit total looked
  /// like a bug. Callers should pick whichever their copy actually means.
  int get unitCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get totalAmount {
    return _items.fold(0.0, (sum, item) => sum + item.total);
  }

  void addItem(ProductModel product, {ProductVariantModel? variant}) {
    final itemKey = variant != null 
        ? '${product.id}_${variant.id}'
        : '${product.id}_null';
    
    final existingIndex = _items.indexWhere((item) => item.key == itemKey);

    if (existingIndex >= 0) {
      final maxStock = variant?.stock ?? product.stock;
      if (_items[existingIndex].quantity < maxStock) {
        _items[existingIndex].quantity++;
      }
    } else {
      _items.add(CartItem(product: product, variant: variant, quantity: 1));
    }
  }

  void removeItem(int productId, {int? variantId}) {
    if (variantId != null) {
      _items.removeWhere((item) => 
          item.product.id == productId && item.variant?.id == variantId);
    } else {
      _items.removeWhere((item) => 
          item.product.id == productId && item.variant == null);
    }
  }

  void updateQuantity(int productId, int quantity, {int? variantId}) {
    final itemKey = variantId != null 
        ? '${productId}_$variantId'
        : '${productId}_null';
    
    // No orElse on firstWhere threw StateError when the line was gone — reachable
    // from a stepper firing after a concurrent removal, or when two screens
    // disagree about variant identity. The exception escaped CartProvider into
    // the widget tree AND skipped the _saveCart that follows, leaving the
    // persisted cart inconsistent. getQuantity and contains both already guard
    // for exactly this; updateQuantity was the one that did not.
    final index = _items.indexWhere((item) => item.key == itemKey);
    if (index < 0) return;
    final item = _items[index];

    if (quantity <= 0) {
      removeItem(productId, variantId: variantId);
    } else {
      final maxStock = item.variant?.stock ?? item.product.stock;
      if (quantity <= maxStock) {
        item.quantity = quantity;
      }
    }
  }

  void clear() {
    _items.clear();
  }

  bool contains(int productId, {int? variantId}) {
    if (variantId != null) {
      return _items.any((item) => 
          item.product.id == productId && item.variant?.id == variantId);
    }
    return _items.any((item) => 
        item.product.id == productId && item.variant == null);
  }

  int getQuantity(int productId, {int? variantId}) {
    try {
      if (variantId != null) {
        return _items.firstWhere((item) => 
            item.product.id == productId && item.variant?.id == variantId).quantity;
      }
      return _items.firstWhere((item) => 
          item.product.id == productId && item.variant == null).quantity;
    } catch (e) {
      return 0;
    }
  }
}

