import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/startup_deep_link.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'widgets/app_lifecycle_refresh.dart';
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

  // Load month/weekday names for every supported locale. DateFormat(fmt, 'hi')
  // throws if its locale data was never initialized, so this must run before
  // the first screen builds.
  await initializeDateFormatting();

  // Initialize SharedPreferences before Firebase cold-start route (needs role from prefs)
  final prefs = await SharedPreferences.getInstance();

  // Initialize Firebase (required for FCM notifications — mobile only)
  if (!kIsWeb) {
    await Firebase.initializeApp();
    // Single read of getInitialMessage — used by GoRouter redirect (no home → order flash)
    final initial = await FirebaseMessaging.instance.getInitialMessage();
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
        StartupDeepLink.registerColdStart(route: path, refreshData: data);
      }
    }
  }

  // Initialize Razorpay (only for mobile platforms, not web)
  if (!kIsWeb) {
    RazorpayService.initialize();
  }
  
  runApp(MyApp(prefs: prefs));
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;
  
  const MyApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    // Create a shared function to set up API service with token refresh
    ApiService createApiService(AuthProvider authProvider) {
      final apiService = ApiService();
      // Set up automatic token refresh callback
      apiService.onTokenExpired = () async {
        return await authProvider.refreshAccessToken();
      };
      // So retries after a refresh pick up the fresh token (all verbs).
      apiService.getCurrentToken = () => authProvider.token;
      return apiService;
    }
    
    return MultiProvider(
      providers: [
        // Language — created first so ApiService.language is set before any
        // other provider fires its first request.
        ChangeNotifierProvider(
          create: (_) => LocaleProvider(prefs: prefs),
        ),
        ChangeNotifierProvider(
          create: (_) {
            final apiService = ApiService();
            final authService = AuthService(apiService: apiService);
            final authProvider = AuthProvider(
              authService: authService,
              prefs: prefs,
            );
            // Set up automatic token refresh callback after provider is created
            // We'll set it up in update callbacks for other providers
            return authProvider;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => CartProvider()..initialize(),
        ),
        ChangeNotifierProxyProvider<AuthProvider, ProductProvider>(
          create: (_) => ProductProvider(apiService: ApiService()),
          update: (_, authProvider, previous) {
            if (previous != null) {
              // Update existing provider's API service callback
              previous.apiService.onTokenExpired = () async {
                return await authProvider.refreshAccessToken();
              };
              previous.apiService.getCurrentToken = () => authProvider.token;
              return previous;
            }
            return ProductProvider(apiService: createApiService(authProvider));
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, OrderProvider>(
          create: (_) => OrderProvider(apiService: ApiService()),
          update: (_, authProvider, previous) {
            if (previous != null) {
              // Update existing provider's API service callback
              previous.apiService.onTokenExpired = () async {
                return await authProvider.refreshAccessToken();
              };
              previous.apiService.getCurrentToken = () => authProvider.token;
              return previous;
            }
            return OrderProvider(apiService: createApiService(authProvider));
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, DeliveryProvider>(
          create: (_) => DeliveryProvider(apiService: ApiService()),
          update: (_, authProvider, previous) {
            if (previous != null) {
              // Update existing provider's API service callback
              previous.apiService.onTokenExpired = () async {
                return await authProvider.refreshAccessToken();
              };
              previous.apiService.getCurrentToken = () => authProvider.token;
              return previous;
            }
            return DeliveryProvider(apiService: createApiService(authProvider));
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, AdminProvider>(
          create: (_) => AdminProvider(apiService: ApiService()),
          update: (_, authProvider, previous) {
            if (previous != null) {
              // Update existing provider's API service callback
              previous.apiService.onTokenExpired = () async {
                return await authProvider.refreshAccessToken();
              };
              previous.apiService.getCurrentToken = () => authProvider.token;
              return previous;
            }
            return AdminProvider(apiService: createApiService(authProvider));
          },
        ),
        ChangeNotifierProvider(
          create: (_) => ServiceAreaProvider(),
        ),
        // Location — GPS permission + coordinates + reverse geocode
        ChangeNotifierProvider(
          create: (_) => LocationProvider(),
        ),
        // Address — Saved addresses CRUD + selection
        ChangeNotifierProvider(
          create: (_) => AddressProvider(),
        ),
        // Proximity — GPS vs saved addresses distance + decision
        ChangeNotifierProvider(
          create: (_) => ProximityProvider(),
        ),
        // Store open/closed — public endpoint, so no auth wiring needed.
        // Fetched immediately: the home banner and the checkout buttons both
        // read it, and guests need it before they ever log in.
        ChangeNotifierProvider(
          create: (_) => StoreStatusProvider()..refresh(),
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

