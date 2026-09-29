class CategoryModel {
  final int id;
  final String name;
  final String? description;
  final String? imageUrl;
  final bool isActive;
  final int? parentCategoryId;
  final CategoryModel? parentCategory;
  final List<CategoryModel>? subcategories;
  final int displayOrder;

  CategoryModel({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    required this.isActive,
    this.parentCategoryId,
    this.parentCategory,
    this.subcategories,
    this.displayOrder = 0,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      parentCategoryId: json['parentCategoryId'] as int?,
      parentCategory: json['parentCategory'] != null
          ? CategoryModel.fromJson(json['parentCategory'] as Map<String, dynamic>)
          : null,
      subcategories: json['subcategories'] != null
          ? (json['subcategories'] as List<dynamic>)
              .map((sub) => CategoryModel.fromJson(sub as Map<String, dynamic>))
              .toList()
          : null,
      displayOrder: json['displayOrder'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'isActive': isActive,
      'parentCategoryId': parentCategoryId,
      'parentCategory': parentCategory?.toJson(),
      'subcategories': subcategories?.map((sub) => sub.toJson()).toList(),
      'displayOrder': displayOrder,
    };
  }

  /// Check if this category has subcategories
  bool get hasSubcategories => subcategories != null && subcategories!.isNotEmpty;

  /// Check if this is a top-level category (no parent)
  bool get isTopLevel => parentCategoryId == null;

  /// Check if this is a subcategory (has parent)
  bool get isSubcategory => parentCategoryId != null;

  /// Create a copy with overridden fields
  CategoryModel copyWith({int? parentCategoryId}) {
    return CategoryModel(
      id: id,
      name: name,
      description: description,
      imageUrl: imageUrl,
      isActive: isActive,
      parentCategoryId: parentCategoryId ?? this.parentCategoryId,
      parentCategory: parentCategory,
      subcategories: subcategories,
      displayOrder: displayOrder,
    );
  }
}

