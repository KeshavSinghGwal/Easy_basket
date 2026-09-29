import '../services/api_service.dart';

/// The ONE [ApiService] every authenticated call in the app shares.
///
/// Each provider used to build its own, so `_refreshInFlight` was per-instance
/// and the single-flight guard did not span providers: several providers hitting
/// a 401 together fired several parallel refreshes. Providers and services
/// created without wiring (AddressProvider, ServiceAreaProvider, RazorpayService,
/// NotificationService) got an instance that could not refresh at ALL, so their
/// calls simply failed once the 15-minute access token lapsed.
///
/// The Razorpay case was the sharpest: `/payment/create-order` and
/// `/payment/verify` sit in the middle of checkout, and their unwired instance
/// meant an expired token stopped a payment from starting with no recovery.
///
/// One instance means no caller can be constructed unwired, and the single-flight
/// guard is finally global — a hard prerequisite for rotating refresh tokens
/// later (EB-014b), since parallel refreshes against a rotating token would
/// invalidate each other and log everyone out.
///
/// Lives at module scope so RestartWidget (language change) rebuilding MyApp
/// cannot hand the providers a fresh instance mid-session. Wired exactly once,
/// in main.dart, where the AuthProvider first exists.
final ApiService sharedApiService = ApiService();

/// Deliberately SEPARATE and deliberately unwired — for `/auth/*` only.
///
/// If the auth endpoints shared the instance above, a 401 from `/auth/refresh`
/// would call onTokenExpired -> refreshAccessToken -> `/auth/refresh` -> 401.
/// With a real single-flight future that is a deadlock against itself, not
/// merely a loop. Auth endpoints must never auto-refresh.
final ApiService authApiService = ApiService();
