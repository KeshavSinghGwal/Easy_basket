import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/session.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/store_status_provider.dart';
import '../../services/notification_service.dart';
import '../../utils/theme.dart';
import 'package:intl/intl.dart';

import '../../widgets/dashboard/dashboard_header.dart';
import '../../widgets/dashboard/dashboard_stat_tile.dart';
import '../../widgets/dashboard/revenue_card.dart';
import '../../widgets/dashboard/quick_action_card.dart';
import '../../widgets/dashboard/section_title.dart';
import '../../widgets/dashboard/dashboard_theme.dart';
import '../../widgets/dashboard/pending_orders_card.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with WidgetsBindingObserver {
  Timer? _refreshTimer;
  bool _isScreenActive = true;
  DateTime? _lastRefreshTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
      _startAutoRefresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Pause auto-refresh when app goes to background
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _isScreenActive = false;
      _refreshTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _isScreenActive = true;
      // Refresh immediately when app comes to foreground
      _loadInitialData();
      _startAutoRefresh();
    }
  }

void _loadInitialData() {
  final adminProvider = Provider.of<AdminProvider>(context, listen: false);
  final authProvider = Provider.of<AuthProvider>(context, listen: false);

  if (authProvider.token != null) {
    Future.wait([
      adminProvider.fetchStats(
        token: authProvider.token,
      ),

      adminProvider.fetchOrders(
        token: authProvider.token, // Removed status: "pending"
      ),
    ]);

    _lastRefreshTime = DateTime.now();
  }
}

void _startAutoRefresh() {
  _refreshTimer?.cancel();

  // Refresh every 10 seconds
  _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (_isScreenActive && mounted) {
      final adminProvider =
          Provider.of<AdminProvider>(context, listen: false);
      final authProvider =
          Provider.of<AuthProvider>(context, listen: false);

      if (authProvider.token != null) {
        await Future.wait([
          adminProvider.fetchStats(
            token: authProvider.token,
          ),

          adminProvider.fetchOrders(
            token: authProvider.token, // Removed status: "pending"
          ),
        ]);

        _lastRefreshTime = DateTime.now();
      }
    }
  });
}
  @override
  Widget build(BuildContext context) {
    final adminProvider = Provider.of<AdminProvider>(context);
    final actionRequiredOrders = adminProvider.orders.where((order) {
  final status = order.status.toLowerCase();

  return status == 'pending' ||
      // Paid and waiting on an accept/refuse decision — the single most
      // action-required state there is.
      status == 'awaiting_acceptance' ||
      status == 'accepted' ||
      status == 'preparing';
}).toList();
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
                  
     final screenWidth = MediaQuery.of(context).size.width;

  final isDesktop = screenWidth >= 1100;

  final isTablet =
      screenWidth >= 700 && screenWidth < 1100;

    return Scaffold(
       backgroundColor: DashboardTheme.background,

       appBar: AppBar(
         elevation: 0,
         backgroundColor: Colors.white,
         surfaceTintColor: Colors.white,
         title: const Text(
            'Easy Basket Admin',
             style: TextStyle(
             fontWeight: FontWeight.bold,
             color: DashboardTheme.title,
         ),
  ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
  final authProvider =
      Provider.of<AuthProvider>(context, listen: false);

  await Future.wait([
    adminProvider.fetchStats(
      token: authProvider.token,
    ),
    adminProvider.fetchOrders(
      token: authProvider.token,
    ),
  ]);

  setState(() {
    _lastRefreshTime = DateTime.now();
  });
},
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'refresh_fcm') {
                if (kIsWeb) return;
                
                try {
                  final authProvider = Provider.of<AuthProvider>(context, listen: false);
                  final adminProvider = Provider.of<AdminProvider>(context, listen: false);

                  
                  
                  // Initialize or refresh notification service
                  await NotificationService().initialize(
                    context: context,
                    adminProvider: adminProvider,
                    authProvider: authProvider,
                  );
                  
                  // Ensure token is sent
                  await NotificationService().ensureTokenSent();
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('FCM token refreshed and sent to backend'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('Error refreshing FCM token: $e');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error refreshing FCM token: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } else if (value == 'logout') {
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
              if (!kIsWeb)
                PopupMenuItem(
                  value: 'refresh_fcm',
                  child: const Row(
                    children: [
                      Icon(Icons.notifications_active, size: 20),
                      SizedBox(width: 8),
                      Text('Refresh FCM Token'),
                    ],
                  ),
                ),
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
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          await Provider.of<StoreStatusProvider>(context, listen: false)
              .refresh(force: true);
          await adminProvider.fetchStats(token: authProvider.token);
        },
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Closed-store alert. Loud and top-of-page on purpose: a store
              // left accidentally closed earns nothing, and the failure is
              // silent otherwise — no orders simply looks like a quiet day.
              Consumer<StoreStatusProvider>(
                builder: (context, storeStatus, _) {
                  if (storeStatus.isOpen) return const SizedBox.shrink();
                  final status = storeStatus.status;
                  return InkWell(
                    onTap: () => context.push('/admin/store-status'),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: status.reason.gradient),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.pause_circle_filled_rounded,
                              color: Colors.white, size: 28),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'STORE IS CLOSED',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Not accepting new orders — tap to reopen',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // Stats Overview
              if (adminProvider.stats != null)
  Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        //removed dashboard heading //--------//

        // DashboardHeader(
        //   updatedText: _lastRefreshTime == null
        //       ? "Loading..."
        //       : "Updated ${_formatLastRefresh(_lastRefreshTime!)}",
        // ),

        // const SizedBox(height: 24),
        
        //added pending orders//
       const SectionTitle(
  title: "Orders Requiring Action",
),
const SizedBox(height: 16),

        actionRequiredOrders.isEmpty
    ? Container(
        padding: const EdgeInsets.all(20),
        decoration: DashboardTheme.cardDecoration,
        child: const Center(
  child: Text("No Orders Requiring Action"),
),
      )
    : Column(
        children: actionRequiredOrders
    .take(5)
            .map(
              (order) => PendingOrdersCard(
                order: order,
              ),
            )
            .toList(),
      ),

const SizedBox(height: 24),
        

        const SectionTitle(
          title: "Performance Summary",
        ),

        // RevenueCard(
        //   amount: currencyFormat.format(
        //     (adminProvider.stats!['revenue']?['today'] ?? 0).toDouble(),
        //   ),
        // ),

        // const SizedBox(height: 24),

        Container(
          decoration: DashboardTheme.cardDecoration,
          child: Column(
            children: [

              _summaryTile(
                Icons.shopping_bag_outlined,
                "Total Orders",
                "${adminProvider.stats!['orders']['total']}",
                DashboardTheme.primary,
              ),

              _summaryTile(
  Icons.pending_actions,
  "Action Required",
  "${actionRequiredOrders.length}",
  Colors.orange,
),

              _summaryTile(
                Icons.today_outlined,
                "Today's Orders",
                "${adminProvider.stats!['orders']['today']}",
                Colors.blue,
              ),

              _summaryTile(
                Icons.people_outline,
                "Users",
                "${adminProvider.stats!['users']['total']}",
                Colors.purple,
              ),

              _summaryTile(
                Icons.inventory_2_outlined,
                "Products",
                "${adminProvider.stats!['products']['total']}",
                Colors.teal,
              ),

              _summaryTile(
                Icons.warning_amber_rounded,
                "Low Stock",
                "${adminProvider.stats!['products']['lowStock']}",
                Colors.red,
              ),

            ],
          ),
        ),

        const SizedBox(height: 24),

      ],
    ),
  ),

              // Quick Actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Column(
  children: [

    Consumer<StoreStatusProvider>(
      builder: (context, storeStatus, _) => ActionTile(
        title: "Store Status",
        subtitle: storeStatus.isOpen
            ? "Open — accepting orders"
            : "Closed — ${storeStatus.status.reason.adminLabel}",
        icon: storeStatus.isOpen
            ? Icons.storefront_outlined
            : Icons.pause_circle_outline_rounded,
        onTap: () => context.push('/admin/store-status'),
      ),
    ),

    ActionTile(
      title: "Orders",
      subtitle: "Manage customer orders",
      icon: Icons.shopping_bag_outlined,
      onTap: () => context.push('/admin/orders'),
    ),

    ActionTile(
      title: "Users",
      subtitle: "Manage registered users",
      icon: Icons.people_outline,
      onTap: () => context.push('/admin/users'),
    ),

    ActionTile(
      title: "Riders",
      subtitle: "Manage delivery partners",
      icon: Icons.delivery_dining_outlined,
      onTap: () => context.push('/admin/riders'),
    ),
    ActionTile(
  title: "Support Requests",
  subtitle: "Manage customer complaints",
  icon: Icons.support_agent_outlined,
  onTap: () => context.push('/admin/support-requests'),
),

    ActionTile(
      title: "Products",
      subtitle: "Inventory management",
      icon: Icons.inventory_2_outlined,
      onTap: () => context.push('/admin/products'),
    ),
    

    ActionTile(
      title: "Categories",
      subtitle: "Manage categories",
      icon: Icons.category_outlined,
      onTap: () => context.push('/admin/categories'),
    ),

    ActionTile(
      title: "Category Order",
      subtitle: "Sort categories",
      icon: Icons.sort,
      onTap: () => context.push('/admin/categories/order'),
    ),

    ActionTile(
      title: "Campaigns",
      subtitle: "Offers & promotions",
      icon: Icons.campaign_outlined,
      onTap: () => context.push('/admin/campaigns'),
    ),

    ActionTile(
      title: "Push Notifications",
      subtitle: "Send notifications",
      icon: Icons.notifications_active_outlined,
      onTap: () => context.push('/admin/notifications'),
    ),

  ],
),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _formatLastRefresh(DateTime lastRefresh) {
    final now = DateTime.now();
    final difference = now.difference(lastRefresh);
    
    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${difference.inHours}h ago';
    }
  }
}

Widget _summaryTile(
  IconData icon,
  String title,
  String value,
  Color color,
) {
  return ListTile(
    leading: CircleAvatar(
      radius: 20,
      backgroundColor: color.withOpacity(.12),
      child: Icon(icon, color: color, size: 20),
    ),
    title: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
      ),
    ),
    trailing: Text(
      value,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: color),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                  height: 1.1,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.grey,
                height: 1.1,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class ActionTile extends StatelessWidget {

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const ActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {

    return Container(

      margin: const EdgeInsets.only(bottom: 12),

      child: Material(

        borderRadius: BorderRadius.circular(16),

        color: Colors.white,

        child: InkWell(

          borderRadius: BorderRadius.circular(16),

          onTap: onTap,

          child: Padding(

            padding: const EdgeInsets.all(16),

            child: Row(

              children: [

                CircleAvatar(
                  radius: 24,
                  backgroundColor: DashboardTheme.primary.withOpacity(.12),
                  child: Icon(
                    icon,
                    color: DashboardTheme.primary,
                  ),
                ),

                const SizedBox(width: 16),

                Expanded(

                  child: Column(

                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [

                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),

                    ],
                  ),
                ),

                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 18,
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }
}