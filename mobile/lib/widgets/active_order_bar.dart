import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/order_provider.dart';
import '../providers/auth_provider.dart';
import '../models/active_order_model.dart';
import '../l10n/app_localizations.dart';

/// Active order bar — home screen ke bottom pe dikhta hai jab orders active hain
/// Multiple orders hain toh horizontal scroll hota hai (Zomato/Blinkit style)
/// Kyun: User ko pata rahe ki order ka kya status hai bina orders page khole
class ActiveOrderBar extends StatefulWidget {
  const ActiveOrderBar({super.key});

  @override
  State<ActiveOrderBar> createState() => _ActiveOrderBarState();
}

class _ActiveOrderBarState extends State<ActiveOrderBar> {
  // PageController — horizontal scroll ke liye
  // Kyun: PageView use kar rahe hain taki ek ek card snap ho, free scroll nahi
  final PageController _pageController = PageController(
    viewportFraction: 0.92, // 92% width — thoda adjacent card ka hint dikhega
  );
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose(); // Memory leak se bachao — controller dispose karo
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<OrderProvider, AuthProvider>(
      builder: (context, orderProvider, authProvider, _) {
        // activeOrders already filtered from backend (status=active&fields=light)
        final activeOrders = orderProvider.activeOrders;

        if (activeOrders.isEmpty) return const SizedBox.shrink();

        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Horizontal scrollable order cards
                // Kyun: Agar 3 orders hain toh vertically stack karna bahut jagah leta hai
                // Horizontal swipe = compact + modern
                SizedBox(
                  height: 76,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: activeOrders.length,
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _OrderCard(order: activeOrders[index]),
                      );
                    },
                  ),
                ),
                // Page indicator dots — sirf tab dikhao jab 2+ orders hain
                // Kyun: 1 order pe dots dikhana unnecessary hai
                if (activeOrders.length > 1) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(activeOrders.length, (index) {
                      final isActive = index == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        height: 6,
                        // Active dot wider hota hai — visual feedback ki kaunsa card dikh raha hai
                        width: isActive ? 20 : 6,
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF0A5C18)
                              : const Color(0xFFD0D0D0),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Individual order card — ek active order ka status dikhata hai
/// Tap karne pe order tracking screen pe le jaata hai
class _OrderCard extends StatelessWidget {
  final ActiveOrderModel order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final statusInfo = _getStatusInfo(order.status);
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return GestureDetector(
      onTap: () => context.push('/order/${order.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          // Gradient — status ke hisaab se color change hota hai
          // pending=orange, accepted=blue, preparing=purple, out_for_delivery=green
          gradient: LinearGradient(
            colors: [statusInfo.color, statusInfo.color.withValues(alpha: 0.85)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: statusInfo.color.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Status icon — pastel circle mein
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(statusInfo.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            // Order info — ID + status + amount
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Order #${order.id} • ${statusInfo.label}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${currencyFormat.format(order.totalAmount)} • ${statusInfo.subtitle}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            // Track button — white pill, tap pe order detail khulta hai
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                AppLocalizations.of(context).orderTrackShort,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: statusInfo.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Status ke hisaab se color, icon, label decide karo
  /// Kyun: Har status ka alag visual feedback hona chahiye — user ko turant pata chale
  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case 'pending':
        return _StatusInfo(
          label: 'Order Placed',
          subtitle: 'Confirming your order...',
          icon: Icons.schedule_rounded,
          color: const Color(0xFFFF9800),
        );
      // Paid, waiting on the store's accept/refuse decision. Newly reachable —
      // the backend's `active` filter omitted this status, so a successfully
      // paid order used to vanish from this bar entirely. Without a case here
      // it would fall through to the grey "Processing / Please wait..." default,
      // which tells a paying customer nothing.
      case 'awaiting_acceptance':
        return _StatusInfo(
          label: 'Confirmed',
          subtitle: 'Payment received — sending to store',
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF00897B),
        );
      case 'accepted':
        return _StatusInfo(
          // 'Confirmed' now belongs to the paid-but-unaccepted step above; once
          // the store has actually accepted, say so rather than repeating the
          // same word. Matches ActiveOrderModel.statusText.
          label: 'Accepted',
          subtitle: 'Order accepted by store',
          icon: Icons.storefront_rounded,
          color: const Color(0xFF2196F3),
        );
      case 'preparing':
        return _StatusInfo(
          label: 'Preparing',
          subtitle: 'Being packed with care',
          icon: Icons.inventory_2_rounded,
          color: const Color(0xFF9C27B0),
        );
      case 'out_for_delivery':
        return _StatusInfo(
          label: 'On the way',
          subtitle: 'Arriving soon!',
          icon: Icons.delivery_dining_rounded,
          color: const Color(0xFF0A5C18),
        );
      default:
        return _StatusInfo(
          label: 'Processing',
          subtitle: 'Please wait...',
          icon: Icons.hourglass_top_rounded,
          color: const Color(0xFF757575),
        );
    }
  }
}

class _StatusInfo {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;

  _StatusInfo({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}
