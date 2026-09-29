import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/order_provider.dart';
import '../providers/store_status_provider.dart';

/// When the app returns to foreground, refetch active orders so the home bar
/// matches server state (FCM does not deliver [onMessage] while backgrounded).
class AppLifecycleRefresh extends StatefulWidget {
  const AppLifecycleRefresh({super.key, required this.child});

  final Widget child;

  @override
  State<AppLifecycleRefresh> createState() => _AppLifecycleRefreshState();
}

class _AppLifecycleRefreshState extends State<AppLifecycleRefresh>
    with WidgetsBindingObserver {
  DateTime? _lastResumeRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;

    final now = DateTime.now();
    if (_lastResumeRefresh != null &&
        now.difference(_lastResumeRefresh!) < const Duration(seconds: 2)) {
      return;
    }
    _lastResumeRefresh = now;

    // Store open/closed first, and for EVERY user including guests — this is
    // the main way a long-lived app instance learns the store closed (or
    // reopened) while it sat in the background. It must run before the token
    // check below, or guests would never see the banner update.
    Provider.of<StoreStatusProvider>(context, listen: false).refresh(force: true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.token == null) {
      if (kDebugMode) {
        debugPrint('🔄 [AppLifecycle] resumed → store status only (guest)');
      }
      return;
    }

    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    orderProvider.fetchActiveOrders(
      auth.token!,
      getUpdatedToken: () => auth.token,
    );
    if (kDebugMode) {
      debugPrint('🔄 [AppLifecycle] resumed → store status + fetchActiveOrders');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
