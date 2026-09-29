import 'package:flutter/foundation.dart' show kIsWeb;
import '../config/app_config.dart';
import 'api_service.dart';
import '../core/api_client.dart';

// Conditional import - only import Razorpay on mobile platforms
import 'package:razorpay_flutter/razorpay_flutter.dart' if (dart.library.html) 'razorpay_web_stub.dart';

class RazorpayService {
  static Razorpay? _razorpay;
  static bool _initialized = false;

  static void initialize() {
    if (_initialized || kIsWeb) return;
    try {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
      _initialized = true;
    } catch (e) {
      print('Razorpay initialization error: $e');
    }
  }

  static Function(PaymentSuccessResponse)? onSuccess;
  static Function(PaymentFailureResponse)? onError;
  static Function(ExternalWalletResponse)? onExternalWallet;

  static void _handlePaymentSuccess(PaymentSuccessResponse response) {
    if (onSuccess != null) {
      onSuccess!(response);
    }
  }

  static void _handlePaymentError(PaymentFailureResponse response) {
    if (onError != null) {
      onError!(response);
    }
  }

  static void _handleExternalWallet(ExternalWalletResponse response) {
    if (onExternalWallet != null) {
      onExternalWallet!(response);
    }
  }

  static Future<Map<String, dynamic>?> createOrder({
    required double amount,
    required int orderId,
    required String token,
  }) async {
    try {
      // sharedApiService, not a fresh ApiService(): a locally built one carries
      // no onTokenExpired, so an access token that lapsed while the customer
      // filled their cart made this 401 with no refresh and no way to start
      // the payment. Checkout is the worst place in the app for that.
      final apiService = sharedApiService;
      final response = await apiService.post(
        '/payment/create-order',
        {
          'amount': amount,
          'orderId': orderId,
        },
        token: token,
      );

      return response as Map<String, dynamic>?;
    } catch (e) {
      print('Error creating Razorpay order: $e');
      return null;
    }
  }

  /// Ask the server to verify the checkout signature.
  ///
  /// Returns `true` only when the server actually confirmed it. Returns `false`
  /// for BOTH a server rejection and a network failure — callers must not treat
  /// `false` as "the payment failed", because by the time this runs Razorpay has
  /// already taken the customer's money.
  ///
  /// It previously returned `response != null` inside a catch-all that mapped every
  /// exception to `false`, and the caller rendered that as "Payment verification
  /// failed. Please contact support or try again." with the cart still populated —
  /// so a single network blip after a successful payment funnelled the customer
  /// straight into paying a second time.
  static Future<bool> verifyPayment({
    required int orderId,
    required String paymentId,
    required String signature,
    required String razorpayOrderId,
    required String token,
  }) async {
    try {
      // sharedApiService, not a fresh ApiService(): a locally built one carries
      // no onTokenExpired, so an access token that lapsed while the customer
      // filled their cart made this 401 with no refresh and no way to start
      // the payment. Checkout is the worst place in the app for that.
      final apiService = sharedApiService;
      final response = await apiService.post(
        '/payment/verify',
        {
          'orderId': orderId,
          'paymentId': paymentId,
          'signature': signature,
          'razorpayOrderId': razorpayOrderId,
        },
        token: token,
      );

      return response != null;
    } catch (e) {
      // Transport failure or a non-2xx. Either way the webhook remains the
      // authority on this payment, so we report "not yet confirmed", never "failed".
      print('Payment verify did not confirm (webhook will settle it): $e');
      return false;
    }
  }

  /// [amountPaise] MUST be the integer paise amount the SERVER used to create the
  /// Razorpay order (the `amount` field of /payment/create-order).
  ///
  /// It used to take rupees as a double and compute `(amount * 100).toInt()` here.
  /// That truncates instead of rounding — Dart evaluates `354.7 * 100` as
  /// 35469.999999999996, so `.toInt()` yielded 35469 against an order created for
  /// 35470. Razorpay Checkout validates this option against the order it was given
  /// and refuses to open on a mismatch, so specific cart totals could never be paid.
  /// Passing server paise through untouched removes the float arithmetic entirely.
  static void openCheckout({
    required String keyId,
    required int amountPaise,
    required String orderId,
    required String name,
    required String description,
    String? prefillEmail,
    String? prefillContact,
    Map<String, dynamic>? notes,
  }) {
    if (kIsWeb) {
      // For web, open Razorpay checkout in new window
      _openRazorpayWebCheckout(
        keyId: keyId,
        amountPaise: amountPaise,
        orderId: orderId,
        name: name,
        description: description,
        prefillEmail: prefillEmail,
        prefillContact: prefillContact,
        notes: notes,
      );
      return;
    }

    if (_razorpay == null) {
      print('Razorpay not initialized');
      return;
    }

    final options = {
      'key': keyId,
      'amount': amountPaise, // already paise, straight from the server
      'name': name,
      'description': description,
      'order_id': orderId,
      'prefill': {
        if (prefillEmail != null) 'email': prefillEmail,
        if (prefillContact != null) 'contact': prefillContact,
      },
      'external': {
        'wallets': ['paytm']
      },
      if (notes != null) 'notes': notes,
      'theme': {
        'color': '#00A859' // AppTheme.primaryGreen
      }
    };

    _razorpay!.open(options);
  }

  static void _openRazorpayWebCheckout({
    required String keyId,
    required int amountPaise,
    required String orderId,
    required String name,
    required String description,
    String? prefillEmail,
    String? prefillContact,
    Map<String, dynamic>? notes,
  }) {
    // For web, we'll use Razorpay Checkout.js
    // This requires adding Razorpay script to index.html
    // For now, show a message to use mobile app or implement web checkout
    print('Web Razorpay checkout - requires web implementation');
    // TODO: Implement Razorpay Checkout.js for web
  }

  static void clear() {
    if (!kIsWeb && _razorpay != null) {
      _razorpay!.clear();
    }
  }
}

