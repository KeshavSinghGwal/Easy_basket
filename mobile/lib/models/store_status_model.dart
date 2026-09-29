import 'package:flutter/material.dart';

/// Why the store is closed. Mirrors the backend enum in
/// `entities/StoreStatus.ts` — the reason drives which visual we render, which
/// a free-text string could not.
enum StoreClosedReason {
  rain,
  holiday,
  maintenance,
  highDemand,
  outOfHours,
  other;

  /// Unknown values from a newer backend degrade to [other] rather than
  /// throwing — an app that can't parse a new reason should still show the
  /// banner, just with the generic visual.
  static StoreClosedReason fromApi(String? value) {
    switch (value) {
      case 'rain':
        return StoreClosedReason.rain;
      case 'holiday':
        return StoreClosedReason.holiday;
      case 'maintenance':
        return StoreClosedReason.maintenance;
      case 'high_demand':
        return StoreClosedReason.highDemand;
      case 'out_of_hours':
        return StoreClosedReason.outOfHours;
      default:
        return StoreClosedReason.other;
    }
  }

  String get apiValue => switch (this) {
        StoreClosedReason.rain => 'rain',
        StoreClosedReason.holiday => 'holiday',
        StoreClosedReason.maintenance => 'maintenance',
        StoreClosedReason.highDemand => 'high_demand',
        StoreClosedReason.outOfHours => 'out_of_hours',
        StoreClosedReason.other => 'other',
      };

  /// Label shown in the admin picker.
  String get adminLabel => switch (this) {
        StoreClosedReason.rain => 'Bad weather / rain',
        StoreClosedReason.holiday => 'Holiday',
        StoreClosedReason.maintenance => 'Maintenance',
        StoreClosedReason.highDemand => 'Too many orders',
        StoreClosedReason.outOfHours => 'Outside store hours',
        StoreClosedReason.other => 'Other',
      };

  /// Headline used when the admin didn't write a custom message.
  String get defaultHeadline => switch (this) {
        StoreClosedReason.rain => 'Closed due to heavy rain',
        StoreClosedReason.holiday => "We're closed for a holiday",
        StoreClosedReason.maintenance => 'Down for maintenance',
        StoreClosedReason.highDemand => 'Too many orders right now',
        StoreClosedReason.outOfHours => "We're closed right now",
        StoreClosedReason.other => "We're closed right now",
      };

  /// Supporting line under the headline.
  String get defaultSubtitle => switch (this) {
        StoreClosedReason.rain =>
          'Our riders are waiting for the rain to ease. Browse away — you can order as soon as we reopen.',
        StoreClosedReason.holiday =>
          "Back soon! Feel free to browse and build your cart in the meantime.",
        StoreClosedReason.maintenance =>
          "We're doing a quick tune-up. Browsing still works — ordering will be back shortly.",
        StoreClosedReason.highDemand =>
          "We're catching up on a rush of orders. Hang tight, we'll reopen very soon.",
        StoreClosedReason.outOfHours =>
          'Browse now and build your cart — you can place the order when we reopen.',
        StoreClosedReason.other =>
          "Browse now and build your cart — you can place the order when we reopen.",
      };

  IconData get icon => switch (this) {
        StoreClosedReason.rain => Icons.water_drop_rounded,
        StoreClosedReason.holiday => Icons.celebration_rounded,
        StoreClosedReason.maintenance => Icons.build_rounded,
        StoreClosedReason.highDemand => Icons.local_fire_department_rounded,
        StoreClosedReason.outOfHours => Icons.bedtime_rounded,
        StoreClosedReason.other => Icons.storefront_rounded,
      };

  /// Banner gradient. Rain gets a cool slate-blue, everything else stays in
  /// warmer territory so "closed" never reads as "error".
  List<Color> get gradient => switch (this) {
        StoreClosedReason.rain => const [Color(0xFF3E5C76), Color(0xFF5A7D9A)],
        StoreClosedReason.holiday => const [Color(0xFF7B4397), Color(0xFFA05195)],
        StoreClosedReason.maintenance => const [Color(0xFF4A5568), Color(0xFF6B7280)],
        StoreClosedReason.highDemand => const [Color(0xFFB44B1F), Color(0xFFD97036)],
        StoreClosedReason.outOfHours => const [Color(0xFF2C3E6B), Color(0xFF44578F)],
        StoreClosedReason.other => const [Color(0xFF44576B), Color(0xFF63798F)],
      };
}

/// Whether the store is accepting new orders, plus the context to explain it.
@immutable
class StoreStatusModel {
  const StoreStatusModel({
    required this.isOpen,
    this.closedReason,
    this.customMessage,
    this.expectedReopenAt,
    this.closedAt,
  });

  final bool isOpen;
  final StoreClosedReason? closedReason;
  final String? customMessage;

  /// Display only — the store does NOT reopen by itself when this passes.
  /// Parsed as UTC and converted to device local time (IST for our users).
  final DateTime? expectedReopenAt;
  final DateTime? closedAt;

  /// The optimistic default. Used before the first fetch completes and whenever
  /// a fetch fails — we never block a customer because of a flaky network; the
  /// server rejects the order if the store is genuinely closed.
  static const StoreStatusModel open = StoreStatusModel(isOpen: true);

  factory StoreStatusModel.fromJson(Map<String, dynamic> json) {
    return StoreStatusModel(
      isOpen: json['isOpen'] as bool? ?? true,
      closedReason: json['closedReason'] == null
          ? null
          : StoreClosedReason.fromApi(json['closedReason'] as String?),
      customMessage: (json['customMessage'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['customMessage'] as String).trim(),
      expectedReopenAt: _parseUtc(json['expectedReopenAt']),
      closedAt: _parseUtc(json['closedAt']),
    );
  }

  /// The backend sends ISO-8601 UTC. `toLocal()` renders it in the device's
  /// zone so an IST user sees IST, not UTC.
  static DateTime? _parseUtc(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  StoreClosedReason get reason => closedReason ?? StoreClosedReason.other;

  /// Admin's words when they wrote some, otherwise the per-reason default.
  String get headline => customMessage ?? reason.defaultHeadline;

  /// Only show the generic subtitle when it isn't just repeating the headline.
  String get subtitle => reason.defaultSubtitle;
}
