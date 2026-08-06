import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../models/product_model.dart';
import '../../models/product_variant_model.dart';
import '../../providers/cart_provider.dart';
import '../../providers/product_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/floating_cart_bar.dart';
import '../../widgets/product_card.dart';
import '../../services/api_service.dart';

class ProductDetailScreen extends StatefulWidget {
  final int productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _quantity = 1;
  ProductVariantModel? _selectedVariant;
  bool _showFullDescription = false;
  ProductModel? _fetchedProduct;
  List<ProductModel> _relatedProducts = [];
  final ScrollController _relatedScrollController = ScrollController();
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = Provider.of<ProductProvider>(context, listen: false);
      final fetched = await provider.fetchProductById(widget.productId);
      if (mounted && fetched != null) {
        setState(() {
          _fetchedProduct = fetched;
          if (fetched.hasVariants && fetched.variants != null && fetched.variants!.isNotEmpty) {
            _selectedVariant = fetched.variants!.firstWhere(
              (v) => v.isDefault,
              orElse: () => fetched.variants!.first,
            );
          }
        });
        // Fetch related products from same category
        _fetchRelatedProducts(fetched);
      }
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _relatedScrollController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_relatedScrollController.hasClients) return;
      final maxScroll = _relatedScrollController.position.maxScrollExtent;
      final currentScroll = _relatedScrollController.offset;
      final nextScroll = currentScroll + 187; // card width + gap
      if (nextScroll >= maxScroll) {
        _relatedScrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      } else {
        _relatedScrollController.animateTo(nextScroll, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      }
    });
  }

  Future<void> _fetchRelatedProducts(ProductModel product) async {
    final categoryId = product.category?.id;
    if (categoryId == null) return;
    try {
      final apiService = ApiService();
      final response = await apiService.get('/products?categoryId=$categoryId');
      final List<dynamic> data = response is List ? response : [];
      final products = data
          .map((json) => ProductModel.fromJson(json as Map<String, dynamic>))
          .where((p) => p.id != widget.productId && p.isAvailable && p.stock > 0)
          .toList();
      if (mounted) {
        setState(() => _relatedProducts = products);
        if (products.isNotEmpty) _startAutoScroll();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = Provider.of<CartProvider>(context);
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return Consumer<ProductProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Scaffold(
            backgroundColor: Color(0xFFF6F6F6),
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
              ),
            ),
          );
        }

        final product = _resolveProduct(provider);
        if (product == null) {
          return Scaffold(
            backgroundColor: const Color(0xFFF6F6F6),
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.info_outline, size: 40, color: Colors.orange),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Product unavailable right now',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      await provider.fetchProductById(widget.productId);
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        // Ensure a default variant is selected
        if (_selectedVariant == null &&
            product.hasVariants &&
            product.variants != null &&
            product.variants!.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedVariant = product.variants!.firstWhere(
                  (v) => v.isDefault,
                  orElse: () => product.variants!.first,
                );
              });
            }
          });
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF6F6F6),
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  onPressed: () => context.pop(),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.share, color: Colors.white, size: 20),
                    onPressed: () {
                      final p = _fetchedProduct;
                      if (p != null) {
                        final price = '₹${p.price.toStringAsFixed(0)}';
                        final unit = p.unit ?? '';
                        final category = p.category?.name ?? '';
                        SharePlus.instance.share(
                          ShareParams(
                            text: '🛒 Check out *${p.name}* on Easy Basket!\n\n💰 Price: $price ${unit.isNotEmpty ? '/ $unit' : ''}\n📦 ${category.isNotEmpty ? 'Category: $category\n' : ''}🚚 Delivery in 5-15 mins\n\nDownload Easy Basket for quick grocery delivery!',
                          ),
                        );
                      }
                    },
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              // Green gradient behind status bar
              Container(
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color.fromARGB(255, 123, 226, 127).withValues(alpha: 0.18),
                      const Color(0xFFF6F6F6),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.6],
                  ),
                ),
              ),
              // Main content
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.only(
                  bottom: cartProvider.itemCount > 0 ? 200 : 110,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero image
                    _buildHeroSection(product),
                    const SizedBox(height: 12),
                    // Product info card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: _buildProductInfoCard(product, currencyFormat),
                    ),
                    const SizedBox(height: 12),
                    // Variant section or single product info
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: () {
                        final usableVariants = product.hasVariants && product.variants != null
                            ? product.variants!.where((v) => v.isAvailable).toList()
                            : <ProductVariantModel>[];
                        if (usableVariants.length > 1) {
                          return _buildVariantSection(product, cartProvider, currencyFormat);
                        }
                        return const SizedBox.shrink();
                      }(),
                    ),
                    Container(height: 0.5, margin: const EdgeInsets.only(top: 12), color: Colors.grey.withValues(alpha: 0.2)),
                    // Features - horizontal scroll pills
                    Padding(
                      padding: const EdgeInsets.only(left: 14, top: 10, bottom: 10),
                      child: _buildInfoCards(),
                    ),
                    Container(height: 0.5, color: Colors.grey.withValues(alpha: 0.2)),
                    const SizedBox(height: 12),
                    // Description
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: _buildDescription(product),
                    ),
                    if (_isDetailsMissing(product)) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: _buildFallbackNotice(),
                      ),
                    ],
                    // You may also like
                    if (_relatedProducts.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(height: 0.5, color: Colors.grey.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      _buildRelatedProducts(product),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
              // Floating Cart Bar
              if (cartProvider.itemCount > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 100,
                  child: const FloatingCartBar(),
                ),
              // Sticky CTA
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildStickyCta(product, cartProvider, currencyFormat),
              ),
            ],
          ),
        );
      },
    );
  }

  ProductModel? _resolveProduct(ProductProvider provider) {
    if (_fetchedProduct != null) return _fetchedProduct;
    if (provider.products.isEmpty) return null;
    try {
      return provider.products.firstWhere((p) => p.id == widget.productId);
    } catch (_) {
      return provider.products.first;
    }
  }

  // ── Hero Section ──
  Widget _buildHeroSection(ProductModel product) {
    final hasImage = product.imageUrl != null && product.imageUrl!.isNotEmpty;
    final topPadding = MediaQuery.of(context).padding.top;

    return SizedBox(
      height: 340 + topPadding,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Full-width image (edge-to-edge, no rounded corners)
          if (hasImage)
            CachedNetworkImage(
              imageUrl: product.imageUrl!,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: const Color(0xFFF0F0F0),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFFF0F0F0),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image_outlined, size: 48, color: AppTheme.grey),
                    SizedBox(height: 8),
                    Text('Image unavailable', style: TextStyle(color: AppTheme.grey)),
                  ],
                ),
              ),
            )
          else
            Container(
              color: AppTheme.primaryGreen.withValues(alpha: 0.06),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, size: 72, color: AppTheme.grey),
                    SizedBox(height: 8),
                    Text('Image not available', style: TextStyle(color: AppTheme.grey, fontSize: 14)),
                  ],
                ),
              ),
            ),
          // Bottom gradient overlay for text readability
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 120,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),
          // Product name + rating overlay
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name.isNotEmpty ? product.name : 'Product',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                    const SizedBox(width: 4),
                    const Text(
                      '4.7',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• 1.2k reviews',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Product Info Card ──
  Widget _buildProductInfoCard(ProductModel product, NumberFormat currencyFormat) {
    final bool hasVariants = _hasUsableVariants(product);
    final List<ProductVariantModel> availableVariants = hasVariants
        ? product.variants!.where((v) => v.isAvailable).toList()
        : <ProductVariantModel>[];
    final double displayPrice = hasVariants && availableVariants.isNotEmpty
        ? (_selectedVariant?.price ?? availableVariants.first.price)
        : product.price;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product name
          Text(
            product.name.isNotEmpty ? product.name : 'Product',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          // Price row
          Row(
            children: [
              Text(
                currencyFormat.format(displayPrice),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: product.stock > 0 ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  product.stock > 0 ? 'In stock' : 'Limited',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: product.stock > 0 ? AppTheme.primaryGreen : Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Divider
          Container(height: 0.5, color: Colors.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 6),
          // Info rows
          Row(
            children: [
              const Icon(Icons.category_outlined, size: 15, color: AppTheme.primaryGreen),
              const SizedBox(width: 6),
              Text(
                product.category?.name ?? 'Grocery',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(Icons.delivery_dining_outlined, size: 15, color: Colors.orange),
              const SizedBox(width: 6),
              const Text('Delivery in 5–15 mins', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black)),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(Icons.eco_outlined, size: 15, color: AppTheme.primaryGreen),
              const SizedBox(width: 6),
              Text(
                product.stock > 20 ? 'Always fresh' : 'Restocking soon',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Variant Section ──
  Widget _buildVariantSection(
    ProductModel product,
    CartProvider cartProvider,
    NumberFormat currencyFormat,
  ) {
    final variants = product.variants!.where((v) => v.isAvailable).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select Quantity', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black)),
        const SizedBox(height: 8),
        Row(
          children: variants.map((variant) {
            final isSelected = _selectedVariant?.id == variant.id;

            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedVariant = variant),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isSelected ? const Color(0xFF0C831F) : Colors.white,
                    border: Border.all(
                      color: isSelected ? const Color(0xFF0C831F) : const Color(0xFFD0D0D0),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          variant.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 3),
                        const Icon(Icons.check, color: Colors.white, size: 14),
                      ],
                      if (!isSelected) ...[
                        const SizedBox(width: 4),
                        Text(
                          currencyFormat.format(variant.price),
                          style: const TextStyle(fontSize: 11, color: AppTheme.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Highlights Row ──
  // ── Description ──
  Widget _buildDescription(ProductModel product) {
    final description = (product.description != null && product.description!.trim().isNotEmpty)
        ? product.description!
        : 'Fresh groceries delivered quickly.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info, size: 22, color: AppTheme.grey),
              const SizedBox(width: 8),
              const Text('About this product', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black)),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _showFullDescription = !_showFullDescription),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    description,
                    style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                    maxLines: _showFullDescription ? null : 2,
                    overflow: _showFullDescription ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _showFullDescription ? 'Show less' : 'Read more \u2192',
                  style: const TextStyle(color: Color(0xFF0C831F), fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Features Section (horizontal scroll pills) ──
  Widget _buildInfoCards() {
    final items = [
      (Icons.delivery_dining_outlined, 'Fast delivery', AppTheme.primaryGreen),
      (Icons.shield_outlined, 'Safe packaging', Colors.blue),
      (Icons.verified_outlined, 'Trusted quality', Colors.orange),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.$1, size: 18, color: item.$3),
                const SizedBox(width: 6),
                Text(item.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Fallback Notice ──
  Widget _buildFallbackNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_outline, color: AppTheme.grey, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Some details are missing for this product. You can still add it to cart.',
              style: TextStyle(fontSize: 12, color: AppTheme.darkGrey),
            ),
          ),
        ],
      ),
    );
  }

  // ── You May Also Like ──
  Widget _buildRelatedProducts(ProductModel product) {
    final parentCategoryId = product.category?.parentCategoryId ?? product.category?.id;
    final parentCategoryName = product.category?.parentCategory?.name ?? product.category?.name ?? 'Category';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const Text(
                'You may also like',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  if (parentCategoryId != null) {
                    context.push('/categories/$parentCategoryId/products', extra: {
                      'parentCategoryName': parentCategoryName,
                    });
                  }
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View All',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0C831F)),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFF0C831F)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 240,
          child: ListView.separated(
            controller: _relatedScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            itemCount: _relatedProducts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return SizedBox(
                width: 175,
                child: ProductCard(product: _relatedProducts[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Sticky CTA ──
  Widget _buildStickyCta(
    ProductModel product,
    CartProvider cartProvider,
    NumberFormat currencyFormat,
  ) {
    final bool hasVariants = _hasUsableVariants(product);
    final List<ProductVariantModel> availableVariants = hasVariants
        ? product.variants!.where((v) => v.isAvailable).toList()
        : <ProductVariantModel>[];
    final ProductVariantModel? activeVariant = hasVariants
        ? (_selectedVariant ??
            (availableVariants.isNotEmpty ? availableVariants.first : product.variants!.first))
        : null;

    final int variantQuantity = hasVariants && activeVariant != null
        ? (cartProvider.contains(product.id, variantId: activeVariant.id)
            ? cartProvider.getQuantity(product.id, variantId: activeVariant.id)
            : 0)
        : 0;

    final bool isOutOfStock = hasVariants
        ? (activeVariant == null || activeVariant.stock <= 0)
        : (!product.isAvailable || product.stock <= 0);

    final double displayPrice = hasVariants && activeVariant != null
        ? activeVariant.price
        : product.price;

    final String sizeLabel = hasVariants && activeVariant != null
        ? activeVariant.label
        : _nonVariantLabel(product);

    final bool nonVariantInCart = !hasVariants && cartProvider.contains(product.id);
    final int nonVariantQty = !hasVariants ? cartProvider.getQuantity(product.id) : 0;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Row(
          children: [
            // Left — price info
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currencyFormat.format(displayPrice),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
                ),
                const SizedBox(height: 2),
                Text(
                  sizeLabel.isNotEmpty ? sizeLabel : product.name,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.grey),
                ),
              ],
            ),
            const Spacer(),
            // Right — action button
            if (isOutOfStock)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Out of stock',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 14),
                ),
              )
            else if (hasVariants && activeVariant != null)
              variantQuantity > 0
                  ? _buildQuantitySelector(
                      quantity: variantQuantity,
                      onDecrement: () async {
                        if (variantQuantity > 1) {
                          await cartProvider.updateQuantity(product.id, variantQuantity - 1, variantId: activeVariant.id);
                        } else {
                          await cartProvider.removeItem(product.id, variantId: activeVariant.id);
                        }
                        if (context.mounted) setState(() {});
                      },
                      onIncrement: variantQuantity < activeVariant.stock
                          ? () async {
                              await cartProvider.updateQuantity(product.id, variantQuantity + 1, variantId: activeVariant.id);
                              if (context.mounted) setState(() {});
                            }
                          : null,
                    )
                  : _buildAddToCartButton(
                      onPressed: () async {
                        await cartProvider.addItem(product, variant: activeVariant);
                        if (context.mounted) setState(() => _selectedVariant = activeVariant);
                      },
                    )
            else if (!hasVariants)
              nonVariantQty > 0
                  ? _buildQuantitySelector(
                      quantity: nonVariantQty,
                      onDecrement: () async {
                        if (nonVariantQty > 1) {
                          await cartProvider.updateQuantity(product.id, nonVariantQty - 1);
                        } else {
                          await cartProvider.removeItem(product.id);
                        }
                        setState(() => _quantity = nonVariantQty > 1 ? nonVariantQty - 1 : 1);
                      },
                      onIncrement: nonVariantQty < product.stock
                          ? () async {
                              await cartProvider.updateQuantity(product.id, nonVariantQty + 1);
                              setState(() => _quantity = nonVariantQty + 1);
                            }
                          : null,
                    )
                  : _buildAddToCartButton(
                      onPressed: () async {
                        await cartProvider.addItem(product);
                        setState(() => _quantity = cartProvider.getQuantity(product.id));
                      },
                    )
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  // ── Quantity Selector (dark green gradient) ──
  Widget _buildQuantitySelector({
    required int quantity,
    required VoidCallback onDecrement,
    VoidCallback? onIncrement,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A5C18), Color(0xFF1B8A2E), Color(0xFF0A5C18)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onDecrement,
            child: Container(
              width: 40,
              height: 44,
              alignment: Alignment.center,
              child: const Text('–', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 32),
            alignment: Alignment.center,
            child: Text(
              quantity.toString(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
          GestureDetector(
            onTap: onIncrement,
            child: Container(
              width: 40,
              height: 44,
              alignment: Alignment.center,
              child: Text(
                '+',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: onIncrement != null ? Colors.white : Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Add to Cart Button (light green gradient with green border) ──
  Widget _buildAddToCartButton({required VoidCallback onPressed}) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8F5E9), Colors.white, Color(0xFFE8F5E9)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0C831F), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          splashColor: const Color(0xFF0C831F).withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.shopping_cart_outlined, size: 18, color: Color(0xFF0C831F)),
                SizedBox(width: 8),
                Text(
                  'Add to cart',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0C831F)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Footer ──
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
      color: AppTheme.lightGrey.withValues(alpha: 0.15),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTrustBadge(icon: Icons.verified_user_outlined, text: '100% Genuine'),
              _buildTrustBadge(icon: Icons.local_shipping_outlined, text: 'Fast Delivery'),
              _buildTrustBadge(icon: Icons.refresh_outlined, text: 'Easy Returns'),
            ],
          ),
          const SizedBox(height: 6),
          Divider(color: AppTheme.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 6),
          const Text(
            'Live for food, delivered by Easy Basket',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.grey, letterSpacing: 0.5, fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Made with ', style: TextStyle(fontSize: 12, color: AppTheme.grey)),
              Icon(Icons.favorite, color: Colors.red, size: 14),
              Text(' in India', style: TextStyle(fontSize: 12, color: AppTheme.grey)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Easy Basket \u00A9 ${DateTime.now().year}',
            style: TextStyle(fontSize: 12, color: AppTheme.grey.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustBadge({required IconData icon, required String text}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade200, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 14,
                spreadRadius: 1,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Icon(icon, color: AppTheme.primaryGreen, size: 20),
        ),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.darkGrey)),
      ],
    );
  }

  // ── Helpers ──
  String _nonVariantLabel(ProductModel product) {
    final name = product.name;
    final bracketMatch = RegExp(r'\(([^)]+)\)$').firstMatch(name);
    if (bracketMatch != null) {
      final content = bracketMatch.group(1)!.trim();
      if (content.isNotEmpty) return content;
    }
    if (product.minQuantity != null && product.unit != null) {
      final q = product.minQuantity!;
      final qStr = q % 1 == 0 ? q.toInt().toString() : q.toString();
      return '$qStr ${product.unit}';
    }
    if (product.unit != null) return '1 ${product.unit}';
    return '';
  }

  bool _isDetailsMissing(ProductModel product) {
    final hasImage = product.imageUrl != null && product.imageUrl!.isNotEmpty;
    final hasDescription = product.description != null && product.description!.trim().isNotEmpty;
    return !hasImage || !hasDescription;
  }

  bool _hasUsableVariants(ProductModel product) {
    return product.hasVariants &&
        product.variants != null &&
        product.variants!.isNotEmpty &&
        product.variants!.any((v) => v.isAvailable);
  }
}
