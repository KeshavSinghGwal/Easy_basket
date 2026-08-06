import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/cart_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/proximity_provider.dart';
import '../../widgets/address_completion_sheet.dart';
import '../../utils/theme.dart';
import 'package:intl/intl.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cartProvider = Provider.of<CartProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final orderProvider = Provider.of<OrderProvider>(context);
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final addressProvider = Provider.of<AddressProvider>(context);
    final hasAddress = orderProvider.addresses.isNotEmpty || addressProvider.hasAddresses;

    if (cartProvider.items.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F6F6),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          title: const Text('My Cart', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.black)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.black),
            onPressed: () => context.go('/home'),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(36),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shopping_cart_outlined, size: 80, color: AppTheme.primaryGreen),
              ),
              const SizedBox(height: 24),
              const Text('Your cart is empty', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Add items to your cart to get started', style: TextStyle(fontSize: 14, color: AppTheme.grey)),
              const SizedBox(height: 32),
              AppTheme.gradientButton(
                onPressed: () => context.go('/home'),
                padding: const EdgeInsets.symmetric(horizontal: 32),
                height: 48,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_bag_rounded, size: 20, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Start Shopping', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          'My Cart (${cartProvider.itemCount} ${cartProvider.itemCount == 1 ? 'item' : 'items'})',
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.black),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.black),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Stack(
        children: [
          // Green gradient from top
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
          // Content
          Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight + 8),
              // Cart Items
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  itemCount: cartProvider.items.length,
                  itemBuilder: (context, index) {
                    final item = cartProvider.items[index];
                    return _buildCartItem(context, item, cartProvider, currencyFormat);
                  },
                ),
              ),
              // Checkout Section
              _buildCheckoutSection(context, cartProvider, authProvider, hasAddress, currencyFormat),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(
    BuildContext context,
    dynamic item,
    CartProvider cartProvider,
    NumberFormat currencyFormat,
  ) {
    final quantity = item.quantity;
    final maxStock = item.variant?.stock ?? item.product.stock;
    final canIncrement = quantity < maxStock && (item.variant?.isAvailable ?? item.product.isAvailable);

    return Dismissible(
      key: Key('${item.product.id}_${item.variant?.id ?? ""}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 24),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => _buildRemoveDialog(ctx, item, cartProvider),
        ) ?? false;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
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
            // Product Image — compact
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: item.product.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: item.product.imageUrl!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 60, height: 60,
                        color: const Color(0xFFF5F5F5),
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 60, height: 60,
                        color: const Color(0xFFF5F5F5),
                        child: const Icon(Icons.image, color: AppTheme.grey, size: 24),
                      ),
                    )
                  : Container(
                      width: 60, height: 60,
                      color: const Color(0xFFF5F5F5),
                      child: const Icon(Icons.image, color: AppTheme.grey, size: 24),
                    ),
            ),
            const SizedBox(width: 10),
            // Product Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.product.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.black),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.variant != null
                        ? item.variant!.label
                        : (item.product.unit != null ? 'Per ${item.product.unit}' : ''),
                    style: TextStyle(fontSize: 11, color: AppTheme.grey),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        currencyFormat.format((item.variant?.price ?? item.product.price) * item.quantity),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.black),
                      ),
                      if (item.quantity > 1) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(${currencyFormat.format(item.variant?.price ?? item.product.price)} x ${item.quantity})',
                          style: TextStyle(fontSize: 11, color: AppTheme.grey),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Quantity Selector — dark green gradient
            Container(
              height: 32,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      if (quantity > 1) {
                        await cartProvider.updateQuantity(item.product.id, quantity - 1, variantId: item.variant?.id);
                      } else {
                        await cartProvider.removeItem(item.product.id, variantId: item.variant?.id);
                      }
                    },
                    child: const SizedBox(
                      width: 32, height: 32,
                      child: Center(child: Text('–', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    alignment: Alignment.center,
                    child: Text(
                      quantity.toString(),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  GestureDetector(
                    onTap: canIncrement
                        ? () async {
                            await cartProvider.updateQuantity(item.product.id, quantity + 1, variantId: item.variant?.id);
                          }
                        : null,
                    child: SizedBox(
                      width: 32, height: 32,
                      child: Center(
                        child: Text('+',
                          style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold,
                            color: canIncrement ? Colors.white : Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  AlertDialog _buildRemoveDialog(BuildContext context, dynamic item, CartProvider cartProvider) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Remove Item', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Text('Remove ${item.product.name}${item.variant != null ? " (${item.variant!.label})" : ""} from cart?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: AppTheme.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            cartProvider.removeItem(item.product.id, variantId: item.variant?.id);
            Navigator.pop(context, true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${item.product.name} removed from cart'),
                backgroundColor: AppTheme.primaryGreen,
                duration: const Duration(seconds: 1),
              ),
            );
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('Remove'),
        ),
      ],
    );
  }

  Widget _buildCheckoutSection(
    BuildContext context,
    CartProvider cartProvider,
    AuthProvider authProvider,
    bool hasAddress,
    NumberFormat currencyFormat,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, -3),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Price summary in a card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F6F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildPriceRow('Subtotal', cartProvider.totalAmount, currencyFormat, false),
                    const SizedBox(height: 6),
                    _buildPriceRow('Delivery Fee', 0, currencyFormat, false, isFree: true),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    _buildPriceRow('Total', cartProvider.totalAmount, currencyFormat, true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Address warning
              if (!hasAddress && authProvider.isAuthenticated)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_off_rounded, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Delivery address required',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
                            const SizedBox(height: 2),
                            Text('Add address to proceed',
                                style: TextStyle(fontSize: 11, color: Colors.orange.shade600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // Checkout button
              SizedBox(
                width: double.infinity,
                child: AppTheme.gradientButton(
                  onPressed: () {
                    if (!authProvider.isAuthenticated) {
                      // Bounce back to /cart after OTP so the user keeps their items
                      // and the button auto-updates to "Add Address" / "Proceed to Checkout".
                      context.go('/login?returnTo=${Uri.encodeComponent('/cart')}');
                    } else if (!hasAddress) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.location_off, color: Colors.white),
                              SizedBox(width: 8),
                              Expanded(child: Text('Please add a delivery address first')),
                            ],
                          ),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                      // GPS partial (populated for guests via ProximityProvider
                      // .seedPartial on home) → prefilled address sheet.
                      final proximityProv = Provider.of<ProximityProvider>(context, listen: false);
                      final partial = proximityProv.partialAddress;
                      if (partial != null) {
                        // Show bottom sheet — quick address completion (Blinkit style)
                        AddressCompletionSheet.show(
                          context: context,
                          preFilledData: {
                            'city': partial.city ?? '',
                            'state': partial.state ?? '',
                            'pincode': partial.pincode ?? '',
                            'latitude': partial.latitude.toString(),
                            'longitude': partial.longitude.toString(),
                            'area': partial.area ?? '',
                          },
                          onSaved: () {
                            final authProv = Provider.of<AuthProvider>(context, listen: false);
                            final addrProv = Provider.of<AddressProvider>(context, listen: false);
                            if (authProv.token != null) {
                              Provider.of<OrderProvider>(context, listen: false).fetchAddresses(authProv.token!);
                              addrProv.fetchAddresses(authProv.token!).then((_) {
                                final selectedId = addrProv.selectedAddress?.id ?? addrProv.defaultAddress?.id;
                                if (selectedId != null && context.mounted) {
                                  // The /payment route expects the addressId as a
                                  // plain int (same as the address list passes) —
                                  // NOT a map, which would crash on `extra as int?`.
                                  context.push('/payment', extra: selectedId);
                                }
                              });
                            }
                          },
                        );
                      } else {
                        // No GPS data — open address list (has search, map, manual)
                        context.push('/addresses');
                      }
                    } else {
                      // Has address — go to select address screen
                      // User picks address → proceeds to payment from there
                      context.push('/addresses');
                    }
                  },
                  height: 50,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        !authProvider.isAuthenticated
                            ? Icons.login_rounded
                            : !hasAddress
                                ? Icons.location_on_rounded
                                : Icons.shopping_cart_checkout_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        !authProvider.isAuthenticated
                            ? 'Login to Checkout'
                            : !hasAddress
                                ? 'Add Address to Checkout'
                                : 'Proceed to Checkout',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
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

  Widget _buildPriceRow(
    String label,
    double amount,
    NumberFormat currencyFormat,
    bool isTotal, {
    bool isFree = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(
          fontSize: isTotal ? 16 : 13,
          fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
          color: AppTheme.black,
        )),
        Text(
          isFree ? 'FREE' : currencyFormat.format(amount),
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: FontWeight.bold,
            color: isTotal ? AppTheme.primaryGreen : AppTheme.black,
          ),
        ),
      ],
    );
  }
}
