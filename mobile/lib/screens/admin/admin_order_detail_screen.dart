import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/order_model.dart';
import '../../models/refund_info.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme.dart';
import '../../utils/navigation_utils.dart';

class AdminOrderDetailScreen extends StatefulWidget {
  final int orderId;

  const AdminOrderDetailScreen({super.key, required this.orderId});

  @override
  State<AdminOrderDetailScreen> createState() => _AdminOrderDetailScreenState();
}

class _AdminOrderDetailScreenState extends State<AdminOrderDetailScreen> {
  OrderModel? _order;
  bool _isLoading = true;
  String? _error;

  /// Refund state for this order, or null when no refund was ever raised.
  RefundInfo? _refund;

  /// True while a manual retry is in flight — keeps the button disabled so a
  /// double-tap cannot queue a second attempt.
  bool _retryingRefund = false;

  @override
  void initState() {
    super.initState();
    _loadOrder().then((_) => _loadRefund());
  }

  /// Refund state lives behind its own endpoint rather than on the order
  /// payload, so fetching the order list stays a single query.
  Future<void> _loadRefund() async {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.accessToken;
    if (token == null) return;

    final info = await adminProvider.fetchRefundInfo(
      token: token,
      orderId: widget.orderId,
    );
    if (!mounted) return;
    setState(() => _refund = info);
  }

  Future<void> _loadOrder() async {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.accessToken == null) {
      setState(() {
        _error = 'Authentication required';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // First try to find in existing orders
      final existingOrder = adminProvider.orders.firstWhere(
        (o) => o.id == widget.orderId,
        orElse: () => throw Exception('Not in list'),
      );
      
      setState(() {
        _order = existingOrder;
        _isLoading = false;
      });
    } catch (e) {
      // If not in list, fetch from API
      try {
        final response = await adminProvider.apiService.get(
          '/admin/orders/${widget.orderId}',
          token: authProvider.accessToken!,
        );
        
        if (response == null) {
          throw Exception('Failed to fetch order');
        }
        final order = OrderModel.fromJson(response as Map<String, dynamic>);
        
        // Add to provider's list if not already there
        if (!adminProvider.orders.any((o) => o.id == order.id)) {
          adminProvider.orders.insert(0, order);
        }
        
        setState(() {
          _order = order;
          _isLoading = false;
        });
      } catch (apiError) {
        setState(() {
          _error = 'Failed to load order: ${apiError.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final adminProvider = Provider.of<AdminProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');

    if (_isLoading) {
      return popScopeWithRoleHubFallback(
        context,
        Scaffold(
          appBar: AppBar(
            title: Text('Order #${widget.orderId}'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => popOrRoleHub(context),
            ),
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null || _order == null) {
      return popScopeWithRoleHubFallback(
        context,
        Scaffold(
          appBar: AppBar(
            title: Text('Order #${widget.orderId}'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => popOrRoleHub(context),
            ),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: AppTheme.grey),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Order not found',
                  style: TextStyle(color: AppTheme.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadOrder,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final order = _order!;

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
          // Phase 3: Timeline view — full audit trail of state transitions.
          IconButton(
            tooltip: 'Order timeline',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/admin/order/${order.id}/timeline'),
          ),
          // Phase 3: Assign rider — only when not yet assigned and order is live.
          if (order.deliveryBoy == null &&
              order.status != 'delivered' &&
              order.status != 'cancelled')
            IconButton(
              tooltip: 'Assign rider',
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: () => _showAssignRiderSheet(order),
            ),
          // Phase 3: Complete RTO — only when in rto_pending.
          if (order.deliveryStatus == 'rto_pending')
            IconButton(
              tooltip: 'Mark RTO complete',
              icon: const Icon(Icons.assignment_return),
              onPressed: () => _confirmCompleteRto(order),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadOrder();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Status Card
            _buildStatusCard(context, order, currencyFormat, dateFormat),
            
            // Customer Information
            _buildCustomerCard(order),
            
            // Order Items with Variants
            _buildOrderItemsCard(order, currencyFormat),
            
            // Delivery Address
            _buildAddressCard(order),
            
            // Payment Information
            _buildPaymentCard(order, currencyFormat),

            // Refund status + manual retry. Renders only when a refund exists.
            _buildRefundCard(currencyFormat),

            // Customer cancellation/refund request — approve or reject
            if (order.cancelRequestStatus == 'requested')
              _buildCancellationRequestCard(order),

            // Action Buttons
            if (order.status != 'delivered' && order.status != 'cancelled')
              _buildActionButtons(context, order, adminProvider, authProvider),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildStatusCard(BuildContext context, OrderModel order, NumberFormat currencyFormat, DateFormat dateFormat) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getStatusColor(order.status).withOpacity(0.1),
            _getStatusColor(order.status).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getStatusColor(order.status).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${order.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(order.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getStatusColor(order.status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    order.statusText.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Amount',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currencyFormat.format(order.totalAmount),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                ],
              ),
              if (order.paymentMethod != null) _paymentStateChip(order),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(OrderModel order) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: AppTheme.primaryGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Customer',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.user.name ?? 'Guest User',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                          order.user.phoneNumber,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (order.deliveryBoy != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.delivery_dining,
                      color: Colors.blue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delivery Agent',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.deliveryBoy!.name ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (order.deliveryBoy!.phoneNumber != null)
                          Text(
                            order.deliveryBoy!.phoneNumber!,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItemsCard(OrderModel order, NumberFormat currencyFormat) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    Icons.shopping_bag,
                    color: AppTheme.primaryGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Order Items (${order.items.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...order.items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return _buildOrderItemTile(item, currencyFormat, index + 1);
            }),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  currencyFormat.format(order.totalAmount),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItemTile(OrderItemModel item, NumberFormat currencyFormat, int index) {
    final hasVariant = item.variant != null;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.lightGrey.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: hasVariant
            ? Border.all(color: AppTheme.primaryGreen.withOpacity(0.3), width: 1.5)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: item.product.imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: item.product.imageUrl!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 60,
                      height: 60,
                      color: AppTheme.lightGrey,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 60,
                      height: 60,
                      color: AppTheme.lightGrey,
                      child: const Icon(Icons.image, size: 30),
                    ),
                  )
                : Container(
                    width: 60,
                    height: 60,
                    color: AppTheme.lightGrey,
                    child: const Icon(Icons.image, size: 30),
                  ),
          ),
          const SizedBox(width: 12),
          // Product Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '$index',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.product.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Variant Information
                if (hasVariant) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2,
                          size: 14,
                          color: AppTheme.primaryGreen,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.displayLabel ?? item.variant!.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    Text(
                      'Qty: ${item.quantity}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.grey,
                      ),
                    ),
                    if (item.unit != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '• ${item.unit}',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.grey,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${currencyFormat.format(item.price)} × ${item.quantity}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.grey,
                      ),
                    ),
                    Text(
                      currencyFormat.format(item.total),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryGreen,
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

  Widget _buildAddressCard(OrderModel order) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Delivery Address',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              order.deliveryAddress.fullAddress,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (order.deliveryAddress.landmark != null) ...[
              const SizedBox(height: 8),
              Text(
                'Landmark: ${order.deliveryAddress.landmark}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(OrderModel order, NumberFormat currencyFormat) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.payment,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Payment Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Payment Method',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.grey,
                  ),
                ),
                Text(
                  order.paymentMethod?.toUpperCase() ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (order.paymentId != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Payment ID',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.grey,
                    ),
                  ),
                  Text(
                    order.paymentId!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Status',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.grey,
                  ),
                ),
                _paymentStateChip(order),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Refund status card. Only rendered when a refund actually exists.
  ///
  /// This is the surface that was missing entirely: a permanently failed refund
  /// previously displayed as "Refund in progress" forever, with no way for an
  /// admin to tell it apart from a healthy one or to do anything about it.
  Widget _buildRefundCard(NumberFormat currencyFormat) {
    final refund = _refund;
    if (refund == null) return const SizedBox.shrink();

    final (Color color, IconData icon, String title, String detail) = switch (refund) {
      _ when refund.isProcessed => (
          Colors.green.shade700,
          Icons.check_circle,
          'Refund completed',
          'The customer has been refunded. It reflects in their account within 2–7 working days.',
        ),
      _ when refund.isFailed => (
          Colors.red.shade700,
          Icons.error_outline,
          'Refund failed',
          'Tried ${refund.attemptCount} time${refund.attemptCount == 1 ? '' : 's'} automatically. '
              'The customer has NOT been refunded — retry below.',
        ),
      _ when refund.isAutoRetrying => (
          Colors.orange.shade800,
          Icons.autorenew,
          'Retrying automatically',
          'Attempt ${refund.attemptCount} of ${refund.maxAutoAttempts} failed. '
              'The next attempt runs on its own — no action needed yet.',
        ),
      _ => (
          Colors.blue.shade700,
          Icons.schedule,
          'Refund in progress',
          'Razorpay has accepted the refund and is settling it. '
              'This usually completes within a few minutes.',
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                Text(
                  currencyFormat.format(refund.amountRupees),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(detail, style: const TextStyle(fontSize: 13, color: AppTheme.grey)),

            // Surface the real reason so support can act without reading server logs.
            if (refund.lastError != null && !refund.isProcessed) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  refund.lastError!,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: color,
                  ),
                ),
              ),
            ],

            if (refund.razorpayRefundId != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Razorpay refund: ${refund.razorpayRefundId}',
                style: const TextStyle(fontSize: 11, color: AppTheme.grey),
              ),
            ],

            // Only shown when the server says a manual attempt is meaningful —
            // never while a refund is completed or an automatic retry is pending.
            if (refund.canRetry) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _retryingRefund ? null : _handleRetryRefund,
                  icon: _retryingRefund
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(_retryingRefund ? 'Retrying…' : 'Retry refund'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One tap = one attempt. The button is disabled for the duration, and the
  /// server's adopt-before-create check means even a stuck tap cannot cause a
  /// second real refund.
  Future<void> _handleRetryRefund() async {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.accessToken;
    if (token == null) return;

    setState(() => _retryingRefund = true);

    final info = await adminProvider.retryRefund(
      token: token,
      orderId: widget.orderId,
    );

    if (!mounted) return;
    setState(() {
      _retryingRefund = false;
      if (info != null) _refund = info;
    });

    final failure = adminProvider.error;
    final succeeded = info?.isProcessed == true || info?.isAwaitingRazorpay == true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          succeeded
              ? 'Refund re-submitted successfully.'
              : failure ?? 'Retry did not go through. Check the reason above.',
        ),
        backgroundColor: succeeded ? Colors.green : Colors.red,
      ),
    );

    // Pull the order again so the payment badge matches the new refund state.
    await _loadOrder();
  }

  Widget _buildActionButtons(
    BuildContext context,
    OrderModel order,
    AdminProvider adminProvider,
    AuthProvider authProvider,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // COD only at 'pending'. An online order sitting at 'pending' is UNPAID,
          // and accepting it would hide it from both auto-cancel and the
          // stock-restore path, stranding its inventory permanently.
          if (order.status == 'pending' && order.isCod)
            ElevatedButton.icon(
              onPressed: () => _updateStatus(context, order.id, 'accepted', adminProvider, authProvider),
              icon: const Icon(Icons.check_circle),
              label: const Text('Accept Order'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          if (order.status == 'awaiting_acceptance') ...[
            ElevatedButton.icon(
              onPressed: () => _updateStatus(context, order.id, 'accepted', adminProvider, authProvider),
              icon: const Icon(Icons.check_circle),
              label: const Text('Accept Order'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _refuseOrder(context, order, adminProvider, authProvider),
              icon: const Icon(Icons.block),
              label: const Text('Refuse Order'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepOrange,
                side: const BorderSide(color: Colors.deepOrange),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
          if (order.status == 'accepted') ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _updateStatus(context, order.id, 'preparing', adminProvider, authProvider),
              icon: const Icon(Icons.restaurant),
              label: const Text('Start Preparing'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
          if (order.status == 'preparing') ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _updateStatus(context, order.id, 'out_for_delivery', adminProvider, authProvider),
              icon: const Icon(Icons.local_shipping),
              label: const Text('Out for Delivery'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
          if (order.status == 'out_for_delivery') ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _updateStatus(context, order.id, 'delivered', adminProvider, authProvider),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Mark as Delivered'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
          if (order.status != 'delivered') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _updateStatus(context, order.id, 'cancelled', adminProvider, authProvider),
              icon: const Icon(Icons.cancel),
              label: const Text('Cancel Order'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Same fixed list as the orders list — refusals must be countable, not free text.
  static const List<String> _refusalReasons = [
    'Item out of stock',
    'Store too busy',
    'Address not serviceable',
    'Closing soon',
    'Other',
  ];

  /// Refusing is a cancel with a reason. The backend restores stock and refunds the
  /// customer through the same path admin-cancel already uses.
  Future<void> _refuseOrder(
    BuildContext context,
    dynamic order,
    AdminProvider adminProvider,
    AuthProvider authProvider,
  ) async {
    if (authProvider.accessToken == null) return;

    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Refuse order #${order.id}?'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'The customer has already paid. They will be refunded automatically.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          for (final r in _refusalReasons)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(r),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Keep order', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;

    final ok = await adminProvider.updateOrderStatus(
      token: authProvider.accessToken!,
      orderId: order.id as int,
      status: 'cancelled',
      cancellationReason: reason,
    );
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Order refused — customer is being refunded.'
            : (adminProvider.error ?? 'Failed to refuse order')),
        backgroundColor: ok ? Colors.deepOrange : Colors.red,
      ),
    );
    if (ok) {
      await _loadOrder();
      adminProvider.fetchOrders(token: authProvider.accessToken);
    }
  }

  Future<void> _updateStatus(
    BuildContext context,
    int orderId,
    String status,
    AdminProvider adminProvider,
    AuthProvider authProvider,
  ) async {
    if (authProvider.accessToken == null) return;

    final success = await adminProvider.updateOrderStatus(
      token: authProvider.accessToken!,
      orderId: orderId,
      status: status,
    );

    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order status updated to ${status.replaceAll('_', ' ')}'),
          backgroundColor: Colors.green,
        ),
      );
      // Refresh the order in detail view
      await _loadOrder();
      
      // Also refresh the orders list in background
      adminProvider.fetchOrders(token: authProvider.accessToken);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(adminProvider.error ?? 'Failed to update status'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

  // ════════════════════════════════════════════════════════════════════════
  // Phase 3 — Assign rider + Complete RTO actions
  // ════════════════════════════════════════════════════════════════════════

  /// Bottom sheet listing every rider with availability + active count, sorted
  /// idle-first so admin's eye lands on the best candidate.
  Future<void> _showAssignRiderSheet(OrderModel order) async {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) return;

    // Fetch fresh — availability changes minute-to-minute.
    await adminProvider.fetchRiders(token: token);
    if (!mounted) return;

    final riders = [...adminProvider.riders];
    // Sort: idle > busy > offline; within each, fewer active orders first.
    int rank(Map<String, dynamic> r) {
      switch (r['availability'] as String? ?? 'offline') {
        case 'idle':
          return 0;
        case 'busy':
          return 1;
        default:
          return 2;
      }
    }
    riders.sort((a, b) {
      final cmp = rank(a).compareTo(rank(b));
      if (cmp != 0) return cmp;
      final ac = (a['activeOrderCount'] as int?) ?? 0;
      final bc = (b['activeOrderCount'] as int?) ?? 0;
      return ac.compareTo(bc);
    });

    final selectedRiderId = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Assign rider',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${riders.length} rider${riders.length == 1 ? '' : 's'} available',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetCtx).size.height * 0.6,
                ),
                child: riders.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No riders found.\nMake sure rider users have role=\'delivery\'.',
                            textAlign: TextAlign.center),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: riders.length,
                        itemBuilder: (_, i) {
                          final r = riders[i];
                          final av = r['availability'] as String? ?? 'offline';
                          final color = av == 'idle'
                              ? Colors.green
                              : av == 'busy'
                                  ? Colors.orange
                                  : Colors.grey;
                          final activeCount = (r['activeOrderCount'] as int?) ?? 0;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.15),
                              foregroundColor: color,
                              child: Text(((r['name'] as String?) ?? '?')[0].toUpperCase()),
                            ),
                            title: Text(r['name'] as String? ?? 'Rider',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${r['phoneNumber'] ?? ''} · $activeCount active',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                av.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            ),
                            onTap: () => Navigator.pop(sheetCtx, r['riderId'] as int),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selectedRiderId == null || !mounted) return;

    final ok = await adminProvider.assignRiderToOrder(
      token: token,
      orderId: order.id,
      riderId: selectedRiderId,
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Rider assigned'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
      await _loadOrder();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(adminProvider.error ?? 'Failed to assign rider'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  /// Confirm + call complete-rto. Restores inventory + auto-refunds prepaid.
  Future<void> _confirmCompleteRto(OrderModel order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark RTO complete?'),
        content: const Text(
          'Confirm the rider has physically returned the inventory to the hub. '
          'Stock will be restored and any prepaid amount will be refunded.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) return;
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final ok = await adminProvider.completeRto(token: token, orderId: order.id);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('RTO completed — stock restored, refund initiated if prepaid.'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
      await _loadOrder();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(adminProvider.error ?? 'Failed to complete RTO'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Widget _buildCancellationRequestCard(OrderModel order) {
    final reason = order.cancellationReason;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.report_problem_outlined, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Text('Cancellation requested',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 8),
          if (reason != null && reason.isNotEmpty) ...[
            Text('Reason: $reason',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
            const SizedBox(height: 8),
          ],
          Text(
            // Payment-aware. This was hardcoded to mention a refund "(if
            // prepaid)", so a cash order — where no money has moved and none
            // ever will — was presented as a refund decision.
            order.paymentStatus == 'paid'
                ? 'Approving cancels the order and initiates a full refund to the customer.'
                : 'Approving cancels the order. Nothing was paid, so there is no refund to issue.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleCancellationDecision(order, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade800,
                    side: BorderSide(color: Colors.grey.shade400),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleCancellationDecision(order, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    order.paymentStatus == 'paid'
                        ? 'Approve & Refund'
                        : 'Approve cancellation',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleCancellationDecision(OrderModel order, bool approve) async {
    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) return;
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final ok = approve
        ? await adminProvider.approveCancellation(token: token, orderId: order.id)
        : await adminProvider.rejectCancellation(token: token, orderId: order.id);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(SnackBar(
        content: Text(approve
            ? 'Cancellation approved — refund initiated if prepaid.'
            : 'Cancellation request declined.'),
        backgroundColor: const Color(0xFF2E7D32),
      ));
      await _loadOrder();
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(adminProvider.error ?? 'Action failed'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  /// Payment badge that reflects the real payment state — including refund states —
  /// instead of only `isPaid` (which stays true after a refund).
  Widget _paymentStateChip(OrderModel order) {
    final ps = order.paymentStatus;
    final String label;
    final Color color;
    final IconData icon;

    // A failed refund releases the payment back to `paid`, so paymentStatus alone
    // would render a reassuring "Paid" badge while the customer is still owed
    // money. The refund row is the truth here, so it wins.
    final refund = _refund;
    if (refund != null && refund.isFailed) {
      label = 'Refund failed';
      color = Colors.red.shade700;
      icon = Icons.error_outline;
    } else if (refund != null && refund.isAutoRetrying) {
      label = 'Refund retrying';
      color = Colors.orange.shade800;
      icon = Icons.autorenew;
    } else if (ps == 'refunded') {
      label = 'Refunded';
      color = Colors.grey.shade600;
      icon = Icons.undo;
    } else if (ps == 'refund_pending') {
      label = 'Refund in progress';
      color = Colors.orange.shade700;
      icon = Icons.undo;
    } else if (order.isPaid) {
      label = 'Paid';
      color = Colors.green;
      icon = Icons.check_circle;
    } else {
      label = 'Pending';
      color = Colors.orange;
      icon = Icons.pending;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

