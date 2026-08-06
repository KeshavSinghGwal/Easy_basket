import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../providers/auth_provider.dart';
import '../../providers/admin_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/proximity_provider.dart';
import '../../providers/service_area_provider.dart';
import '../../services/notification_service.dart';
import '../../utils/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isOtpSent = false;
  bool _isLoading = false;
  late AnimationController _lineAnim;

  @override
  void initState() {
    super.initState();
    _lineAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _lineAnim.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    if (_phoneController.text.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 10-digit phone number')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.sendOTP(_phoneController.text);

    setState(() => _isLoading = false);

    if (authProvider.error == null) {
      setState(() => _isOtpSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP sent successfully!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authProvider.error ?? 'Failed to send OTP')),
      );
    }
  }

  Future<void> _verifyOTP() async {
    if (_otpController.text.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter 6-digit OTP')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.verifyOTP(
      _phoneController.text,
      _otpController.text,
    );

    setState(() => _isLoading = false);

    if (success) {
      if (mounted) {
        if (!kIsWeb) {
          try {
            final authProvider = Provider.of<AuthProvider>(context, listen: false);
            final adminProvider = Provider.of<AdminProvider>(context, listen: false);
            await NotificationService().initialize(
              context: context,
              adminProvider: adminProvider,
              authProvider: authProvider,
            );
          } catch (e) {
            debugPrint('❌ [LOGIN] Error initializing notification service: $e');
          }
        }

        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final userRole = authProvider.user?.role;

        if (userRole == 'admin') {
          context.go('/admin/dashboard');
        } else if (userRole == 'delivery') {
          context.go('/delivery/dashboard');
        } else {
          // Customer login — if we were sent here by a gated route (checkout, profile, etc.),
          // honor returnTo and skip location/address re-detection. The guest cart is in
          // SharedPreferences, so it persists across the login transition automatically.
          final returnTo = GoRouterState.of(context).uri.queryParameters['returnTo'];
          if (returnTo != null && returnTo.isNotEmpty) {
            if (mounted) context.go(Uri.decodeComponent(returnTo));
          } else {
            await _handleCustomerPostLogin();
          }
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authProvider.error ?? 'Invalid OTP')),
      );
    }
  }

  /// Customer post-login flow:
  /// 1. Check if user has saved addresses
  ///    → YES: Go to home (existing user)
  ///    → NO: Check GPS permission
  ///       → Granted: Detect GPS → check service → home or "not available"
  ///       → Not asked: Show permission screen
  ///       → Denied: Go to manual address form
  Future<void> _handleCustomerPostLogin() async {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final addressProvider = Provider.of<AddressProvider>(context, listen: false);
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    final proximityProvider = Provider.of<ProximityProvider>(context, listen: false);

    // Fresh start — reset previous user's data
    locationProvider.reset();
    addressProvider.reset();
    proximityProvider.reset();

    // Step 1: Fetch saved addresses
    if (authProvider.token != null) {
      await addressProvider.fetchAddresses(authProvider.token!);
    }

    if (!mounted) return;

    // Step 2: Has saved addresses? → Still gate when permission not settled (same as splash).
    if (addressProvider.hasAddresses) {
      await locationProvider.checkPermission();
      if (!mounted) return;
      if (!locationProvider.isPermissionGranted &&
          !locationProvider.isPermissionPermanentlyDenied) {
        if (mounted) context.go('/location-gate');
        return;
      }
      if (locationProvider.isPermissionGranted) {
        await locationProvider.detectLocation(force: true);
      }
      if (mounted) context.go('/home');
      return;
    }

    // Step 3: New user — no saved addresses
    // Check GPS permission status
    await locationProvider.checkPermission();

    if (!mounted) return;

    if (locationProvider.isPermissionGranted) {
      // GPS already granted — detect location and check service
      await _detectAndCheckService(locationProvider, authProvider);
    } else if (locationProvider.isPermissionPermanentlyDenied) {
      // Permanently denied — go to address list (has search, map, manual options)
      context.go('/addresses');
    } else {
      context.go('/location-gate');
    }
  }

  /// Detect GPS location and check if serviceable
  /// If serviceable → go to home
  /// If not → show "we don't deliver here" screen
  Future<void> _detectAndCheckService(
    LocationProvider locationProvider,
    AuthProvider authProvider,
  ) async {
    // Detect GPS location
    await locationProvider.detectLocation();

    if (!mounted) return;

    final partial = locationProvider.detectedAddress;
    if (partial == null || partial.pincode == null) {
      // GPS failed to get address — go to address list
      context.go('/addresses');
      return;
    }

    // Check service availability
    final serviceAreaProvider = Provider.of<ServiceAreaProvider>(context, listen: false);
    final isServiceable = await serviceAreaProvider.checkServiceAvailability(
      pincode: partial.pincode!,
      country: 'India',
    );

    if (!mounted) return;

    if (isServiceable) {
      // Serviceable — go to home with partial address
      // Home screen will show "📍 CURRENT LOCATION - Sector 70, Mohali"
      // Full address will be asked at checkout
      context.go('/home');
    } else {
      // Not serviceable — show "we don't deliver here" screen
      context.go('/service-not-available', extra: {
        'pincode': partial.pincode,
        'city': partial.city,
        'state': partial.state,
        'country': 'India',
        'returnTo': '/home',
        'isOnboarding': true,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppTheme.primaryGreen,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Animated background on the green section
          AnimatedBuilder(
            animation: _lineAnim,
            builder: (context, _) => CustomPaint(
              painter: _BgPainter(_lineAnim.value),
              size: size,
            ),
          ),

          Column(
            children: [
              // ── Brand Section (top) ──────────────────────────────
              Expanded(
                flex: 45,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    // Scale the whole brand block down when vertical space is
                    // tight (short devices / keyboard open) so it never
                    // overflows. At normal size scaleDown renders identically.
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo circle
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.shopping_basket_rounded,
                            size: 46,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Easy Basket',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -1,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Fresh groceries at your doorstep',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.85),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Trust row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TrustBadge(icon: Icons.bolt_rounded, label: 'Fast'),
                            _dividerDot(),
                            _TrustBadge(icon: Icons.eco_rounded, label: 'Fresh'),
                            _dividerDot(),
                            _TrustBadge(icon: Icons.verified_rounded, label: 'Trusted'),
                          ],
                        ),
                      ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Form Card (bottom) ───────────────────────────────
              Expanded(
                flex: 55,
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.08),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _isOtpSent ? _OtpForm(
                        key: const ValueKey('otp'),
                        phone: _phoneController.text,
                        controller: _otpController,
                        isLoading: _isLoading,
                        onVerify: _verifyOTP,
                        onChangePhone: () => setState(() {
                          _isOtpSent = false;
                          _otpController.clear();
                        }),
                      ) : _PhoneForm(
                        key: const ValueKey('phone'),
                        controller: _phoneController,
                        isLoading: _isLoading,
                        onSend: _sendOTP,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dividerDot() => Container(
        width: 4,
        height: 4,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
      );
}

// ─── Phone form ──────────────────────────────────────────────────────────────

class _PhoneForm extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSend;

  const _PhoneForm({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Login / Sign up',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A1A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'We\'ll send a one-time password to verify',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 28),

        // Phone field
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF6F7F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8E8E8)),
          ),
          child: Row(
            children: [
              // +91 prefix box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Color(0xFFE8E8E8)),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      '🇮🇳',
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '+91',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              // Number input
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  enabled: !isLoading,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter your phone number',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey.shade400,
                      letterSpacing: 0,
                    ),
                    border: InputBorder.none,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Send OTP button
        _GreenButton(
          label: 'Send OTP',
          isLoading: isLoading,
          onPressed: onSend,
        ),

        const SizedBox(height: 24),
        Center(
          child: Text(
            'By continuing, you agree to our Terms of Service\nand Privacy Policy',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ─── OTP form ────────────────────────────────────────────────────────────────

class _OtpForm extends StatelessWidget {
  final String phone;
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onVerify;
  final VoidCallback onChangePhone;

  const _OtpForm({
    super.key,
    required this.phone,
    required this.controller,
    required this.isLoading,
    required this.onVerify,
    required this.onChangePhone,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Verify OTP',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A1A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            children: [
              const TextSpan(text: 'OTP sent to '),
              TextSpan(
                text: '+91 $phone',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // OTP field
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF6F7F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8E8E8)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 10,
              color: AppTheme.primaryGreen,
            ),
            decoration: InputDecoration(
              hintText: '------',
              hintStyle: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w400,
                letterSpacing: 10,
                color: Colors.grey.shade300,
              ),
              border: InputBorder.none,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            ),
          ),
        ),
        const SizedBox(height: 24),

        _GreenButton(
          label: 'Verify & Continue',
          isLoading: isLoading,
          onPressed: onVerify,
        ),

        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: onChangePhone,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryGreen,
            ),
            child: const Text(
              'Change phone number',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Gradient green button ───────────────────────────────────────────────────

class _GreenButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  const _GreenButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isLoading ? null : AppTheme.primaryGradient,
          color: isLoading ? Colors.grey.shade200 : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isLoading
              ? []
              : [
                  BoxShadow(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─── Trust badge ─────────────────────────────────────────────────────────────

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.9)),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

// ─── Animated background painter ─────────────────────────────────────────────

class _BgPainter extends CustomPainter {
  final double animValue;

  _BgPainter(this.animValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // Sweeping diagonal lines across the green top section
    final offset = (animValue * 60.0) % 60.0;
    for (int i = -3; i < 14; i++) {
      final x = i * 60.0 + offset;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height * 0.5, size.height * 0.5),
        paint,
      );
    }

    // Radiating arcs from top-right
    final arcPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (int i = 1; i <= 6; i++) {
      final radius = 40.0 + i * 45.0 + math.sin(animValue * 2 * math.pi) * 10;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(size.width, 0), radius: radius),
        math.pi * 0.5,
        math.pi * 0.5,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BgPainter oldDelegate) =>
      oldDelegate.animValue != animValue;
}
