import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/product_model.dart';
import '../providers/cart_provider.dart';
import '../utils/theme.dart';
import '../utils/responsive.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';

class ProductCard extends StatelessWidget {
  final ProductModel product;

  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final cartProvider = Provider.of<CartProvider>(context);
    // For products with variants, check if any variant is in cart
    final isInCart = product.hasVariants && product.variants != null && product.variants!.isNotEmpty
        ? product.variants!.any((v) => cartProvider.contains(product.id, variantId: v.id))
        : cartProvider.contains(product.id);
    final quantity = isInCart 
        ? (product.hasVariants && product.variants != null && product.variants!.isNotEmpty
            ? product.variants!.fold<int>(0, (sum, v) => sum + cartProvider.getQuantity(product.id, variantId: v.id))
            : cartProvider.getQuantity(product.id))
        : 0;
    final isAdding = cartProvider.isAddingItem(product.id);
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final responsive = Responsive(context);
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Responsive font sizes - no fixed height, let grid control it
    final fontSize = screenWidth < 360 ? 11.0 : screenWidth < 400 ? 12.0 : 13.0;
    final nameFontSize = screenWidth < 360 ? 12.0 : screenWidth < 400 ? 13.0 : 14.0;
    final priceFontSize = screenWidth < 360 ? 14.0 : screenWidth < 400 ? 15.0 : 16.0;
    final buttonFontSize = screenWidth < 360 ? 10.0 : screenWidth < 400 ? 11.0 : 12.0;

    // Calculate discount percentage (if originalPrice exists, otherwise use placeholder)
    final discountPercent = _calculateDiscount();
    final hasDiscount = discountPercent > 0;
    
    // Get variant count
    final variantCount = product.hasVariants && product.variants != null 
        ? product.variants!.where((v) => v.isAvailable).length 
        : 0;

    // Check if product is out of stock
    final isOutOfStock = !product.isAvailable || 
        ((product.hasVariants && product.variants != null && !product.variants!.any((v) => v.isAvailable && v.stock > 0)) ||
         (!product.hasVariants && product.stock <= 0));

    return GestureDetector(
      onTap: () => context.push('/product/${product.id}'),
      child: Container(
        // Remove fixed height - let grid's aspect ratio control it
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              spreadRadius: 2,
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Main content
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                    // Image Section with Discount Badge - Use Expanded with flex
                    Expanded(
                      flex: 58, // 58% for image
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: product.imageUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: product.imageUrl!,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.center,
                                      placeholder: (context, url) => Container(
                                        color: const Color(0xFFF8F8F8),
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        color: const Color(0xFFF8F8F8),
                                        child: Icon(Icons.image, size: responsive.iconSize(40), color: AppTheme.grey),
                                      ),
                                      fadeInDuration: const Duration(milliseconds: 300),
                                      fadeOutDuration: const Duration(milliseconds: 100),
                                    )
                                  : Container(
                                      color: const Color(0xFFF8F8F8),
                                      child: Icon(Icons.image, size: responsive.iconSize(40), color: AppTheme.grey),
                                    ),
                            ),
                          ),
                          // Discount Badge
                          if (hasDiscount)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0C831F), // Blinkit green
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${discountPercent.toStringAsFixed(0)}% OFF',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Content Section
                    Expanded(
                      flex: 42, // 42% for content
                      child: ClipRect(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: screenWidth < 360 ? 8.0 : 10.0,
                            right: screenWidth < 360 ? 5.0 : 6.0,
                            top: 1,
                            bottom: 6,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Product Name
                              _buildProductName(nameFontSize, screenWidth),
                              const SizedBox(height: 1),
                              // Weight/Unit Display - Optional, can be removed if space is tight
                              if (product.unit != null || (product.hasVariants && product.variants != null && product.variants!.isNotEmpty))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Text(
                                    _getWeightDisplay(),
                                    style: TextStyle(
                                      fontSize: screenWidth < 360 ? 9.0 : 10.0,
                                      color: AppTheme.darkGrey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              // Price and ADD Button in same row (Blinkit style) - Saves space
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Price on the left - Flexible to prevent overflow
                                  Flexible(
                                    flex: 2,
                                    child: _buildPriceDisplay(product, currencyFormat, priceFontSize, hasDiscount),
                                  ),
                                  SizedBox(width: screenWidth < 360 ? 2 : 3),
                                  // ADD Button or Quantity Selector on the right
                                  quantity > 0
                                      ? _buildQuantitySelector(context, cartProvider, quantity, responsive, screenWidth)
                                      : _buildAddButton(context, cartProvider, isAdding, buttonFontSize, screenWidth, variantCount),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              // Grey overlay for out of stock products
              if (isOutOfStock)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              // Out of Stock Banner
              if (isOutOfStock)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child:  Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.block, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          AppLocalizations.of(context).productOutOfStockCaps,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Calculate discount percentage (placeholder - can be enhanced with originalPrice field)
  int _calculateDiscount() {
    // For now, return 0. In future, if product has originalPrice field:
    // if (product.originalPrice != null && product.originalPrice! > product.price) {
    //   return ((product.originalPrice! - product.price) / product.originalPrice! * 100).round();
    // }
    return 0; // Placeholder - no discount by default
  }

  // Build product name - Consistent dark color (Blinkit style) with proper ellipsis
  Widget _buildProductName(double fontSize, double screenWidth) {
    final name = product.name;

    return Text(
      name,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: AppTheme.black,
        height: 1.1, // Tighter line height for better fit
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      softWrap: true, // Enable text wrapping
    );
  }

  // Get weight/unit display
  String _getWeightDisplay() {
    if (product.hasVariants && product.variants != null && product.variants!.isNotEmpty) {
      final availableVariants = product.variants!.where((v) => v.isAvailable).toList();
      if (availableVariants.isNotEmpty) {
        availableVariants.sort((a, b) {
          final priceComp = a.price.compareTo(b.price);
          if (priceComp != 0) return priceComp;
          return a.quantity.compareTo(b.quantity);
        });
        return availableVariants.first.label;
      }
    }
    // No variants: try to infer quantity from product name "(...)" or minQuantity
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

  // Build price display with original price if discounted
  Widget _buildPriceDisplay(ProductModel product, NumberFormat currencyFormat, double fontSize, bool hasDiscount) {
    if (product.hasVariants && product.variants != null && product.variants!.isNotEmpty) {
      // Get available variants
      final availableVariants = product.variants!.where((v) => v.isAvailable).toList();
      if (availableVariants.isNotEmpty) {
        // Sort by price to get min
        availableVariants.sort((a, b) => a.price.compareTo(b.price));
        final minPrice = availableVariants.first.price;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                currencyFormat.format(minPrice),
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ),
            if (hasDiscount)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  currencyFormat.format(minPrice * 1.2),
                  style: TextStyle(
                    fontSize: fontSize - 3,
                    color: AppTheme.grey,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
          ],
        );
      }
    }
    
    // No variants - show base price
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            currencyFormat.format(product.price),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryGreen,
            ),
          ),
        ),
        if (hasDiscount)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              currencyFormat.format(product.price * 1.2), // Placeholder original price
              style: TextStyle(
                fontSize: fontSize - 3,
                color: AppTheme.grey,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ),
      ],
    );
  }

  // Build ADD button with Blinkit style - Positioned on the side (bottom-right)
  Widget _buildAddButton(
    BuildContext context,
    CartProvider cartProvider,
    bool isAdding,
    double buttonFontSize,
    double screenWidth,
    int variantCount,
  ) {
    final isAvailable = product.isAvailable && 
        ((product.hasVariants && product.variants != null && product.variants!.any((v) => v.isAvailable && v.stock > 0)) ||
         (!product.hasVariants && product.stock > 0));
    
    // ADD button sizing - compact width
    final buttonWidth = variantCount > 1
        ? (screenWidth < 360 ? 58.0 : 66.0)
        : (screenWidth < 360 ? 52.0 : 60.0);
    final buttonHeight = screenWidth < 360 ? 26.0 : 30.0;

    return Container(
      width: buttonWidth,
      height: buttonHeight,
      margin: const EdgeInsets.only(right: 2, bottom: 4),
      decoration: BoxDecoration(
        gradient: isAvailable && !isAdding
            ? const LinearGradient(
                colors: [
                  Color(0xFFE8F5E9),  // light green
                  Colors.white,       // white (middle)
                  Color(0xFFE8F5E9),  // light green
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [0.0, 0.5, 1.0],
              )
            : null,
        color: isAvailable && !isAdding ? null : AppTheme.grey.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: isAvailable && !isAdding
            ? Border.all(color: const Color(0xFF0C831F), width: 1.5)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          hoverColor: const Color(0xFF0C831F).withValues(alpha: 0.08),
          splashColor: const Color(0xFF0C831F).withValues(alpha: 0.15),
          highlightColor: const Color(0xFF0C831F).withValues(alpha: 0.05),
          onTap: (isAvailable && !isAdding)
              ? () async {
                  if (product.hasVariants && product.variants != null && product.variants!.isNotEmpty) {
                    final availableVariants = product.variants!
                        .where((v) => v.isAvailable && v.stock > 0)
                        .toList();
                    if (availableVariants.length == 1) {
                      await cartProvider.addItem(product, variant: availableVariants.first);
                    } else {
                      await _showVariantBottomSheet(context);
                    }
                  } else {
                    await cartProvider.addItem(product);
                  }
                }
              : null,
          borderRadius: BorderRadius.circular(10),
      child: Container(
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: isAdding
            ? SizedBox(
                height: screenWidth < 360 ? 14 : 16,
                width: screenWidth < 360 ? 14 : 16,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C831F)),
                ),
              )
            : variantCount > 1
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          AppLocalizations.of(context).productAdd,
                          style: TextStyle(
                            fontSize: screenWidth < 360 ? 11 : 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0C831F),
                            height: 1.0,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '$variantCount options',
                          style: TextStyle(
                            fontSize: screenWidth < 360 ? 8.5 : 9.5,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF0C831F).withValues(alpha: 0.8),
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  )
                : Text(
                    AppLocalizations.of(context).productAdd,
                    style: TextStyle(
                      fontSize: screenWidth < 360 ? 12 : 13,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0C831F),
                      letterSpacing: 0.3,
                    ),
                  ),
      ),
        ),
      ),
    );
  }

  // Compact integrated quantity selector - All in one green container
  Widget _buildQuantitySelector(
    BuildContext context,
    CartProvider cartProvider,
    int quantity,
    Responsive responsive,
    double screenWidth,
  ) {
    final variantCount = product.hasVariants && product.variants != null
        ? product.variants!.where((v) => v.isAvailable).length
        : 0;
    // For products with variants, we can't increment from card - need to go to detail page
    final canIncrement = (!product.hasVariants && quantity < product.stock && product.isAvailable) ||
        (product.hasVariants && variantCount == 1);
    final canDecrement = quantity > 0;
    
    // Sizing matched to ADD button height, wider to expand from left
    final height = screenWidth < 360 ? 26.0 : 30.0;
    final iconSize = screenWidth < 360 ? 12.0 : screenWidth < 400 ? 14.0 : 16.0;
    final fontSize = screenWidth < 360 ? 11.0 : screenWidth < 400 ? 12.0 : 13.0;
    final buttonWidth = screenWidth < 360 ? 22.0 : screenWidth < 400 ? 24.0 : 26.0;
    final horizontalPadding = screenWidth < 360 ? 3.0 : screenWidth < 400 ? 4.0 : 6.0;
    final maxWidth = screenWidth < 360 ? 80.0 : screenWidth < 400 ? 88.0 : 96.0;

    return Container(
      height: height,
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0A5C18),  // dark green
            Color(0xFF1B8A2E),  // lighter green (middle)
            Color(0xFF0A5C18),  // dark green
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Minus button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                if (product.hasVariants && product.variants != null && product.variants!.isNotEmpty) {
                  if (variantCount > 1) {
                    await _showVariantBottomSheet(context);
                    return;
                  }
                  // Single variant: update directly
                  final v = product.variants!.firstWhere((vv) => vv.isAvailable, orElse: () => product.variants!.first);
                  if (quantity > 1) {
                    await cartProvider.updateQuantity(product.id, quantity - 1, variantId: v.id);
                  } else {
                    await cartProvider.removeItem(product.id, variantId: v.id);
                  }
                } else {
                  if (quantity > 1) {
                    await cartProvider.updateQuantity(product.id, quantity - 1);
                  } else {
                    // Remove item when quantity becomes 0
                    await cartProvider.removeItem(product.id);
                  }
                }
              },
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                bottomLeft: Radius.circular(6),
              ),
              child: Container(
                width: buttonWidth,
                height: height,
                alignment: Alignment.center,
                child: Text(
                  '-',
                  style: TextStyle(
                    fontSize: iconSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
          // Quantity display
          Container(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            constraints: BoxConstraints(minWidth: screenWidth < 360 ? 14 : 16),
            child: Text(
              quantity.toString(),
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.0,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Plus button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canIncrement
                  ? () async {
                      if (product.hasVariants && product.variants != null && product.variants!.isNotEmpty) {
                        if (variantCount > 1) {
                          await _showVariantBottomSheet(context);
                          return;
                        }
                        // Single variant: update directly
                        final v = product.variants!.firstWhere((vv) => vv.isAvailable, orElse: () => product.variants!.first);
                        await cartProvider.updateQuantity(product.id, quantity + 1, variantId: v.id);
                      } else {
                        await cartProvider.updateQuantity(product.id, quantity + 1);
                      }
                    }
                  : (product.hasVariants && product.variants != null && product.variants!.isNotEmpty)
                      ? () async => _showVariantBottomSheet(context)
                      : null,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(6),
                bottomRight: Radius.circular(6),
              ),
              child: Container(
                width: buttonWidth,
                height: height,
                alignment: Alignment.center,
                child: Text(
                  '+',
                  style: TextStyle(
                    fontSize: iconSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showVariantBottomSheet(BuildContext context) async {
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final variants = (product.variants ?? [])
        .where((v) => v.isAvailable)
        .toList()
      ..sort((a, b) {
        final priceComp = a.price.compareTo(b.price);
        if (priceComp != 0) return priceComp;
        return a.displayOrder.compareTo(b.displayOrder);
      });

    if (variants.isEmpty) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        final titleStyle = TextStyle(
          fontSize: screenWidth < 360 ? 14 : 16,
          fontWeight: FontWeight.w700,
          color: AppTheme.black,
        );
        final labelStyle = TextStyle(
          fontSize: screenWidth < 360 ? 12 : 13,
          fontWeight: FontWeight.w500,
          color: AppTheme.black,
        );
        final priceStyle = TextStyle(
          fontSize: screenWidth < 360 ? 13 : 14,
          fontWeight: FontWeight.w700,
          color: AppTheme.black,
        );
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: titleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemBuilder: (context, index) {
                      final v = variants[index];
                      final available = v.stock > 0 && v.isAvailable;
                      return Consumer<CartProvider>(
                        builder: (context, cp, _) {
                          final qty = cp.getQuantity(product.id, variantId: v.id);
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.lightGrey),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    v.label,
                                    style: labelStyle,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Text(
                                    currencyFormat.format(v.price),
                                    style: priceStyle,
                                  ),
                                ),
                                if (qty > 0 && available)
                                  Container(
                                    height: 32,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF0A5C18),
                                          Color(0xFF1B8A2E),
                                          Color(0xFF0A5C18),
                                        ],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        stops: [0.0, 0.5, 1.0],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GestureDetector(
                                          onTap: () async {
                                            if (qty > 1) {
                                              await cp.updateQuantity(product.id, qty - 1, variantId: v.id);
                                            } else {
                                              await cp.removeItem(product.id, variantId: v.id);
                                            }
                                          },
                                          child: Container(
                                            width: 32,
                                            height: 32,
                                            alignment: Alignment.center,
                                            child: const Text(
                                              '–',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                height: 1.0,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          constraints: const BoxConstraints(minWidth: 24),
                                          alignment: Alignment.center,
                                          child: Text(
                                            qty.toString(),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () async {
                                            if (qty < v.stock) {
                                              await cp.updateQuantity(product.id, qty + 1, variantId: v.id);
                                            }
                                          },
                                          child: Container(
                                            width: 32,
                                            height: 32,
                                            alignment: Alignment.center,
                                            child: const Text(
                                              '+',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                height: 1.0,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    height: 32,
                                    decoration: BoxDecoration(
                                      gradient: available
                                          ? const LinearGradient(
                                              colors: [
                                                Color(0xFFE8F5E9),
                                                Colors.white,
                                                Color(0xFFE8F5E9),
                                              ],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                              stops: [0.0, 0.5, 1.0],
                                            )
                                          : null,
                                      color: available ? null : AppTheme.grey.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(8),
                                      border: available
                                          ? Border.all(color: const Color(0xFF0C831F), width: 1.5)
                                          : null,
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: available
                                            ? () async {
                                                await cp.addItem(product, variant: v);
                                              }
                                            : null,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          child: Center(
                                            child: Text(
                                              available ? AppLocalizations.of(context).productAdd : AppLocalizations.of(context).productOutOfStockCaps,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: screenWidth < 360 ? 12 : 13,
                                                color: available ? const Color(0xFF0C831F) : AppTheme.grey,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: variants.length,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
