import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Pops when the router stack allows; otherwise goes to the role hub (e.g. after
/// cold start from a notification, when [order] is the only route).
void popOrRoleHub(BuildContext context) {
  if (!context.mounted) return;
  if (context.canPop()) {
    context.pop();
    return;
  }
  final loc = GoRouterState.of(context).matchedLocation;
  if (loc.startsWith('/admin/')) {
    context.go('/admin/dashboard');
  } else if (loc.startsWith('/delivery/')) {
    context.go('/delivery/dashboard');
  } else {
    context.go('/home');
  }
}

/// Wraps a screen so Android/iOS system back matches AppBar “up” when stack is empty.
Widget popScopeWithRoleHubFallback(BuildContext context, Widget child) {
  return PopScope(
    canPop: context.canPop(),
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      popOrRoleHub(context);
    },
    child: child,
  );
}
