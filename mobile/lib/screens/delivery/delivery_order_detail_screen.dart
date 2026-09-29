import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../providers/delivery_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme.dart';
import '../../utils/navigation_utils.dart';
import '../../models/order_model.dart';

class DeliveryOrderDetailScreen extends StatefulWidget {
  final int orderId;

  const DeliveryOrderDetailScreen({super.key, required this.orderId});

  @override
  State<DeliveryOrderDetailScreen> createState() => _DeliveryOrderDetailScreenState();
}

class _DeliveryOrderDetailScreenState extends State<DeliveryOrderDetailScreen> {
  OrderModel? _order;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrderDetails();
  }

  Future<void> _loadOrderDetails() async {
    final deliveryProvider = Provider.of<DeliveryProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.accessToken;
    final order = await deliveryProvider.getOrderDetails(widget.orderId, token: token);
    setState(() {
      _order = order;
      _isLoading = false;
    });
  }

  Future<void> _openNavigation() async {
    if (_order == null) return;

    final address = _order!.deliveryAddress;

    // Use exact coordinates if available (more accurate for instant delivery)
    if (address.latitude != null && address.longitude != null) {
      try {
        final lat = double.parse(address.latitude!);
        final lng = double.parse(address.longitude!);

        // Open Google Maps with exact coordinates for turn-by-turn navigation
        final url = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'
        );

        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open Google Maps')),
            );
          }
        }
      } catch (e) {
        // Fallback to text search if coordinate parsing fails
        _openNavigationWithText(address);
      }
    } else {
      // Fallback to text-based search if coordinates not available
      _openNavigationWithText(address);
    }
  }

  Future<void> _openNavigationWithText(dynamic address) async {
    final query = '${address.addressLine1}, ${address.city}, ${address.state} ${address.pincode}';
    final encodedQuery = Uri.encodeComponent(query);
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedQuery');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Google Maps')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _viewOnMaps() async {
    if (_order == null) return;

    final address = _order!.deliveryAddress;

    // Use exact coordinates if available
    if (address.latitude != null && address.longitude != null) {
      try {
        final lat = double.parse(address.latitude!);
        final lng = double.parse(address.longitude!);

        // Navigate to map view screen with route
        context.push('/delivery/map', extra: {
          'destinationLat': lat,
          'destinationLng': lng,
          'destinationAddress': _order!.deliveryAddress.addressLine1,
          'orderId': _order!.id,
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid coordinates')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Address coordinates not available')),
        );
      }
    }
  }

  Future<void> _callCustomer() async {
    if (_order == null) return;

    final phoneNumber = _order!.user.phoneNumber;
    final url = Uri.parse('tel:$phoneNumber');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not make phone call')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return popScopeWithRoleHubFallback(
        context,
        Scaffold(
          appBar: AppBar(
            title: const Text('Order Details'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => popOrRoleHub(context),
            ),
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_order == null) {
      return popScopeWithRoleHubFallback(
        context,
        Scaffold(
          appBar: AppBar(
            title: const Text('Order Details'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => popOrRoleHub(context),
            ),
          ),
          body: const Center(child: Text('Order not found')),
        ),
      );
    }

    final order = _order!;
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return popScopeWithRoleHubFallback(
      context,
      Scaffold(
      appBar: AppBar(
        title: Text('Order #${order.id}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => popOrRoleHub(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrderDetails,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // BIG COD collect banner — first thing the rider sees on this screen.
            // Only renders when there is cash to collect. Prepaid orders skip this.
            if (order.isCod && !order.isPaid)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: const BoxDecoration(
                  color: Color(0xFFD32F2F),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.payments_outlined, color: Colors.white, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'COLLECT FROM CUSTOMER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      currencyFormat.format(order.totalAmount),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'CASH ON DELIVERY',
                      style: TextStyle(
                        color: Color(0xFFFFCDD2),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),

            // Status Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: _getStatusColor(order.status).withOpacity(0.1),
              child: Column(
                children: [
                  Text(
                    order.statusText,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(order.status),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total: ${currencyFormat.format(order.totalAmount)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (order.isCod && order.isPaid) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'CASH COLLECTED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2E7D32),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Customer Info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Customer Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.person, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              order.user.name ?? 'Customer',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              order.user.phoneNumber,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.call, color: AppTheme.primaryGreen),
                            onPressed: _callCustomer,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Delivery Address
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: AppTheme.primaryGreen,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Delivery Address',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.deliveryAddress.addressLine1,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (order.deliveryAddress.addressLine2 != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                order.deliveryAddress.addressLine2!,
                                style: const TextStyle(fontSize: 15),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              '${order.deliveryAddress.city}, ${order.deliveryAddress.state} - ${order.deliveryAddress.pincode}',
                              style: TextStyle(
                                fontSize: 15,
                                color: AppTheme.grey,
                              ),
                            ),
                            if (order.deliveryAddress.landmark != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Landmark: ${order.deliveryAddress.landmark}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Show coordinates if available
                      if (order.deliveryAddress.latitude != null && order.deliveryAddress.longitude != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.lightGrey,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.gps_fixed, size: 14, color: AppTheme.primaryGreen),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${order.deliveryAddress.latitude}, ${order.deliveryAddress.longitude}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.grey,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Navigation buttons - Stack vertically on small screens
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // If width is less than 350, stack buttons vertically
                          if (constraints.maxWidth < 350) {
                            return Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _openNavigation,
                                    icon: const Icon(Icons.directions, size: 18),
                                    label: const Text('Get Directions'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryGreen,
                                      foregroundColor: AppTheme.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _viewOnMaps,
                                    icon: const Icon(Icons.map, size: 18),
                                    label: const Text('View Map'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          } else {
                            // Horizontal layout for larger screens
                            return Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _openNavigation,
                                    icon: const Icon(Icons.directions, size: 18),
                                    label: const Text('Get Directions'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryGreen,
                                      foregroundColor: AppTheme.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _viewOnMaps,
                                    icon: const Icon(Icons.map, size: 18),
                                    label: const Text('View Map'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Order Items
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Order Items',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...order.items.map((item) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: item.product.imageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: item.product.imageUrl!,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const SizedBox(
                                    width: 50,
                                    height: 50,
                                    child: Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => const Icon(Icons.image),
                                )
                              : const Icon(Icons.image),
                          title: Text(item.product.name),
                          subtitle: Text(
                            item.displayLabel != null
                                ? '${item.displayLabel} x ${currencyFormat.format(item.price)}'
                                : 'Qty: ${item.quantity} x ${currencyFormat.format(item.price)}',
                          ),
                          trailing: Text(
                            currencyFormat.format(item.total),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )),
                ],
              ),
            ),

            // Action Buttons — always state-machine flow (legacy 3-button fork removed).
            // Orders with delivery_status=null fall through to the "Waiting for admin"
            // banner inside _buildStateMachineActions until backfill SQL runs on prod.
            if (order.status != 'delivered' && order.status != 'cancelled')
              Padding(
                padding: const EdgeInsets.all(16),
                child: _buildStateMachineActions(order),
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.grey;
      case 'accepted':
        return Colors.blue;
      case 'preparing':
        return Colors.orange;
      case 'out_for_delivery':
        return Colors.purple;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return AppTheme.primaryGreen;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Action buttons
  // ═════════════════════════════════════════════════════════════════════════

  /// Phase 1 state-machine actions. Each transition button is gated on the
  /// order's current `deliveryStatus` so only the legal next step is shown
  /// (the backend rejects illegal ones with 409 anyway, but no-show is friendlier).
  ///
  /// COD orders at `arrived`/`payment_pending` route to the dedicated COD
  /// collection screen — that's where OTP entry + cash collection lives.
  Widget _buildStateMachineActions(OrderModel order) {
    final ds = order.deliveryStatus;

    Widget bigButton({
      required String label,
      required IconData icon,
      required Color color,
      required VoidCallback onPressed,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 22),
          label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ds == 'unassigned' || ds == null)
          const _InfoBanner(
            text: 'Waiting for admin to assign this order',
            color: Colors.grey,
          ),
        if (ds == 'assigned')
          bigButton(
            label: 'Arrived at Store',
            icon: Icons.storefront_outlined,
            color: Colors.blue.shade600,
            onPressed: () => _runTransition(
              (token) => Provider.of<DeliveryProvider>(context, listen: false)
                  .arrivedAtStore(token: token, orderId: order.id),
            ),
          ),
        if (ds == 'at_store')
          bigButton(
            label: 'Picked Order',
            icon: Icons.shopping_bag_outlined,
            color: Colors.orange.shade700,
            onPressed: () => _runTransition(
              (token) => Provider.of<DeliveryProvider>(context, listen: false)
                  .pickedOrder(token: token, orderId: order.id),
            ),
          ),
        if (ds == 'picked')
          bigButton(
            label: 'Start Delivery (Send OTP)',
            icon: Icons.local_shipping_outlined,
            color: Colors.purple.shade600,
            onPressed: () => _runStartDelivery(order),
          ),
        if (ds == 'out_for_delivery')
          bigButton(
            label: 'Mark Arrived',
            icon: Icons.flag_outlined,
            color: Colors.indigo.shade600,
            onPressed: () => _runTransition(
              (token) => Provider.of<DeliveryProvider>(context, listen: false)
                  .arrivedAtCustomer(token: token, orderId: order.id),
            ),
          ),
        if (ds == 'arrived' || ds == 'payment_pending') ...[
          if (order.needsCashCollection)
            bigButton(
              label: 'Collect Cash ₹${order.totalAmount.toStringAsFixed(0)}',
              icon: Icons.payments_outlined,
              color: const Color(0xFFD32F2F),
              onPressed: () => context.push('/delivery/cod/${order.id}'),
            )
          else
            bigButton(
              label: 'Verify OTP & Deliver',
              icon: Icons.check_circle_outline,
              color: Colors.green.shade600,
              // Same screen as COD; it self-detects prepaid via order.isCod
              // and switches the API call + UI accents.
              onPressed: () => context.push('/delivery/cod/${order.id}'),
            ),
        ],
        if (ds == 'rto_pending')
          const _InfoBanner(
            text: 'Order returning to hub. Hand it to the supervisor at the store.',
            color: Color(0xFFD84315),
          ),
        if (ds != 'delivered' && ds != 'rto_completed') ...[
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => _showReportIssueSheet(order),
            icon: const Icon(Icons.error_outline, size: 20),
            label: const Text('Report a Problem'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ],
    );
  }

  /// Generic wrapper for any state transition that returns a {deliveryStatus}
  /// map. Refreshes the screen + handles errors uniformly so each button is a one-liner.
  Future<void> _runTransition(
    Future<Map<String, dynamic>> Function(String token) call,
  ) async {
    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) return;
    try {
      await call(token);
      if (mounted) await _loadOrderDetails();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    }
  }

  /// Wrapper for start-delivery. OTP is sent via Twilio SMS by the backend.
  Future<void> _runStartDelivery(OrderModel order) async {
    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) return;
    try {
      await Provider.of<DeliveryProvider>(context, listen: false)
          .startDelivery(token: token, orderId: order.id);
      if (mounted) {
        await _loadOrderDetails();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP sent to customer via SMS.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    }
  }

  /// Bottom sheet to capture an issue reason + optional note. Reasons match
  /// the backend's whitelist (customer_refused | not_reachable | wrong_address |
  /// damaged | other).
  Future<void> _showReportIssueSheet(OrderModel order) async {
    final reasons = const [
      ('not_reachable', 'Customer not reachable', Icons.phone_disabled),
      ('customer_refused', 'Customer refused order', Icons.cancel_outlined),
      ('wrong_address', 'Wrong / unreachable address', Icons.wrong_location),
      ('damaged', 'Items damaged in transit', Icons.broken_image_outlined),
      ('other', 'Other', Icons.more_horiz),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text('What happened?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final r in reasons)
              ListTile(
                leading: Icon(r.$3),
                title: Text(r.$2),
                onTap: () => Navigator.pop(sheetCtx, r.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;

    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) return;
    try {
      final result = await Provider.of<DeliveryProvider>(context, listen: false)
          .reportIssue(token: token, orderId: order.id, reason: selected);
      if (mounted) {
        await _loadOrderDetails();
        final next = result['nextAction'] as String?;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next == 'return_to_hub'
                ? 'Issue logged — return order to hub.'
                : 'Issue logged — try again later.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    }
  }
}

/// Static info banner used when no action is available (waiting / RTO transit).
class _InfoBanner extends StatelessWidget {
  final String text;
  final Color color;
  const _InfoBanner({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

