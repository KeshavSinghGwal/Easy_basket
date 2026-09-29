import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/session.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/delivery_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/order_model.dart';
import '../../utils/theme.dart';
import '../../utils/date_utils.dart';
import 'package:intl/intl.dart';

class DeliveryDashboardScreen extends StatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  State<DeliveryDashboardScreen> createState() => _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState extends State<DeliveryDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  // 30s background fetch — belt-and-suspenders for FCM. If a rider has push
  // disabled or the token is stale, this keeps the orders list current while
  // they have the dashboard open. Cheap: one GET every 30s, no isLoading flicker
  // because fetchOrders only flips the spinner when the list is empty.
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Rebuild on tab change so the list below the bar swaps without animating.
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final deliveryProvider = Provider.of<DeliveryProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (authProvider.accessToken != null) {
        final token = authProvider.accessToken!;
        deliveryProvider.fetchOrders(token: token);
        deliveryProvider.fetchWallet(token: token);
      }
      _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!mounted) return;
        final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
        if (token == null) return;
        final dp = Provider.of<DeliveryProvider>(context, listen: false);
        dp.fetchOrders(token: token);
        dp.fetchWallet(token: token);
      });
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deliveryProvider = Provider.of<DeliveryProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final token = authProvider.accessToken;
              if (token != null) {
                deliveryProvider.fetchOrders(token: token);
                deliveryProvider.fetchWallet(token: token);
              }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                );
                
                if (confirmed == true && context.mounted) {
                  // Same teardown as every other logout button — this one used
                  // to call logout() alone and reset nothing.
                  await endSession(context);
                  if (context.mounted) {
                    context.go('/login');
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Logout', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final token = authProvider.accessToken;
          if (token != null) {
            await deliveryProvider.fetchOrders(token: token);
            await deliveryProvider.fetchWallet(token: token);
          }
        },
        child: _buildBody(deliveryProvider),
      ),
    );
  }

  /// Body: wallet card → tab bar (Current | Past) → top-3 orders for the
  /// selected tab → "View All" link. Whole thing scrolls as a single column;
  /// each tab swaps the list inline rather than using a TabBarView so the
  /// wallet card stays sticky at the top of the scroll.
  Widget _buildBody(DeliveryProvider deliveryProvider) {
    final all = deliveryProvider.orders;
    final isPastTab = _tabController.index == 1;

    bool isPast(OrderModel o) {
      final ds = o.deliveryStatus;
      if (ds == 'delivered' || ds == 'rto_completed') return true;
      // Fallback for orders that never entered the new state machine.
      if (o.status == 'delivered' || o.status == 'cancelled') return true;
      return false;
    }

    final filtered = all.where((o) => isPastTab ? isPast(o) : !isPast(o)).toList();
    final shown = filtered.take(3).toList();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WalletCard(wallet: deliveryProvider.wallet),
          const SizedBox(height: 8),

          // Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F8E9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.primaryGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.primaryGreen,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              tabs: const [
                Tab(text: 'Current Orders'),
                Tab(text: 'Past Orders'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // List body
          if (deliveryProvider.isLoading && all.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      isPastTab ? Icons.history : Icons.inbox_outlined,
                      size: 56,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isPastTab ? 'No past deliveries yet' : 'No active orders',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: shown.length,
              itemBuilder: (context, i) => _OrderCard(order: shown[i]),
            ),

          // View all (only when there are more than 3)
          if (filtered.length > 3)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => context.push('/delivery/orders'),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text('View all (${filtered.length})'),
                ),
              ),
            ),

          const SizedBox(height: 24),
        ],
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
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/delivery/order/${order.id}'),
        child: Padding(
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
                        color: _getStatusColor(order.status).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        order.statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(order.status),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${order.deliveryAddress.addressLine1}, ${order.deliveryAddress.city}',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.grey,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    currencyFormat.format(order.totalAmount),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                  Row(
                    children: [
                      // Quick navigation button if coordinates available
                      if (order.deliveryAddress?.latitude != null && order.deliveryAddress?.longitude != null)
                        IconButton(
                          icon: const Icon(Icons.navigation, size: 20, color: AppTheme.primaryGreen),
                          onPressed: () async {
                            final lat = double.parse(order.deliveryAddress.latitude!);
                            final lng = double.parse(order.deliveryAddress.longitude!);
                            final url = Uri.parse(
                              'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'
                            );
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            }
                          },
                          tooltip: 'Get Directions',
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
}

/// Big "Cash In Hand" card displayed at the top of the rider dashboard.
///
/// Reads `wallet.cashInHandPaise` (paise -> rupees) and shows it large so a
/// rider glancing at the screen mid-shift can immediately see how much cash
/// they're carrying. Lifetime collected/deposited shown as small chips below.
class _WalletCard extends StatelessWidget {
  final Map<String, dynamic>? wallet;
  const _WalletCard({required this.wallet});

  @override
  Widget build(BuildContext context) {
    final cashPaise = (wallet?['cashInHandPaise'] as num?)?.toInt() ?? 0;
    final lifetimeCollectedPaise =
        (wallet?['lifetimeCollectedPaise'] as num?)?.toInt() ?? 0;
    final lifetimeDepositedPaise =
        (wallet?['lifetimeDepositedPaise'] as num?)?.toInt() ?? 0;

    String fmt(int paise) {
      final rupees = paise / 100.0;
      return NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(rupees);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.account_balance_wallet,
                  color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text(
                'CASH IN HAND',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            wallet == null ? '—' : fmt(cashPaise),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Deposit to admin at end of shift',
            style: TextStyle(
              color: Color(0xFFC8E6C9),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (wallet != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _MiniStat(
                  label: 'Collected',
                  value: fmt(lifetimeCollectedPaise),
                ),
                const SizedBox(width: 12),
                _MiniStat(
                  label: 'Deposited',
                  value: fmt(lifetimeDepositedPaise),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFC8E6C9),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

