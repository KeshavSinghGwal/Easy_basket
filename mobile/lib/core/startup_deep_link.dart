import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Maps FCM `data` + user role to a single GoRouter path (same rules as [NotificationService]).
String? routePathFromFcmData(Map<String, dynamic> data, String? role) {
  final type = (data['type'] as String? ?? '').toLowerCase();
  final orderIdRaw = data['orderId']?.toString();
  final productId = data['productId']?.toString();
  final categoryId = data['categoryId']?.toString();

  if (type.contains('promo') && categoryId != null && categoryId.isNotEmpty) {
    final cid = int.tryParse(categoryId);
    if (cid != null) return '/categories/$cid/products';
  }

  if (type.startsWith('stock_') && productId != null && productId.isNotEmpty) {
    final pid = int.tryParse(productId);
    if (pid != null) return '/product/$pid';
  }

  final isOrderContext = type.contains('order') ||
      type.contains('payment') ||
      (orderIdRaw != null && orderIdRaw.isNotEmpty);

  if (isOrderContext && orderIdRaw != null && orderIdRaw.isNotEmpty) {
    final orderId = int.tryParse(orderIdRaw);
    if (orderId == null) return null;
    if (role == 'admin') return '/admin/orders/$orderId';
    if (role == 'delivery') return '/delivery/order/$orderId';
    return '/order/$orderId';
  }

  return null;
}

/// Cold-start tap: [getInitialMessage] is read once in [main] before [runApp].
/// GoRouter redirect uses [takePendingRoute] so the first screen is the deep link, not home.
class StartupDeepLink {
  static String? _pendingRoute;
  static Map<String, dynamic>? _pendingRefreshData;

  static void registerColdStart({required String route, Map<String, dynamic>? refreshData}) {
    _pendingRoute = route;
    _pendingRefreshData = refreshData;
  }

  /// Only when still at splash/login — avoids home flash before order screen on cold start.
  static String? takePendingAtEntryRoute(String currentLocation) {
    if (currentLocation != '/splash' && currentLocation != '/login') return null;
    final r = _pendingRoute;
    _pendingRoute = null;
    return r;
  }

  /// After navigation, refresh orders once (optional).
  static Map<String, dynamic>? takePendingRefreshData() {
    final d = _pendingRefreshData;
    _pendingRefreshData = null;
    return d;
  }

  /// Role from prefs before [AuthProvider] runs (same JSON as [AuthProvider]).
  static String? readRoleFromPrefs(SharedPreferences prefs) {
    final userJson = prefs.getString('user_data');
    if (userJson == null) return null;
    try {
      final map = jsonDecode(userJson) as Map<String, dynamic>;
      return map['role'] as String?;
    } catch (_) {
      return null;
    }
  }
}
