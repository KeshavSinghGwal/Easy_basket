import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/razorpay_service.dart';
import '../../utils/theme.dart';
import '../../providers/proximity_provider.dart';
import '../../providers/address_provider.dart';
import '../../widgets/address_completion_sheet.dart';
import 'payment_status_screen.dart';
import 'package:intl/intl.dart';

// Conditional import for Razorpay types
import 'package:razorpay_flutter/razorpay_flutter.dart' if (dart.library.html) '../../services/razorpay_web_stub.dart';

class PaymentScreen extends StatefulWidget {
  final int? addressId;

  const PaymentScreen({super.key, this.addressId});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> with WidgetsBindingObserver {
  String _selectedPaymentMethod = 'razorpay';
  final _notesController = TextEditingController();
  bool _isProcessingPayment = false;
  DateTime? _paymentStartTime;
  int? _currentOrderId; // Store the order ID we're processing

  // Stable idempotency key for THIS checkout attempt. Reused on retry (timeout,
  // double-tap) so the backend returns the same order instead of creating a
  // duplicate + double-decrementing stock.
  late final String _checkoutKey =
      'ord-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0x7fffffff)}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Set up Razorpay callbacks (only for mobile)
    if (!kIsWeb) {
      RazorpayService.onSuccess = _handlePaymentSuccess;
      RazorpayService.onError = _handlePaymentError;
      RazorpayService.onExternalWallet = _handleExternalWallet;
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // When app comes back to foreground after payment
    if (state == AppLifecycleState.resumed && _isProcessingPayment) {
      // On resume, the Razorpay success/error callback usually fires a moment later
      // and races with this fallback. Wait a short grace period so it can resolve the
      // payment first (it sets _isProcessingPayment=false); only if it truly didn't
      // fire — and checkout has been open a while — fall back to the "pending" screen.
      // The old 5s threshold pre-empted successful payers and skipped client-verify.
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted || !_isProcessingPayment) return; // callback already handled it
        final started = _paymentStartTime;
        if (started != null && DateTime.now().difference(started).inSeconds > 15) {
          _checkPaymentStatus();
        }
      });
    }
  }
  
  Future<void> _checkPaymentStatus() async {
    if (!mounted) return;
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    
    if (authProvider.token == null) return;
    
    try {
      // Refresh orders to see if payment went through
      await orderProvider.fetchOrders(authProvider.token!);
      
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
          _paymentStartTime = null;
        });
        
        // Navigate to payment status page (pending - check orders)
        if (mounted) {
          context.go('/payment/status', extra: {
            'status': PaymentStatus.pending,
            'message': 'Please check your orders to confirm payment status.',
            'orderId': null,
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
          _paymentStartTime = null;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notesController.dispose();
    // Reset loading state before disposing
    if (_isProcessingPayment) {
      _isProcessingPayment = false;
    }
    _currentOrderId = null; // Clear stored order ID
    RazorpayService.clear();
    // Clear callbacks to prevent memory leaks
    RazorpayService.onSuccess = null;
    RazorpayService.onError = null;
    RazorpayService.onExternalWallet = null;
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    
    // Immediately reset loading state
    if (mounted) {
      setState(() => _isProcessingPayment = false);
    }
    
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    
    // Show processing message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verifying payment...'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    if (authProvider.token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login to continue.'),
            backgroundColor: Colors.red,
          ),
        );
        context.go('/login');
      }
      return;
    }

    // Get order ID from stored state (we stored it when opening Razorpay)
    int? orderId = _currentOrderId;

    if (orderId == null) {
      // If order ID is not in state, try to extract from Razorpay orderId
      // Razorpay order ID format might be "ORDER_123" (our format) or "order_ABC123" (Razorpay format)
      final orderIdStr = response.orderId;
      if (orderIdStr != null && orderIdStr.isNotEmpty) {
        if (orderIdStr.contains('_')) {
          final parts = orderIdStr.split('_');
          // Check if it's our format "ORDER_123"
          if (parts.length >= 2 && parts[0].toUpperCase() == 'ORDER') {
            orderId = int.tryParse(parts.last);
          }
        } else {
          // Try parsing as direct number
          orderId = int.tryParse(orderIdStr);
        }
      }
    }

    if (orderId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to identify order. Please check your orders.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        // Instead of going back, go to orders page
        context.go('/orders');
      }
      return;
    }

    final paymentId = response.paymentId ?? '';
      final signature = response.signature ?? '';
      final razorpayOrderId = response.orderId ?? ''; // This is Razorpay's order ID

      if (paymentId.isEmpty || signature.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid payment response. Missing payment details.'),
              backgroundColor: Colors.red,
            ),
          );
          context.go('/orders'); // Go to orders instead of back
        }
        return;
      }

    try {
      // Verify payment with backend
      final verified = await RazorpayService.verifyPayment(
        orderId: orderId,
        paymentId: paymentId,
        signature: signature,
        razorpayOrderId: razorpayOrderId, // Use Razorpay's order ID
        token: authProvider.token!,
      );

      if (verified) {
        // Refresh orders before navigating
        await orderProvider.fetchOrders(authProvider.token!);
        
        if (mounted) {
          // Navigate to payment status page FIRST (before clearing cart to avoid showing zero)
          context.go('/payment/status', extra: {
            'status': PaymentStatus.success,
            // Client 'verify' only advances to success_unverified — the webhook is
            // the authority. Don't claim a definitive "successful/placed" that a
            // later webhook could contradict; reassure without overstating.
            'message':
                'Payment received — we\'re confirming your order. It\'ll appear in your Orders shortly.',
            'orderId': orderId,
          });
          
          // Clear cart AFTER navigation to avoid showing zero value during redirect
          // Use post-frame callback to ensure navigation completes first
          WidgetsBinding.instance.addPostFrameCallback((_) {
            cartProvider.clear();
          });
        }
      } else {
        if (mounted) {
          // Navigate to payment status page with failure
          context.go('/payment/status', extra: {
            'status': PaymentStatus.failed,
            'message': 'Payment verification failed. Please contact support or try again.',
            'orderId': orderId,
          });
        }
      }
    } catch (e) {
      // Ensure loading state is reset on error
      if (mounted) {
        setState(() => _isProcessingPayment = false);
        // Navigate to payment status page with error
        context.go('/payment/status', extra: {
          'status': PaymentStatus.failed,
          'message': 'Error processing payment: ${e.toString()}',
          'orderId': _currentOrderId,
        });
      }
    } finally {
      // Always reset loading state
      if (mounted && _isProcessingPayment) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    
    setState(() => _isProcessingPayment = false);
    
    if (mounted) {
      // Navigate to payment status page with failure
      context.go('/payment/status', extra: {
        'status': PaymentStatus.failed,
        'message': 'Payment failed: ${response.message ?? 'Unknown error'}',
        'orderId': _currentOrderId,
      });
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('External wallet selected: ${response.walletName}'),
        ),
      );
    }
  }

  Future<void> _placeOrder() async {
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first')),
      );
      return;
    }

    // Resolve the address to use FIRST. If we arrived with a concrete address
    // (just added, passed from the address list) or one is selected, the user
    // HAS an address — proceed, don't re-prompt.
    final addressProvider = Provider.of<AddressProvider>(context, listen: false);
    final addressId = widget.addressId ?? addressProvider.selectedAddress?.id;

    if (addressId == null) {
      // No usable address. Only now consider a GPS partial + address completion.
      // (Checking proximity.needsAddressCompletion first would re-open the sheet
      // even after an address was added, because that result is stale — adding an
      // address doesn't re-run the proximity check.)
      final proximityProvider = Provider.of<ProximityProvider>(context, listen: false);
      if (proximityProvider.needsAddressCompletion && proximityProvider.partialAddress != null) {
        final partial = proximityProvider.partialAddress!;
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
            _placeOrder();
          },
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an address')),
      );
      return;
    }

    final items = cartProvider.items.map((item) {
      final itemMap = <String, dynamic>{
        'productId': item.product.id,
        'quantity': item.quantity,
      };
      // Include variantId if item has a variant
      if (item.variant != null) {
        itemMap['variantId'] = item.variant!.id;
      }
      return itemMap;
    }).toList();

    // Refresh token before creating order to avoid 401
    await authProvider.refreshAccessToken();

    // First create the order in our system
    final order = await orderProvider.createOrder(
      token: authProvider.token!,
      items: items,
      addressId: addressId,
      paymentMethod: _selectedPaymentMethod,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      idempotencyKey: _checkoutKey,
    );

    if (order == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(orderProvider.error ?? 'Failed to create order')),
        );
      }
      return;
    }

    // Handle payment based on method
    if (_selectedPaymentMethod == 'razorpay') {
      if (kIsWeb) {
        // Web platform - show message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Online payment is currently available on mobile app only. Please use Cash on Delivery or test on Android/iOS.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      await _processRazorpayPayment(order.id, cartProvider.totalAmount, authProvider.token!);
    } else if (_selectedPaymentMethod == 'cash') {
      // Cash on Delivery - order already created
      // For COD, show order confirmation (not payment success)
      if (mounted) {
        // Refresh orders before navigating
        await orderProvider.fetchOrders(authProvider.token!);
        
        // Navigate to order confirmation page (not payment status)
        // Use orderPlaced status to show appropriate UI
        if (mounted) {
          context.go('/payment/status', extra: {
            'status': PaymentStatus.orderPlaced, // Use orderPlaced instead of success
            'message': 'Your order has been placed successfully! Please keep cash ready for delivery.',
            'orderId': order.id,
          });
          
          // Clear cart AFTER navigation to avoid showing zero value during redirect
          // Use post-frame callback to ensure navigation completes first
          WidgetsBinding.instance.addPostFrameCallback((_) {
            cartProvider.clear();
          });
        }
      }
    }
  }

  Future<void> _processRazorpayPayment(int orderId, double amount, String token) async {
    if (!mounted) return;
    
    setState(() {
      _isProcessingPayment = true;
      _paymentStartTime = DateTime.now();
    });

    try {
      // Create Razorpay order
      final razorpayOrder = await RazorpayService.createOrder(
        amount: amount,
        orderId: orderId,
        token: token,
      );

      if (razorpayOrder == null) {
        setState(() => _isProcessingPayment = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to initialize payment. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Extract values with null safety
      final keyId = razorpayOrder['key'] as String?;
      final razorpayOrderId = razorpayOrder['razorpayOrderId'] as String?;

      if (keyId == null || razorpayOrderId == null) {
        setState(() => _isProcessingPayment = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid payment response. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.user;

      // Store order ID in state for payment callback
      setState(() {
        _currentOrderId = orderId;
      });

      // Open Razorpay checkout
      RazorpayService.openCheckout(
        keyId: keyId,
        amount: amount,
        orderId: razorpayOrderId,
        name: 'Easy Basket',
        description: 'Grocery Order #$orderId',
        prefillEmail: user?.email,
        prefillContact: user?.phoneNumber,
        notes: {
          'orderId': orderId.toString(),
          'internalOrderId': orderId.toString(), // Store in multiple places for reliability
        },
      );
    } catch (e) {
      setState(() => _isProcessingPayment = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = Provider.of<CartProvider>(context);
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text('Payment', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // Order Summary Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.receipt_long_rounded, size: 16, color: Color(0xFF0C831F)),
                    ),
                    const SizedBox(width: 8),
                    const Text('Order Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${cartProvider.items.length} items', style: TextStyle(fontSize: 12, color: AppTheme.grey)),
                  ],
                ),
                const SizedBox(height: 12),
                ...cartProvider.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item.product.name} x ${item.quantity}',
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        currencyFormat.format(item.total),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )),
                Container(height: 0.5, color: const Color(0xFFE0E0E0)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(
                      currencyFormat.format(cartProvider.totalAmount),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Payment Method
          const Text('Payment Method', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),

          // Online Payment tile
          _buildPaymentTile(
            title: 'Online Payment',
            subtitle: 'Cards, UPI, Wallets, Netbanking',
            icon: Icons.payment_rounded,
            value: 'razorpay',
          ),
          const SizedBox(height: 8),

          // COD tile
          _buildPaymentTile(
            title: 'Cash on Delivery',
            subtitle: 'Pay when you receive',
            icon: Icons.money_rounded,
            value: 'cash',
          ),
          const SizedBox(height: 16),

          // Delivery Notes
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Delivery Notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Any special instructions... (optional)',
                    hintStyle: TextStyle(fontSize: 13, color: AppTheme.grey),
                    filled: true,
                    fillColor: const Color(0xFFF6F6F6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // Sticky bottom CTA — Blinkit style
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, -2)),
            ],
          ),
          child: Consumer<OrderProvider>(
            builder: (context, orderProvider, _) => Row(
              children: [
                // Total on left
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total', style: TextStyle(fontSize: 11, color: AppTheme.grey)),
                    const SizedBox(height: 2),
                    Text(
                      currencyFormat.format(cartProvider.totalAmount),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                // Place Order button
                Expanded(
                  child: AppTheme.gradientButton(
                    onPressed: (orderProvider.isLoading || _isProcessingPayment) ? null : _placeOrder,
                    height: 48,
                    child: (orderProvider.isLoading || _isProcessingPayment)
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _selectedPaymentMethod == 'razorpay' ? 'Pay & Place Order' : 'Place Order',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
  }) {
    final isSelected = _selectedPaymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedPaymentMethod = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8F5E9) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF0C831F) : const Color(0xFFE0E0E0),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? const Color(0xFF0C831F) : AppTheme.grey,
              size: 20,
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0C831F).withValues(alpha: 0.1) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: isSelected ? const Color(0xFF0C831F) : AppTheme.grey),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isSelected ? Colors.black : AppTheme.darkGrey)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: AppTheme.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

