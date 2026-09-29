import 'package:flutter/material.dart';

/// Rebuilds the entire widget subtree from scratch.
///
/// Used when the language changes. Swapping `MaterialApp.locale` alone
/// re-renders the UI, but it does NOT clear provider state — ProductProvider
/// still holds the `_products` and `_categories` it fetched while
/// `Accept-Language` was set to the previous language, and HomeScreen only
/// fetches in initState, so a plain `context.go('/home')` can land the user
/// on a screen full of catalogue names in the language they just left.
///
/// Replacing the subtree key forces every provider to be constructed again,
/// which re-reads the persisted locale and re-fetches the catalogue under the
/// new header.
class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});

  final Widget child;

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restart();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  void restart() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
