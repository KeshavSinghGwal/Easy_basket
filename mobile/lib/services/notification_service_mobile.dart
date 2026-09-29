import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../core/api_client.dart';
import 'package:provider/provider.dart';
import '../providers/admin_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/order_provider.dart';
import '../providers/store_status_provider.dart';
import '../routes/app_router.dart';
import '../core/startup_deep_link.dart';

// Background message handler — must be top-level function (not inside class)
// Kyun: Flutter requires background handlers to be top-level
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  debugPrint('📩 [FCM] Background message received: ${message.notification?.title}');
  // System automatically shows notification in notification bar
  // No extra code needed here
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // sharedApiService, not a fresh ApiService(): the FCM-token calls this makes
  // are ordinary authenticated requests, and a locally built instance carries no
  // onTokenExpired, so they silently stopped working once the access token
  // lapsed — leaving the device registered under a stale token.
  final ApiService _apiService = sharedApiService;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  BuildContext? _context;
  AdminProvider? _adminProvider;
  AuthProvider? _authProvider;
  bool _isInitialized = false;
  String? _fcmToken;

  String? get fcmToken => _fcmToken;

  // ── Notification Channel (Generic — sab type ki notifications isme aayengi) ──
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'easy_basket_notifications', // same as AndroidManifest mein
    'Easy Basket Notifications', // user ko dikhne wala naam
    description: 'Order updates, offers, and more',
    importance: Importance.high, // high = sound + popup
  );

  /// Initialize Notification Service
  /// Kyun: App start hote hi FCM setup karna zaroori hai
  Future<void> initialize({
    required BuildContext context,
    required AdminProvider adminProvider,
    required AuthProvider authProvider,
  }) async {
    if (kIsWeb) {
      debugPrint('⚠️ Notifications not supported on web');
      return;
    }

    if (_isInitialized) {
      debugPrint('⚠️ [FCM] Service already initialized');
      return;
    }

    _context = context;
    _adminProvider = adminProvider;
    _authProvider = authProvider;

    // 1. Notification permission — DON'T ask on login
    // Ask after first order (higher accept rate — Blinkit style)
    // _requestPermission() will be called from payment success screen

    // 2. Local notifications setup karo (foreground mein dikhane ke liye)
    await _setupLocalNotifications();

    // 3. FCM token lo (device ka unique address)
    await _getToken();

    // 4. Token refresh listener lagao (agar Firebase token change kare)
    _listenTokenRefresh();

    // 5. Foreground listener — app khuli hai tab
    _listenForeground();

    // 6. Background handler — app band hai tab
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // 7. Tap handler — user notification tap kare tab
    _listenNotificationTap();

    // 8. Check — agar app notification tap se khuli hai (cold start)
    _handleInitialMessageRefreshOnly();

    // 9. Broadcast topic — store reopen announcements jaate hain yahan
    // Kyun: pincode topic sirf address save karne ke baad milta hai, isliye
    // naye users reopen push miss kar dete.
    // Note: guests yahan tak pahunchte hi nahi (initialize sirf logged-in users
    // ke liye chalta hai), isliye main.dart ise alag se bhi call karta hai.
    await subscribeToBroadcastTopic();

    _isInitialized = true;
    debugPrint('✅ [FCM] Notification service initialized');
    await _sendTokenToBackend();
  }

  // ── 1. Permission maango ──
  // Kyun: Android 13+ mein bina permission ke notification nahi dikhegi
  /// Request notification permission — call after an order.
  /// Returns true if granted (authorized or provisional).
  Future<bool> requestNotificationPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,    // notification dikhao
      badge: true,    // app icon pe badge dikhao
      sound: true,    // sound bajao
    );
    debugPrint('📋 [FCM] Permission status: ${settings.authorizationStatus}');
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Whether notifications are already granted — checked (does NOT prompt) so we
  /// can skip re-asking once the user has enabled them.
  Future<bool> areNotificationsEnabled() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  // ── 2. Local notifications setup ──
  // Kyun: Jab app foreground mein ho tab in-app banner dikhane ke liye
  Future<void> _setupLocalNotifications() async {
    // Android settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // Initialize
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    // Notification channel create karo
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Foreground mein Firebase ki default notification BAND karo
    // Kyun: Hum khud in-app banner dikhayenge, phone bar mein nahi
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
  }

  // ── 3. FCM Token lo ──
  // Kyun: Ye device ka unique address hai — backend ko ye dena padta hai
  Future<void> _getToken() async {
    try {
      _fcmToken = await _messaging.getToken();
      debugPrint('🔑 [FCM] Token: ${_fcmToken?.substring(0, 20)}...');
    } catch (e) {
      debugPrint('❌ [FCM] Error getting token: $e');
    }
  }

  // ── 4. Token refresh listener ──
  // Kyun: Kabhi kabhi Firebase token change karta hai — naya token backend ko bhejte raho
  void _listenTokenRefresh() {
    _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('🔄 [FCM] Token refreshed');
      _fcmToken = newToken;
      _sendTokenToBackend();
    });
  }

  // ── 5. Foreground listener ──
  // Kyun: Jab app KHULI hai tab notification aaye toh in-app banner dikhao
  // + agar order related notification hai toh orders refresh karo (active order bar update hoga)
  void _listenForeground() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📩 [FCM] Foreground message: ${message.notification?.title}');

      // Refresh bar even for data-only messages (notification can be null)
      _maybeRefreshOrdersFromPayload(message.data);

      final notification = message.notification;
      if (notification == null) return;

      _showInAppBanner(
        title: notification.title ?? 'Easy Basket',
        body: notification.body ?? '',
        data: message.data,
      );
    });
  }

  /// Any backend payload that signals an order lifecycle change → refetch active orders bar.
  void _maybeRefreshOrdersFromPayload(Map<String, dynamic> data) {
    final type = (data['type'] as String? ?? '').toLowerCase();
    final orderIdRaw = data['orderId']?.toString();
    final hasOrderId = orderIdRaw != null && orderIdRaw.isNotEmpty;
    final shouldRefresh =
        type.contains('order') || (hasOrderId && type.isEmpty);
    if (shouldRefresh) {
      _refreshOrders();
    }

    // Store reopened while the app was open — refresh so the closed banner
    // disappears and the checkout buttons come back to life without the user
    // having to background the app or pull to refresh.
    if (type == 'store_reopened') {
      _refreshStoreStatus();
    }
  }

  /// Re-read store status. No auth needed — the endpoint is public.
  void _refreshStoreStatus() {
    if (_context == null) return;

    try {
      Provider.of<StoreStatusProvider>(_context!, listen: false)
          .refresh(force: true);
      debugPrint('🏪 [FCM] Store status refreshed after reopen push');
    } catch (e) {
      debugPrint('❌ [FCM] Error refreshing store status: $e');
    }
  }

  // ── Orders refresh karo (FCM trigger pe) ──
  // Kyun: Jab order status change ho toh active order bar turant update ho
  void _refreshOrders() {
    if (_context == null || _authProvider?.token == null) return;

    try {
      final orderProvider = Provider.of<OrderProvider>(_context!, listen: false);
      orderProvider.fetchActiveOrders(
        _authProvider!.token!,
        getUpdatedToken: () => _authProvider?.token,
      );
      debugPrint('🔄 [FCM] Orders refreshed after order notification');
    } catch (e) {
      debugPrint('❌ [FCM] Error refreshing orders: $e');
    }
  }

  // ── 6. Notification tap handler ──
  // Kyun: User notification tap kare toh sahi screen pe le jao
  void _listenNotificationTap() {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('👆 [FCM] Notification tapped: ${message.notification?.title}');
      _maybeRefreshOrdersFromPayload(message.data);
      _navigateFromNotification(message.data);
    });
  }

  // ── 7. Cold start check ──
  // Kyun: Agar app band thi aur user ne notification tap karke kholi toh navigate karo
  /// Cold-start navigation is handled in [main] + [StartupDeepLink] + GoRouter redirect
  /// (getInitialMessage is read once). Here we only refresh the order bar if needed.
  void _handleInitialMessageRefreshOnly() {
    final data = StartupDeepLink.takePendingRefreshData();
    if (data == null) return;
    debugPrint('🚀 [FCM] Cold start refresh from pending notification data');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeRefreshOrdersFromPayload(data);
    });
  }

  // ── In-app banner dikhao (foreground) ──
  void _showInAppBanner({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) {
    if (_context == null) return;

    final type = data?['type'] as String? ?? '';
    final status = data?['status'] as String? ?? '';
    final isAdmin = _authProvider?.user?.role == 'admin';
    final isAdminOrderAction = isAdmin && type == 'new_order';
    // Customer raised a cancellation/refund request → urgent admin action banner.
    final isCancelRequest = isAdmin && type == 'refund_requested';

    final overlay = Overlay.of(_context!);
    late OverlayEntry entry;

    if (isAdminOrderAction) {
      entry = OverlayEntry(
        builder: (context) => _AdminActionBanner(
          title: title,
          body: body,
          onAccept: () async {
            entry.remove();
            final orderId = data?['orderId'] as String?;
            if (orderId != null && _adminProvider != null && _authProvider?.token != null) {
              await _adminProvider!.updateOrderStatus(
                token: _authProvider!.token!,
                orderId: int.parse(orderId),
                status: 'accepted',
              );
            }
          },
          onReject: () async {
            entry.remove();
            final orderId = data?['orderId'] as String?;
            if (orderId != null && _adminProvider != null && _authProvider?.token != null) {
              await _adminProvider!.updateOrderStatus(
                token: _authProvider!.token!,
                orderId: int.parse(orderId),
                status: 'cancelled',
                notes: 'Rejected by admin',
              );
            }
          },
          onDismiss: () => entry.remove(),
          onTap: () {
            entry.remove();
            if (data != null) _navigateFromNotification(data);
          },
        ),
      );
      overlay.insert(entry);
    } else if (isCancelRequest) {
      entry = OverlayEntry(
        builder: (context) => _AdminActionBanner(
          title: title,
          body: body,
          icon: Icons.report_gmailerrorred_rounded,
          iconBg: const Color(0xFFFFEBEE),
          iconColor: Colors.red,
          acceptLabel: 'Approve',
          rejectLabel: 'Reject',
          onAccept: () async {
            entry.remove();
            final orderId = data?['orderId'] as String?;
            if (orderId != null && _adminProvider != null && _authProvider?.token != null) {
              await _adminProvider!.approveCancellation(
                token: _authProvider!.token!,
                orderId: int.parse(orderId),
              );
            }
          },
          onReject: () async {
            entry.remove();
            final orderId = data?['orderId'] as String?;
            if (orderId != null && _adminProvider != null && _authProvider?.token != null) {
              await _adminProvider!.rejectCancellation(
                token: _authProvider!.token!,
                orderId: int.parse(orderId),
              );
            }
          },
          onDismiss: () => entry.remove(),
          onTap: () {
            entry.remove();
            if (data != null) _navigateFromNotification(data);
          },
        ),
      );
      overlay.insert(entry);
    } else {
      // Status-based banner
      final isCancelled = status == 'cancelled' || type.contains('cancelled');
      entry = OverlayEntry(
        builder: (context) => _NotificationBanner(
          title: title,
          body: body,
          status: status,
          type: type,
          isCancelled: isCancelled,
          onTap: () {
            entry.remove();
            if (data != null) _navigateFromNotification(data);
          },
          onDismiss: () => entry.remove(),
        ),
      );
      overlay.insert(entry);
      // Cancelled = stays 10 sec, normal = 6 sec
      Future.delayed(Duration(seconds: isCancelled ? 10 : 6), () {
        if (entry.mounted) entry.remove();
      });
    }
  }

  // ── Navigate based on notification type ──
  // Kyun: Har notification type ke liye alag screen pe le jaana hai
  void _navigateFromNotification(Map<String, dynamic> data) {
    if (_context == null) return;

    final type = (data['type'] as String? ?? '').toLowerCase();
    final orderIdRaw = data['orderId']?.toString();
    final productId = data['productId']?.toString();
    final categoryId = data['categoryId']?.toString();

    debugPrint('🧭 [FCM] Navigate — type: $type, orderId: $orderIdRaw');

    if (type.contains('promo') && categoryId != null && categoryId.isNotEmpty) {
      final cid = int.tryParse(categoryId);
      if (cid != null) {
        _context!.push('/categories/$cid/products', extra: {
          'parentCategoryName': data['categoryName'] ?? 'Offers',
        });
      }
      return;
    }

    if (type.startsWith('stock_') && productId != null && productId.isNotEmpty) {
      final pid = int.tryParse(productId);
      if (pid != null) _context!.push('/product/$pid');
      return;
    }

    final isOrderContext =
        type.contains('order') || type.contains('payment') || (orderIdRaw != null && orderIdRaw.isNotEmpty);

    if (isOrderContext && orderIdRaw != null && orderIdRaw.isNotEmpty) {
      final orderId = int.tryParse(orderIdRaw);
      if (orderId == null) {
        _pushDefaultHubForRole();
        return;
      }
      final role = _authProvider?.user?.role;
      if (role == 'admin') {
        AppRouter.router.push('/admin/orders/$orderId');
      } else if (role == 'delivery') {
        AppRouter.router.push('/delivery/order/$orderId');
      } else {
        AppRouter.router.push('/order/$orderId');
      }
      return;
    }

    _pushDefaultHubForRole();
  }

  void _pushDefaultHubForRole() {
    final role = _authProvider?.user?.role;
    if (role == 'admin') {
      AppRouter.router.push('/admin/orders');
    } else if (role == 'delivery') {
      AppRouter.router.push('/delivery/orders');
    } else {
      AppRouter.router.push('/orders');
    }
  }

  // ── Local notification response handler ──
  void _handleNotificationResponse(NotificationResponse response) {
    _onNotificationTap(response.payload);
  }

  // ── Local notification tap handler ──
  void _onNotificationTap(String? payload) {
    if (payload == null || _context == null) return;
    // payload mein orderId ya route aata hai
    _context!.push(payload);
  }

  // ── Backend ko FCM token bhejo ──
  // Kyun: Backend ko token chahiye taki wo notification bhej sake is device pe
  Future<void> _sendTokenToBackend() async {
    if (_fcmToken == null) return;
    final jwt = _authProvider?.token;
    if (jwt == null || jwt.isEmpty) {
      debugPrint('⚠️ [FCM] Skipping /auth/fcm-token — no access token yet');
      return;
    }

    try {
      await _apiService.post(
        '/auth/fcm-token',
        {'fcmToken': _fcmToken},
        token: jwt,
      );
      debugPrint('✅ [FCM] Token sent to backend');
    } catch (e) {
      debugPrint('❌ [FCM] Error sending token to backend: $e');
    }
  }

  /// Login ke baad call karo — token backend ko bhejta hai
  Future<void> ensureTokenSent() async {
    if (kIsWeb) return;
    await _getToken();
    await _sendTokenToBackend();
  }

  /// Context update karo (navigation ke liye zaroori)
  void updateContext(BuildContext context) {
    _context = context;
  }

  /// Providers update karo
  void updateProviders({
    AdminProvider? adminProvider,
    AuthProvider? authProvider,
  }) {
    if (adminProvider != null) _adminProvider = adminProvider;
    if (authProvider != null) _authProvider = authProvider;
  }

  // ── FCM Topic Subscribe (Pincode-based promo notifications) ──
  // Rule: User is subscribed to ONLY 1 pincode topic at a time
  // This ensures user only receives promos for their current delivery area

  /// Broadcast topic — sab devices isme rehte hain.
  /// Store reopen announcement isi topic pe jaata hai (backend:
  /// StoreStatusController.broadcastReopen).
  static const String broadcastTopic = 'all_users';

  /// Ek hi baar subscribe karo — main.dart ka postFrameCallback har rebuild pe
  /// chalta hai, warna har rebuild pe ek network call chali jaati.
  bool _broadcastSubscribed = false;

  /// Subscribe to the broadcast topic.
  ///
  /// PUBLIC and deliberately independent of [initialize] — that runs only for
  /// logged-in users (see main.dart), so guests would otherwise never receive
  /// the store-reopen announcement. Only needs Firebase.initializeApp(), which
  /// main() already does unconditionally on mobile.
  ///
  /// Failure yahan swallow karte hain — notification na milna app ko todna
  /// nahi chahiye.
  Future<void> subscribeToBroadcastTopic() async {
    if (kIsWeb || _broadcastSubscribed) return;
    try {
      await _messaging.subscribeToTopic(broadcastTopic);
      _broadcastSubscribed = true;
      debugPrint('📌 [FCM] Subscribed to: $broadcastTopic');
    } catch (e) {
      // Leave the flag false so a later attempt can retry (e.g. iOS before the
      // APNs token exists).
      debugPrint('⚠️ [FCM] Broadcast topic subscribe failed: $e');
    }
  }

  /// Currently subscribed pincode — track to avoid unnecessary calls
  String? _currentSubscribedPincode;

  /// Get current subscribed pincode
  String? get currentSubscribedPincode => _currentSubscribedPincode;

  /// Switch pincode topic — unsubscribe old + subscribe new (1 call)
  /// This is the ONLY method to call from outside — handles everything
  Future<void> switchPincodeTopic(String newPincode) async {
    if (kIsWeb || newPincode.isEmpty) return;
    if (newPincode == _currentSubscribedPincode) return; // Same — no change

    // Unsubscribe old
    if (_currentSubscribedPincode != null && _currentSubscribedPincode!.isNotEmpty) {
      final oldTopic = 'pincode_$_currentSubscribedPincode';
      await _messaging.unsubscribeFromTopic(oldTopic);
      debugPrint('📌 [FCM] Unsubscribed from: $oldTopic');
    }

    // Subscribe new
    final newTopic = 'pincode_$newPincode';
    await _messaging.subscribeToTopic(newTopic);
    _currentSubscribedPincode = newPincode;
    debugPrint('📌 [FCM] Subscribed to: $newTopic');
  }

  /// Subscribe to a specific pincode (used on first address save)
  Future<void> subscribeToPincode(String pincode) async {
    await switchPincodeTopic(pincode);
  }

  /// Subscribe to all pincodes — DEPRECATED, kept for backward compat
  /// Now only subscribes to FIRST (default) pincode
  Future<void> subscribeToAllPincodes(List<String> pincodes) async {
    if (kIsWeb || pincodes.isEmpty) return;
    // Only subscribe to first/default pincode — not all
    await switchPincodeTopic(pincodes.first);
  }

  /// Unsubscribe from current topic — call on logout
  Future<void> unsubscribeCurrentTopic() async {
    if (kIsWeb) return;
    if (_currentSubscribedPincode != null && _currentSubscribedPincode!.isNotEmpty) {
      final topic = 'pincode_$_currentSubscribedPincode';
      await _messaging.unsubscribeFromTopic(topic);
      debugPrint('📌 [FCM] Unsubscribed (logout): $topic');
      _currentSubscribedPincode = null;
    }
  }
}

// ── Admin Action Banner Widget ──
// Kyun: Admin ko new order aaye toh Accept/Reject buttons dikhane ke liye
class _AdminActionBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onDismiss;
  final VoidCallback onTap;
  // Customisable so the same banner serves new orders (Accept/Reject, bag icon)
  // and cancellation requests (Approve/Reject, warning icon).
  final String acceptLabel;
  final String rejectLabel;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;

  const _AdminActionBanner({
    required this.title,
    required this.body,
    required this.onAccept,
    required this.onReject,
    required this.onDismiss,
    required this.onTap,
    this.acceptLabel = 'Accept',
    this.rejectLabel = 'Reject',
    this.icon = Icons.shopping_bag_rounded,
    this.iconBg = const Color(0xFFFFF3E0),
    this.iconColor = const Color(0xFFFF9800),
  });

  @override
  State<_AdminActionBanner> createState() => _AdminActionBannerState();
}

class _AdminActionBannerState extends State<_AdminActionBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          margin: EdgeInsets.only(top: topPadding + 4, left: 12, right: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top row — icon, title, close
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.iconBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.icon, color: widget.iconColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onTap,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.body,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Icon(Icons.close, size: 18, color: Colors.grey[400]),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Action buttons
              if (_isLoading)
                const SizedBox(
                  height: 36,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                Row(
                  children: [
                    // Reject button
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _isLoading = true);
                          widget.onReject();
                        },
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Center(
                            child: Text(
                              widget.rejectLabel,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.red),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Accept button
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _isLoading = true);
                          widget.onAccept();
                        },
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0A5C18), Color(0xFF1B8A2E), Color(0xFF0A5C18)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              stops: [0.0, 0.5, 1.0],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  widget.acceptLabel,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status-based styling helper ──
class _BannerStyle {
  final Color bgColor;
  final Color iconBgColor;
  final Color iconColor;
  final Color accentColor;
  final IconData icon;
  final String emoji;

  const _BannerStyle({
    required this.bgColor,
    required this.iconBgColor,
    required this.iconColor,
    required this.accentColor,
    required this.icon,
    required this.emoji,
  });

  static _BannerStyle fromStatus(String status, String type) {
    final s = status.toLowerCase();
    final t = type.toLowerCase();

    if (s == 'cancelled' || t.contains('cancelled')) {
      return const _BannerStyle(
        bgColor: Color(0xFFFFF5F5),
        iconBgColor: Color(0xFFFFEBEE),
        iconColor: Color(0xFFE53935),
        accentColor: Color(0xFFE53935),
        icon: Icons.cancel_rounded,
        emoji: '⚠️',
      );
    }
    if (s == 'delivered' || t.contains('delivered')) {
      return const _BannerStyle(
        bgColor: Color(0xFFF1F8E9),
        iconBgColor: Color(0xFFC8E6C9),
        iconColor: Color(0xFF2E7D32),
        accentColor: Color(0xFF2E7D32),
        icon: Icons.check_circle_rounded,
        emoji: '✅',
      );
    }
    if (s == 'out_for_delivery') {
      return const _BannerStyle(
        bgColor: Color(0xFFE8F5E9),
        iconBgColor: Color(0xFFC8E6C9),
        iconColor: Color(0xFF43A047),
        accentColor: Color(0xFF43A047),
        icon: Icons.delivery_dining_rounded,
        emoji: '🚚',
      );
    }
    if (s == 'preparing') {
      return const _BannerStyle(
        bgColor: Color(0xFFFFF8E1),
        iconBgColor: Color(0xFFFFECB3),
        iconColor: Color(0xFFF57C00),
        accentColor: Color(0xFFF57C00),
        icon: Icons.restaurant_rounded,
        emoji: '🍳',
      );
    }
    if (s == 'accepted' || s == 'confirmed') {
      return const _BannerStyle(
        bgColor: Color(0xFFE3F2FD),
        iconBgColor: Color(0xFFBBDEFB),
        iconColor: Color(0xFF1565C0),
        accentColor: Color(0xFF1565C0),
        icon: Icons.thumb_up_rounded,
        emoji: '🔵',
      );
    }
    if (s == 'pending' || t.contains('new_order')) {
      return const _BannerStyle(
        bgColor: Color(0xFFFFF8E1),
        iconBgColor: Color(0xFFFFF3E0),
        iconColor: Color(0xFFFF9800),
        accentColor: Color(0xFFFF9800),
        icon: Icons.shopping_bag_rounded,
        emoji: '🟡',
      );
    }
    // Default — generic notification
    return const _BannerStyle(
      bgColor: Color(0xFFF5F5F5),
      iconBgColor: Color(0xFFE8F5E9),
      iconColor: Color(0xFF4CAF50),
      accentColor: Color(0xFF4CAF50),
      icon: Icons.notifications_active_rounded,
      emoji: '🔔',
    );
  }
}

// ── In-App Notification Banner Widget ──
class _NotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final String status;
  final String type;
  final bool isCancelled;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationBanner({
    required this.title,
    required this.body,
    required this.status,
    required this.type,
    required this.isCancelled,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<_NotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final style = _BannerStyle.fromStatus(widget.status, widget.type);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onTap: widget.onTap,
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
              widget.onDismiss();
            }
          },
          child: Container(
            margin: EdgeInsets.only(top: topPadding + 8, left: 14, right: 14),
            decoration: BoxDecoration(
              color: style.bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: style.accentColor.withValues(alpha: 0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: style.accentColor.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Accent bar at top
                Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color: style.accentColor,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    children: [
                      // Status icon with colored bg
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: style.iconBgColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(style.icon, color: style.iconColor, size: 24),
                      ),
                      const SizedBox(width: 12),
                      // Title + Body
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: widget.isCancelled ? const Color(0xFFE53935) : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.body,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[700],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Action area — Track button or dismiss
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: widget.onDismiss,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.05),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.close, size: 14, color: Colors.grey[500]),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Track arrow
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: style.accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.arrow_forward_rounded, size: 16, color: style.accentColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
