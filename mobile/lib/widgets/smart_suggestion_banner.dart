import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/address_provider.dart';
import '../models/address_model.dart';
import '../utils/theme.dart';
import '../l10n/app_localizations.dart';

/// Smart Suggestion Banner — Phase 3
///
/// Shows contextual suggestions on home screen:
/// - Morning (6AM-6PM): "Heading to office? Deliver to Office address" [Switch]
/// - Evening (6PM-11PM): "Back home? Deliver to Home" [Switch]
/// - Already on correct address: Don't show
///
/// This widget automatically hides if:
/// - User has only 1 address (nothing to switch to)
/// - User dismissed it
/// - Suggested address is already selected
class SmartSuggestionBanner extends StatefulWidget {
  const SmartSuggestionBanner({super.key});

  @override
  State<SmartSuggestionBanner> createState() => _SmartSuggestionBannerState();
}

class _SmartSuggestionBannerState extends State<SmartSuggestionBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return Consumer<AddressProvider>(
      builder: (context, addressProvider, _) {
        // Need at least 2 addresses to suggest switching
        if (addressProvider.addresses.length < 2) return const SizedBox.shrink();

        final selected = addressProvider.selectedAddress;
        final suggestion = _getSuggestion(addressProvider.addresses, selected);

        // No suggestion or already on suggested address
        if (suggestion == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  suggestion.bgColor.withValues(alpha: 0.15),
                  suggestion.bgColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: suggestion.bgColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: suggestion.bgColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(suggestion.icon, color: suggestion.iconColor, size: 20),
                ),
                const SizedBox(width: 10),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.title,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey[800]),
                      ),
                      Text(
                        suggestion.subtitle,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                // Switch button
                GestureDetector(
                  onTap: () {
                    addressProvider.selectAddress(suggestion.address);
                    setState(() => _dismissed = true);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: suggestion.iconColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:  Text(
                      AppLocalizations.of(context).commonSwitch,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Dismiss
                GestureDetector(
                  onTap: () => setState(() => _dismissed = true),
                  child: Icon(Icons.close, color: Colors.grey[400], size: 16),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Get time-based suggestion
  /// Morning/afternoon → suggest Office address
  /// Evening/night → suggest Home address
  _Suggestion? _getSuggestion(List<AddressModel> addresses, AddressModel? selected) {
    final hour = DateTime.now().hour;

    // Find Home and Office addresses
    final homeAddr = addresses.where((a) => a.tag?.toLowerCase() == 'home').firstOrNull;
    final officeAddr = addresses.where((a) => a.tag?.toLowerCase() == 'office').firstOrNull;

    // Morning/Afternoon (6AM - 6PM) → suggest Office
    if (hour >= 6 && hour < 18 && officeAddr != null) {
      // Don't suggest if already on Office
      if (selected?.id == officeAddr.id) return null;

      return _Suggestion(
        title: 'Heading to office?',
        subtitle: 'Deliver to Office address',
        icon: Icons.business_rounded,
        iconColor: const Color(0xFF1565C0),
        bgColor: const Color(0xFF42A5F5),
        address: officeAddr,
      );
    }

    // Evening/Night (6PM - 11PM) → suggest Home
    if (hour >= 18 && hour < 23 && homeAddr != null) {
      // Don't suggest if already on Home
      if (selected?.id == homeAddr.id) return null;

      return _Suggestion(
        title: 'Back home?',
        subtitle: 'Deliver to Home address',
        icon: Icons.home_rounded,
        iconColor: AppTheme.primaryGreen,
        bgColor: AppTheme.primaryGreen,
        address: homeAddr,
      );
    }

    return null;
  }
}

class _Suggestion {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final AddressModel address;

  _Suggestion({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.address,
  });
}
