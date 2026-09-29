import 'user_model.dart';
import 'refund_info.dart';
import 'address_model.dart';
import 'product_model.dart';
import 'product_variant_model.dart';

class OrderItemModel {
  final int id;
  final ProductModel product;
  final ProductVariantModel? variant; // Variant if product has variants
  final int quantity;
  final double price;
  final double total;
  final String? unit; // Unit of measurement
  final String? displayLabel; // Display label (e.g., "2 × 1 kg")

  OrderItemModel({
    required this.id,
    required this.product,
    this.variant,
    required this.quantity,
    required this.price,
    required this.total,
    this.unit,
    this.displayLabel,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    // Helper to parse numeric values (handles both string and num from MySQL DECIMAL)
    double parseDouble(dynamic value) {
      if (value is num) {
        return value.toDouble();
      } else if (value is String) {
        return double.parse(value);
      } else {
        return 0.0;
      }
    }

    // Helper to parse quantity (can be int or decimal, but we store as int)
    int parseQuantity(dynamic value) {
      if (value is int) {
        return value;
      } else if (value is num) {
        return value.toInt();
      } else if (value is String) {
        // Handle string like "1.000" or "1"
        final parsed = double.tryParse(value);
        return parsed?.toInt() ?? 0;
      } else {
        return 0;
      }
    }

    return OrderItemModel(
      id: json['id'] as int,
      product: ProductModel.fromJson(json['product'] as Map<String, dynamic>),
      variant: json['variant'] != null
          ? ProductVariantModel.fromJson(json['variant'] as Map<String, dynamic>)
          : null,
      quantity: parseQuantity(json['quantity']),
      price: parseDouble(json['price']),
      total: parseDouble(json['total']),
      unit: json['unit'] as String?,
      displayLabel: json['displayLabel'] as String?,
    );
  }
}

class OrderModel {
  final int id;
  final UserModel user;
  final AddressModel deliveryAddress;
  final List<OrderItemModel> items;
  final double totalAmount;
  final String status;
  final String? paymentMethod;
  final String? paymentId;
  final bool isPaid;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final UserModel? deliveryBoy;

  /// Phase 1 delivery state-machine fields. All nullable so this model still
  /// parses orders created before the migration ran.
  final String? deliveryStatus; // unassigned|assigned|at_store|picked|out_for_delivery|arrived|payment_pending|delivered|rto_pending|rto_completed
  final String? paymentStatus; // initiated|success_unverified|paid|failed|refund_pending|refunded

  /// Latest refund's status for this order: 'pending' | 'processed' | 'failed'.
  /// Null when no refund was ever raised. Sent only on admin list endpoints.
  final String? refundStatus;

  /// True when that refund exhausted its automatic retries and needs an admin
  /// to press "Retry refund". Drives the warning badge on the orders list —
  /// without it a broken refund is only discoverable by opening each order.
  final bool refundNeedsAttention;

  /// Full customer-facing refund detail. Present only on the order DETAIL
  /// response — list endpoints send the two flags above instead, to keep the
  /// per-page cost to one batched query.
  final CustomerRefund? refund;

  final int? cashCollectedPaise;
  final int deliveryAttempts;
  final DateTime? deliveryAssignedAt;
  final DateTime? deliveryPickedAt;
  final DateTime? deliveryArrivedAt;
  final DateTime? deliveryCompletedAt;

  /// Customer cancellation/refund request state: 'none' | 'requested' | 'rejected'.
  final String cancelRequestStatus;
  final String? cancellationReason;

  OrderModel({
    required this.id,
    required this.user,
    required this.deliveryAddress,
    required this.items,
    required this.totalAmount,
    required this.status,
    this.paymentMethod,
    this.paymentId,
    required this.isPaid,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deliveryBoy,
    this.deliveryStatus,
    this.paymentStatus,
    this.refundStatus,
    this.refundNeedsAttention = false,
    this.refund,
    this.cashCollectedPaise,
    this.deliveryAttempts = 0,
    this.deliveryAssignedAt,
    this.deliveryPickedAt,
    this.deliveryArrivedAt,
    this.deliveryCompletedAt,
    this.cancelRequestStatus = 'none',
    this.cancellationReason,
  });

  /// Refund-eligible window: customer can request cancellation WITH a refund only
  /// before packing begins (status pending/accepted). Matches the backend guard.
  /// Cancellation/refund is allowed right up until the store starts preparing.
  /// `awaiting_acceptance` MUST be here: it is where every paid order now lands,
  /// so omitting it would silently strip the cancel option from every customer
  /// who paid online.
  bool get isRefundEligible =>
      status == 'pending' || status == 'awaiting_acceptance' || status == 'accepted';

  /// After packing: customer can still cancel, but NO refund is given.
  bool get canCancelNoRefund => status == 'preparing' || status == 'out_for_delivery';

  bool get hasPendingCancelRequest => cancelRequestStatus == 'requested';
  bool get cancelRequestRejected => cancelRequestStatus == 'rejected';

  /// Convenience: is this a Cash-on-Delivery order?
  /// The backend normalizes COD to `paymentMethod='cod'` (it aliases 'cash' ->
  /// 'cod' at order creation), so 'cod' is the canonical stored value. 'cash' is
  /// kept here only for any legacy rows written before that normalization.
  bool get isCod {
    final m = paymentMethod?.toLowerCase();
    return m == 'cod' || m == 'cash';
  }

  /// Amount in paise the rider must collect at the door (or 0 for prepaid).
  int get amountToCollectPaise => isCod && !isPaid ? (totalAmount * 100).round() : 0;

  /// True only when cash must physically be collected. A COD order that was paid
  /// online at the door (rider "Switch to UPI") is COD by method but already paid,
  /// so it closes via the OTP/mark-delivered path, NOT collect-cash.
  bool get needsCashCollection => isCod && !isPaid;

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    // Helper to parse numeric values (handles both string and num from MySQL DECIMAL)
    double parseDouble(dynamic value) {
      if (value is num) {
        return value.toDouble();
      } else if (value is String) {
        return double.parse(value);
      } else {
        return 0.0;
      }
    }

    // Helper to parse DateTime (handles both string and DateTime)
    DateTime parseDateTime(dynamic value) {
      if (value is DateTime) {
        return value;
      } else if (value is String) {
        return DateTime.parse(value);
      } else {
        return DateTime.now();
      }
    }

    DateTime? parseNullableDateTime(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String && value.isNotEmpty) {
        try {
          return DateTime.parse(value);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    int? parseNullableInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return OrderModel(
      id: json['id'] as int,
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      deliveryAddress: AddressModel.fromJson(json['deliveryAddress'] as Map<String, dynamic>),
      items: (json['items'] as List<dynamic>)
          .map((item) => OrderItemModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalAmount: parseDouble(json['totalAmount']),
      status: json['status'] as String,
      paymentMethod: json['paymentMethod'] as String?,
      paymentId: json['paymentId'] as String?,
      isPaid: json['isPaid'] as bool? ?? false,
      notes: json['notes'] as String?,
      createdAt: parseDateTime(json['createdAt']),
      updatedAt: parseDateTime(json['updatedAt']),
      deliveryBoy: json['deliveryBoy'] != null
          ? UserModel.fromJson(json['deliveryBoy'] as Map<String, dynamic>)
          : null,
      deliveryStatus: json['deliveryStatus'] as String? ?? json['delivery_status'] as String?,
      paymentStatus: json['paymentStatus'] as String? ?? json['payment_status'] as String?,
      refundStatus: json['refundStatus'] as String? ?? json['refund_status'] as String?,
      refundNeedsAttention:
          json['refundNeedsAttention'] as bool? ?? json['refund_needs_attention'] as bool? ?? false,
      refund: json['refund'] is Map<String, dynamic>
          ? CustomerRefund.fromJson(json['refund'] as Map<String, dynamic>)
          : null,
      cashCollectedPaise: parseNullableInt(json['cashCollectedPaise'] ?? json['cash_collected_paise']),
      deliveryAttempts: parseNullableInt(json['deliveryAttempts'] ?? json['delivery_attempts']) ?? 0,
      deliveryAssignedAt: parseNullableDateTime(json['deliveryAssignedAt'] ?? json['delivery_assigned_at']),
      deliveryPickedAt: parseNullableDateTime(json['deliveryPickedAt'] ?? json['delivery_picked_at']),
      deliveryArrivedAt: parseNullableDateTime(json['deliveryArrivedAt'] ?? json['delivery_arrived_at']),
      deliveryCompletedAt: parseNullableDateTime(json['deliveryCompletedAt'] ?? json['delivery_completed_at']),
      cancelRequestStatus:
          (json['cancelRequestStatus'] ?? json['cancel_request_status']) as String? ?? 'none',
      cancellationReason:
          (json['cancellationReason'] ?? json['cancellation_reason']) as String?,
    );
  }

  String get statusText {
    switch (status) {
      case 'pending':
        return 'Pending';
      // Paid, waiting for the store to accept. From the customer's side the only
      // thing that has happened is that their payment went through, so that is
      // what we tell them — not 'Accepted', which would claim a decision the
      // store has not actually made yet.
      case 'awaiting_acceptance':
        return 'Confirmed';
      case 'accepted':
        return 'Accepted';
      case 'preparing':
        return 'Preparing';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }
}

