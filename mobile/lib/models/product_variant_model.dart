class ProductVariantModel {
  final int id;
  final double quantity;
  final String unit;
  final String label;
  final double price;
  final int stock;
  final bool isAvailable;
  final double? minQuantity;
  final double? maxQuantity;
  final int displayOrder;
  final bool isDefault;

  ProductVariantModel({
    required this.id,
    required this.quantity,
    required this.unit,
    required this.label,
    required this.price,
    required this.stock,
    required this.isAvailable,
    this.minQuantity,
    this.maxQuantity,
    required this.displayOrder,
    required this.isDefault,
  });

  factory ProductVariantModel.fromJson(Map<String, dynamic> json) {
    // Handle price as string (from database decimal) or number
    double priceValue;
    final priceData = json['price'];
    if (priceData is String) {
      priceValue = double.parse(priceData);
    } else if (priceData is num) {
      priceValue = priceData.toDouble();
    } else {
      priceValue = 0.0;
    }

    // Handle quantity
    double quantityValue;
    final quantityData = json['quantity'];
    if (quantityData is String) {
      quantityValue = double.parse(quantityData);
    } else if (quantityData is num) {
      quantityValue = quantityData.toDouble();
    } else {
      quantityValue = 0.0;
    }

    return ProductVariantModel(
      id: json['id'] as int,
      quantity: quantityValue,
      unit: json['unit'] as String,
      label: json['label'] as String,
      price: priceValue,
      stock: json['stock'] is int ? json['stock'] as int : (json['stock'] as num?)?.toInt() ?? 0,
      isAvailable: json['isAvailable'] as bool? ?? true,
      minQuantity: json['minQuantity'] != null
          ? (json['minQuantity'] is String
              ? double.parse(json['minQuantity'] as String)
              : (json['minQuantity'] as num).toDouble())
          : null,
      maxQuantity: json['maxQuantity'] != null
          ? (json['maxQuantity'] is String
              ? double.parse(json['maxQuantity'] as String)
              : (json['maxQuantity'] as num).toDouble())
          : null,
      displayOrder: json['displayOrder'] as int? ?? 0,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'quantity': quantity,
      'unit': unit,
      'label': label,
      'price': price,
      'stock': stock,
      'isAvailable': isAvailable,
      'minQuantity': minQuantity,
      'maxQuantity': maxQuantity,
      'displayOrder': displayOrder,
      'isDefault': isDefault,
    };
  }
}

