import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/products/product_list_screen.dart';
import '../screens/products/product_detail_screen.dart';
import '../screens/categories/categories_screen.dart';
import '../screens/categories/subcategory_selection_screen.dart';
import '../screens/categories/category_with_subcategories_screen.dart';
import '../screens/cart/cart_screen.dart';
import '../screens/address/address_list_screen.dart';
import '../screens/address/add_address_screen.dart';
import '../screens/address/edit_address_screen.dart';
import '../screens/address/map_address_picker_screen.dart';
import '../screens/payment/payment_screen.dart';
import '../screens/payment/payment_status_screen.dart';
import '../screens/orders/order_tracking_screen.dart';
import '../screens/orders/order_list_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/language_screen.dart';
import '../screens/delivery/delivery_dashboard_screen.dart';
import '../screens/delivery/delivery_orders_screen.dart';
import '../screens/delivery/delivery_order_detail_screen.dart';
import '../screens/delivery/delivery_map_view_screen.dart';
import '../screens/delivery/delivery_cod_collect_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_orders_screen.dart';
import '../screens/admin/admin_order_detail_screen.dart';
import '../screens/admin/admin_order_timeline_screen.dart';
import '../screens/admin/admin_riders_screen.dart';
import '../screens/admin/admin_users_screen.dart';
import '../screens/admin/admin_products_screen.dart';
import '../screens/admin/admin_categories_screen.dart';
import '../screens/admin/add_edit_category_screen.dart';
import '../screens/admin/add_edit_product_screen.dart';
import '../screens/admin/category_order_screen.dart';
import '../screens/admin/send_notification_screen.dart';
import '../screens/admin/campaign_list_screen.dart';
import '../screens/admin/campaign_form_screen.dart';
import '../screens/admin/store_status_screen.dart';
import '../models/address_model.dart';
import '../models/campaign_model.dart';
import '../screens/service_area/service_not_available_screen.dart';
import '../screens/address/location_mismatch_screen.dart';
import '../screens/address/places_search_screen.dart';
import '../screens/onboarding/location_detection_screen.dart';
import '../screens/onboarding/location_permission_screen.dart';
import '../screens/address/location_permission_screen.dart' as customer_location_gate;
import '../core/startup_deep_link.dart';
import '../core/auth_refresh_notifier.dart';
import '../screens/help/help_support_screen.dart';
import '../screens/support/support_request_screen.dart';
import '../screens/admin/admin_support_requests_screen.dart';

class AppRouter {
  /// Routes that require an authenticated customer (or admin/delivery).
  /// Blinkit-style: browsing + cart is open; only transactions and personal data gate.
  /// When a guest hits one of these, we redirect to /login?returnTo=<originalPath>.
  static bool _requiresLogin(String path) {
    if (path.startsWith('/payment')) return true;
    if (path == '/orders' || path.startsWith('/order/')) return true;
    if (path == '/profile' || path.startsWith('/profile/')) return true;
    if (path == '/addresses' || path.startsWith('/address/add') || path.startsWith('/address/edit')) return true;
    return false;
  }

  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    // Without this, `redirect` below ran only on explicit navigation — it reads
    // AuthProvider with listen:false, so a logout (including the automatic one
    // after a failed token refresh) left the user sitting on a gated screen
    // making calls with a null token. See core/auth_refresh_notifier.dart.
    refreshListenable: AuthRefreshNotifier.instance,
    redirect: (context, state) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final isAuthenticated = authProvider.isAuthenticated;
      final isLoginRoute = state.matchedLocation == '/login';
      final currentLocation = state.matchedLocation;

      // Guests are blocked only from login-required routes (checkout, profile, orders, address book).
      // Everything else — splash, home, location-gate, categories, products, cart, address-search/map — is open.
      if (!isAuthenticated && !isLoginRoute && _requiresLogin(currentLocation)) {
        final returnTo = Uri.encodeComponent(state.uri.toString());
        return '/login?returnTo=$returnTo';
      }

      // If authenticated, check role and redirect accordingly
      if (isAuthenticated) {
        final coldStart = StartupDeepLink.takePendingAtEntryRoute(currentLocation);
        if (coldStart != null) {
          return coldStart;
        }

        final userRole = authProvider.user?.role;
        
        // Admin users
        if (userRole == 'admin') {
          if (currentLocation != '/admin/dashboard' && 
              !currentLocation.startsWith('/admin/') &&
              currentLocation != '/splash' &&
              currentLocation != '/login') {
            return '/admin/dashboard';
          }
          if (isLoginRoute || currentLocation == '/splash') {
            return '/admin/dashboard';
          }
        }
        // Delivery users
        else if (userRole == 'delivery') {
          if (currentLocation != '/delivery/dashboard' && 
              !currentLocation.startsWith('/delivery/') &&
              currentLocation != '/splash' &&
              currentLocation != '/login') {
            return '/delivery/dashboard';
          }
          if (isLoginRoute || currentLocation == '/splash') {
            return '/delivery/dashboard';
          }
        }
        // Customer users
        else {
          // If customer user tries to access admin/delivery routes, redirect to home
          if (currentLocation.startsWith('/admin/') || currentLocation.startsWith('/delivery/')) {
            return '/home';
          }
          
          // Don't redirect if already on address or onboarding screens
          if (currentLocation.startsWith('/address') ||
              currentLocation == '/service-not-available' ||
              currentLocation == '/location-mismatch' ||
              currentLocation == '/location-gate' ||
              currentLocation.startsWith('/onboarding/')) {
            return null;
          }
          
          // Splash lets customer choose /location-gate vs /home after permission check (no instant /home).
          if (currentLocation == '/splash') {
            return null;
          }
          if (isLoginRoute) {
            // If checkout/profile/etc bounced here for OTP and user is already authenticated,
            // jump straight to the original destination instead of looping back to home.
            final returnTo = state.uri.queryParameters['returnTo'];
            if (returnTo != null && returnTo.isNotEmpty) {
              return Uri.decodeComponent(returnTo);
            }
            return '/home';
          }
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/location-gate',
        builder: (context, state) => const customer_location_gate.LocationPermissionScreen(),
      ),
      GoRoute(
        path: '/onboarding/location',
        builder: (context, state) => const LocationDetectionScreen(),
      ),
      GoRoute(
        path: '/onboarding/location-permission',
        builder: (context, state) => const LocationPermissionScreen(),
      ),
      GoRoute(
        path: '/location-mismatch',
        builder: (context, state) => const LocationMismatchScreen(),
      ),
      GoRoute(
        path: '/address/search',
        builder: (context, state) => const PlacesSearchScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
  path: '/support',
  builder: (context, state) {
    

    return const SupportRequestScreen();
  },
),
     GoRoute(
  path: '/admin/support-requests',
  builder: (context, state) =>
      const AdminSupportRequestsScreen(),
),
      GoRoute(
        path: '/service-not-available',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ServiceNotAvailableScreen(
            pincode: extra?['pincode'] as String?,
            city: extra?['city'] as String?,
            state: extra?['state'] as String?,
            country: extra?['country'] as String?,
            returnTo: extra?['returnTo'] as String?,
            isOnboarding: extra?['isOnboarding'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/categories',
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/categories/:id/subcategories',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          final extra = state.extra as Map<String, dynamic>?;
          return SubcategorySelectionScreen(
            parentCategoryId: id,
            parentCategoryName: extra?['parentCategoryName'] as String? ?? 'Category',
          );
        },
      ),
      GoRoute(
        path: '/categories/:id/products',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          final extra = state.extra as Map<String, dynamic>?;
          return CategoryWithSubcategoriesScreen(
            parentCategoryId: id,
            parentCategoryName: extra?['parentCategoryName'] as String? ?? 'Category',
          );
        },
      ),
      GoRoute(
        path: '/products',
        builder: (context, state) {
          final categoryId = state.uri.queryParameters['categoryId'];
          final voice = state.uri.queryParameters['voice'] == 'true';
          return ProductListScreen(
            categoryId: categoryId != null ? int.parse(categoryId) : null,
            startVoiceSearch: voice,
          );
        },
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return ProductDetailScreen(productId: id);
        },
      ),
      GoRoute(
        path: '/cart',
        builder: (context, state) => const CartScreen(),
      ),
      GoRoute(
        path: '/addresses',
        builder: (context, state) => const AddressListScreen(),
      ),
      GoRoute(
        path: '/address/add',
        builder: (context, state) {
          final preFilledData = state.extra as Map<String, dynamic>?;
          return AddAddressScreen(preFilledData: preFilledData);
        },
      ),
      GoRoute(
        path: '/address/edit',
        builder: (context, state) {
          final address = state.extra as AddressModel;
          return EditAddressScreen(address: address);
        },
      ),
      GoRoute(
        path: '/address/map-picker',
        builder: (context, state) {
          return MapAddressPickerScreen(
            onLocationSelected: (lat, lng, address) {
              context.pop({
                'latitude': lat,
                'longitude': lng,
                'address': address,
              });
            },
          );
        },
      ),
      GoRoute(
        path: '/payment',
        builder: (context, state) {
          // Accept either a plain int addressId or a {'addressId': int} map, so a
          // caller passing the wrong shape never hard-crashes the screen.
          final extra = state.extra;
          final addressId = extra is Map
              ? extra['addressId'] as int?
              : extra as int?;
          return PaymentScreen(addressId: addressId);
        },
      ),
      GoRoute(
        path: '/payment/status',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          if (extra == null) {
            return const PaymentStatusScreen(
              status: PaymentStatus.failed,
              message: 'Invalid payment status',
            );
          }
          return PaymentStatusScreen(
            status: extra['status'] as PaymentStatus,
            message: extra['message'] as String,
            orderId: extra['orderId'] as int?,
          );
        },
      ),
      GoRoute(
        path: '/orders',
        builder: (context, state) => const OrderListScreen(),
      ),
      GoRoute(
        path: '/order/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return OrderTrackingScreen(orderId: id);
        },
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/help-support',
        builder: (context, state) => const HelpSupportScreen(),
     ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const EditProfileScreen(),
      ),
      // Top-level, NOT under /profile/, because _requiresLogin gates every
      // /profile/* path — a guest must be able to pick their language before
      // signing in.
      GoRoute(
        path: '/language',
        builder: (context, state) => const LanguageScreen(),
      ),
      // Delivery Routes
      GoRoute(
        path: '/delivery/dashboard',
        builder: (context, state) => const DeliveryDashboardScreen(),
      ),
      GoRoute(
        path: '/delivery/orders',
        builder: (context, state) {
          final status = state.uri.queryParameters['status'];
          return DeliveryOrdersScreen(status: status);
        },
      ),
      GoRoute(
        path: '/delivery/order/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return DeliveryOrderDetailScreen(orderId: id);
        },
      ),
      GoRoute(
        path: '/delivery/cod/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return DeliveryCodCollectScreen(orderId: id);
        },
      ),
      GoRoute(
        path: '/delivery/map',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          if (extra == null) {
            return const Scaffold(
              body: Center(child: Text('Invalid map parameters')),
            );
          }
          return DeliveryMapViewScreen(
            destinationLat: extra['destinationLat'] as double,
            destinationLng: extra['destinationLng'] as double,
            destinationAddress: extra['destinationAddress'] as String,
            orderId: extra['orderId']?.toString(),
          );
        },
      ),
      // Admin Routes
      GoRoute(
        path: '/admin/dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/admin/orders',
        builder: (context, state) {
          final status = state.uri.queryParameters['status'];
          return AdminOrdersScreen(status: status);
        },
      ),
      GoRoute(
        path: '/admin/orders/:id',
        builder: (context, state) {
          final orderId = int.parse(state.pathParameters['id']!);
          return AdminOrderDetailScreen(orderId: orderId);
        },
      ),
      // Phase 3: timeline. Admin order detail uses `/admin/order/:id/timeline`
      // (singular `order`) so we mount that exact path here.
      GoRoute(
        path: '/admin/order/:id/timeline',
        builder: (context, state) {
          final orderId = int.parse(state.pathParameters['id']!);
          return AdminOrderTimelineScreen(orderId: orderId);
        },
      ),
      GoRoute(
        path: '/admin/riders',
        builder: (context, state) => const AdminRidersScreen(),
      ),
      GoRoute(
        path: '/admin/users',
        builder: (context, state) {
          final role = state.uri.queryParameters['role'];
          return AdminUsersScreen(role: role);
        },
      ),
      GoRoute(
        path: '/admin/products',
        builder: (context, state) => const AdminProductsScreen(),
      ),
      GoRoute(
        path: '/admin/categories',
        builder: (context, state) => const AdminCategoriesScreen(),
      ),
      GoRoute(
        path: '/admin/categories/add',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return AddEditCategoryScreen(
            parentCategoryId: extra?['parentCategoryId'] as int?,
          );
        },
      ),
      GoRoute(
        path: '/admin/categories/:id/edit',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          // We'll fetch category by ID in the screen if needed
          return AddEditCategoryScreen(categoryId: id);
        },
      ),
      GoRoute(
        path: '/admin/categories/order',
        builder: (context, state) => const CategoryOrderScreen(),
      ),
      GoRoute(
        path: '/admin/notifications',
        builder: (context, state) => const SendNotificationScreen(),
      ),
      GoRoute(
        path: '/admin/campaigns',
        builder: (context, state) => const CampaignListScreen(),
      ),
      GoRoute(
        path: '/admin/campaigns/create',
        builder: (context, state) => const CampaignFormScreen(),
      ),
      GoRoute(
        path: '/admin/campaigns/edit',
        builder: (context, state) {
          final campaign = state.extra as CampaignModel?;
          return CampaignFormScreen(campaign: campaign);
        },
      ),
      GoRoute(
        path: '/admin/store-status',
        builder: (context, state) => const StoreStatusScreen(),
      ),
      GoRoute(
        path: '/admin/products/add',
        builder: (context, state) => const AddEditProductScreen(),
      ),
      GoRoute(
        path: '/admin/products/:id/edit',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          // We'll fetch product by ID in the screen if needed
          return AddEditProductScreen(productId: id);
        },
      ),
    ],
  );
}

