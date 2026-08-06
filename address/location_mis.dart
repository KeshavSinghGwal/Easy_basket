import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/proximity_provider.dart';
import '../../providers/address_provider.dart';
import '../../utils/theme.dart';

/// Location Mismatch Screen
///
/// Shows when: User is >20km from all saved addresses (different city)
/// Example: User in Mohali, saved address in Bareilly (500km away)
///
/// UI: Map illustration with two pins
///     "You're in a different city!"
///     Current: Mohali, Punjab
///     Saved: Bareilly, UP (500km away)
///     [Add New Address] green button
///     [Use Saved Address Anyway] outlined button
class LocationMismatchScreen extends StatelessWidget {
  const LocationMismatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final proximityProvider = Provider.of<ProximityProvider>(context);
    final addressProvider = Provider.of<AddressProvider>(context);

    final result = proximityProvider.result;
    final partial = result?.partialAddress;
    final nearest = result?.nearestAddress;
    final distanceKm = result?.distanceKm;

    // Current location text
    final currentCity = partial?.city ?? 'Unknown';
    final currentState = partial?.state ?? '';
    final currentText = currentState.isNotEmpty ? '$currentCity, $currentState' : currentCity;

    // Saved address text
    final savedCity = nearest?.city ?? 'Unknown';
    final savedState = nearest?.state ?? '';
    final savedText = savedState.isNotEmpty ? '$savedCity, $savedState' : savedCity;
    final distanceText = distanceKm != null ? '(${distanceKm.toStringAsFixed(0)}km away)' : '';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Map illustration with two pins
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F9F5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Dotted line between two pins (simulated)
                    Positioned(
                      top: 80,
                      left: 60,
                      right: 60,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                              width: 2,
                              style: BorderStyle.solid,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Left pin — Current location
                    Positioned(
                      left: 40,
                      top: 40,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currentCity,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            currentState,
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    // Car/travel icon in middle
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(Icons.directions_car_rounded, color: Colors.grey[600], size: 20),
                    ),
                    // Right pin — Saved address
                    Positioned(
                      right: 40,
                      top: 40,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE53935).withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            savedCity,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '$savedState $distanceText',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 1),

              // Title
              const Text(
                "You're in a different city!",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Current location row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.my_location_rounded, color: AppTheme.primaryGreen, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Current: $currentText',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Saved address row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_rounded, color: Color(0xFFE53935), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Saved: $savedText $distanceText',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const Spacer(flex: 2),

              // Add New Address Button — green gradient
              SizedBox(
                width: double.infinity,
                height: 50,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        // Go to add address with GPS pre-fill
                        final extra = <String, dynamic>{};
                        if (partial != null) {
                          extra['city'] = partial.city ?? '';
                          extra['state'] = partial.state ?? '';
                          extra['pincode'] = partial.pincode ?? '';
                          extra['latitude'] = partial.latitude.toString();
                          extra['longitude'] = partial.longitude.toString();
                        }
                        context.push('/address/add', extra: extra);
                      },
                      child: const Center(
                        child: Text(
                          'Add New Address',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Use Saved Address Anyway — outlined button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () {
                    // Use saved address — dismiss mismatch
                    if (nearest != null) {
                      addressProvider.selectAddress(nearest);
                    }
                    proximityProvider.dismissWarning();
                    context.go('/home');
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    'Use Saved Address Anyway',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                  ),
                ),
              ),

              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
