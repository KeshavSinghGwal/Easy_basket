import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../providers/order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/order_model.dart';
import '../../config/app_config.dart';
import '../../utils/navigation_utils.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class OrderTrackingScreen extends StatefulWidget {
  final int orderId;

  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen>
    with SingleTickerProviderStateMixin {
  bool _hasFetched = false;
  /// True once a fetch attempt for this order has actually completed (success or
  /// fail). Until then we show "please wait" instead of "Order not found" — the
  /// global [OrderProvider.isLoading] flag is false before the post-frame fetch
  /// starts, which otherwise flashes "not found" on cold-start from a notification.
  bool _fetchCompleted = false;
  /// Guards against overlapping fetches (post-frame, poll, and auth-ready retry
  /// can all fire close together).
  bool _isFetching = false;
  Timer? _pollingTimer;
  late AnimationController _pulseController;
  /// Held so we can detach the listener in dispose.
  AuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // On cold-start from a notification the auth token is restored from storage
      // asynchronously. Listen so we can fetch the moment it lands instead of
      // waiting for the 15s poll.
      _authProvider = Provider.of<AuthProvider>(context, listen: false);
      _authProvider!.addListener(_onAuthChanged);
      _fetchOrder();
      _startPolling();
    });
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthChanged);
    _pollingTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  /// Retry the initial fetch as soon as the token becomes available (e.g. after
  /// storage restore on cold-start), so the user never sits on "please wait".
  void _onAuthChanged() {
    if (!mounted || _fetchCompleted) return;
    if (_authProvider?.accessToken != null) {
      _fetchOrder();
    }
  }

  Future<void> _fetchOrder() async {
    if (_isFetching) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    if (authProvider.accessToken == null) return;

    _isFetching = true;
    try {
      await orderProvider.fetchOrderById(widget.orderId, authProvider.accessToken!);
    } finally {
      _isFetching = false;
    }
    // Mark the attempt complete so the UI can distinguish "still loading" from
    // "genuinely not found".
    if (mounted) setState(() => _fetchCompleted = true);
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final orderProvider =
          Provider.of<OrderProvider>(context, listen: false);
      final order = orderProvider.orders
          .where((o) => o.id == widget.orderId)
          .firstOrNull;
      if (order != null &&
          (order.status == 'delivered' || order.status == 'cancelled')) {
        _pollingTimer?.cancel();
        return;
      }
      _fetchOrder();
    });
  }

  // ═══════════════════════════════════════
  // STATUS HELPERS
  // ═══════════════════════════════════════

  static const _statusOrder = [
    'pending',
    'accepted',
    'preparing',
    'out_for_delivery',
    'delivered',
  ];

  int _statusIndex(String status) {
    final i = _statusOrder.indexOf(status);
    return i == -1 ? 0 : i;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Confirmed';
      case 'preparing':
        return 'Packing';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  String _statusSubtext(String status) {
    switch (status) {
      case 'pending':
        return 'Your order is being processed';
      case 'accepted':
        return 'Your order has been confirmed';
      case 'preparing':
        return 'Your order is being packed';
      case 'out_for_delivery':
        return 'Your order is on the way!';
      case 'delivered':
        return 'Your order has been delivered!';
      case 'cancelled':
        return 'This order was cancelled';
      default:
        return '';
    }
  }

  String _etaText(String status) {
    switch (status) {
      case 'pending':
        return 'Estimated delivery in 25 mins';
      case 'accepted':
        return 'Estimated delivery in 20 mins';
      case 'preparing':
        return 'Estimated delivery in 15 mins';
      case 'out_for_delivery':
        return 'Arriving in 10 mins';
      default:
        return '';
    }
  }

  String _timeRange() {
    final now = DateTime.now();
    final start = now.add(const Duration(minutes: 10));
    final end = now.add(const Duration(minutes: 20));
    final fmt = DateFormat('h:mm a');
    return '${fmt.format(start)} - ${fmt.format(end)}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFFF9800);
      case 'accepted':
        return const Color(0xFF2196F3);
      case 'preparing':
        return const Color(0xFF1565C0);
      case 'out_for_delivery':
      case 'delivered':
        return const Color(0xFF2E7D32);
      case 'cancelled':
        return const Color(0xFFE53935);
      default:
        return Colors.grey;
    }
  }

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final orderProvider = Provider.of<OrderProvider>(context);
    final fmt = NumberFormat.currency(symbol: '\u20B9', decimalDigits: 0);
    final order =
        orderProvider.orders.where((o) => o.id == widget.orderId).firstOrNull;

    if (order == null && !_hasFetched) {
      _hasFetched = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchOrder());
    }

    if (order == null) {
      return popScopeWithRoleHubFallback(
        context,
        Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: const Color(0xFF2E7D32),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => popOrRoleHub(context),
            ),
            title: const Text('Track Order',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18)),
            centerTitle: true,
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Still loading if the global flag says so OR we simply haven't
                  // finished the first fetch attempt yet (post-frame gap). Only a
                  // completed fetch with no result is a genuine "not found".
                  if (orderProvider.isLoading || !_fetchCompleted) ...[
                    const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(Color(0xFF2E7D32))),
                    const SizedBox(height: 16),
                    Text(
                      'Please wait while we fetch your order details',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                  ] else ...[
                    Icon(Icons.receipt_long_outlined,
                        size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Order not found',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    final isCancelled = order.status == 'cancelled';
    final isOutForDelivery = order.status == 'out_for_delivery';

    return popScopeWithRoleHubFallback(
      context,
      Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: Column(
          children: [
            // ── GREEN HEADER ──
            _buildGreenHeader(order),

            // ── SCROLLABLE BODY ──
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  children: [
                    // Live Map on top when out for delivery
                    if (isOutForDelivery) _buildMapSection(order),
                    if (isOutForDelivery) const SizedBox(height: 16),

                    // Status + ETA
                    _buildStatusSection(order),
                    const SizedBox(height: 16),

                    // Horizontal Progress Tracker
                    if (!isCancelled) _buildProgressTracker(order),
                    if (!isCancelled) const SizedBox(height: 16),

                    // Delivery Partner Card (only when out for delivery)
                    if (isOutForDelivery) _buildDriverCard(order),
                    if (isOutForDelivery) const SizedBox(height: 16),

                    // Order Details
                    _buildOrderDetails(order, fmt),
                    const SizedBox(height: 16),

                    // Delivery Address
                    _buildAddressCard(order),
                    const SizedBox(height: 16),

                    // Payment Info
                    _buildPaymentCard(order, fmt),
                    const SizedBox(height: 20),

                    // Cancellation / refund-request actions
                    _buildCancellationSection(order),

                    // Need Help button
                    _buildNeedHelpButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // GREEN BRANDED HEADER
  // ═══════════════════════════════════════

  Widget _buildGreenHeader(OrderModel order) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: const BoxDecoration(
        color: Color(0xFF2E7D32),
      ),
      child: Column(
        children: [
          // App bar row
          SizedBox(
            height: 56,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 22),
                  onPressed: () => popOrRoleHub(context),
                ),
                const Expanded(
                  child: Text(
                    'Track Your Order',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 48), // balance the back button
              ],
            ),
          ),
          // Order ID
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'Order #EB${order.id.toString().padLeft(6, '0')}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // STATUS SECTION
  // ═══════════════════════════════════════

  Widget _buildStatusSection(OrderModel order) {
    final color = _statusColor(order.status);
    final isActive = order.status != 'delivered' && order.status != 'cancelled';

    return _card(
      child: Column(
        children: [
          // Status label
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isActive)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, __) => Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: color.withValues(
                          alpha: 0.4 + _pulseController.value * 0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Text(
                _statusLabel(order.status),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _statusSubtext(order.status),
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          if (isActive) ...[
            const SizedBox(height: 4),
            Text(
              _etaText(order.status),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2E7D32),
              ),
            ),
            Text(
              _timeRange(),
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // HORIZONTAL PROGRESS TRACKER
  // ═══════════════════════════════════════

  Widget _buildProgressTracker(OrderModel order) {
    final steps = [
      {'key': 'pending', 'label': 'Order\nPlaced', 'icon': Icons.receipt_long_rounded},
      {'key': 'preparing', 'label': 'Out for\nDelivery', 'icon': Icons.local_shipping_rounded},
      {'key': 'out_for_delivery', 'label': 'Arriving\nSoon', 'icon': Icons.delivery_dining_rounded},
      {'key': 'delivered', 'label': 'Delivered', 'icon': Icons.home_rounded},
    ];

    final currentIdx = _statusIndex(order.status);

    return _card(
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line
            final leftStep = steps[i ~/ 2];
            final leftPos = _statusOrder.indexOf(leftStep['key'] as String);
            final isDone = currentIdx > leftPos;
            return Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }

          final step = steps[i ~/ 2];
          final stepPos = _statusOrder.indexOf(step['key'] as String);
          final isDone = currentIdx >= stepPos;
          final isCurrent = currentIdx == stepPos ||
              (step['key'] == 'preparing' && order.status == 'accepted');

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFF5F5F5),
                  shape: BoxShape.circle,
                  border: isCurrent && !isDone
                      ? Border.all(color: const Color(0xFF2E7D32), width: 2)
                      : null,
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : null,
                ),
                child: Icon(
                  step['icon'] as IconData,
                  color: isDone ? Colors.white : Colors.grey[400],
                  size: 24,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step['label'] as String,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: isDone
                      ? const Color(0xFF2E7D32)
                      : Colors.grey[400],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════
  // CANCELLED BANNER
  // ═══════════════════════════════════════

  // ═══════════════════════════════════════
  // DRIVER CARD
  // ═══════════════════════════════════════

  Widget _buildDriverCard(OrderModel order) {
    final name = order.deliveryBoy?.name ?? 'Delivery Partner';

    return _accentCard(
      title: 'Driver is on the way!',
      titleColor: const Color(0xFF2E7D32),
      child: Row(
        children: [
          // Dummy avatar
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.person_rounded,
                color: Color(0xFF2E7D32), size: 36),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your Delivery Partner',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
                const SizedBox(height: 2),
                Text(
                  'Est. Arrival: ${DateFormat('h:mm a').format(DateTime.now().add(const Duration(minutes: 10)))}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomChild: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton.icon(
          onPressed: () {
            final phone = order.deliveryBoy?.phoneNumber;
            if (phone != null && phone.isNotEmpty) {
              launchUrl(Uri.parse('tel:$phone'));
            }
          },
          icon: const Icon(Icons.phone_rounded, size: 18),
          label: const Text('Contact Driver',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // ORDER DETAILS
  // ═══════════════════════════════════════

  Widget _buildOrderDetails(OrderModel order, NumberFormat fmt) {
    final subtotal =
        order.items.fold<double>(0, (sum, item) => sum + item.total);
    final deliveryFee = order.totalAmount - subtotal;

    return _accentCard(
      title: 'Order Details',
      child: Column(
        children: [
          ...order.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.product.name}${item.displayLabel != null ? ' - ${item.displayLabel}' : (item.variant != null ? ' - ${item.variant!.label}' : '')}',
                        style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'x${item.quantity}',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      fmt.format(item.total),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                  ],
                ),
              )),
          const Divider(height: 20, thickness: 1, color: Color(0xFFF0F0F0)),
          _row('Subtotal', fmt.format(subtotal)),
          const SizedBox(height: 4),
          _row(
              'Delivery Fee',
              deliveryFee > 0 ? fmt.format(deliveryFee) : 'FREE',
              valueColor:
                  deliveryFee > 0 ? Colors.black87 : const Color(0xFF2E7D32)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Amount',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87)),
                Text(
                  fmt.format(order.totalAmount),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2E7D32)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.black87)),
      ],
    );
  }

  // ═══════════════════════════════════════
  // LIVE MAP SECTION
  // ═══════════════════════════════════════

  Widget _buildMapSection(OrderModel order) {
    final custLat = double.tryParse(order.deliveryAddress.latitude ?? '');
    final custLng = double.tryParse(order.deliveryAddress.longitude ?? '');

    // If customer has no coordinates, show fallback
    if (custLat == null || custLng == null) {
      return _accentCard(
        title: 'Live Order Tracking',
        child: Container(
          height: 180,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_rounded, size: 40, color: Colors.grey[300]),
              const SizedBox(height: 8),
              Text('Map not available',
                  style: TextStyle(fontSize: 13, color: Colors.grey[400])),
            ],
          ),
        ),
      );
    }

    const storeLat = AppConfig.storeLat;
    const storeLng = AppConfig.storeLng;

    // Calculate distance
    final distanceMeters = Geolocator.distanceBetween(
        storeLat, storeLng, custLat, custLng);
    final distanceKm = (distanceMeters / 1000).toStringAsFixed(1);

    // Map bounds to fit both markers
    final southWestLat = storeLat < custLat ? storeLat : custLat;
    final southWestLng = storeLng < custLng ? storeLng : custLng;
    final northEastLat = storeLat > custLat ? storeLat : custLat;
    final northEastLng = storeLng > custLng ? storeLng : custLng;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('store'),
        position: LatLng(storeLat, storeLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Easy Basket Store'),
      ),
      Marker(
        markerId: const MarkerId('customer'),
        position: LatLng(custLat, custLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Your Location'),
      ),
    };

    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: [
          LatLng(storeLat, storeLng),
          LatLng(custLat, custLng),
        ],
        color: const Color(0xFF2E7D32),
        width: 4,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ),
    };

    return _accentCard(
      title: 'Live Order Tracking',
      child: Column(
        children: [
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: kIsWeb
                  ? Container(
                      color: const Color(0xFFF5F5F5),
                      alignment: Alignment.center,
                      child: Text('Map not available on web',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[400])),
                    )
                  : GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          (storeLat + custLat) / 2,
                          (storeLng + custLng) / 2,
                        ),
                        zoom: 12,
                      ),
                      markers: markers,
                      polylines: polylines,
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                      mapToolbarEnabled: false,
                      compassEnabled: false,
                      liteModeEnabled: true,
                      onMapCreated: (controller) {
                        // Fit both markers in view
                        controller.animateCamera(
                          CameraUpdate.newLatLngBounds(
                            LatLngBounds(
                              southwest:
                                  LatLng(southWestLat, southWestLng),
                              northeast:
                                  LatLng(northEastLat, northEastLng),
                            ),
                            50, // padding
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          // Distance + ETA info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.store_rounded,
                    size: 16, color: Color(0xFF2E7D32)),
                const SizedBox(width: 6),
                Text(
                  '$distanceKm km away',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('\u2022',
                      style:
                          TextStyle(fontSize: 8, color: Colors.grey[300])),
                ),
                const Icon(Icons.access_time_rounded,
                    size: 14, color: Color(0xFF2E7D32)),
                const SizedBox(width: 4),
                const Text(
                  'ETA ~15 mins',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // DELIVERY ADDRESS CARD
  // ═══════════════════════════════════════

  Widget _buildAddressCard(OrderModel order) {
    return _accentCard(
      title: 'Delivering To',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_rounded,
              color: Color(0xFF2E7D32), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (order.deliveryAddress.tag != null)
                  Text(
                    order.deliveryAddress.tag!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                if (order.deliveryAddress.tag != null)
                  const SizedBox(height: 3),
                Text(
                  order.deliveryAddress.fullAddress,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
                if (order.notes != null && order.notes!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    order.notes!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[400],
                      fontStyle: FontStyle.italic,
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

  // ═══════════════════════════════════════
  // PAYMENT INFO CARD
  // ═══════════════════════════════════════

  Widget _buildPaymentCard(OrderModel order, NumberFormat fmt) {
    final isCash = order.isCod;
    final isPaid = order.isPaid;
    final ps = order.paymentStatus;
    String payLabel;
    Color payColor;
    if (ps == 'refunded') {
      payLabel = 'Refunded';
      payColor = const Color(0xFF2E7D32);
    } else if (ps == 'refund_pending') {
      payLabel = 'Refund in progress';
      payColor = Colors.orange;
    } else if (isCash) {
      payLabel = 'Cash on Delivery';
      payColor = Colors.orange;
    } else {
      payLabel = isPaid ? 'Paid Online' : 'Pending';
      payColor = isPaid ? const Color(0xFF2E7D32) : Colors.orange;
    }

    return _accentCard(
      title: 'Payment',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.paymentMethod?.toUpperCase() ?? 'N/A',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: payColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(payLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: payColor)),
              ),
            ],
          ),
          Text(
            fmt.format(order.totalAmount),
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2E7D32)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // CANCELLATION / REFUND REQUEST
  // ═══════════════════════════════════════

  Widget _buildCancellationSection(OrderModel order) {
    // A request is already pending admin decision.
    if (order.hasPendingCancelRequest) {
      final reason = order.cancellationReason;
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.hourglass_top, color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Cancellation requested',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: Colors.black87)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  order.isPaid
                      ? 'Awaiting approval. If approved, your full amount will be refunded to your original payment method in 2–7 working days.'
                      : 'Awaiting approval. Your order will be cancelled once approved.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                if (reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Reason: $reason',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    // Before packing → can request a refund (admin-approved).
    if (order.isRefundEligible) {
      return Column(
        children: [
          if (order.cancelRequestRejected)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Your previous cancellation request was declined.',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
            ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => _onRequestCancellation(order),
              icon: const Icon(Icons.replay, size: 18),
              label: Text(order.isPaid ? 'Cancel & Request Refund' : 'Request Cancellation',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD32F2F),
                side: const BorderSide(color: Color(0xFFD32F2F)),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    // After packing → can cancel, but NO refund.
    if (order.canCancelNoRefund) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => _onCancelNoRefund(order),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Cancel Order',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD32F2F),
                side: const BorderSide(color: Color(0xFFD32F2F)),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _onRequestCancellation(OrderModel order) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final op = Provider.of<OrderProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final reason = await _pickCancellationReason();
    if (reason == null) return; // dismissed
    if (auth.accessToken == null) return;
    final ok =
        await op.requestCancellation(order.id, auth.accessToken!, reason: reason);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Refund request submitted — awaiting approval.'
          : (op.error ?? 'Could not submit request')),
    ));
  }

  Future<void> _onCancelNoRefund(OrderModel order) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final op = Provider.of<OrderProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel order?'),
        content: const Text(
            'Your order is already packed. Cancelling now will NOT refund your payment. Do you want to continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep order')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel anyway',
                style: TextStyle(color: Color(0xFFD32F2F))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (auth.accessToken == null) return;
    final ok = await op.cancelOrder(order.id, auth.accessToken!);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content:
          Text(ok ? 'Order cancelled' : (op.error ?? 'Could not cancel order')),
    ));
  }

  /// Bottom sheet of preset reasons. Returns the chosen reason, or null if dismissed.
  Future<String?> _pickCancellationReason() {
    const reasons = [
      'Ordered by mistake',
      'Found a better price',
      'Delivery taking too long',
      'Changed my mind',
      'Other',
    ];
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Why are you cancelling?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final r in reasons)
              ListTile(
                title: Text(r),
                onTap: () => Navigator.pop(ctx, r),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // NEED HELP BUTTON
  // ═══════════════════════════════════════

  Widget _buildNeedHelpButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: const Text(
          'Need Help?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // CARD BUILDERS
  // ═══════════════════════════════════════

  /// Plain white card (no accent border)
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  /// Card with green left accent border (like reference)
  Widget _accentCard({
    required String title,
    required Widget child,
    Color titleColor = Colors.black87,
    Widget? bottomChild,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: Color(0xFF2E7D32), width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: titleColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: child,
          ),
          if (bottomChild != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: bottomChild,
            ),
        ],
      ),
    );
  }
}

