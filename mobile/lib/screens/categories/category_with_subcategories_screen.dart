import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/category_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/product_card.dart';
import '../../widgets/floating_cart_bar.dart';
import '../../utils/theme.dart';
import '../../utils/responsive.dart';
import '../../l10n/app_localizations.dart';

class CategoryWithSubcategoriesScreen extends StatefulWidget {
  final int parentCategoryId;
  final String parentCategoryName;

  const CategoryWithSubcategoriesScreen({
    super.key,
    required this.parentCategoryId,
    required this.parentCategoryName,
  });

  @override
  State<CategoryWithSubcategoriesScreen> createState() => _CategoryWithSubcategoriesScreenState();
}

class _CategoryWithSubcategoriesScreenState extends State<CategoryWithSubcategoriesScreen> {
  List<CategoryModel> _subcategories = [];
  int? _selectedSubcategoryId;
  bool _isLoadingSubcategories = true;
  bool _isLoadingProducts = false;

  @override
  void initState() {
    super.initState();
    _loadSubcategories();
  }

  Future<void> _loadSubcategories() async {
    setState(() => _isLoadingSubcategories = true);
    
    final provider = Provider.of<ProductProvider>(context, listen: false);
    
    try {
      debugPrint('🔄 Loading subcategories for parent category ID: ${widget.parentCategoryId}');
      final endpoint = '/categories/${widget.parentCategoryId}/subcategories';
      debugPrint('📡 API endpoint: $endpoint');
      
      final response = await provider.apiService.get(endpoint);
      
      debugPrint('📦 Raw API response type: ${response.runtimeType}');
      debugPrint('📦 Raw API response: $response');
      
      if (response is Map<String, dynamic>) {
        debugPrint('✅ Response is Map');
        debugPrint('📋 Response keys: ${response.keys.toList()}');
        
        if (response.containsKey('subcategories')) {
          final List<dynamic>? data = response['subcategories'] as List<dynamic>?;
          debugPrint('✅ Found subcategories key, data type: ${data.runtimeType}');
          debugPrint('📊 Subcategories count: ${data?.length ?? 0}');
          
          if (data != null && data.isNotEmpty) {
            debugPrint('📝 Parsing ${data.length} subcategories...');
            final parsed = <CategoryModel>[];
            
            for (var item in data) {
              try {
                if (item is Map<String, dynamic>) {
                  final subcategory = CategoryModel.fromJson(item);
                  parsed.add(subcategory);
                  debugPrint('  ✅ Parsed: ${subcategory.name} (ID: ${subcategory.id})');
                } else {
                  debugPrint('  ❌ Item is not Map: ${item.runtimeType}');
                }
              } catch (e) {
                debugPrint('  ❌ Error parsing subcategory: $e');
                debugPrint('  📄 Item data: $item');
              }
            }
            
            debugPrint('✅ Successfully parsed ${parsed.length} subcategories');
            
            setState(() {
              _subcategories = parsed;
              _isLoadingSubcategories = false;
              
              // Auto-select first subcategory if available
              if (_subcategories.isNotEmpty) {
                _selectedSubcategoryId = _subcategories.first.id;
                debugPrint('🎯 Auto-selected first subcategory: ${_subcategories.first.name} (ID: ${_subcategories.first.id})');
                _loadProducts(_subcategories.first.id);
              } else {
                debugPrint('⚠️ No subcategories after parsing, loading parent products');
                _selectedSubcategoryId = null;
                _loadProducts(widget.parentCategoryId);
              }
            });
          } else {
            debugPrint('⚠️ Subcategories array is empty or null');
            setState(() {
              _subcategories = [];
              _isLoadingSubcategories = false;
              _selectedSubcategoryId = null;
              _loadProducts(widget.parentCategoryId);
            });
          }
        } else {
          debugPrint('❌ Response does not contain "subcategories" key');
          debugPrint('📋 Available keys: ${response.keys.toList()}');
          setState(() {
            _subcategories = [];
            _isLoadingSubcategories = false;
            _selectedSubcategoryId = null;
            _loadProducts(widget.parentCategoryId);
          });
        }
      } else {
        debugPrint('❌ Response is not a Map, it is: ${response.runtimeType}');
        setState(() {
          _subcategories = [];
          _isLoadingSubcategories = false;
          _selectedSubcategoryId = null;
          _loadProducts(widget.parentCategoryId);
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading subcategories: $e');
      debugPrint('📚 Stack trace: $stackTrace');
      setState(() {
        _subcategories = [];
        _isLoadingSubcategories = false;
        _selectedSubcategoryId = null;
        _loadProducts(widget.parentCategoryId);
      });
    }
  }

  Future<void> _loadProducts(int categoryId) async {
    setState(() => _isLoadingProducts = true);
    final provider = Provider.of<ProductProvider>(context, listen: false);
    await provider.fetchProducts(categoryId: categoryId);
    setState(() => _isLoadingProducts = false);
  }

  void _onSubcategorySelected(int subcategoryId) {
    setState(() {
      _selectedSubcategoryId = subcategoryId;
    });
    _loadProducts(subcategoryId);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = Responsive(context);
    final isMobile = MediaQuery.of(context).size.width < 600;
    final cartProvider = Provider.of<CartProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          widget.parentCategoryName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _isLoadingSubcategories
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                    ),
                  )
                : _subcategories.isEmpty
                    ? _buildProductsOnlyView(cartProvider)
                    : _buildSideBySideView(isMobile, cartProvider),
          ),
          // Floating Cart Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: const FloatingCartBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsOnlyView(CartProvider cartProvider) {
    final provider = Provider.of<ProductProvider>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Column(
      children: [
        // Products grid - No search bar for cleaner UI
        Expanded(
          child: _isLoadingProducts
              ? const Center(child: CircularProgressIndicator())
              : provider.products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_bag_outlined, size: 64, color: AppTheme.grey),
                          const SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(context).productNoneFound,
                            style: TextStyle(
                              fontSize: 18,
                              color: AppTheme.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadProducts(widget.parentCategoryId),
                      child: GridView.builder(
                        padding: EdgeInsets.only(
                          left: screenWidth < 360 ? 8 : 12,
                          right: screenWidth < 360 ? 8 : 12,
                          top: screenWidth < 360 ? 8 : 12,
                          // ~1/4 of screen height below the last card → cart bar never
                          // overlaps and the user gets visual breathing room.
                          bottom: MediaQuery.of(context).size.height / 4,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          // More granular aspect ratio for better text rendering on small screens
                          childAspectRatio: screenWidth < 360 ? 0.52 : screenWidth < 400 ? 0.54 : 0.56,
                          crossAxisSpacing: screenWidth < 360 ? 8 : 12,
                          mainAxisSpacing: screenWidth < 360 ? 8 : 12,
                        ),
                        itemCount: provider.products.length,
                        itemBuilder: (context, index) {
                          return ProductCard(product: provider.products[index]);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildSideBySideView(bool isMobile, CartProvider cartProvider) {
    // Blinkit-style: Side-by-side layout for both mobile and desktop
    // Mobile: Compact sidebar to give more space to products
    final sidebarWidth = isMobile ? 80.0 : 200.0;
    
    return Row(
      children: [
        // Left sidebar - Subcategories with images (Blinkit style)
        Container(
          width: sidebarWidth,
          decoration: BoxDecoration(
            color: AppTheme.lightGrey.withOpacity(0.3),
            border: Border(
              right: BorderSide(color: AppTheme.lightGrey, width: 1),
            ),
          ),
          child: Column(
            children: [
              // Subcategories list with images
              Expanded(
                child: ListView.builder(
                  itemCount: _subcategories.length,
                  itemBuilder: (context, index) {
                    final subcategory = _subcategories[index];
                    final isSelected = _selectedSubcategoryId == subcategory.id;
                    
                    return InkWell(
                      onTap: () => _onSubcategorySelected(subcategory.id),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 4 : 8,
                          vertical: isMobile ? 6 : 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryGreen
                              : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(color: AppTheme.lightGrey, width: 1),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Subcategory Image - More compact
                            Container(
                              width: isMobile ? 40 : 50,
                              height: isMobile ? 40 : 50,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withOpacity(0.2)
                                    : AppTheme.primaryGreen.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
                              ),
                              child: subcategory.imageUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(isMobile ? 6 : 10),
                                      child: CachedNetworkImage(
                                        imageUrl: subcategory.imageUrl!,
                                        width: isMobile ? 40 : 50,
                                        height: isMobile ? 40 : 50,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => Container(
                                          color: AppTheme.primaryGreen.withOpacity(0.1),
                                          child: Center(
                                            child: SizedBox(
                                              width: isMobile ? 16 : 20,
                                              height: isMobile ? 16 : 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  isSelected ? Colors.white : AppTheme.primaryGreen,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        errorWidget: (context, url, error) => Icon(
                                      Icons.category,
                                      size: isMobile ? 20 : 24,
                                      color: isSelected ? Colors.white : AppTheme.primaryGreen,
                                    ),
                                        fadeInDuration: const Duration(milliseconds: 300),
                                      ),
                                    )
                                  : Icon(
                                      Icons.category,
                                      size: isMobile ? 20 : 24,
                                      color: isSelected ? Colors.white : AppTheme.primaryGreen,
                                    ),
                            ),
                            if (!isMobile) ...[
                              const SizedBox(height: 6),
                              Flexible(
                                child: Text(
                                  subcategory.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.white
                                        : AppTheme.black,
                                    height: 1.2,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            // Mobile: Show name below image in smaller text - More compact
                            if (isMobile) ...[
                              const SizedBox(height: 2),
                              Flexible(
                                child: Text(
                                  subcategory.name,
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.white
                                        : AppTheme.black,
                                    height: 1.0,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Right side - Products (no search bar for cleaner UI)
        Expanded(
          child: _buildProductsGrid(showSearchBar: false, cartProvider: cartProvider),
        ),
      ],
    );
  }


  Widget _buildProductsGrid({bool showSearchBar = true, CartProvider? cartProvider}) {
    final provider = Provider.of<ProductProvider>(context);
    final responsive = Responsive(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    // Adjust grid columns based on available width (accounting for sidebar)
    final sidebarWidth = isMobile ? 80.0 : 200.0;
    final availableWidth = screenWidth - sidebarWidth;
    final crossAxisCount = isMobile 
        ? 2 
        : (availableWidth < 600 ? 2 : (availableWidth < 900 ? 3 : 4));
    
    return _isLoadingProducts
        ? const Center(child: CircularProgressIndicator())
        : provider.products.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_bag_outlined, size: 64, color: AppTheme.grey),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context).productNoneFound,
                      style: TextStyle(
                        fontSize: 18,
                        color: AppTheme.grey,
                      ),
                    ),
                  ],
                ),
              )
            : NotificationListener<ScrollNotification>(
                // Bottom ke paas pahunche → next page load karo
                onNotification: (scrollInfo) {
                  if (scrollInfo is ScrollEndNotification &&
                      scrollInfo.metrics.extentAfter < 200) {
                    if (provider.hasMore && !provider.isLoadingMore) {
                      provider.loadMoreProducts();
                    }
                  }
                  return false;
                },
                child: RefreshIndicator(
                  onRefresh: () {
                    final categoryId = _selectedSubcategoryId ?? (_subcategories.isNotEmpty ? _subcategories.first.id : widget.parentCategoryId);
                    return _loadProducts(categoryId);
                  },
                  child: GridView.builder(
                    padding: EdgeInsets.only(
                      left: screenWidth < 360 ? 8 : 12,
                      right: screenWidth < 360 ? 8 : 12,
                      top: screenWidth < 360 ? 8 : 12,
                      // ~1/4 of screen height below the last card.
                      bottom: MediaQuery.of(context).size.height / 4,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: screenWidth < 360 ? 0.52 : screenWidth < 400 ? 0.54 : 0.56,
                      crossAxisSpacing: screenWidth < 360 ? 8 : 12,
                      mainAxisSpacing: screenWidth < 360 ? 8 : 12,
                    ),
                    // +1 for loading indicator at bottom
                    itemCount: provider.products.length + (provider.isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= provider.products.length) {
                        // Loading indicator at bottom
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                            ),
                          ),
                        );
                      }
                      return ProductCard(product: provider.products[index]);
                    },
                  ),
                ),
              );
  }
}

