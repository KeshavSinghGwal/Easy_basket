/// Customer-facing refund state, attached as `refund` on the order detail
/// response.
///
/// Deliberately smaller than [RefundInfo]: retry counts and raw Razorpay error
/// strings are for admins. A customer needs how much, how far along, roughly
/// when, and a reference number their bank will accept.
class CustomerRefund {
  /// 'pending' | 'processed' | 'failed'
  final String status;
  final int amountPaise;
  final DateTime? initiatedAt;

  /// Razorpay refund id — worth showing so a customer chasing their bank has
  /// something concrete to quote.
  final String? referenceId;

  /// Razorpay has accepted the refund. Only then does the 2–7 working day
  /// window mean anything, so the countdown copy is gated on this.
  final bool acceptedByProvider;

  /// Automatic retries are spent and our team is handling it manually.
  final bool needsAttention;

  const CustomerRefund({
    required this.status,
    required this.amountPaise,
    required this.initiatedAt,
    required this.referenceId,
    required this.acceptedByProvider,
    required this.needsAttention,
  });

  double get amountRupees => amountPaise / 100.0;

  bool get isProcessed => status == 'processed';

  /// Accepted and settling — the normal in-flight state.
  bool get isSettling => status == 'pending' && acceptedByProvider;

  /// Raised but not yet accepted by Razorpay. Still fine; just earlier.
  bool get isInitiating => status == 'pending' && !acceptedByProvider;

  /// The end of the "2–7 working days" window, counted from acceptance.
  /// Approximate by design — working days are not modelled, and over-promising
  /// a precise date is worse than a rough one.
  DateTime? get expectedBy => initiatedAt?.add(const Duration(days: 7));

  factory CustomerRefund.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amountPaise'];
    return CustomerRefund(
      status: json['status']?.toString() ?? 'pending',
      // MySQL BIGINT serialises as a string.
      amountPaise: rawAmount is int
          ? rawAmount
          : int.tryParse(rawAmount?.toString() ?? '') ?? 0,
      initiatedAt: json['initiatedAt'] is String
          ? DateTime.tryParse(json['initiatedAt'] as String)
          : null,
      referenceId: json['referenceId']?.toString(),
      acceptedByProvider: json['acceptedByProvider'] as bool? ?? false,
      needsAttention: json['needsAttention'] as bool? ?? false,
    );
  }
}

/// Refund state for a single order, as returned by
/// `GET /admin/orders/:id/refund`.
///
/// This exists because `OrderModel.paymentStatus` alone cannot tell an admin
/// whether a refund is healthy or broken: a refund that failed permanently used
/// to keep showing "Refund in progress" forever. The fields below carry the
/// retry bookkeeping that makes the difference visible and actionable.
class RefundInfo {
  final String refundId;

  /// 'pending' | 'processed' | 'failed'
  final String status;

  final int amountPaise;

  /// Null until Razorpay has accepted the refund. Null + status 'pending'
  /// means our API call has not landed yet.
  final String? razorpayRefundId;

  /// How many times we have actually POSTed this refund to Razorpay.
  final int attemptCount;

  /// Automatic attempts allowed before an admin has to step in.
  final int maxAutoAttempts;

  /// Reason for the most recent failure, shown to the admin verbatim.
  final String? lastError;

  /// When the automatic retry is due, if one is scheduled.
  final DateTime? nextRetryAt;

  /// Why the refund was raised (admin_cancelled, rto, …).
  final String? reason;

  /// Server's verdict on whether the manual "Retry refund" button should be
  /// enabled. False once the refund is processed, and false while an automatic
  /// retry is still pending, so a manual attempt can't stack on a scheduled one.
  final bool canRetry;

  final DateTime? createdAt;

  const RefundInfo({
    required this.refundId,
    required this.status,
    required this.amountPaise,
    required this.razorpayRefundId,
    required this.attemptCount,
    required this.maxAutoAttempts,
    required this.lastError,
    required this.nextRetryAt,
    required this.reason,
    required this.canRetry,
    required this.createdAt,
  });

  double get amountRupees => amountPaise / 100.0;

  /// Refund completed — money is on its way to the customer.
  bool get isProcessed => status == 'processed';

  /// Permanently failed: automatic retries are spent and an admin must act.
  bool get isFailed => status == 'failed';

  /// An automatic retry is still scheduled — show "retrying", not "failed".
  bool get isAutoRetrying =>
      status == 'pending' &&
      razorpayRefundId == null &&
      attemptCount < maxAutoAttempts;

  /// Accepted by Razorpay and waiting on the settlement webhook. The healthy
  /// in-flight state.
  bool get isAwaitingRazorpay => status == 'pending' && razorpayRefundId != null;

  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static DateTime? _toDate(dynamic v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  factory RefundInfo.fromJson(Map<String, dynamic> json) {
    return RefundInfo(
      refundId: json['refundId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      // amountPaise arrives as a string: MySQL BIGINT is serialised as text.
      amountPaise: _toInt(json['amountPaise']),
      razorpayRefundId: json['razorpayRefundId']?.toString(),
      attemptCount: _toInt(json['attemptCount']),
      maxAutoAttempts: _toInt(json['maxAutoAttempts'], 2),
      lastError: json['lastError']?.toString(),
      nextRetryAt: _toDate(json['nextRetryAt']),
      reason: json['reason']?.toString(),
      canRetry: json['canRetry'] as bool? ?? false,
      createdAt: _toDate(json['createdAt']),
    );
  }
}
