import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Enhanced API Service with automatic token refresh
/// This service automatically refreshes access tokens when they expire
class ApiServiceWithRefresh {
  final ApiService _apiService;
  final AuthService _authService;
  
  // Callback to get current tokens and refresh them
  String? Function()? getAccessToken;
  String? Function()? getRefreshToken;
  Future<bool> Function()? refreshTokenCallback;

  ApiServiceWithRefresh({
    required ApiService apiService,
    required AuthService authService,
    this.getAccessToken,
    this.getRefreshToken,
    this.refreshTokenCallback,
  })  : _apiService = apiService,
        _authService = authService;

  static String get baseUrl => AppConfig.apiBaseUrl;

  Future<dynamic> get(String endpoint, {String? token, bool retry = true}) async {
    try {
      final accessToken = token ?? getAccessToken?.call();
      return await _apiService.get(endpoint, token: accessToken);
    } on TokenExpiredException catch (e) {
      if (retry && await _handleTokenRefresh()) {
        // Retry with new token
        final newToken = getAccessToken?.call();
        return await _apiService.get(endpoint, token: newToken);
      }
      rethrow;
    }
  }

  Future<dynamic> post(
    String endpoint,
    Map<String, dynamic> data, {
    String? token,
    bool retry = true,
  }) async {
    try {
      final accessToken = token ?? getAccessToken?.call();
      return await _apiService.post(endpoint, data, token: accessToken);
    } on TokenExpiredException catch (e) {
      if (retry && await _handleTokenRefresh()) {
        // Retry with new token
        final newToken = getAccessToken?.call();
        return await _apiService.post(endpoint, data, token: newToken);
      }
      rethrow;
    }
  }

  Future<dynamic> put(
    String endpoint,
    Map<String, dynamic> data, {
    String? token,
    bool retry = true,
  }) async {
    try {
      final accessToken = token ?? getAccessToken?.call();
      return await _apiService.put(endpoint, data, token: accessToken);
    } on TokenExpiredException catch (e) {
      if (retry && await _handleTokenRefresh()) {
        // Retry with new token
        final newToken = getAccessToken?.call();
        return await _apiService.put(endpoint, data, token: newToken);
      }
      rethrow;
    }
  }

  Future<dynamic> delete(String endpoint, {String? token, bool retry = true}) async {
    try {
      final accessToken = token ?? getAccessToken?.call();
      return await _apiService.delete(endpoint, token: accessToken);
    } on TokenExpiredException catch (e) {
      if (retry && await _handleTokenRefresh()) {
        // Retry with new token
        final newToken = getAccessToken?.call();
        return await _apiService.delete(endpoint, token: newToken);
      }
      rethrow;
    }
  }

  Future<bool> _handleTokenRefresh() async {
    final refreshToken = getRefreshToken?.call();
    if (refreshToken == null) {
      return false;
    }

    try {
      // Use callback if provided, otherwise use auth service directly
      if (refreshTokenCallback != null) {
        return await refreshTokenCallback!();
      } else {
        final result = await _authService.refreshToken(refreshToken);
        // Update token via callback if available
        // Note: The AuthProvider should handle token updates
        return true;
      }
    } catch (e) {
      return false;
    }
  }
}

