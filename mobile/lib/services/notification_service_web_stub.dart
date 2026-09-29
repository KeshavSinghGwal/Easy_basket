// Web stub for NotificationService - Firebase Messaging not supported on web
import 'package:flutter/material.dart';
import '../providers/admin_provider.dart';
import '../providers/auth_provider.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  String? get fcmToken => null;

  Future<void> initialize({
    required BuildContext context,
    required AdminProvider adminProvider,
    required AuthProvider authProvider,
  }) async {
    debugPrint('⚠️ FCM not supported on web platform');
  }

  void updateContext(BuildContext context) {
    // No-op for web
  }

  void updateProviders({
    AdminProvider? adminProvider,
    AuthProvider? authProvider,
  }) {
    // No-op for web
  }

  /// Request notification permission — no-op on web
  Future<bool> requestNotificationPermission() async => true;

  /// Web is never prompted (kIsWeb guards the caller); report enabled so the
  /// "ask until granted" flow treats web as already handled.
  Future<bool> areNotificationsEnabled() async => true;

  String? get currentSubscribedPincode => null;
  /// No-op on web — FCM topics aren't supported here. Web users pick up a
  /// store reopen via app-resume refresh or pull-to-refresh instead.
  Future<void> subscribeToBroadcastTopic() async {}

  Future<void> switchPincodeTopic(String newPincode) async {}
  Future<void> subscribeToPincode(String pincode) async {}
  Future<void> subscribeToAllPincodes(List<String> pincodes) async {}
  Future<void> unsubscribeCurrentTopic() async {}

  /// Manually trigger FCM token generation and send to backend
  /// No-op for web since FCM is not supported
  Future<void> ensureTokenSent() async {
    debugPrint('⚠️ NotificationService: ensureTokenSent() called but FCM not supported on web.');
    // No-op for web
  }
}

