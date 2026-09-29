import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class ApiService {
  static String get baseUrl => AppConfig.apiBaseUrl;

  /// Language sent as `Accept-Language` on every request, which is how the
  /// backend decides whether to resolve product and category names into
  /// Hindi or Punjabi (see backend ResponseTranslator).
  ///
  /// Static because `ApiService()` is constructed independently in several
  /// providers — an instance field would leave some of them still asking for
  /// English. Owned by LocaleProvider; nothing else should assign to it.
  static String language = 'en';

  // Callback to refresh the token when the server reports it expired (401).
  Future<bool> Function()? onTokenExpired;

  // Returns the CURRENT valid token after a refresh, so retries pick up the new
  // one without every caller having to pass `getUpdatedToken`. Wired in main.dart.
  String? Function()? getCurrentToken;

  /// The refresh currently in flight, if any. Concurrent callers await THIS
  /// future rather than polling a flag, so they observe its real result.
  Future<bool>? _refreshInFlight;

  ApiService({this.onTokenExpired, this.getCurrentToken});

  static const _timeout = Duration(seconds: 30);

  // ---------------------------------------------------------------------------
  // Public verbs — thin wrappers over the shared _send (which now does the
  // refresh-and-retry-on-401 for EVERY verb, not just GET).
  // ---------------------------------------------------------------------------

  Future<dynamic> get(
    String endpoint, {
    String? token,
    bool retryOnExpired = true,
    String? Function()? getUpdatedToken,
  }) {
    return _send(
      method: 'GET',
      endpoint: endpoint,
      token: token,
      retryOnExpired: retryOnExpired,
      getUpdatedToken: getUpdatedToken,
    );
  }

  Future<dynamic> post(
    String endpoint,
    Map<String, dynamic> data, {
    String? token,
    Map<String, String>? extraHeaders,
    bool retryOnExpired = true,
  }) {
    return _send(
      method: 'POST',
      endpoint: endpoint,
      token: token,
      body: data,
      extraHeaders: extraHeaders,
      retryOnExpired: retryOnExpired,
    );
  }

  Future<dynamic> put(
    String endpoint,
    Map<String, dynamic> data, {
    String? token,
    bool retryOnExpired = true,
  }) {
    return _send(
      method: 'PUT',
      endpoint: endpoint,
      token: token,
      body: data,
      retryOnExpired: retryOnExpired,
    );
  }

  /// PATCH. Mirrors put() exactly.
  ///
  /// This was missing while admin_support_requests_screen.dart already called it,
  /// so the whole app failed to compile ("The method 'patch' isn't defined for the
  /// type 'ApiService'"). The backend route it targets really is a PATCH
  /// (support.routes.ts: router.patch('/:id/status')), so adding the verb is the
  /// correct fix rather than rewriting the caller to use put().
  Future<dynamic> patch(
    String endpoint,
    Map<String, dynamic> data, {
    String? token,
    bool retryOnExpired = true,
  }) {
    return _send(
      method: 'PATCH',
      endpoint: endpoint,
      token: token,
      body: data,
      retryOnExpired: retryOnExpired,
    );
  }

  Future<dynamic> delete(
    String endpoint, {
    String? token,
    bool retryOnExpired = true,
  }) {
    return _send(
      method: 'DELETE',
      endpoint: endpoint,
      token: token,
      retryOnExpired: retryOnExpired,
    );
  }

  // ---------------------------------------------------------------------------
  // Shared request path with refresh-and-retry.
  // ---------------------------------------------------------------------------

  Future<dynamic> _send({
    required String method,
    required String endpoint,
    String? token,
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
    bool retryOnExpired = true,
    String? Function()? getUpdatedToken,
  }) async {
    Future<http.Response> dispatch(String? authToken) {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept-Language': language,
      };
      if (authToken != null) headers['Authorization'] = 'Bearer $authToken';
      if (extraHeaders != null) headers.addAll(extraHeaders);

      // ignore: avoid_print
      print('[API][$method] $baseUrl$endpoint');
      final uri = Uri.parse('$baseUrl$endpoint');
      final encoded = body != null ? jsonEncode(body) : null;

      switch (method) {
        case 'GET':
          return http.get(uri, headers: headers).timeout(_timeout, onTimeout: _onTimeout);
        case 'POST':
          return http.post(uri, headers: headers, body: encoded).timeout(_timeout, onTimeout: _onTimeout);
        case 'PUT':
          return http.put(uri, headers: headers, body: encoded).timeout(_timeout, onTimeout: _onTimeout);
        case 'PATCH':
          return http.patch(uri, headers: headers, body: encoded).timeout(_timeout, onTimeout: _onTimeout);
        case 'DELETE':
          return http.delete(uri, headers: headers).timeout(_timeout, onTimeout: _onTimeout);
        default:
          throw Exception('Unsupported method: $method');
      }
    }

    final initialToken = token ?? getUpdatedToken?.call() ?? getCurrentToken?.call();

    try {
      return _handleResponse(await dispatch(initialToken));
    } on TokenExpiredException {
      // Standard behaviour for EVERY verb: refresh once, then retry with the new
      // token. Previously only GET retried, and only when the caller passed
      // getUpdatedToken — so writes (place order, profile, address) failed after
      // the 15-min access-token expiry.
      if (retryOnExpired && await _handleTokenExpiration()) {
        final newToken =
            getUpdatedToken?.call() ?? getCurrentToken?.call() ?? initialToken;
        return _handleResponse(await dispatch(newToken));
      }
      rethrow;
    } on ApiException {
      // The server answered and we understood it. This is NOT a transport
      // problem, so it must not go through _mapNetworkError — that is what
      // relabelled every business rule ("item out of stock", "outside our
      // service area", "store closed") as a network failure.
      rethrow;
    } catch (e) {
      // Only genuine transport failures reach here: DNS, refused connection,
      // TLS, timeout.
      throw _mapNetworkError(e);
    }
  }

  static Never _onTimeout() {
    throw Exception(
      'Request timeout: Server took too long to respond. Please check if backend is running and database is connected.',
    );
  }

  Exception _mapNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('failed host lookup') || s.contains('connection refused')) {
      return Exception('Cannot connect to server. Check if backend is running at $baseUrl');
    }
    if (s.contains('failed to fetch') || s.contains('networkerror')) {
      return Exception(
        'Network error: Cannot reach server at $baseUrl. Check:\n1. Backend is running\n2. CORS is enabled\n3. No firewall blocking connection',
      );
    }
    if (s.contains('timeout')) {
      return Exception('Request timeout: Server took too long to respond');
    }
    if (s.contains('certificate') || s.contains('ssl') || s.contains('tls')) {
      return Exception('SSL certificate error. Please check if HTTPS is properly configured on the server.');
    }
    return Exception('Network error: $e');
  }

  /// Decode a JSON object body, or null when it is empty / not an object
  /// (e.g. Express's default HTML 404). Never throws — the caller decides.
  static Map<String, dynamic>? _tryDecodeMap(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Used ONLY when the server sent no usable `message`. Never overrides one.
  static String _fallbackMessage(int statusCode) {
    if (statusCode == 400) {
      return 'That request was not valid. Please check the details and try again.';
    }
    // Must stay exactly 'Authentication required': address_provider,
    // order_provider and add_address_screen all test for that substring to
    // decide whether to re-throw an auth failure to their caller.
    if (statusCode == 401) return 'Authentication required';
    if (statusCode == 403) return "You don't have permission to do that.";
    if (statusCode == 404) return 'We could not find what you were looking for.';
    if (statusCode == 409) {
      return 'That conflicted with something else. Please refresh and try again.';
    }
    if (statusCode == 429) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    if (statusCode >= 500) {
      return 'The server had a problem. Please try again in a moment.';
    }
    return 'Request failed (status $statusCode).';
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return [];
      }
      try {
        return jsonDecode(response.body);
      } catch (_) {
        // ApiException, not a bare Exception: _send must pass this through rather
        // than relabel a malformed response as a network failure.
        throw ApiException(
          message: 'The server sent a response we could not read.',
          statusCode: response.statusCode,
        );
      }
    }

    // ---- Error status -------------------------------------------------------
    // Decode FIRST, then throw. The throw must not sit inside a try whose catch
    // would swallow it — that is what used to replace every server message with
    // a raw status dump, because `catch (e)` catches our own deliberate throw.
    final body = _tryDecodeMap(response.body);

    final rawMessage = body?['message'];
    final message = rawMessage is String && rawMessage.trim().isNotEmpty
        ? rawMessage.trim()
        : _fallbackMessage(response.statusCode);

    // Machine-readable reason where the backend sends one (STORE_CLOSED,
    // OUT_OF_SERVICE_AREA, USE_REQUEST_CANCELLATION, ALREADY_PACKED, ...).
    final rawCode = body?['code'];
    final code = rawCode is String && rawCode.isNotEmpty ? rawCode : null;

    if (response.statusCode == 401) {
      throw TokenExpiredException(message);
    }

    throw ApiException(
      message: message,
      statusCode: response.statusCode,
      code: code,
    );
  }

  /// Handle token expiration with automatic refresh (single-flight).
  ///
  /// The previous version polled a boolean for up to 2 seconds and then returned
  /// `!_isRefreshing` — reporting success merely because the other refresh had
  /// FINISHED, with no visibility of whether it actually worked. After a failed
  /// refresh, waiters retried with the stale token, hit another 401, and
  /// surfaced an error instead of a clean logout. It also gave up after 2s on a
  /// slow network, and `_isRefreshing` was per-instance so the guard never
  /// spanned providers.
  ///
  /// Awaiting one shared future fixes all three: real result, no timeout, and —
  /// now that every provider shares one ApiService — genuinely global. That last
  /// property is what makes refresh-token rotation safe to add later; parallel
  /// refreshes against a rotating token would invalidate each other.
  Future<bool> _handleTokenExpiration() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final refresh = onTokenExpired;
    if (refresh == null) return false;

    // Sanitised so every waiter sees `false` rather than an exception raised on
    // a different caller's stack.
    final future = Future<bool>(() async {
      try {
        return await refresh();
      } catch (_) {
        return false;
      }
    });

    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      _refreshInFlight = null;
    }
  }
}

// Custom exception for token expiration
class TokenExpiredException implements Exception {
  final String message;
  TokenExpiredException(this.message);

  @override
  String toString() => message;
}

/// A response the server really produced and we understood: a non-2xx carrying
/// (usually) a `message` written for the user.
///
/// Deliberately distinct from a transport failure. `_send` lets this pass through
/// untouched, so the backend's wording survives to the UI — every one of these
/// used to be rewritten as "Network error: ...", which is why "An item just went
/// out of stock" and "Delivery address is outside our service area" never reached
/// anyone.
class ApiException implements Exception {
  /// Safe to show the user. Either the server's `message` or, only when the
  /// server sent none, a status-appropriate fallback.
  final String message;

  final int statusCode;

  /// The backend's machine-readable reason where it sends one — e.g.
  /// 'STORE_CLOSED', 'OUT_OF_SERVICE_AREA', 'USE_REQUEST_CANCELLATION',
  /// 'ALREADY_PACKED'. Lets callers branch on the reason instead of matching
  /// message text. Null when the response carried no `code`.
  final String? code;

  ApiException({
    required this.message,
    required this.statusCode,
    this.code,
  });

  /// Just the message — call sites do `toString().replaceAll('Exception: ', '')`
  /// and must keep producing clean, user-facing text. Same contract as
  /// TokenExpiredException above.
  @override
  String toString() => message;
}
