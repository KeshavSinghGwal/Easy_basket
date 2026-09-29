import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/startup_deep_link.dart';
import 'core/api_client.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'widgets/app_lifecycle_refresh.dart';
import 'widgets/restart_widget.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/product_provider.dart';
import 'providers/order_provider.dart';
import 'providers/delivery_provider.dart';
import 'providers/admin_provider.dart';
import 'providers/service_area_provider.dart';
import 'providers/location_provider.dart';
import 'providers/address_provider.dart';
import 'providers/proximity_provider.dart';
import 'providers/store_status_provider.dart';
import 'providers/locale_provider.dart';
import 'l10n/app_localizations.dart';
import 'routes/app_router.dart';
import 'utils/theme.dart';
import 'services/razorpay_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SharedPreferences is needed early for auth + notification deep-link handling.
  final prefs = await SharedPreferences.getInstance();

  // Firebase is required early only on mobile so we can detect
  // notification cold-start navigation.
  if (!kIsWeb) {
    await Firebase.initializeApp();

    final initial =
        await FirebaseMessaging.instance.getInitialMessage();

    if (initial != null &&
        prefs.getString('access_token') != null &&
        prefs.getString('user_data') != null) {
      final role = StartupDeepLink.readRoleFromPrefs(prefs);

      final data = <String, dynamic>{};

      initial.data.forEach((k, v) {
        data[k.toString()] = v is String ? v : v.toString();
      });

      final path = routePathFromFcmData(data, role);

      if (path != null) {
        StartupDeepLink.registerColdStart(
          route: path,
          refreshData: data,
        );
      }
    }
  }

  // Start the UI without waiting for non-critical initialization.
  // Wrapped so a language change can rebuild every provider from scratch
  // (see RestartWidget) instead of leaving stale catalogue data behind.
  runApp(RestartWidget(child: MyApp(prefs: prefs)));

  // Non-critical initialization can happen after the app starts.
  initializeDateFormatting();

  if (!kIsWeb) {
    RazorpayService.initialize();
  }
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;

  const MyApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Language — created first so ApiService.language is set before any
        // other provider fires its first request.
        ChangeNotifierProvider(
          create: (_) => LocaleProvider(prefs: prefs),
        ),
        ChangeNotifierProvider(
          // lazy:false so the wiring below happens at startup, before any other
          // provider can issue an authenticated request against an unwired
          // sharedApiService.
          lazy: false,
          create: (_) {
            final authProvider = AuthProvider(
              authService: AuthService(apiService: authApiService),
              prefs: prefs,
            );
            // Wire the shared instance exactly once, here, where the
            // AuthProvider first exists. Re-runs if RestartWidget rebuilds,
            // re-pointing at the new AuthProvider — which is what we want.
            sharedApiService.onTokenExpired = authProvider.refreshAccessToken;
            sharedApiService.getCurrentToken = () => authProvider.token;
            return authProvider;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => CartProvider()..initialize(),
        ),
        // These were ChangeNotifierProxyProvider<AuthProvider, X> whose ONLY job
        // was re-attaching onTokenExpired/getCurrentToken to a per-provider
        // ApiService on every AuthProvider notification. With one shared
        // instance wired above, that duplication is gone and none of them
        // actually derives state from AuthProvider.
        ChangeNotifierProvider(
          create: (_) => ProductProvider(apiService: sharedApiService),
        ),
        ChangeNotifierProvider(
          create: (_) => OrderProvider(apiService: sharedApiService),
        ),
        ChangeNotifierProvider(
          create: (_) => DeliveryProvider(apiService: sharedApiService),
        ),
        ChangeNotifierProvider(
          create: (_) => AdminProvider(apiService: sharedApiService),
        ),
        ChangeNotifierProvider(
          create: (_) => ServiceAreaProvider(apiService: sharedApiService),
        ),
        // Location — GPS permission + coordinates + reverse geocode
        ChangeNotifierProvider(
          create: (_) => LocationProvider(),
        ),
        // Address — Saved addresses CRUD + selection.
        // Now shares the wired ApiService, so address calls refresh an expired
        // token like every other authenticated call.
        ChangeNotifierProvider(
          create: (_) => AddressProvider(apiService: sharedApiService),
        ),
        // Proximity — GPS vs saved addresses distance + decision
        ChangeNotifierProvider(
          create: (_) => ProximityProvider(),
        ),
        // Store open/closed — public endpoint, but it goes through the shared
        // instance too so there is exactly one ApiService in the app.
        // Fetched immediately: the home banner and the checkout buttons both
        // read it, and guests need it before they ever log in.
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => StoreStatusProvider(apiService: sharedApiService)..refresh(),
        ),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, _) => MaterialApp.router(
        title: 'Easy Basket',
        debugShowCheckedModeBanner: false,
        // Swaps to Noto Sans Gurmukhi for Punjabi; Poppins covers en + hi.
        theme: AppTheme.themeFor(localeProvider.language.code),
        // Explicit user choice — deliberately NOT the device locale.
        locale: localeProvider.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: AppRouter.router,
        builder: (context, child) {
          final content = child ?? const SizedBox.shrink();
          // Refresh store status (and active orders) when the app returns to the
          // foreground. Mounted here, globally, because home_screen already
          // assumes it exists — it dropped its own observer with a comment
          // pointing at this wrapper, so while this was unwrapped NEITHER ran.
          // Guests depend on it most: they never reach the FCM push path.
          final wrapped = AppLifecycleRefresh(child: content);
          if (!kIsWeb) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              try {
                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                final adminProvider = Provider.of<AdminProvider>(context, listen: false);

                // Store-reopen broadcast — subscribed for EVERY device, logged
                // in or not. initialize() below runs only for logged-in users,
                // so leaving this inside it meant guests never got the push.
                // Self-guards against the repeat calls this callback makes.
                NotificationService().subscribeToBroadcastTopic();

                if (authProvider.user != null) {
                  debugPrint('📱 [NOTIFICATION] Initializing for user: ${authProvider.user!.role}');
                  NotificationService().initialize(
                    context: context,
                    adminProvider: adminProvider,
                    authProvider: authProvider,
                  );
                } else {
                  debugPrint('⚠️ [NOTIFICATION] User not logged in, skipping initialization');
                }
              } catch (e) {
                debugPrint('❌ [NOTIFICATION] Error initializing: $e');
              }
            });
          }
          return wrapped;
        },
      ),
      ),
    );
  }
}

