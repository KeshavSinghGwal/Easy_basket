import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/location_provider.dart';
import '../../providers/service_area_provider.dart';
import '../../utils/theme.dart';
import '../../l10n/app_localizations.dart';

/// Places Search Screen
///
/// User types address/area → search results show → user selects
/// Pre-fill address form with selected location
///
/// Phase 2: Currently uses device geocoder (FREE)
/// Can upgrade to Google Places API later for better results
class PlacesSearchScreen extends StatefulWidget {
  const PlacesSearchScreen({super.key});

  @override
  State<PlacesSearchScreen> createState() => _PlacesSearchScreenState();
}

class _PlacesSearchScreenState extends State<PlacesSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  List<_SearchResult> _results = [];
  bool _isSearching = false;
  bool _isCheckingService = false;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Search with debounce — wait 500ms after user stops typing
  /// Why debounce? Reduce unnecessary API calls while user is still typing
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();

    if (query.trim().length < 3) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query.trim());
    });
  }

  /// Perform geocode search — convert text to lat/lng + address
  Future<void> _performSearch(String query) async {
    try {
      // Use device geocoder to search
      final locations = await locationFromAddress(query);

      if (!mounted) return;

      final results = <_SearchResult>[];

      for (final location in locations.take(5)) {
        // Reverse geocode each result to get full address
        try {
          final placemarks = await placemarkFromCoordinates(
            location.latitude,
            location.longitude,
          );

          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            results.add(_SearchResult(
              title: _buildTitle(place),
              subtitle: _buildSubtitle(place),
              latitude: location.latitude,
              longitude: location.longitude,
              city: place.locality ?? place.subAdministrativeArea ?? '',
              state: place.administrativeArea ?? '',
              pincode: place.postalCode?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
              area: place.subLocality ?? '',
            ));
          }
        } catch (_) {
          // Skip this result if reverse geocode fails
        }
      }

      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _results = [];
          _isSearching = false;
        });
      }
    }
  }

  String _buildTitle(Placemark place) {
    final parts = <String>[];
    if (place.subLocality != null && place.subLocality!.isNotEmpty) {
      parts.add(place.subLocality!);
    }
    if (place.locality != null && place.locality!.isNotEmpty) {
      parts.add(place.locality!);
    }
    if (parts.isEmpty && place.name != null) parts.add(place.name!);
    return parts.join(', ');
  }

  String _buildSubtitle(Placemark place) {
    final parts = <String>[];
    if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
      parts.add(place.administrativeArea!);
    }
    if (place.postalCode != null && place.postalCode!.isNotEmpty) {
      parts.add(place.postalCode!);
    }
    return parts.join(' - ');
  }

  /// User selected a search result → check service → navigate
  Future<void> _onResultSelected(_SearchResult result) async {
    setState(() => _isCheckingService = true);

    // Check service availability
    if (result.pincode.length == 6) {
      final serviceAreaProvider = Provider.of<ServiceAreaProvider>(context, listen: false);
      final isServiceable = await serviceAreaProvider.checkServiceAvailability(
        latitude: result.latitude,
        longitude: result.longitude,
        pincode: result.pincode,
        country: 'India',
      );

      if (!mounted) return;

      if (!isServiceable) {
        setState(() => _isCheckingService = false);
        // Show "we don't deliver here" dialog
        _showNotServiceableDialog(result);
        return;
      }
    }

    setState(() => _isCheckingService = false);

    if (!mounted) return;

    // Navigate to add address with pre-filled data
    context.push('/address/add', extra: {
      'city': result.city,
      'state': result.state,
      'pincode': result.pincode,
      'latitude': result.latitude.toString(),
      'longitude': result.longitude.toString(),
      'addressLine1': result.area.isNotEmpty ? result.area : result.title,
    });
  }

  void _showNotServiceableDialog(_SearchResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.location_off_rounded, color: Color(0xFFE53935), size: 20),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text("We don't deliver here yet", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: Text(
          'Easy Basket is not available in ${result.city} yet. Try a different location.',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:  Text(AppLocalizations.of(context).commonOk),
          ),
        ],
      ),
    );
  }

  /// Use current GPS location
  Future<void> _useCurrentLocation() async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);

    if (!locationProvider.isPermissionGranted) {
      final granted = await locationProvider.requestPermission();
      if (!granted) return;
    }

    await locationProvider.detectLocation();

    if (!mounted) return;

    final partial = locationProvider.detectedAddress;
    if (partial != null) {
      context.push('/address/add', extra: {
        'city': partial.city ?? '',
        'state': partial.state ?? '',
        'pincode': partial.pincode ?? '',
        'latitude': partial.latitude.toString(),
        'longitude': partial.longitude.toString(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.pop(),
        ),
        title:  Text(AppLocalizations.of(context).addressSearchTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87)),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).addressSearchYourArea,
                hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                suffixIcon: _searchController.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() {
                            _results = [];
                            _isSearching = false;
                          });
                        },
                        child: Icon(Icons.close, color: Colors.grey[400], size: 20),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          // Loading indicator
          if (_isSearching || _isCheckingService)
            const LinearProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
              backgroundColor: Color(0xFFE8F5E9),
            ),

          // Search results
          Expanded(
            child: _results.isNotEmpty
                ? ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F9F5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.location_on_rounded, color: AppTheme.primaryGreen, size: 20),
                        ),
                        title: Text(
                          result.title,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          result.subtitle,
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                        onTap: () => _onResultSelected(result),
                      );
                    },
                  )
                : _buildDefaultOptions(),
          ),
        ],
      ),
    );
  }

  /// Default options when no search results — Use Current Location + Enter Manually
  Widget _buildDefaultOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Use Current Location
          GestureDetector(
            onTap: _useCurrentLocation,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F9F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.my_location_rounded, color: AppTheme.primaryGreen, size: 20),
                  const SizedBox(width: 12),
                   Expanded(
                    child: Text(
                      AppLocalizations.of(context).locationUseCurrent,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Enter Manually
          GestureDetector(
            onTap: () => context.push('/address/add'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_rounded, color: Colors.grey[600], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).addressEnterManually,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Hint text
          Text(
            AppLocalizations.of(context).addressSearchByArea,
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Internal search result model
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
