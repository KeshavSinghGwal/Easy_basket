import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/service_area_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/proximity_provider.dart';
import 'dart:async';
import 'package:geocoding/geocoding.dart';
import '../../models/address_model.dart';
import '../../utils/theme.dart';
import '../../services/notification_service.dart';
import '../../widgets/address_completion_sheet.dart';
import 'map_address_picker_screen.dart';

class AddressListScreen extends StatefulWidget {
  const AddressListScreen({super.key});

  @override
  State<AddressListScreen> createState() => _AddressListScreenState();
}

class _AddressListScreenState extends State<AddressListScreen> {
  int? _selectedAddressId;
  bool _isFromCheckout = false;
  bool _isUpdating = false;

  // Search state
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<_SearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  bool _isCheckingService = false; // Track if checking service availability
  int? _lastCheckedAddressId; // Track which address was last checked to prevent showing wrong result
  GoRouter? _router; // Store router reference to avoid context issues

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      final serviceAreaProvider = Provider.of<ServiceAreaProvider>(context, listen: false);
      
      // Reset service area provider state when screen loads
      // This ensures we don't have stale state from previous checks
      serviceAreaProvider.reset();
      
      // Check if user came from checkout (has items in cart)
      _isFromCheckout = cartProvider.items.isNotEmpty;
      
      if (authProvider.token != null) {
        orderProvider.fetchAddresses(authProvider.token!).then((_) {
          // Auto-select default address (or first address if no default)
          if (orderProvider.addresses.isNotEmpty) {
            final defaultAddress = orderProvider.addresses.firstWhere(
              (addr) => addr.isDefault,
              orElse: () => orderProvider.addresses.first,
            );
            setState(() {
              _selectedAddressId = defaultAddress.id;
            });
          }
        });
      }
    });
  }

  /// Open universal address form bottom sheet
  void _showAddressSheet(Map<String, dynamic> preFilledData) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    AddressCompletionSheet.show(
      context: context,
      preFilledData: preFilledData,
      onSaved: () {
        // Refresh addresses after save
        if (authProvider.token != null) {
          Provider.of<OrderProvider>(context, listen: false).fetchAddresses(authProvider.token!);
          Provider.of<AddressProvider>(context, listen: false).fetchAddresses(authProvider.token!);
        }
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── Search methods ──

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();

    if (query.trim().length < 3) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    try {
      final locations = await locationFromAddress(query);
      if (!mounted) return;

      final results = <_SearchResult>[];
      for (final location in locations.take(5)) {
        try {
          final placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            final title = [place.subLocality, place.locality].where((s) => s != null && s.isNotEmpty).join(', ');
            final subtitle = [place.administrativeArea, place.postalCode].where((s) => s != null && s.isNotEmpty).join(' - ');
            results.add(_SearchResult(
              title: title.isNotEmpty ? title : place.name ?? query,
              subtitle: subtitle,
              latitude: location.latitude,
              longitude: location.longitude,
              city: place.locality ?? place.subAdministrativeArea ?? '',
              state: place.administrativeArea ?? '',
              pincode: place.postalCode?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
              area: place.subLocality ?? '',
            ));
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
          _showSearchResults = true;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _showSearchResults = false;
          _isSearching = false;
        });
      }
    }
  }

  void _onSearchResultTap(_SearchResult result) {
    // Clear search
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _showSearchResults = false;
    });

    // Open address form bottom sheet with pre-filled data
    _showAddressSheet({
      'area': result.area.isNotEmpty ? result.area : result.title,
      'city': result.city,
      'state': result.state,
      'pincode': result.pincode,
      'latitude': result.latitude.toString(),
      'longitude': result.longitude.toString(),
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Store router reference to avoid context issues in async callbacks
    _router = GoRouter.of(context);
    
    // Reset service area provider and selection when coming back from service not available screen
    // This is called when the route changes (e.g., coming back from another screen)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      final serviceAreaProvider = Provider.of<ServiceAreaProvider>(context, listen: false);
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);
      
      // CRITICAL: Completely reset service area provider state
      serviceAreaProvider.reset();
      
      // Clear last checked address ID to ensure fresh checks
      _lastCheckedAddressId = null;
      
      // Reset checking state
      _isCheckingService = false;
      
      // Reset selected address to default address when coming back
      // This ensures we don't have stale selection from previous non-serviceable address
      if (orderProvider.addresses.isNotEmpty) {
        final defaultAddress = orderProvider.addresses.firstWhere(
          (addr) => addr.isDefault,
          orElse: () => orderProvider.addresses.first,
        );
        setState(() {
          _selectedAddressId = defaultAddress.id;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = Provider.of<OrderProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.shopping_basket_rounded, color: Colors.white, size: 18),
          ),
        ),
        title: const Text('Choose Delivery Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black54),
            onPressed: () => context.pop(),
          ),
        ],
      ),
      body: (orderProvider.isLoading || _isUpdating || _isCheckingService)
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen)))
          : orderProvider.addresses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.location_off_outlined, size: 48, color: AppTheme.primaryGreen),
                      ),
                      const SizedBox(height: 16),
                      const Text('No addresses found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('Add a delivery address to get started', style: TextStyle(fontSize: 13, color: AppTheme.grey)),
                      const SizedBox(height: 20),
                      AppTheme.gradientButton(
                        onPressed: () => _showAddressSheet({}),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: const Text('Add Address', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // ─── Search bar — directly on UI, white bg, soft shadow ───
                    Container(
                      margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(50),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 3)),
                          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1)),
                        ],
                      ),
                      child: TextField(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              decoration: InputDecoration(
                                hintText: 'Search area, street, landmark...',
                                hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
                                prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[400], size: 20),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? GestureDetector(
                                        onTap: () {
                                          _searchController.clear();
                                          setState(() {
                                            _searchResults = [];
                                            _showSearchResults = false;
                                            _isSearching = false;
                                          });
                                        },
                                        child: Icon(Icons.close_rounded, color: Colors.grey[400], size: 20),
                                      )
                                    : null,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),

                          // Search results — show below search bar when active
                          if (_isSearching)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppTheme.primaryGreen)))),
                            ),

                          if (_showSearchResults && _searchResults.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFF0F0F0)),
                              ),
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: _searchResults.length,
                                separatorBuilder: (_, __) => Container(height: 0.5, color: const Color(0xFFF0F0F0)),
                                itemBuilder: (context, index) {
                                  final result = _searchResults[index];
                                  return InkWell(
                                    onTap: () => _onSearchResultTap(result),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF5F9F5),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.location_on_rounded, color: AppTheme.primaryGreen, size: 16),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(result.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                if (result.subtitle.isNotEmpty)
                                                  Text(result.subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
                                              ],
                                            ),
                                          ),
                                          Icon(Icons.chevron_right_rounded, color: Colors.grey[300], size: 18),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                    // ─── Location options card (separate) ───
                    Container(
                      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Use Current Location
                          Consumer<LocationProvider>(
                            builder: (context, locationProvider, _) {
                              return InkWell(
                                onTap: () async {
                                  if (locationProvider.isPermissionGranted) {
                                    await locationProvider.detectLocation(force: true);
                                    if (mounted && locationProvider.detectedAddress != null) {
                                      final partial = locationProvider.detectedAddress!;
                                      if (mounted) {
                                        _showAddressSheet({
                                          'city': partial.city ?? '',
                                          'state': partial.state ?? '',
                                          'pincode': partial.pincode ?? '',
                                          'latitude': partial.latitude.toString(),
                                          'longitude': partial.longitude.toString(),
                                          'area': partial.area ?? '',
                                        });
                                      }
                                    }
                                  } else if (locationProvider.isPermissionPermanentlyDenied) {
                                    await locationProvider.openAppSettings();
                                  } else {
                                    final granted = await locationProvider.requestPermission();
                                    if (granted) {
                                      await locationProvider.detectLocation(force: true);
                                      if (mounted && locationProvider.detectedAddress != null) {
                                        final partial = locationProvider.detectedAddress!;
                                        if (mounted) {
                                          _showAddressSheet({
                                            'city': partial.city ?? '',
                                            'state': partial.state ?? '',
                                            'pincode': partial.pincode ?? '',
                                            'latitude': partial.latitude.toString(),
                                            'longitude': partial.longitude.toString(),
                                          });
                                        }
                                      }
                                    }
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryGreen.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(9),
                                        ),
                                        child: const Icon(Icons.my_location_rounded, color: AppTheme.primaryGreen, size: 16),
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Use Current Location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen)),
                                            SizedBox(height: 1),
                                            Text('Detect via GPS', style: TextStyle(fontSize: 11, color: AppTheme.grey)),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, color: Colors.grey[300], size: 22),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          Container(height: 0.5, margin: const EdgeInsets.symmetric(horizontal: 16), color: const Color(0xFFF0F0F0)),

                          // Pick on Map
                          InkWell(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MapAddressPickerScreen(
                                    onLocationSelected: (lat, lng, address) {},
                                  ),
                                ),
                              ).then((result) {
                                if (result != null && result is Map<String, dynamic> && mounted) {
                                  _showAddressSheet({
                                    'addressLine1': result['addressLine1'] ?? '',
                                    'city': result['city'] ?? '',
                                    'state': result['state'] ?? '',
                                    'pincode': result['pincode'] ?? '',
                                    'latitude': result['latitude']?.toString() ?? '',
                                    'longitude': result['longitude']?.toString() ?? '',
                                  });
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE3F2FD),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: const Icon(Icons.map_rounded, color: Color(0xFF1565C0), size: 16),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Pick on Map', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1565C0))),
                                        SizedBox(height: 1),
                                        Text('Choose from map', style: TextStyle(fontSize: 11, color: AppTheme.grey)),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded, color: Colors.grey[300], size: 22),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ─── "Your Saved Addresses" header ───
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          Text('Your Saved Addresses', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.grey)),
                          const Spacer(),
                          Text('${orderProvider.addresses.length} saved', style: TextStyle(fontSize: 11, color: AppTheme.grey)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: orderProvider.addresses.length,
                        itemBuilder: (context, index) {
                          final address = orderProvider.addresses[index];
                          final isSelected = _selectedAddressId == address.id;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF0C831F) : Colors.transparent,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                if (kDebugMode) {
                                  print('👆 [TAP] User tapped on address ID: ${address.id}, Pincode: ${address.pincode}');
                                  print('📍 Current selected address ID: $_selectedAddressId');
                                  print('📍 Is default: ${address.isDefault}, Is from checkout: $_isFromCheckout');
                                }
                                
                                // Check service availability for clicked address
                                final isServiceable = await _checkServiceAvailability(address);

                                if (!mounted) return;

                                if (!isServiceable) {
                                  if (kDebugMode) {
                                    print('🚫 [TAP] Service not available for address ID: ${address.id}');
                                  }
                                  return;
                                }
                                
                                // Serviceable — select, switch topic, go home
                                Provider.of<AddressProvider>(context, listen: false).selectAddress(address);
                                Provider.of<ProximityProvider>(context, listen: false).reset();
                                // Switch promo notification topic to selected address pincode
                                NotificationService().switchPincodeTopic(address.pincode);

                                if (_isFromCheckout) {
                                  // From checkout — select and stay on list
                                  setState(() => _selectedAddressId = address.id);
                                } else {
                                  // From home / address-pill — set default in background, pop back
                                  // to the previous screen (home) instead of `go('/home')`.
                                  // Why pop, not go? `go` rebuilds the home stack from scratch,
                                  // re-running `_initSmartAddressFlow` which can wipe the user's
                                  // manual pick. Pop preserves the existing home instance and the
                                  // Consumer<AddressProvider> rebuilds with the new selection.
                                  final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                  final orderProvider = Provider.of<OrderProvider>(context, listen: false);
                                  if (authProvider.token != null && !address.isDefault) {
                                    // Fire and forget — don't wait for API
                                    orderProvider.updateAddress(
                                      token: authProvider.token!,
                                      addressId: address.id,
                                      isDefault: true,
                                    );
                                  }
                                  if (context.canPop()) {
                                    context.pop();
                                  } else {
                                    // Edge case: address list opened as the entry route — fall
                                    // back to navigating home explicitly.
                                    context.go('/home');
                                  }
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Radio / selected indicator
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Icon(
                                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                        color: isSelected ? const Color(0xFF0C831F) : AppTheme.grey,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Address content
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Tag + Default badge row
                                          Row(
                                            children: [
                                              if (address.tag != null) ...[
                                                Icon(
                                                  address.tag == 'home' ? Icons.home_rounded
                                                      : address.tag == 'office' ? Icons.work_rounded
                                                      : Icons.location_on_rounded,
                                                  size: 16,
                                                  color: const Color(0xFF0C831F),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  address.tag!.toUpperCase(),
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                              ],
                                              if (address.tag == null)
                                                const Text(
                                                  'ADDRESS',
                                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black),
                                                ),
                                              if (address.isDefault) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFE8F5E9),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    'DEFAULT',
                                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF0C831F)),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          // Full address
                                          Text(
                                            address.fullAddress,
                                            style: TextStyle(fontSize: 13, color: AppTheme.darkGrey, height: 1.4),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Distance badge + Edit button column
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        // Distance badge — shows "2.3 km" from GPS
                                        Consumer<LocationProvider>(
                                          builder: (context, locationProvider, _) {
                                            if (!locationProvider.isPermissionGranted ||
                                                locationProvider.currentPosition == null ||
                                                address.latitude == null ||
                                                address.longitude == null) {
                                              return const SizedBox.shrink();
                                            }
                                            final proximityProvider = Provider.of<ProximityProvider>(context, listen: false);
                                            final dist = proximityProvider.getDistanceKm(
                                              locationProvider.currentPosition!,
                                              address,
                                            );
                                            if (dist == null) return const SizedBox.shrink();
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: dist < 5
                                                    ? const Color(0xFFE8F5E9)
                                                    : dist < 20
                                                        ? const Color(0xFFFFF8E1)
                                                        : const Color(0xFFFFEBEE),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                dist < 1
                                                    ? '${(dist * 1000).toStringAsFixed(0)}m'
                                                    : '${dist.toStringAsFixed(1)} km',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: dist < 5
                                                      ? AppTheme.primaryGreen
                                                      : dist < 20
                                                          ? const Color(0xFFF57C00)
                                                          : const Color(0xFFE53935),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        // Edit button
                                        GestureDetector(
                                          onTap: () => context.push('/address/edit', extra: address),
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF5F5F5),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.grey),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Bottom buttons
                    SafeArea(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.07),
                              blurRadius: 10,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Add New Address button
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: OutlinedButton.icon(
                                onPressed: () => _showAddressSheet({}),
                                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                                label: const Text('Add New Address', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF0C831F),
                                  side: const BorderSide(color: Color(0xFF0C831F), width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            // Continue to Payment (only from checkout)
                            if (_isFromCheckout && _selectedAddressId != null) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: AppTheme.gradientButton(
                                  onPressed: _isCheckingService ? null : () async {
                                    if (_selectedAddressId != null) {
                                      final selectedAddress = orderProvider.addresses.firstWhere(
                                        (addr) => addr.id == _selectedAddressId,
                                      );
                                      final isServiceable = await _checkServiceAvailability(selectedAddress);
                                      if (isServiceable && mounted) {
                                        context.push('/payment', extra: _selectedAddressId);
                                      }
                                    }
                                  },
                                  height: 48,
                                  child: _isCheckingService
                                      ? const SizedBox(
                                          height: 20, width: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                        )
                                      : const Text('Continue to Payment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Check service availability for an address
  /// Quick service check — no delays, no redirects, just true/false
  Future<bool> _checkServiceAvailability(AddressModel address) async {
    // Prefer GPS coordinates (radius check); fall back to pincode for legacy
    // coord-less addresses.
    final lat = double.tryParse(address.latitude ?? '');
    final lng = double.tryParse(address.longitude ?? '');
    final pincode = address.pincode.trim().replaceAll(' ', '');
    if (lat == null && lng == null && pincode.isEmpty) return true; // nothing to check

    try {
      final serviceAreaProvider = Provider.of<ServiceAreaProvider>(context, listen: false);
      final isAvailable = await serviceAreaProvider.checkServiceAvailability(
        latitude: lat,
        longitude: lng,
        pincode: pincode,
        country: 'India',
      );

      if (!isAvailable && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("We don't deliver to ${address.city} yet"),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      return isAvailable;
    } catch (e) {
      debugPrint('❌ Service check error: $e');
      return true; // On error, allow — don't block user
    }
  }

  Future<void> _updateDefaultAddress(int addressId) async {
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (authProvider.token == null) return;
    
    final address = orderProvider.addresses.firstWhere(
      (addr) => addr.id == addressId,
    );
    
    // If address is already default, verify it's serviceable and navigate to home
    if (address.isDefault) {
      // Double-check service availability for the default address
      // This ensures we check the correct address even after returning from service not available
      final isServiceable = await _checkServiceAvailability(address);
      
      // CRITICAL: Check if widget is still mounted before using context
      if (!mounted) {
        if (kDebugMode) {
          print('⚠️ [UPDATE] Widget no longer mounted, skipping navigation');
        }
        return;
      }
      
      if (isServiceable) {
        // Default address is serviceable, navigate to home
        if (kDebugMode) {
          print('✅ [UPDATE] Default address is serviceable, navigating to home');
        }
        
        // Navigate to home using router reference to avoid context issues
        if (mounted && _router != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _router != null) {
              _router!.go('/home');
            }
          });
        }
      } else {
        // Default address is not serviceable, service not available screen is already shown
        if (kDebugMode) {
          print('🚫 [UPDATE] Default address is not serviceable');
        }
      }
      return;
    }
    
    // Note: Service availability was already checked before calling this method
    // So we don't need to check again here to avoid double checking
    // The check happens in onTap/onChanged before calling this method
    
    // Only update if not already default
    if (!address.isDefault) {
      setState(() => _isUpdating = true);
      final success = await orderProvider.updateAddress(
        token: authProvider.token!,
        addressId: addressId,
        isDefault: true,
      );
      setState(() => _isUpdating = false);
      
      if (success && mounted) {
        // Reset proximity so home screen re-checks with new address
        Provider.of<ProximityProvider>(context, listen: false).reset();

        // Pop back to whichever screen pushed this list. Don't `go('/home')` —
        // that rebuilds the home stack and would re-run the smart flow.
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(orderProvider.error ?? 'Failed to update address'),
          ),
        );
      }
    } else {
      // Already default, just go back after a brief moment
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        context.pop();
      }
    }
  }
}

/// Search result model — holds geocoded address data
class _SearchResult {
  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;
  final String city;
  final String state;
  final String pincode;
  final String area;

  _SearchResult({
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.state,
    required this.pincode,
    required this.area,
  });
}
