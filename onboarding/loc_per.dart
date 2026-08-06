import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../utils/theme.dart';

/// Screen shown when location permission is denied during onboarding
/// Similar to Blinkit's permission explanation screen
class LocationPermissionScreen extends StatelessWidget {
  const LocationPermissionScreen({super.key});

  Future<void> _requestPermissionAgain(BuildContext context) async {
    // Open app settings to allow user to grant permission
    final status = await Permission.location.request();
    
    if (status.isGranted && context.mounted) {
      // Permission granted, go back to home (it will auto-detect)
      context.go('/home');
    } else if (status.isPermanentlyDenied && context.mounted) {
      // Permission permanently denied, open settings
      await openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              
              // Icon - Location with permission symbol
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  size: 80,
                  color: AppTheme.primaryGreen,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Title
              Text(
                'Location Access Required',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.black,
                    ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 16),
              
              // Explanation Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryGreen.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildReasonRow(
                      context,
                      Icons.delivery_dining,
                      'Instant Delivery',
                      'We need your location to provide fast 10-20 minute delivery',
                    ),
                    const SizedBox(height: 16),
                    _buildReasonRow(
                      context,
                      Icons.location_searching,
                      'Service Area Check',
                      'We check if we deliver to your area before you shop',
                    ),
                    const SizedBox(height: 16),
                    _buildReasonRow(
                      context,
                      Icons.map,
                      'Accurate Address',
                      'Auto-fill your address for faster checkout',
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Primary Action - Grant Permission
              SizedBox(
                width: double.infinity,
                child: AppTheme.gradientButton(
                  onPressed: () => _requestPermissionAgain(context),
                  height: 54,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on, size: 22, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Grant Location Permission', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Secondary Action - Add Address Manually
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/address/add'),
                  icon: const Icon(Icons.edit_location),
                  label: const Text(
                    'Add Address Manually',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryGreen,
                    side: const BorderSide(color: AppTheme.primaryGreen, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Privacy Note
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.lightGrey,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 20,
                      color: AppTheme.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your location is only used to find your delivery address. We never share it with anyone.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.grey,
                          height: 1.4,
                        ),
                      ),
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

  Widget _buildReasonRow(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 24,
            color: AppTheme.primaryGreen,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.grey,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

