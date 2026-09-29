import 'dart:convert';
import 'package:flutter/foundation.dart' show ChangeNotifier, kDebugMode, debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../models/user_model.dart';
import '../core/auth_refresh_notifier.dart';

class AuthProvider with ChangeNotifier {
  final AuthService authService;
  final SharedPreferences prefs;

  UserModel? _user;
  String? _accessToken;
  String? _refreshToken;
  bool _isLoading = false;
  String? _error;

  UserModel? get user => _user;
  String? get token => _accessToken; // For backward compatibility
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _accessToken != null && _user != null;

  AuthProvider({
    required this.authService,
    required this.prefs,
  }) {
    _loadAuthData();
  }

  void _loadAuthData() {
    _accessToken = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
    // Also check for old 'auth_token' for backward compatibility
    if (_accessToken == null) {
      _accessToken = prefs.getString('auth_token');
      if (_accessToken != null) {
        // Migrate old token to new format
        prefs.setString('access_token', _accessToken!);
        prefs.remove('auth_token');
      }
    }
    final userJsonString = prefs.getString('user_data');
    if (userJsonString != null && _accessToken != null) {
      try {
        // Parse user data from stored JSON string
        final userJson = jsonDecode(userJsonString) as Map<String, dynamic>;
        _user = UserModel.fromJson(userJson);
        if (kDebugMode) {
          print('Auth data loaded: User role: ${_user?.role}');
        }
      } catch (e) {
        // If parsing fails, clear stored data
        if (kDebugMode) {
          print('Error loading user data from prefs: $e');
        }
        _user = null;
        _accessToken = null;
        _refreshToken = null;
        prefs.remove('access_token');
        prefs.remove('refresh_token');
        prefs.remove('auth_token');
        prefs.remove('user_data');
      }
    }
  }

  Future<void> sendOTP(String phoneNumber) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await authService.sendOTP(phoneNumber);
      if (kDebugMode) {
        print('✅ OTP sent successfully for $phoneNumber');
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      if (kDebugMode) {
        print('❌ Error sending OTP: $_error');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOTP(String phoneNumber, String otp, {String? fcmToken}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Get FCM token if not provided (for push notifications)
      String? tokenToSend = fcmToken;
      if (tokenToSend == null && !kIsWeb) {
        try {
          final notificationService = NotificationService();
          tokenToSend = notificationService.fcmToken;
          // If still null, try to get it
          if (tokenToSend == null) {
            // Will be sent later when notification service initializes
          }
        } catch (e) {
          debugPrint('⚠️ Could not get FCM token: $e');
        }
      }

      final result = await authService.verifyOTP(phoneNumber, otp, fcmToken: tokenToSend);
      _accessToken = result['accessToken'] as String;
      _refreshToken = result['refreshToken'] as String;
      _user = result['user'] as UserModel;

      // Store tokens
      await prefs.setString('access_token', _accessToken!);
      await prefs.setString('refresh_token', _refreshToken!);
      // Remove old auth_token if exists
      await prefs.remove('auth_token');
      
      // Store user data as JSON string for later retrieval
      final userJsonString = jsonEncode(_user!.toJson());
      await prefs.setString('user_data', userJsonString);
      
      // Debug: Print user role to verify
      if (kDebugMode) {
        print('User logged in with role: ${_user!.role}');
      }

      // Try to ensure FCM token is sent to backend (if notification service is initialized)
      if (!kIsWeb) {
        try {
          final notificationService = NotificationService();
          // Small delay to ensure notification service has context
          Future.delayed(const Duration(milliseconds: 500), () {
            notificationService.ensureTokenSent();
          });
        } catch (e) {
          debugPrint('⚠️ Could not ensure FCM token sent: $e');
        }
      }

      _isLoading = false;
      notifyListeners();
      // Tell the router the guards need re-evaluating — it cannot listen to this
      // provider directly. See core/auth_refresh_notifier.dart.
      AuthRefreshNotifier.instance.authChanged();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> updateProfile({
    String? name,
    String? email,
    DateTime? birthday,
    String? fcmToken,
  }) async {
    if (_accessToken == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await authService.updateProfile(
        token: _accessToken!,
        name: name,
        email: email,
        birthday: birthday != null ? birthday.toIso8601String().split('T')[0] : null,
        fcmToken: fcmToken,
      );
      final userJsonString = jsonEncode(_user!.toJson());
      await prefs.setString('user_data', userJsonString);
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) {
      return false;
    }

    try {
      final result = await authService.refreshToken(_refreshToken!);
      _accessToken = result['accessToken'] as String;
      _user = result['user'] as UserModel;

      // Update stored tokens
      await prefs.setString('access_token', _accessToken!);
      final userJsonString = jsonEncode(_user!.toJson());
      await prefs.setString('user_data', userJsonString);

      notifyListeners();

      // Re-register push token via /auth/fcm-token only (not mixed into refresh body)
      if (!kIsWeb) {
        NotificationService().ensureTokenSent();
      }

      return true;
    } catch (e) {
      // Refresh failed, logout user
      if (kDebugMode) {
        print('Token refresh failed: $e');
      }
      await logout();
      return false;
    }
  }

  Future<void> logout() async {
    // Revoke refresh token on server
    if (_refreshToken != null) {
      await authService.logout(_refreshToken, _accessToken);
    }

    // Clear local state
    _user = null;
    _accessToken = null;
    _refreshToken = null;
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('auth_token'); // Remove old token if exists
    await prefs.remove('user_data');
    notifyListeners();
    // Critical on this path: without it the router keeps whatever gated screen
    // the user was on mounted, still issuing calls with a now-null token. This
    // also covers the automatic logout inside refreshAccessToken's catch.
    AuthRefreshNotifier.instance.authChanged();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

