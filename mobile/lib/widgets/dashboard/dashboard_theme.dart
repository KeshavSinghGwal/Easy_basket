import 'package:flutter/material.dart';

class DashboardTheme {
  DashboardTheme._();

  // Colors
  static const Color background = Color(0xffF8FAFC);
  static const Color card = Colors.white;

  static const Color primary = Color(0xff16A34A);

  static const Color title = Color(0xff111827);
  static const Color subtitle = Color(0xff6B7280);

  static const Color border = Color(0xffE5E7EB);

  static const Color success = Color(0xff22C55E);
  static const Color warning = Color(0xffF59E0B);
  static const Color danger = Color(0xffEF4444);
  static const Color info = Color(0xff3B82F6);

  // Radius
  static const double radius = 20;

  // Padding
  static const double pagePadding = 24;
  static const double cardPadding = 18;

  static BoxDecoration cardDecoration = BoxDecoration(
    color: card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(.04),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}