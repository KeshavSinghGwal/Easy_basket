import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/order_provider.dart';
import '../../utils/theme.dart';

class ServiceNotAvailableScreen extends StatelessWidget {
  final String? pincode;
  final String? city;
  final String? state;
  final String? country;
  final String? returnTo; // Where to return after changing address
  final bool isOnboarding; // True if this is shown during onboarding (no addresses yet)

  const ServiceNotAvailableScreen({
    super.key,
    this.pincode,
    this.city,
    this.state,
    this.country,
    this.returnTo,
    this.isOnboarding = false,
  });

  @override
  Widget build(BuildContext context) {
    // Check if user has addresses (to determine if this is onboarding)
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final hasAddresses = orderProvider.addresses.isNotEmpty;
    final isOnboardingFlow = isOnboarding || !hasAddresses;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Not Available'),
        // During onboarding, don't show back button (user must add address)
        automaticallyImplyLeading: !isOnboardingFlow,
        leading: isOnboardingFlow
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  // Navigate back or to home
                  if (returnTo != null) {
                    context.go(returnTo!);
                  } else {
                    context.go('/home');
                  }
                },
              ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // Icon - Blinkit style with warning color
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_off_rounded,
                  size: 80,
                  color: Colors.orange.shade600,
                ),
              ),
              const SizedBox(height: 32),
              
              // Title - More prominent
              Text(
                'Oops! We don\'t deliver here yet',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.black,
                      fontSize: 24,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              
              // Location Info Card - Blinkit style
              if (pincode != null || city != null || state != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.red.shade200,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            color: Colors.red.shade600,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Selected Location',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _getLocationText(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.black,
                        ),
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 32),
              
              // Message - More friendly and clear
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    Text(
                      'We\'re currently not delivering to this location.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppTheme.black,
                            height: 1.6,
                            fontSize: 16,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Don\'t worry! We\'re expanding rapidly and will be in your area soon.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.grey,
                            height: 1.6,
                            fontSize: 14,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Primary Action Button - Add/Change Address
              SizedBox(
                width: double.infinity,
                child: AppTheme.gradientButton(
                  onPressed: () {
                    if (isOnboardingFlow) {
                      context.push('/addresses');
                    } else {
                      context.push('/addresses');
                    }
                  },
                  height: 54,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOnboardingFlow ? Icons.add_location : Icons.location_on,
                        size: 22,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isOnboardingFlow ? 'Add Serviceable Address' : 'Change Address',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Only show "Go to Home" button if user already has addresses (not onboarding)
              if (!isOnboardingFlow) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Go back to home - use go to replace current screen
                      context.go('/home');
                    },
                    icon: const Icon(Icons.home_outlined, size: 20),
                    label: const Text(
                      'Go to Home',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
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
              ],
              
              const SizedBox(height: 40),
              
              // Info Card - Blinkit style notification
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryGreen.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_outlined,
                          color: AppTheme.primaryGreen,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Want to be notified?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We\'ll notify you as soon as we start delivering to your area!',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.grey,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _getLocationText() {
    final parts = <String>[];
    if (city != null) parts.add(city!);
    if (state != null) parts.add(state!);
    if (pincode != null) parts.add(pincode!);
    return parts.join(', ');
  }
}

