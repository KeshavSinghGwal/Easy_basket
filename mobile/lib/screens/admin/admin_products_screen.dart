import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../models/product_model.dart';
import '../../models/category_model.dart';
import '../../utils/theme.dart';
import '../../widgets/variant_management_dialog.dart';
import 'package:intl/intl.dart';

class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  int? _selectedCategoryId;
  String? _searchQuery;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProducts();
      _loadCategories();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      final newQuery = _searchController.text.trim().isEmpty ? null : _searchController.text.trim();
      if (newQuery != _searchQuery) {
        setState(() {
          _searchQuery = newQuery;
        });
        _loadProducts();
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      final adminProvider = Provider.of<AdminProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (adminProvider.hasMore && !adminProvider.isLoadingMore) {
        adminProvider.fetchProducts(
          token: authProvider.token,
          loadMore: true,
          search: _searchQuery,
          categoryId: _selectedCategoryId,
        );
      }
    }
  }

  void _loadProducts() {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    adminProvider.fetchProducts(
      token: authProvider.token,
      search: _searchQuery,
      categoryId: _selectedCategoryId,
    );
  }

  void _loadCategories() {
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    productProvider.fetchCategories();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = null;
      _selectedCategoryId = null;
    });
    _loadProducts();
  }

  bool get _hasActiveFilters => _searchQuery != null || _selectedCategoryId != null;

  Future<void> _deleteProduct(ProductModel product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final adminProvider = Provider.of<AdminProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (authProvider.token == null) return;

      final success = await adminProvider.deleteProduct(
        token: authProvider.token!,
        productId: product.id,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product deleted successfully!')),
        );
        _loadProducts();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminProvider.error ?? 'Failed to delete product')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final adminProvider = Provider.of<AdminProvider>(context);
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Products'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/dashboard'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProducts,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Section
          _SearchAndFilterSection(
            searchController: _searchController,
            searchFocusNode: _searchFocusNode,
            selectedCategoryId: _selectedCategoryId,
            onCategoryChanged: (categoryId) {
              setState(() {
                _selectedCategoryId = categoryId;
              });
              _loadProducts();
            },
            onClearFilters: _hasActiveFilters ? _clearFilters : null,
            onSearchCleared: () {
              setState(() {
                _searchQuery = null;
              });
              _loadProducts();
            },
          ),
          // Products List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _loadProducts();
                _loadCategories();
              },
              child: adminProvider.isLoading && adminProvider.products.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : adminProvider.products.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _hasActiveFilters ? Icons.search_off : Icons.inventory_2_outlined,
                                size: 64,
                                color: AppTheme.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _hasActiveFilters
                                    ? 'No products found matching your search'
                                    : 'No products found',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: AppTheme.grey,
                                ),
                              ),
                              if (_hasActiveFilters) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _clearFilters,
                                  child: const Text('Clear Filters'),
                                ),
                              ],
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: () => context.push('/admin/products/add'),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Product'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: adminProvider.products.length + (adminProvider.hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == adminProvider.products.length) {
                              // Load more indicator
                              if (adminProvider.isLoadingMore) {
                                return const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              return const SizedBox.shrink();
                            }
                            final product = adminProvider.products[index];
                            return _ProductCard(
                              product: product,
                              currencyFormat: currencyFormat,
                              onDelete: () => _deleteProduct(product),
                              onEdit: () async {
                                final result = await context.push('/admin/products/${product.id}/edit');
                                if (result == true) {
                                  _loadProducts();
                                }
                              },
                              onRefresh: _loadProducts,
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await context.push('/admin/products/add');
          if (result == true) {
            _loadProducts();
          }
        },
        backgroundColor: AppTheme.primaryGreen,
        child: const Icon(Icons.add, color: AppTheme.white),
      ),
    );
  }
}

class _SearchAndFilterSection extends StatefulWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final int? selectedCategoryId;
  final ValueChanged<int?> onCategoryChanged;
  final VoidCallback? onClearFilters;
  final VoidCallback? onSearchCleared;

  const _SearchAndFilterSection({
    required this.searchController,
    required this.searchFocusNode,
    required this.selectedCategoryId,
    required this.onCategoryChanged,
    this.onClearFilters,
    this.onSearchCleared,
  });

  @override
  State<_SearchAndFilterSection> createState() => _SearchAndFilterSectionState();
}

class _SearchAndFilterSectionState extends State<_SearchAndFilterSection> {
  // Build a flat list of all categories (parent + subcategories) for the dropdown
  List<CategoryModel> _buildAllCategories(List<CategoryModel> categories) {
    final List<CategoryModel> allCategories = [];
    
    for (final category in categories) {
      if (category.isActive) {
        // Add parent category
        allCategories.add(category);
        
        // Add subcategories if they exist
        if (category.hasSubcategories) {
          final activeSubcategories = category.subcategories!
              .where((sub) => sub.isActive)
              .toList();
          allCategories.addAll(activeSubcategories);
        }
      }
    }
    
    return allCategories;
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = Provider.of<ProductProvider>(context);
    final topLevelCategories = productProvider.categories.where((c) => c.isActive && c.isTopLevel).toList();
    final allCategories = _buildAllCategories(topLevelCategories);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.searchController,
              builder: (context, value, child) {
                return TextField(
                  controller: widget.searchController,
                  focusNode: widget.searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Search products by name, description...',
                    prefixIcon: const Icon(Icons.search, color: AppTheme.grey),
                    suffixIcon: value.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              widget.searchController.clear();
                              widget.onSearchCleared?.call();
                            },
                          )
                        : null,
                filled: true,
                fillColor: AppTheme.lightGrey.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.lightGrey, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.primaryGreen, width: 2),
                ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                );
              },
            ),
          ),
          // Category Filter and Clear Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                // Category Dropdown
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.lightGrey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.lightGrey),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: widget.selectedCategoryId,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primaryGreen),
                        hint: Row(
                          children: [
                            Icon(Icons.category, size: 18, color: AppTheme.grey),
                            const SizedBox(width: 8),
                            Text(
                              'All Categories',
                              style: TextStyle(color: AppTheme.grey, fontSize: 14),
                            ),
                          ],
                        ),
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Row(
                              children: [
                                Icon(Icons.category, size: 18, color: AppTheme.grey),
                                const SizedBox(width: 8),
                                const Text('All Categories'),
                              ],
                            ),
                          ),
                          ...allCategories.map((category) {
                            final isSubcategory = category.isSubcategory;
                            return DropdownMenuItem<int?>(
                              value: category.id,
                              child: Row(
                                children: [
                                  Icon(
                                    isSubcategory ? Icons.subdirectory_arrow_right : Icons.category,
                                    size: 18,
                                    color: isSubcategory ? AppTheme.grey : AppTheme.primaryGreen,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isSubcategory ? '  ${category.name}' : category.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontStyle: isSubcategory ? FontStyle.italic : FontStyle.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        onChanged: widget.onCategoryChanged,
                      ),
                    ),
                  ),
                ),
                // Clear Filters Button
                  if (widget.onClearFilters != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.clear_all, color: AppTheme.primaryGreen),
                        onPressed: widget.onClearFilters,
                        tooltip: 'Clear all filters',
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final NumberFormat currencyFormat;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback? onRefresh;

  const _ProductCard({
    required this.product,
    required this.currencyFormat,
    required this.onDelete,
    required this.onEdit,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: product.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: product.imageUrl!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 80,
                        height: 80,
                        color: AppTheme.lightGrey,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 80,
                        height: 80,
                        color: AppTheme.lightGrey,
                        child: const Icon(Icons.image, size: 40),
                      ),
                    )
                  : Container(
                      width: 80,
                      height: 80,
                      color: AppTheme.lightGrey,
                      child: const Icon(Icons.image, size: 40),
                    ),
            ),
            const SizedBox(width: 12),
            // Product Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product Name
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.description!,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.grey,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  // Price Row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          currencyFormat.format(product.price),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryGreen,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '/ ${product.unit}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.grey,
                          height: 1.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Availability Row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        product.isAvailable ? Icons.check_circle : Icons.cancel,
                        size: 13,
                        color: product.isAvailable ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        product.isAvailable ? 'Available' : 'Unavailable',
                        style: TextStyle(
                          fontSize: 10,
                          color: product.isAvailable ? Colors.green : Colors.red,
                          height: 1.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  if (product.category != null) ...[
                    const SizedBox(height: 4),
                    Chip(
                      label: Text(
                        product.category!.name,
                        style: const TextStyle(fontSize: 9, height: 1.1),
                        overflow: TextOverflow.ellipsis,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ),
            // Actions - Use Column with mainAxisSize.min
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.inventory_2, color: Colors.orange, size: 20),
                  onPressed: () async {
                      final result = await showDialog<bool>(
                      context: context,
                      builder: (context) => VariantManagementDialog(
                        productId: product.id,
                        productName: product.name,
                      ),
                    );
                    if (result == true && onRefresh != null) {
                      onRefresh!();
                    }
                  },
                  tooltip: 'Manage Variants',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                  onPressed: onEdit,
                  tooltip: 'Edit',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

