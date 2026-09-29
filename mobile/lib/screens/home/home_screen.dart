import 'dart:async';
import '../../core/api_client.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../providers/product_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/service_area_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/proximity_provider.dart';
import '../../providers/store_status_provider.dart';
import '../../models/proximity_result.dart';
import '../../services/location_onboarding_service.dart';
import '../../utils/theme.dart';
import '../../utils/responsive.dart';
import '../../widgets/product_card.dart';
import '../../widgets/floating_cart_bar.dart';
import '../../widgets/active_order_bar.dart';
import '../../widgets/address_completion_sheet.dart';
import '../../services/notification_service.dart';
import '../../services/api_service.dart';
import '../../widgets/hero_banner_carousel.dart';
import '../../widgets/promo_banner_widget.dart';
import '../../widgets/store_closed_banner.dart';
import '../../models/campaign_model.dart';
import '../../models/category_model.dart';
import '../../l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool _hasCheckedServiceAvailability = false;
  String? _serviceNotAvailableMessage;

  /// Whether the user closed the "not serviceable" strip. Kept separate from
  /// [_serviceNotAvailableMessage] on purpose: dismissing hides the strip only,
  /// it does not clear the unserviceable state. Sharing one flag meant tapping
  /// × silently marked the area deliverable again.
  bool _serviceBannerDismissed = false;
  bool _isHomeLoading = true;
  Timer? _orderPollingTimer;
  List<CampaignModel> _heroBanners = []; // Homepage promo banners

  // Fun facts — randomly selected, rotate every 1.5 sec
  Timer? _factsTimer;
  int _currentFactIndex = 0;
  static final List<Map<String, String>> _funFacts = [
    {'emoji': '🥛', 'fact': 'India is the world\'s largest milk producer!'},
    {'emoji': '🍚', 'fact': 'Indians consume 100 million tonnes of rice yearly'},
    {'emoji': '🛒', 'fact': 'Online grocery grew 80% in India since 2020'},
    {'emoji': '🥭', 'fact': 'India grows over 1000 varieties of mangoes'},
    {'emoji': '🧈', 'fact': 'Ghee has been used in India for over 5000 years'},
    {'emoji': '🌶️', 'fact': 'Bhut Jolokia was once the world\'s hottest chilli'},
    {'emoji': '🍌', 'fact': 'India is the largest producer of bananas'},
    {'emoji': '🫖', 'fact': 'India is the 2nd largest tea producer globally'},
    {'emoji': '🧅', 'fact': 'India is the 2nd largest onion producer'},
    {'emoji': '🍋', 'fact': 'India produces 16% of the world\'s fruits'},
  ];

  // Product cards auto-scroll
  final ScrollController _productScrollController = ScrollController();
  Timer? _autoScrollTimer;

  // "Shop Now" shake animation
  late AnimationController _shopNowShakeController;
  late Animation<double> _shopNowShakeAnim;
  Timer? _shopNowShakeTimer;

  // Search hint flip animation
  late AnimationController _searchFlipController;
  late Animation<double> _searchFlipAnim;
  Timer? _searchHintTimer;
  int _currentHintIndex = 0;
  final List<String> _searchHints = [
    'Search "rice"',
    'Search "milk"',
    'Search "atta"',
    'Search "ghee"',
    'Search "sugar"',
    'Search "dal"',
    'Search "bread"',
    'Search "eggs"',
  ];

  @override
  void initState() {
    super.initState();
    // Search hint 3D flip animation
    _searchFlipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _searchFlipAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _searchFlipController, curve: Curves.easeInOut),
    );
    _startSearchHintRotation();

    // "Shop Now" shake animation — shakes every 5 seconds
    _shopNowShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shopNowShakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: -4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4, end: 4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shopNowShakeController,
      curve: Curves.easeInOut,
    ));
    _shopNowShakeTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _shopNowShakeController.forward(from: 0);
    });

    // Random starting fact
    _currentFactIndex = DateTime.now().millisecond % _funFacts.length;
    _startFactsRotation();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Sequential: GPS first → then products (products depend on location).
      // Guests don't have saved addresses / active orders, but they still need
      // GPS so the address bar and the soft service-area banner work.
      if (authProvider.token != null) {
        orderProvider.fetchActiveOrders(authProvider.token!, getUpdatedToken: () => authProvider.token);
        await _initSmartAddressFlow(authProvider.token!);
      } else {
        final locationProvider = Provider.of<LocationProvider>(context, listen: false);
        final addressProvider = Provider.of<AddressProvider>(context, listen: false);
        await locationProvider.detectLocation(force: true);
        if (mounted) {
          // Guests never run the proximity flow, so publish the GPS partial into
          // ProximityProvider — the single source every consumer (header, cart,
          // checkout) reads — instead of each call site reaching into LocationProvider.
          Provider.of<ProximityProvider>(context, listen: false)
              .seedPartial(locationProvider.detectedAddress);
          await _softServiceAreaCheck(addressProvider, locationProvider);
        }
      }

      // GPS done → now fetch products for this location
      await Future.wait([
        productProvider.fetchCategories(),
        productProvider.fetchProducts(limit: 15),
      ]);

      if (mounted) _startAutoScroll();

      // DONO done — hide skeleton, show real content
      if (mounted) {
        setState(() => _isHomeLoading = false);
        _factsTimer?.cancel();

        // Subscribe to SELECTED address pincode + fetch campaigns
        final notificationService = NotificationService();
        final addrProv = Provider.of<AddressProvider>(context, listen: false);
        final locationProv = Provider.of<LocationProvider>(context, listen: false);
        final selectedPin = addrProv.selectedAddress?.pincode
            ?? addrProv.defaultAddress?.pincode
            ?? locationProv.detectedAddress?.pincode;
        if (selectedPin != null && selectedPin.isNotEmpty) {
          notificationService.switchPincodeTopic(selectedPin);
          // Fetch campaigns for this pincode
          _fetchCampaigns(selectedPin);
        }

        // Start order polling ONLY if: FCM not available + active orders exist
        final orderProv = Provider.of<OrderProvider>(context, listen: false);
        if ((notificationService.fcmToken == null || notificationService.fcmToken!.isEmpty)
            && orderProv.activeOrders.isNotEmpty) {
          _startOrderPolling();
        }
      }
    });
  }

  /// Smart Address Flow — The main address initialization method
  ///
  /// Flow:
  /// 1. Start GPS detection (LocationProvider) — runs in background
  /// 2. Fetch saved addresses (AddressProvider) — API call
  /// 3. When BOTH ready → run proximity check (ProximityProvider)
  /// 4. Based on decision:
  ///    - autoSelect → select nearest address, no interruption
  ///    - warn → select nearest + show warning banner
  ///    - forceNew → show partial address, ask at checkout
  ///    - noGps → use default saved address
  /// 5. Service area check for selected address
  Future<void> _initSmartAddressFlow(String token) async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    final addressProvider = Provider.of<AddressProvider>(context, listen: false);
    final proximityProvider = Provider.of<ProximityProvider>(context, listen: false);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);

    // Step 1 & 2: Run GPS detection and address fetch in PARALLEL
    // Why parallel? GPS takes 2-3 sec, API takes 1 sec — don't wait sequentially
    // Always force fresh GPS detect — user might have moved
    // Skip address fetch if already loaded (e.g. login just fetched them)
    final needsFetch = addressProvider.addresses.isEmpty;
    await Future.wait([
      locationProvider.detectLocation(force: true),
      if (needsFetch) addressProvider.fetchAddresses(token),
    ]);
    // Sync addresses to OrderProvider (backward compatibility — no extra API call)
    if (mounted) {
      orderProvider.syncAddresses(addressProvider.addresses);
    }

    if (!mounted) return;

    // Early-out: if the user has already manually picked an address (e.g. from
    // /addresses or the address-completion sheet), respect that choice. The smart
    // flow auto-picks for first-time users; once the user has taken a stand, we
    // back off and only do the soft service-area check on their pick.
    if (addressProvider.manuallySelected && addressProvider.selectedAddress != null) {
      debugPrint('🏠 [Home] Manual selection in place → skipping auto-pick');
      await _softServiceAreaCheck(addressProvider, locationProvider);
      return;
    }

    // Step 3: Proximity check
    proximityProvider.checkProximity(
      locationProvider: locationProvider,
      addressProvider: addressProvider,
      force: true,
    );

    final result = proximityProvider.result;

    // Step 4: Silently decide — no warnings, no mismatch screens (Blinkit style)
    if (result != null) {
      if (result.decision == ProximityDecision.noGps) {
        // No GPS — silently use default saved address
        final defaultAddr = addressProvider.defaultAddress;
        if (defaultAddr != null) addressProvider.autoSelectAddress(defaultAddr);
        debugPrint('🏠 [Home] No GPS → default address');
      } else if (result.nearestAddress != null &&
          result.decision != ProximityDecision.forceNew) {
        // Near a saved address → silently select it
        addressProvider.autoSelectAddress(result.nearestAddress!);
        debugPrint('🏠 [Home] Silently selected: ${result.nearestAddress?.tag}');
      } else {
        // Far from saved (or no saved) → use GPS partial
        addressProvider.clearSelection();
        // Switch topic to GPS pincode (user is in new area)
        final gpsPincode = locationProvider.detectedAddress?.pincode;
        if (gpsPincode != null && gpsPincode.isNotEmpty) {
          NotificationService().switchPincodeTopic(gpsPincode);
        }
        debugPrint('🏠 [Home] Using GPS partial: ${locationProvider.detectedAddress?.displayName}');
      }
    }

    // Step 5: Service area check (soft — no hard redirect)
    await _softServiceAreaCheck(addressProvider, locationProvider);
  }

  /// Soft service area check — Blinkit style
  /// No hard redirect. Check GPS pincode first, then saved address.
  /// If not serviceable → show soft banner on home, don't block.
  Future<void> _softServiceAreaCheck(
    AddressProvider addressProvider,
    LocationProvider locationProvider,
  ) async {
    if (_hasCheckedServiceAvailability) return;
    _hasCheckedServiceAvailability = true;

    final serviceAreaProvider = Provider.of<ServiceAreaProvider>(context, listen: false);
    final partial = locationProvider.detectedAddress;
    final selected = addressProvider.selectedAddress;

    // Determine which pincode to check, and the coordinates that go with it.
    // Coordinates matter: the backend does the GPS radius check first and only
    // consults the pincode table when the radius isn't configured. Sending the
    // pincode alone forced the pincode path, so a location comfortably inside
    // the delivery radius was still reported as unserviceable.
    String? pinToCheck;
    String? cityForDisplay;
    double? latToCheck;
    double? lngToCheck;

    if (selected != null) {
      pinToCheck = selected.pincode;
      cityForDisplay = selected.city;
      // Legacy saved addresses may have no coordinates — tryParse yields null
      // and the check falls back to the pincode, as before.
      latToCheck = double.tryParse(selected.latitude ?? '');
      lngToCheck = double.tryParse(selected.longitude ?? '');
    } else if (partial?.pincode != null && partial!.pincode!.isNotEmpty) {
      pinToCheck = partial.pincode;
      cityForDisplay = partial.city;
      latToCheck = partial.latitude;
      lngToCheck = partial.longitude;
    }

    if (pinToCheck == null || pinToCheck.isEmpty) {
      debugPrint('🏠 [Home] No pincode to check — skipping service area');
      return;
    }

    try {
      final isServiceable = await serviceAreaProvider.checkServiceAvailability(
        latitude: latToCheck,
        longitude: lngToCheck,
        pincode: pinToCheck,
        country: 'India',
      );
      debugPrint('🏠 [Home] Service check $pinToCheck: ${isServiceable ? "✅" : "❌"}');

      if (!isServiceable && mounted) {
        // Soft banner — don't block, let user browse
        setState(() {
          _serviceNotAvailableMessage = "We don't deliver to ${cityForDisplay ?? pinToCheck} yet";
          // A fresh unserviceable result re-shows the strip even if the user
          // dismissed a previous one — the location changed, so say so again.
          _serviceBannerDismissed = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [Home] Service check error: $e');
    }
  }

  /// Auto-detect location for new users (seamless onboarding)
  /// Only shows screen if service not available
  Future<void> _autoDetectLocationForNewUser({
    required OrderProvider orderProvider,
    required AuthProvider authProvider,
  }) async {
    final serviceAreaProvider = Provider.of<ServiceAreaProvider>(context, listen: false);
    
    // Auto-detect and save location in background
    final result = await LocationOnboardingService.autoDetectAndSaveLocation(
      orderProvider: orderProvider,
      authProvider: authProvider,
      serviceAreaProvider: serviceAreaProvider,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      // Location detected - show edit screen for user to review/refine (Blinkit-style)
      if (result['addressData'] != null && mounted) {
        // Navigate to add address screen with pre-filled data
        // Open address form bottom sheet with pre-filled data
        AddressCompletionSheet.show(
          context: context,
          preFilledData: result['addressData'] as Map<String, dynamic>,
          onSaved: () {
            final authProv = Provider.of<AuthProvider>(context, listen: false);
            if (authProv.token != null) {
              Provider.of<OrderProvider>(context, listen: false).fetchAddresses(authProv.token!);
              Provider.of<AddressProvider>(context, listen: false).fetchAddresses(authProv.token!);
            }
          },
        );
      } else {
        // Fallback: if no address data, refresh and show success
        await orderProvider.fetchAddresses(authProvider.token!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(AppLocalizations.of(context).homeLocationDetected),
                ],
              ),
              backgroundColor: AppTheme.primaryGreen,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } else if (result['showScreen'] == true) {
      if (result['permissionDenied'] == true) {
        // Permission denied - show permission explanation screen
        context.go('/onboarding/location-permission');
      } else {
        // Service not available - show service not available screen
        // Mark as onboarding since user has no addresses yet
        context.go(
          '/service-not-available',
          extra: {
            'pincode': result['pincode'],
            'city': result['city'],
            'state': result['state'],
            'country': result['country'] ?? 'India',
            'returnTo': '/home',
            'isOnboarding': true, // Mark as onboarding flow
          },
        );
      }
    }
    // If error but don't show screen, user can add address manually via address bar
  }

  /// Check if the default address is serviceable
  Future<void> _checkDefaultAddressServiceAvailability(OrderProvider orderProvider) async {
    // Prevent multiple checks
    if (_hasCheckedServiceAvailability) return;
    
    // Only check if we have addresses
    if (orderProvider.addresses.isEmpty) return;
    
    // Find default address
    final defaultAddress = orderProvider.addresses.firstWhere(
      (addr) => addr.isDefault,
      orElse: () => orderProvider.addresses.first,
    );
    
    if (defaultAddress == null) return;
    
    _hasCheckedServiceAvailability = true;
    
    final serviceAreaProvider = Provider.of<ServiceAreaProvider>(context, listen: false);
    
    try {
      final isAvailable = await serviceAreaProvider.checkServiceAvailability(
        pincode: defaultAddress.pincode,
        country: 'India',
      );
      
      if (kDebugMode) {
        print('🏠 Home screen: Service availability check for default address (${defaultAddress.pincode}): $isAvailable');
      }
      
      if (!isAvailable && mounted) {
        // Show service not available screen
        if (kDebugMode) {
          print('🚫 Default address is not serviceable, showing service not available screen');
        }
        
        // Small delay to ensure home screen is fully rendered
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          // Use context.go to replace home page instead of stacking
          context.go(
            '/service-not-available',
            extra: {
              'pincode': defaultAddress.pincode,
              'city': defaultAddress.city,
              'state': defaultAddress.state,
              'country': 'India',
              'returnTo': '/home',
            },
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking service availability on home screen: $e');
      }
      // Don't block the user if there's an error checking service availability
    }
  }

  /// Order polling — backup when FCM denied
  /// Har 30 sec active orders refresh karo
  void _startOrderPolling() {
    _orderPollingTimer?.cancel();
    _orderPollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);

      // Stop polling if no active orders (saves API calls)
      if (orderProvider.activeOrders.isEmpty) {
        _orderPollingTimer?.cancel();
        debugPrint('⏹️ [Home] Polling stopped — no active orders');
        return;
      }

      if (authProvider.token != null) {
        orderProvider.fetchActiveOrders(authProvider.token!);
      }
    });
    debugPrint('🔄 [Home] Order polling started (FCM not available)');
  }

  // App resume active-order refresh is handled globally by AppLifecycleRefresh
  // (wraps the entire app in main.dart) — no duplicate observer needed here.

  /// Fetch campaigns for active pincode
  Future<void> _fetchCampaigns(String pincode) async {
    try {
      final apiService = sharedApiService;
      final response = await apiService.get('/campaigns?pincode=$pincode');
      if (response is Map<String, dynamic> && mounted) {
        final heroBanners = (response['hero_banners'] as List?)
            ?.map((e) => CampaignModel.fromJson(e as Map<String, dynamic>))
            .toList() ?? [];
        setState(() => _heroBanners = heroBanners);
      }
    } catch (e) {
      debugPrint('❌ [Home] Campaign fetch error: $e');
    }
  }

  void _startFactsRotation() {
    _factsTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      if (!mounted || !_isHomeLoading) {
        _factsTimer?.cancel();
        return;
      }
      setState(() {
        _currentFactIndex = (_currentFactIndex + 1) % _funFacts.length;
      });
    });
  }

  void _startSearchHintRotation() {
    _searchHintTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;

      // Text halfway (0.5) pe change karo — jab text sideways hai aur dikhta nahi
      // Kyun: Agar forward complete hone ke baad change karo toh briefly purana text flash hota hai
      bool hasChanged = false;
      void listener(AnimationStatus status) {
        // Jab forward animation chal rahi hai aur halfway cross ho jaye → text change karo
      }

      _searchFlipController.forward().then((_) {
        if (!mounted) return;
        // Forward complete — ab text change karo (agar halfway pe nahi hua)
        if (!hasChanged) {
          setState(() {
            _currentHintIndex = (_currentHintIndex + 1) % _searchHints.length;
          });
        }
        // Reverse — naya text flip hoke aata hai
        _searchFlipController.reverse();
      });

      // Halfway pe text change karo
      late VoidCallback halfwayListener;
      halfwayListener = () {
        if (_searchFlipAnim.value >= 0.5 && !hasChanged) {
          hasChanged = true;
          if (mounted) {
            setState(() {
              _currentHintIndex = (_currentHintIndex + 1) % _searchHints.length;
            });
          }
          _searchFlipAnim.removeListener(halfwayListener);
        }
      };
      _searchFlipAnim.addListener(halfwayListener);
    });
  }

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_productScrollController.hasClients) return;
      final maxScroll = _productScrollController.position.maxScrollExtent;
      final currentScroll = _productScrollController.offset;
      final nextScroll = currentScroll + 180; // scroll by ~1 card width

      if (nextScroll >= maxScroll) {
        // Scroll back to start
        _productScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      } else {
        _productScrollController.animateTo(
          nextScroll,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _searchHintTimer?.cancel();
    _autoScrollTimer?.cancel();
    _factsTimer?.cancel();
    _orderPollingTimer?.cancel();
    _shopNowShakeTimer?.cancel();
    _shopNowShakeController.dispose();
    _searchFlipController.dispose();
    _productScrollController.dispose();
    super.dispose();
  }

  /// Generates white bokeh dots — small, clustered in the green (top-left) area
  List<Widget> _buildSparkles() {
    final rng = Random(42); // fixed seed for consistent layout
    return List.generate(45, (i) {
      final size = 3.0 + rng.nextDouble() * 8; // 3–11px (smaller)
      // Concentrate in top-left: bias toward lower values
      final top = rng.nextDouble() * rng.nextDouble() * 200; // clustered toward top
      final left = rng.nextDouble() * rng.nextDouble() * 300; // clustered toward left
      final opacity = 0.3 + rng.nextDouble() * 0.5; // 0.3–0.8 (more visible)
      return Positioned(
        top: top,
        left: left,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: opacity),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: opacity * 0.5),
                blurRadius: size,
                spreadRadius: size * 0.2,
              ),
            ],
          ),
        ),
      );
    });
  }

  /// Skeleton loading screen with rotating fun facts
  Widget _buildHomeSkeletonWithFacts() {
    final fact = _funFacts[_currentFactIndex];

    return Container(
      color: const Color(0xFFF4F8F3),
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header skeleton — SHIMMER
              Shimmer.fromColors(
                baseColor: const Color(0xFFE8E8E8),
                highlightColor: const Color(0xFFF8F8F8),
                period: const Duration(milliseconds: 1000),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
                          const SizedBox(width: 10),
                          Container(width: 120, height: 20, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))),
                          const Spacer(),
                          Container(width: 36, height: 36, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(height: 42, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Search bar skeleton — SHIMMER
              Shimmer.fromColors(
                baseColor: const Color(0xFFE8E8E8),
                highlightColor: const Color(0xFFF8F8F8),
                period: const Duration(milliseconds: 1100),
                child: Container(height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
              ),
              const SizedBox(height: 18),

              // Fun fact — plain text, no card (on shimmer bg)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Padding(
                  key: ValueKey(_currentFactIndex),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(fact['emoji']!, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          fact['fact']!,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600], height: 1.3),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Category + Products skeleton — SHIMMER
              Shimmer.fromColors(
                baseColor: const Color(0xFFE8E8E8),
                highlightColor: const Color(0xFFF8F8F8),
                period: const Duration(milliseconds: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category chips
                    SizedBox(
                      height: 90,
                      child: Row(
                        children: List.generate(4, (i) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: i < 3 ? 10 : 0),
                            child: Column(
                              children: [
                                Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
                                const SizedBox(height: 8),
                                Container(width: 48, height: 10, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                              ],
                            ),
                          ),
                        )),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Section title
                    Container(width: 130, height: 16, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 12),

                    // Product cards
                    Row(
                      children: [
                        Expanded(child: _skeletonProductCard()),
                        const SizedBox(width: 12),
                        Expanded(child: _skeletonProductCard()),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeletonProductCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 90, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
          const SizedBox(height: 8),
          Container(width: double.infinity, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 6),
          Container(width: 70, height: 10, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(width: 45, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
              Container(width: 50, height: 26, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = Provider.of<CartProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: AppTheme.white,
      body: _isHomeLoading
          ? _buildHomeSkeletonWithFacts()
          : Stack(
        children: [
          // Green gradient behind status bar + header area
          Container(
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color.fromARGB(255, 123, 226, 127).withValues(alpha: 0.15),
                  Colors.white,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.6],
              ),
            ),
          ),
          SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
            onRefresh: () async {
              final productProvider = Provider.of<ProductProvider>(context, listen: false);
              final orderProvider = Provider.of<OrderProvider>(context, listen: false);
              // Pull-to-refresh is how a user checks "are they open yet?" —
              // force past the throttle so the answer is current.
              await Provider.of<StoreStatusProvider>(context, listen: false)
                  .refresh(force: true);
              await productProvider.fetchCategories();
              await productProvider.fetchProducts();
              if (authProvider.token != null) {
                // Reset and re-run smart address flow on pull-to-refresh
                final proximityProvider = Provider.of<ProximityProvider>(context, listen: false);
                final locationProvider = Provider.of<LocationProvider>(context, listen: false);
                locationProvider.reset();
                proximityProvider.reset();
                _hasCheckedServiceAvailability = false;
                await _initSmartAddressFlow(authProvider.token!);
              }
            },
            child: Consumer<CartProvider>(
              builder: (context, cartProvider, _) {
                return SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: cartProvider.itemCount > 0 ? 120 : 24, // Extra padding when cart button is visible (button height ~90px + margin)
                  ),
                  child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section — gradient card with sparkle dots (matches category card)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFB9E5B8).withValues(alpha: 0.6),
                        const Color(0xFFD4EDC9).withValues(alpha: 0.4),
                        const Color(0xFFECF6E5).withValues(alpha: 0.15),
                        Colors.white,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.2, 0.5, 0.8],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 6,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Stack(
                    children: [
                      // Sparkle dots — same as category card
                      ..._buildSparkles(),
                      Column(
                  children: [
                    // Top Row: Brand, Address, Profile
                    Consumer2<AddressProvider, ProximityProvider>(
                      builder: (context, addressProvider, proximityProvider, _) {
                        // Decide what address text to show
                        final selectedAddr = addressProvider.selectedAddress;
                        // Single source: ProximityProvider exposes the GPS partial
                        // for both logged-in (via checkProximity) and guest (via
                        // seedPartial) flows, so guests see "CURRENT LOCATION" too.
                        final partial = proximityProvider.partialAddress;
                        final proximityRes = proximityProvider.result;

                        // Two-line address display (matches UI design)
                        // Line 1: Label (CURRENT LOCATION / HOME ✓)
                        // Line 2: Address text (Sector 70, Mohali / 856, Doctor Goyal St)
                        String label;
                        String addressLine;
                        // Spec: ✓ only for Case A (~200m match), not for every saved selection
                        final hasCheckmark = selectedAddr != null &&
                            proximityRes != null &&
                            proximityRes.decision == ProximityDecision.autoSelect &&
                            proximityRes.isWithinExactMatch &&
                            proximityRes.nearestAddress?.id == selectedAddr.id;

                        if (selectedAddr != null) {
                          label = selectedAddr.tag?.toUpperCase() ?? 'ADDRESS';
                          addressLine = '${selectedAddr.addressLine1}'
                              '${selectedAddr.addressLine2 != null ? ', ${selectedAddr.addressLine2}' : ''}'
                              ', ${selectedAddr.city}';
                        } else if (partial != null) {
                          label = 'CURRENT LOCATION';
                          addressLine = partial.displayName;
                        } else {
                          label = '';
                          addressLine = 'Add delivery address';
                        }

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Brand Header
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryGreen,
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                                                blurRadius: 8,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.shopping_basket_rounded,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Easy Basket',
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w900,
                                            color: AppTheme.black,
                                            height: 1.0,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Address Card — Two line layout (matches Blinkit UI)
                                    // Line 1: 📍 CURRENT LOCATION / HOME ✓
                                    // Line 2: Sector 70, Mohali / 856, Doctor Goyal St
                                    GestureDetector(
                                      onTap: () {
                                        if (addressProvider.hasAddresses) {
                                          context.push('/addresses');
                                        } else {
                                          // No saved address — open bottom sheet instead of old add address page
                                          final locationProvider = Provider.of<LocationProvider>(context, listen: false);
                                          final partial = locationProvider.detectedAddress;
                                          AddressCompletionSheet.show(
                                            context: context,
                                            preFilledData: partial != null ? {
                                              'city': partial.city ?? '',
                                              'state': partial.state ?? '',
                                              'pincode': partial.pincode ?? '',
                                              'latitude': partial.latitude.toString(),
                                              'longitude': partial.longitude.toString(),
                                              'area': partial.area ?? '',
                                            } : {},
                                            onSaved: () {
                                              // Refresh after save
                                              final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                              if (authProvider.token != null) {
                                                Provider.of<OrderProvider>(context, listen: false).fetchAddresses(authProvider.token!);
                                                Provider.of<AddressProvider>(context, listen: false).fetchAddresses(authProvider.token!);
                                              }
                                            },
                                          );
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              AppTheme.lightGrey.withValues(alpha: 0.5),
                                              Colors.white.withValues(alpha: 0.8),
                                            ],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                                          boxShadow: [
                                            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.location_on_rounded,
                                              color: AppTheme.primaryGreen,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // Label row: CURRENT LOCATION / HOME ✓
                                                  if (label.isNotEmpty)
                                                    Row(
                                                      children: [
                                                        Text(
                                                          label,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w700,
                                                            color: AppTheme.primaryGreen,
                                                            letterSpacing: 0.5,
                                                          ),
                                                        ),
                                                        if (hasCheckmark) ...[
                                                          const SizedBox(width: 4),
                                                          Icon(Icons.check_circle, color: AppTheme.primaryGreen, size: 14),
                                                        ],
                                                      ],
                                                    ),
                                                  // Address text
                                                  Text(
                                                    addressLine,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppTheme.black,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(Icons.chevron_right_rounded, color: AppTheme.black.withValues(alpha: 0.4), size: 22),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => context.push('/profile'),
                                child: Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    border: Border.all(color: Colors.grey.shade200, width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.12),
                                        blurRadius: 14,
                                        spreadRadius: 1,
                                        offset: const Offset(0, 5),
                                      ),
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.04),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.person_outline_rounded, color: AppTheme.black, size: 26),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // Soft "not serviceable" strip — informs and offers the fix
                    // (change address), but never blocks browsing. Ordering is
                    // gated where it belongs: the address list re-checks the
                    // chosen address, and createOrder enforces the radius
                    // server-side with OUT_OF_SERVICE_AREA.
                    if (_serviceNotAvailableMessage != null && !_serviceBannerDismissed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFE0B2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, color: Color(0xFFF57C00), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _serviceNotAvailableMessage!,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFF57C00)),
                                ),
                              ),
                              // The actual fix for most people hitting this:
                              // their GPS is somewhere they're passing through
                              // and their real address is deliverable.
                              GestureDetector(
                                onTap: () => context.push('/addresses'),
                                behavior: HitTestBehavior.opaque,
                                child:  Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  child: Text(
                                    AppLocalizations.of(context).homeChange,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFE65100),
                                      decoration: TextDecoration.underline,
                                      decorationColor: Color(0xFFE65100),
                                    ),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                // Hides the strip only — the unserviceable state
                                // stays in effect.
                                onTap: () => setState(() => _serviceBannerDismissed = true),
                                child: Icon(Icons.close, size: 16, color: Colors.grey[400]),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Enable Location Banner — shows when GPS permission denied
                    Consumer<ProximityProvider>(
                      builder: (context, proximityProvider, _) {
                        if (!proximityProvider.showEnableLocationBanner) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: GestureDetector(
                            onTap: () async {
                              final locationProvider = Provider.of<LocationProvider>(context, listen: false);
                              if (locationProvider.isPermissionPermanentlyDenied) {
                                await locationProvider.openAppSettings();
                              } else {
                                final granted = await locationProvider.requestPermission();
                                if (granted && mounted) {
                                  // Permission granted — re-run smart flow
                                  locationProvider.reset();
                                  proximityProvider.reset();
                                  final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                  if (authProvider.token != null) {
                                    _hasCheckedServiceAvailability = false;
                                    _initSmartAddressFlow(authProvider.token!);
                                  }
                                }
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFE3F2FD), Color(0xFFEBF5FF)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF90CAF9), width: 1),
                                boxShadow: [
                                  BoxShadow(color: const Color(0xFF90CAF9).withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1)),
                                ],
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.my_location_rounded, color: Color(0xFF1565C0), size: 20),
                                  const SizedBox(width: 8),
                                   Expanded(
                                    child: Text(
                                      AppLocalizations.of(context).homeEnableLocationFast,
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1565C0)),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1565C0),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child:  Text(AppLocalizations.of(context).commonEnable, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Search Bar
                    GestureDetector(
                      onTap: () => context.push('/products'),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 14,
                              spreadRadius: 1,
                              offset: const Offset(0, 5),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: AppTheme.black, size: 24),
                            const SizedBox(width: 12),
                            AnimatedBuilder(
                              animation: _searchFlipAnim,
                              builder: (context, child) {
                                // 3D flip: rotate around X axis
                                final angle = _searchFlipAnim.value * pi;
                                return Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, 0.002) // perspective
                                    ..rotateX(angle),
                                  child: _searchFlipAnim.value <= 0.5
                                      ? Text(
                                          _searchHints[_currentHintIndex],
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        )
                                      : Transform(
                                          alignment: Alignment.center,
                                          transform: Matrix4.identity()..rotateX(pi),
                                          child: Text(
                                            _searchHints[_currentHintIndex],
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                );
                              },
                            ),
                            const Spacer(),
                            Container(width: 1, height: 20, color: Colors.grey.shade300),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => context.push('/products?voice=true'),
                              behavior: HitTestBehavior.opaque,
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.mic_none_rounded, color: AppTheme.primaryGreen, size: 24),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
                ),
              ),
              ),
              // Store closed panel — sits directly under the search bar so it
              // lands in the top half of the first screen, above the promo and
              // categories. Not dismissible: the user must understand why the
              // Place Order button is dead before they reach it. Everything
              // below stays visible and scrollable — browsing is encouraged.
              Consumer<StoreStatusProvider>(
                builder: (context, storeStatus, _) {
                  if (storeStatus.isOpen) return const SizedBox.shrink();
                  return StoreClosedBanner(status: storeStatus.status);
                },
              ),
              // Promo Banner with text overlay bottom-right
              Stack(
                children: [
                  const PromoBannerWidget(imagePath: 'assets/images/delievry_boy.png'),
                  Positioned(
                    bottom: 8,
                    right: 16,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                         Text(AppLocalizations.of(context).homeLowestPrices, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87)),
                        AnimatedBuilder(
                          animation: _shopNowShakeAnim,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(_shopNowShakeAnim.value, 0),
                              child: child,
                            );
                          },
                          child: GestureDetector(
                            onTap: () => context.push('/categories'),
                            child: Text(AppLocalizations.of(context).homeShopNow, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.primaryGreen)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Categories Section (Horizontal Scrollable Slider - Blinkit Style)
              Consumer<ProductProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading && provider.categories.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                        ),
                      ),
                    );
                  }
                  if (provider.categories.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFB9E5B8).withValues(alpha: 0.6),
                          const Color(0xFFD4EDC9).withValues(alpha: 0.4),
                          const Color(0xFFECF6E5).withValues(alpha: 0.15),
                          Colors.white,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.2, 0.5, 0.8],
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Sparkle dots
                        ..._buildSparkles(),
                        // Content
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                   Text(
                                    AppLocalizations.of(context).homeShopByCategory,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.black,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => context.push('/categories'),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child:  Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          AppLocalizations.of(context).commonViewAll,
                                          style: TextStyle(
                                            color: AppTheme.primaryGreen,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        SizedBox(width: 2),
                                        Icon(Icons.arrow_forward_ios, size: 13, color: AppTheme.primaryGreen),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // 2 rows × 4 columns grid
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: provider.categories.length > 8 ? 8 : provider.categories.length,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.75,
                                ),
                                itemBuilder: (context, index) {
                                  final category = provider.categories[index];
                                  return _CategoryGridCard(category: category);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // Hero Banner Carousel — promo campaigns
              if (_heroBanners.isNotEmpty)
                HeroBannerCarousel(banners: _heroBanners),

              // Products Section
              Consumer2<ProductProvider, OrderProvider>(
                builder: (context, productProvider, orderProvider, _) {
                  // Check saved addresses + partial GPS address + AddressProvider
                  // If ANY address exists (saved or partial), don't show "add address" box
                  final proximityProv = Provider.of<ProximityProvider>(context);
                  final addrProv = Provider.of<AddressProvider>(context);
                  final hasNoAddress = orderProvider.addresses.isEmpty
                      && !addrProv.hasAddresses
                      && proximityProv.partialAddress == null;

                  // Not serviceable → deliberately NOT blocked here. Browsing
                  // stays open: the commonest cause is a GPS mismatch (user is
                  // travelling, or hasn't set a delivery address yet) and those
                  // people usually DO have a deliverable saved address — hiding
                  // the catalogue from them helps nobody. Out-of-area users may
                  // also legitimately order to another address. The strip above
                  // explains the situation and offers "Change"; ordering itself
                  // is blocked by the address-list re-check and, definitively,
                  // by createOrder's server-side radius check.

                  if (productProvider.isLoading && productProvider.products.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (productProvider.products.isEmpty) {
                    return Container(
                      color: AppTheme.white,
                      padding: const EdgeInsets.all(48.0),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.shopping_bag_outlined,
                              size: 64,
                              color: AppTheme.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context).homeNoProducts,
                              style: TextStyle(
                                fontSize: 18,
                                color: AppTheme.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context).homeCheckBackSoon,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          Colors.grey.withValues(alpha: 0.03),
                          Colors.grey.withValues(alpha: 0.03),
                          Colors.white,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.3, 0.7, 1.0],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Info message for users without address
                        if (hasNoAddress)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16, top: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 20,
                                  color: AppTheme.primaryGreen,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    AppLocalizations.of(context).homeAddAddressToOrder,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 4),

                        // Snack it away Section (Horizontal Carousel - Blinkit Style)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 10.0, right: 4.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                   Text(
                                    AppLocalizations.of(context).homeSnackItAway,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.black,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => context.push('/products'),
                                    child:  Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          AppLocalizations.of(context).commonSeeAll,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0C831F),
                                          ),
                                        ),
                                        SizedBox(width: 2),
                                        Icon(Icons.arrow_forward_ios, size: 13, color: Color(0xFF0C831F)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Builder(
                              builder: (context) {
                                final inStockProducts = productProvider.products.where((p) =>
                                  p.isAvailable &&
                                  ((p.hasVariants && p.variants != null && p.variants!.any((v) => v.isAvailable && v.stock > 0)) ||
                                   (!p.hasVariants && p.stock > 0))
                                ).toList();
                                return SizedBox(
                                  height: 240,
                                  child: ListView.separated(
                                    controller: _productScrollController,
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                    itemCount: inStockProducts.length,
                                    separatorBuilder: (context, index) => const SizedBox(width: 12),
                                    itemBuilder: (context, index) {
                                      return SizedBox(
                                        width: 175,
                                        child: ProductCard(product: inStockProducts[index]),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  );
                },
              ),
              const _HomeFooter(),
            ],
                  ),
                );
              },
            ),
          ),
          // Bottom bars — Cart bar + Active order bar dono dikhenge
          // Cart bar upar, Active order bar neeche
          // Kyun: User ko dono info chahiye — cart mein kya hai + order ka status
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                FloatingCartBar(),     // Cart bar — upar
                ActiveOrderBar(),      // Active orders — neeche
              ],
            ),
          ),
        ],
      ),
    ),
    ],
    ),
  );
}

}

// Category Grid Card — 2 rows × 4 columns, dark highlighted background
class _CategoryGridCard extends StatelessWidget {
  final CategoryModel category;

  const _CategoryGridCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.push('/categories/${category.id}/products', extra: {
          'parentCategoryName': category.name,
        });
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    spreadRadius: 1,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: category.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: category.imageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (context, url) => Container(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.05),
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.05),
                          child: const Icon(Icons.category, size: 28, color: AppTheme.primaryGreen),
                        ),
                      )
                    : Container(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.05),
                        child: const Icon(Icons.category, size: 28, color: AppTheme.primaryGreen),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            category.name,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTheme.black,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}


class _HomeFooter extends StatelessWidget {
  const _HomeFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
      color: AppTheme.lightGrey.withValues(alpha: 0.15),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTrustBadge(
                context,
                icon: Icons.verified_user_outlined,
                text: '100% Genuine',
              ),
              _buildTrustBadge(
                context,
                icon: Icons.local_shipping_outlined,
                text: 'Fast Delivery',
              ),
              _buildTrustBadge(
                context,
                icon: Icons.refresh_outlined,
                text: 'Easy Returns',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Divider(color: AppTheme.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 6),
          const Text(
            'Live for food, delivered by Easy Basket',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.grey,
              letterSpacing: 0.5,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Made with ',
                style: TextStyle(fontSize: 12, color: AppTheme.grey),
              ),
              const Icon(Icons.favorite, color: Colors.red, size: 14),
              const Text(
                ' in India',
                style: TextStyle(fontSize: 12, color: AppTheme.grey),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Easy Basket © ${DateTime.now().year}',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.grey.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustBadge(BuildContext context, {required IconData icon, required String text}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade200, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 14,
                spreadRadius: 1,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Icon(icon, color: AppTheme.primaryGreen, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.darkGrey,
          ),
        ),
      ],
    );
  }
}
