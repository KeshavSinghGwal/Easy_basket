import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/order_model.dart';
import '../../utils/theme.dart';
import '../../utils/date_utils.dart';
import '../../utils/navigation_utils.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({super.key});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  bool _hasLoaded = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollNearBottom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrders();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollNearBottom);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScrollNearBottom() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels < pos.maxScrollExtent - 400) return;

    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.token == null) return;
    if (!orderProvider.hasMoreOrders ||
        orderProvider.isLoadingMore ||
        orderProvider.isLoading) {
      return;
    }
    orderProvider.fetchOrders(
      authProvider.token!,
      paginated: true,
      append: true,
      getUpdatedToken: () {
        final updatedAuth = Provider.of<AuthProvider>(context, listen: false);
        return updatedAuth.token;
      },
    );
  }

  void _loadOrders() async {
    if (_hasLoaded) return;

    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.token != null) {
      _hasLoaded = true;
      if (kDebugMode) {
        print('🔄 Loading orders (paginated)...');
      }
      await orderProvider.fetchOrders(
        authProvider.token!,
        paginated: true,
        append: false,
        getUpdatedToken: () {
          final updatedAuth = Provider.of<AuthProvider>(context, listen: false);
          return updatedAuth.token;
        },
      );
    }
  }

  String _getPaymentStatusText(OrderModel order) {
    // Refund states first: `isPaid` stays true after a refund, so checking it
    // before these showed a flat "Paid" for orders that were already refunded.
    if (order.refundNeedsAttention) {
      return 'Refund delayed';
    }
    final ps = order.paymentStatus;
    if (ps == 'refunded') {
      return 'Refunded';
    }
    if (ps == 'refund_pending') {
      return 'Refund in progress';
    }
    if (order.isCod) {
      return 'Cash on Delivery';
    }
    if (order.isPaid) {
      return 'Paid';
    }
    return 'Pending';
  }

  Widget _buildOrderList(OrderProvider orderProvider, NumberFormat currencyFormat) {
    final orders = orderProvider.orders;
    
    if (orders.isEmpty) {
      return _buildEmptyState();
    }
    
    final showLoadMoreFooter =
        orderProvider.hasMoreOrders || orderProvider.isLoadingMore;

    return RefreshIndicator(
      onRefresh: () async {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        if (authProvider.token != null) {
          await orderProvider.fetchOrders(
            authProvider.token!,
            paginated: true,
            append: false,
            getUpdatedToken: () {
              final updatedAuth = Provider.of<AuthProvider>(context, listen: false);
              return updatedAuth.token;
            },
          );
        }
      },
      color: AppTheme.primaryGreen,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: orders.length + (showLoadMoreFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= orders.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: orderProvider.isLoadingMore
                    ? SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppTheme.primaryGreen,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          }
          final order = orders[index];
          return Padding(
            padding: EdgeInsets.only(bottom: index < orders.length - 1 ? 16 : 0),
            child: _buildOrderCard(order, currencyFormat),
          );
        },
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final orderProvider = Provider.of<OrderProvider>(context);
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title:  Text(AppLocalizations.of(context).orderMyOrders, style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => popOrRoleHub(context),
        ),
      ),
      body: orderProvider.isLoading && orderProvider.orders.isEmpty
          ? _buildLoadingState()
          : orderProvider.error != null && orderProvider.orders.isEmpty
              ? _buildErrorState(orderProvider)
              : _buildOrderList(orderProvider, currencyFormat),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).orderLoading,
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(OrderProvider orderProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: Colors.red.withOpacity(0.7),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).orderSomethingWrong,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              orderProvider.error ?? 'Failed to load orders',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.grey,
              ),
            ),
            const SizedBox(height: 24),
            AppTheme.gradientButton(
              onPressed: () {
                setState(() => _hasLoaded = false);
                _loadOrders();
              },
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child:  Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(AppLocalizations.of(context).commonTryAgain, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: () async {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final orderProvider = Provider.of<OrderProvider>(context, listen: false);
        if (authProvider.token != null) {
          await orderProvider.fetchOrders(
            authProvider.token!,
            paginated: true,
            append: false,
            getUpdatedToken: () {
              final updatedAuth = Provider.of<AuthProvider>(context, listen: false);
              return updatedAuth.token;
            },
          );
        }
      },
      color: AppTheme.primaryGreen,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        primary: false,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primaryGreen.withOpacity(0.15),
                      AppTheme.primaryGreen.withOpacity(0.05),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.shopping_bag_outlined,
                  size: 100,
                  color: AppTheme.primaryGreen,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                AppLocalizations.of(context).orderNoneYet,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.black,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context).orderStartShoppingHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.grey.withOpacity(0.8),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              AppTheme.gradientButton(
                onPressed: () => context.go('/home'),
                padding: const EdgeInsets.symmetric(horizontal: 40),
                height: 52,
                child:  Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_cart_rounded, size: 22, color: Colors.white),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context).cartStartShopping, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(OrderModel order, NumberFormat currencyFormat) {
    final statusColor = _getStatusColor(order.status);
    final statusIcon = _getStatusIcon(order.status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/order/${order.id}'),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row — Order ID + Status badge
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Order #${order.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 12, color: statusColor),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              order.statusText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Date
                Text(
                  formatISTDefault(order.createdAt),
                  style: TextStyle(fontSize: 12, color: AppTheme.grey),
                ),
                const SizedBox(height: 12),
                // Product items — compact row
                if (order.items.isNotEmpty)
                  Row(
                    children: [
                      // Product thumbnails
                      ...order.items.take(3).map((item) => Container(
                        margin: const EdgeInsets.only(right: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: item.product.imageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: item.product.imageUrl!,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    width: 44, height: 44,
                                    color: const Color(0xFFF5F5F5),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    width: 44, height: 44,
                                    color: const Color(0xFFF5F5F5),
                                    child: const Icon(Icons.image, size: 18, color: AppTheme.grey),
                                  ),
                                )
                              : Container(
                                  width: 44, height: 44,
                                  color: const Color(0xFFF5F5F5),
                                  child: const Icon(Icons.image, size: 18, color: AppTheme.grey),
                                ),
                        ),
                      )),
                      if (order.items.length > 3)
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '+${order.items.length - 3}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0C831F)),
                            ),
                          ),
                        ),
                      const Spacer(),
                      // Item count + total
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${order.items.length} item${order.items.length > 1 ? 's' : ''}',
                            style: TextStyle(fontSize: 11, color: AppTheme.grey),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            currencyFormat.format(order.totalAmount),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black),
                          ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                // Divider
                Container(height: 0.5, color: const Color(0xFFE0E0E0)),
                const SizedBox(height: 10),
                // Bottom row — Payment + View Details
                Row(
                  children: [
                    Icon(
                      order.isCod
                          ? Icons.money_rounded
                          : Icons.payment_rounded,
                      size: 14,
                      color: AppTheme.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getPaymentStatusText(order),
                      style: TextStyle(fontSize: 12, color: AppTheme.grey),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.push('/order/${order.id}'),
                      child:  Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppLocalizations.of(context).orderViewDetails,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0C831F)),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFF0C831F)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
      case 'preparing':
        return Colors.blue;
      case 'out_for_delivery':
        return Colors.purple;
      case 'delivered':
        return AppTheme.primaryGreen;
      case 'cancelled':
        return Colors.red;
      default:
        return AppTheme.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.pending;
      case 'accepted':
        return Icons.check_circle_outline;
      case 'preparing':
        return Icons.restaurant;
      case 'out_for_delivery':
        return Icons.delivery_dining;
      case 'delivered':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }
}

