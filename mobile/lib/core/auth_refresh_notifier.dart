import 'package:flutter/foundation.dart';

/// Bridges authentication-state changes into GoRouter's redirect evaluation.
///
/// `AppRouter.router` is a `static final GoRouter` built before any provider
/// exists, and its `redirect` reads `AuthProvider` with `listen: false`. With no
/// `refreshListenable`, redirects ran only on an explicit navigation — never in
/// response to auth state actually changing.
///
/// The consequence: when a token refresh failed mid-session, `logout()` ran and
/// cleared the credentials, but whatever gated screen the user was on stayed
/// mounted and kept issuing calls with a null token. Each one failed, so the
/// session looked broken rather than expired.
///
/// This is a standalone notifier rather than `AuthProvider` itself precisely
/// because the router is constructed statically and cannot be handed a provider
/// instance. Keeping it in its own file also avoids an import cycle between
/// `app_router.dart` and `auth_provider.dart`.
class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier._();

  static final AuthRefreshNotifier instance = AuthRefreshNotifier._();

  /// Call after ANY change to authentication state — sign-in, sign-out, or a
  /// refresh failure — so the router re-runs its guards.
  void authChanged() => notifyListeners();
}
