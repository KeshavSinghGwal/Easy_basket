// Stub file for web platform - Razorpay Flutter doesn't support web
// This file is used when compiling for web to avoid import errors

class Razorpay {
  static const String EVENT_PAYMENT_SUCCESS = 'payment.success';
  static const String EVENT_PAYMENT_ERROR = 'payment.error';
  static const String EVENT_EXTERNAL_WALLET = 'external.wallet';

  void on(String event, Function handler) {
    // Stub - not implemented for web
  }

  void open(Map<String, dynamic> options) {
    // Stub - not implemented for web
    throw UnimplementedError('Razorpay not supported on web platform');
  }

  void clear() {
    // Stub - not implemented for web
  }
}

class PaymentSuccessResponse {
  final String? paymentId;
  final String? orderId;
  final String? signature;

  PaymentSuccessResponse({
    this.paymentId,
    this.orderId,
    this.signature,
  });
}

class PaymentFailureResponse {
  final String? code;
  final String? message;
  final String? source;
  final String? step;
  final String? reason;
  final Map<String, dynamic>? metadata;

  PaymentFailureResponse({
    this.code,
    this.message,
    this.source,
    this.step,
    this.reason,
    this.metadata,
  });
}

class ExternalWalletResponse {
  final String? walletName;

  ExternalWalletResponse({this.walletName});
}

