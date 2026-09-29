import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../utils/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNext();
  }

  /// Do not use a long fixed delay + go(home): it races FCM cold-start deep links and
  /// replaces the stack, so users land on home instead of order detail.
  /// Blinkit-style: location is resolved BEFORE login. Guests can browse;
  /// login is only required at checkout / for profile / orders / addresses.
  /// Admin & delivery roles still go through login (handled by /login screen).
  void _navigateToNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 120), () async {
        if (!mounted) return;

        final path = GoRouterState.of(context).uri.path;
        if (path != '/splash') {
          return;
        }

        final auth = Provider.of<AuthProvider>(context, listen: false);

        // Admin / delivery: skip location flow, go to their dashboards.
        if (auth.isAuthenticated) {
          final role = auth.user?.role;
          if (role == 'admin') {
            context.go('/admin/dashboard');
            return;
          }
          if (role == 'delivery') {
            context.go('/delivery/dashboard');
            return;
          }
        }

        // Customer + guest: location-first.
        final loc = Provider.of<LocationProvider>(context, listen: false);
        await loc.checkPermission();
        if (!mounted) return;

        if (!loc.isPermissionGranted && !loc.isPermissionPermanentlyDenied) {
          context.go('/location-gate');
        } else {
          context.go('/home');
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryGreen,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.shopping_basket,
                size: 80,
                color: AppTheme.primaryGreen,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Easy Basket',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppTheme.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Instant Grocery Delivery',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

