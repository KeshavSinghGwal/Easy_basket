import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/locale_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/restart_widget.dart';

/// Language picker.
///
/// Each option is labelled in its own script, so someone who reads only
/// Gurmukhi can still find Punjabi without reading any English.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  Future<void> _select(
    BuildContext context,
    LocaleProvider provider,
    AppLanguage language,
  ) async {
    if (provider.language == language) {
      context.go('/home');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final ok = await provider.setLanguage(language);

    if (!context.mounted) return;

    if (!ok) {
      // Only surface a message on failure. On success the entire app visibly
      // changing language is the confirmation, and the snackbar would be torn
      // down by the restart below before anyone could read it.
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).languageChangeFailed),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Order matters.
    //
    // 1. Send the router to /splash — NOT straight to /home. Splash is the
    //    app's real bootstrap: it resolves the auth role and awaits
    //    LocationProvider.checkPermission() before deciding where to land.
    //    Jumping directly to /home skips that, and HomeScreen's init then
    //    runs detectLocation() on a freshly-constructed LocationProvider that
    //    has no permission state — the address fetch and the product fetch sit
    //    behind that same `Future.wait`, so the user arrives to "no delivery
    //    address" and an empty catalogue. Splash also routes admin/delivery
    //    users to their own dashboards; /home would have stranded them on the
    //    customer screen.
    // 2. Then rebuild everything. Providers are recreated, so ProductProvider
    //    drops the catalogue it fetched in the old language and it is re-fetched
    //    with the new Accept-Language header.
    //
    // Net effect is the same path a real app relaunch takes, which is why a
    // cold start already showed the correct language and data.
    context.go('/splash');
    RestartWidget.restartApp(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = context.watch<LocaleProvider>();

    return Scaffold(
      backgroundColor: AppTheme.lightGrey,
      appBar: AppBar(
        title: Text(l10n.languageTitle),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: AppTheme.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16, left: 4),
            child: Text(
              l10n.languageSubtitle,
              style: const TextStyle(fontSize: 14, color: AppTheme.grey),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (final language in AppLanguage.values)
                  _LanguageTile(
                    language: language,
                    selected: provider.language == language,
                    isLast: language == AppLanguage.values.last,
                    onTap: () => _select(context, provider, language),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.selected,
    required this.isLast,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(
            language.nativeName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: AppTheme.darkGrey,
            ),
          ),
          subtitle: language.nativeName == language.englishName
              ? null
              : Text(
                  language.englishName,
                  style: const TextStyle(fontSize: 12, color: AppTheme.grey),
                ),
          trailing: selected
              ? const Icon(Icons.check_circle_rounded,
                  color: AppTheme.primaryGreen)
              : const Icon(Icons.circle_outlined, color: AppTheme.grey),
        ),
        if (!isLast)
          const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}
