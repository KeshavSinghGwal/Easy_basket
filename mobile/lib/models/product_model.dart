import 'category_model.dart';
import 'product_variant_model.dart';

class ProductModel {
  final int id;
  final String name;
  final String? description;
  final String? tags;
  final double price;
  final String? imageUrl;
  final CategoryModel? category;
  final int stock;
  final bool isAvailable;
  final String? unit;
  final bool hasVariants;
  final String? baseUnit;
  final double? minQuantity;
  final double? maxQuantity;
  final List<ProductVariantModel>? variants;

  ProductModel({
    required this.id,
    required this.name,
    this.description,
    this.tags,
    required this.price,
    this.imageUrl,
    this.category,
    required this.stock,
    required this.isAvailable,
    this.unit,
    this.hasVariants = false,
    this.baseUnit,
    this.minQuantity,
    this.maxQuantity,
    this.variants,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    // Handle price as string (from database decimal) or number
    double priceValue;
    final priceData = json['price'];
    if (priceData is String) {
      priceValue = double.parse(priceData);
    } else if (priceData is num) {
      priceValue = priceData.toDouble();
    } else {
      // Fallback if price is null or unexpected type
      priceValue = 0.0;
    }
    
    // Parse variants if they exist
    List<ProductVariantModel>? variants;
    if (json['variants'] != null && json['variants'] is List) {
      variants = (json['variants'] as List)
          .map((v) => ProductVariantModel.fromJson(v as Map<String, dynamic>))
          .toList();
    }
    
    // Handle minQuantity and maxQuantity
    double? minQuantity;
    if (json['minQuantity'] != null) {
      if (json['minQuantity'] is String) {
        minQuantity = double.tryParse(json['minQuantity'] as String);
      } else if (json['minQuantity'] is num) {
        minQuantity = (json['minQuantity'] as num).toDouble();
      }
    }
    
    double? maxQuantity;
    if (json['maxQuantity'] != null) {
      if (json['maxQuantity'] is String) {
        maxQuantity = double.tryParse(json['maxQuantity'] as String);
      } else if (json['maxQuantity'] is num) {
        maxQuantity = (json['maxQuantity'] as num).toDouble();
      }
    }
    
    return ProductModel(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      tags: json['tags'] as String?,
      price: priceValue,
      imageUrl: json['imageUrl'] as String?,
      category: json['category'] != null
          ? CategoryModel.fromJson(json['category'] as Map<String, dynamic>)
          : null,
      stock: json['stock'] is int ? json['stock'] as int : (json['stock'] as num?)?.toInt() ?? 0,
      isAvailable: json['isAvailable'] as bool? ?? true,
      unit: json['unit'] as String? ?? 'piece',
      hasVariants: json['hasVariants'] as bool? ?? false,
      baseUnit: json['baseUnit'] as String?,
      minQuantity: minQuantity,
      maxQuantity: maxQuantity,
      variants: variants,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'imageUrl': imageUrl,
      'category': category?.toJson(),
      'stock': stock,
      'isAvailable': isAvailable,
      'unit': unit,
      'hasVariants': hasVariants,
      'baseUnit': baseUnit,
      'minQuantity': minQuantity,
      'maxQuantity': maxQuantity,
      'variants': variants?.map((v) => v.toJson()).toList(),
    };
  }

  /// True when the product (or at least one of its variants, if it has variants)
  /// is available to purchase right now. Use this anywhere you list / filter products.
  bool get hasStock {
    if (!isAvailable) return false;
    if (hasVariants) {
      final vs = variants;
      if (vs == null || vs.isEmpty) return false;
      return vs.any((v) => v.isAvailable && v.stock > 0);
    }
    return stock > 0;
  }
}

