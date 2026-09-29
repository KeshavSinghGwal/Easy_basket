import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/delivery_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme.dart';
import '../../utils/date_utils.dart';
import 'package:intl/intl.dart';

class DeliveryOrdersScreen extends StatefulWidget {
  final String? status;

  const DeliveryOrdersScreen({super.key, this.status});

  @override
  State<DeliveryOrdersScreen> createState() => _DeliveryOrdersScreenState();
}

class _DeliveryOrdersScreenState extends State<DeliveryOrdersScreen> {
  String _selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.status ?? 'all';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrders();
    });
  }

  void _loadOrders() {
    final deliveryProvider = Provider.of<DeliveryProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final status = _selectedStatus == 'all' ? null : _selectedStatus;
    final token = authProvider.accessToken;
    if (token != null) {
      deliveryProvider.fetchOrders(status: status, token: token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deliveryProvider = Provider.of<DeliveryProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/delivery/dashboard'),
        ),
      ),
      body: Column(
        children: [
          // Status Filter
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _StatusChip(
                    label: 'All',
                    isSelected: _selectedStatus == 'all',
                    onTap: () {
                      setState(() => _selectedStatus = 'all');
                      _loadOrders();
                    },
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: 'Accepted',
                    isSelected: _selectedStatus == 'accepted',
                    onTap: () {
                      setState(() => _selectedStatus = 'accepted');
                      _loadOrders();
                    },
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: 'Out for Delivery',
                    isSelected: _selectedStatus == 'out_for_delivery',
                    onTap: () {
                      setState(() => _selectedStatus = 'out_for_delivery');
                      _loadOrders();
                    },
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: 'Delivered',
                    isSelected: _selectedStatus == 'delivered',
                    onTap: () {
                      setState(() => _selectedStatus = 'delivered');
                      _loadOrders();
                    },
                  ),
                ],
              ),
            ),
          ),
          
          // Orders List
          Expanded(
            child: deliveryProvider.isLoading && deliveryProvider.orders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : deliveryProvider.orders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox, size: 64, color: AppTheme.grey),
                            const SizedBox(height: 16),
                            Text(
                              'No orders found',
                              style: TextStyle(
                                fontSize: 18,
                                color: AppTheme.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: deliveryProvider.orders.length,
                        itemBuilder: (context, index) {
                          final order = deliveryProvider.orders[index];
                          return _OrderCard(order: order);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.primaryGreen,
      checkmarkColor: AppTheme.white,
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.white : AppTheme.black,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final dynamic order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final bool showCodBanner = order.isCod && !order.isPaid;
    // Prefer delivery_status when present — it's more granular than the legacy
    // customer-facing status (e.g. 'picked', 'arrived', 'payment_pending').
    final String badgeKey = (order.deliveryStatus as String?) ?? order.status;
    final String badgeLabel = _humanizeStatus(badgeKey);
    final Color badgeColor = _getStatusColor(badgeKey);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/delivery/order/${order.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // COD banner — red-orange, very visible, ONLY when cash is owed.
            // Prepaid orders skip this so the rider isn't visually overloaded.
            if (showCodBanner)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                color: const Color(0xFFFFEBEE),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined, color: Color(0xFFD32F2F), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'COLLECT ${currencyFormat.format(order.totalAmount)} (CASH)',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFD32F2F),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Order #${order.id}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badgeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: badgeColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.person, size: 16, color: AppTheme.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          order.user.name ?? order.user.phoneNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: AppTheme.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${order.deliveryAddress.addressLine1}, ${order.deliveryAddress.city}',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.grey,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            currencyFormat.format(order.totalAmount),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryGreen,
                            ),
                          ),
                          if (!showCodBanner && order.isPaid) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'PAID',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2E7D32),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        formatISTShort(order.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      // Legacy Order.status values
      case 'pending':
        return Colors.grey;
      case 'accepted':
      case 'assigned':
        return Colors.blue;
      case 'preparing':
      case 'at_store':
        return Colors.orange;
      case 'picked':
        return Colors.deepOrange;
      case 'out_for_delivery':
        return Colors.purple;
      case 'arrived':
        return Colors.indigo;
      case 'payment_pending':
        return const Color(0xFFD32F2F);
      case 'delivered':
        return Colors.green;
      case 'cancelled':
      case 'rto_pending':
      case 'rto_completed':
        return Colors.red;
      default:
        return AppTheme.primaryGreen;
    }
  }

  /// Human-readable label for either legacy `status` or new `delivery_status`.
  String _humanizeStatus(String s) {
    switch (s) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'assigned':
        return 'Assigned';
      case 'preparing':
        return 'Preparing';
      case 'at_store':
        return 'At Store';
      case 'picked':
        return 'Picked Up';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'arrived':
        return 'Arrived';
      case 'payment_pending':
        return 'Awaiting Payment';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      case 'rto_pending':
        return 'Return to Hub';
      case 'rto_completed':
        return 'Returned';
      default:
        return s;
    }
  }
}

