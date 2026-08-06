import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../providers/location_provider.dart';
import '../../providers/service_area_provider.dart';
import '../../utils/theme.dart';

/// Location Permission Screen — Premium onboarding with skeleton loading
///
/// Flow:
/// 1. Show permission screen (illustration + CTA)
/// 2. User taps "Allow location access"
/// 3. CrossFade to skeleton loading (simulates home screen)
/// 4. GPS detects → navigate to real home screen
/// 5. Error → show error + allow retry
class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() => _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen>
    with WidgetsBindingObserver {
  bool _isLoadingLocation = false;
  /// True while waiting on system permission / [LocationProvider.requestPermission] — avoids double-tap and shows inline progress.
  bool _isRequestingPermission = false;
  /// True after we send the user to system location settings because their GPS
  /// toggle is off — so when the app resumes we can auto-retry detection.
  bool _awaitingLocationEnable = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When the user returns from the system location settings, re-check the GPS
  /// toggle. If it's now on, auto-retry the whole allow flow so they don't have
  /// to tap "Allow location" a second time.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingLocationEnable) {
      _awaitingLocationEnable = false;
      _retryAfterLocationEnabled();
    }
  }

  Future<void> _retryAfterLocationEnabled() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted || !enabled) return;
    _handleAllowLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isLoadingLocation ? const Color(0xFFF4F8F3) : const Color(0xFFEEF7F0),
      body: AnimatedCrossFade(
        duration: const Duration(milliseconds: 400),
        crossFadeState: _isLoadingLocation ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        firstChild: _buildPermissionScreen(),
        secondChild: _buildSkeletonScreen(),
        layoutBuilder: (topChild, topChildKey, bottomChild, bottomChildKey) {
          return Stack(
            children: [
              Positioned.fill(key: bottomChildKey, child: bottomChild),
              Positioned.fill(key: topChildKey, child: topChild),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════
  // SCREEN 1: Permission UI
  // ═══════════════════════════════════════

  Widget _buildPermissionScreen() {
    final size = MediaQuery.of(context).size;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        // Ambient background — soft vertical wash + bottom wave
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFF3FBF4),
                  const Color(0xFFE8F5E9).withValues(alpha: 0.65),
                  const Color(0xFFFAFDFA),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: ClipPath(
            clipper: _BottomWaveClipper(),
            child: Container(
              height: size.height * 0.22,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFC8E6C9).withValues(alpha: 0.35),
                    const Color(0xFFE8F5E9).withValues(alpha: 0.2),
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
          ),
        ),

        SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final shortScreen = constraints.maxHeight < 560;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: _buildBrandingHeader(),
                  ),
                  // Hero fills this region; sheet is bottom-aligned → no floating art + huge gap
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, right: 4, top: 2),
                            child: _LocationHeroIllustration(
                              viewportHeight: constraints.maxHeight,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0D4F14).withValues(alpha: 0.06),
                                  blurRadius: 22,
                                  offset: const Offset(0, -8),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, -2),
                                ),
                              ],
                            ),
                            child: SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(22, 18, 22, bottomPad + 18),
                              physics: shortScreen
                                  ? const BouncingScrollPhysics()
                                  : const NeverScrollableScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Allow location for delivery',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.4,
                                      color: AppTheme.primaryGreen,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Groceries, delivered fast',
                                    style: GoogleFonts.poppins(
                                      fontSize: (size.width * 0.078).clamp(26.0, 34.0),
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF142118),
                                      letterSpacing: -0.8,
                                      height: 1.1,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Share your location once so we can find your area, show accurate prices, and deliver to the right address.',
                                    style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      color: const Color(0xFF546E7A),
                                      height: 1.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'You can change this anytime in settings.',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF90A4AE),
                                      height: 1.35,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (_errorMessage != null) ...[
                                    const SizedBox(height: 14),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.07),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.error_outline_rounded, color: Color(0xFFC62828), size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _errorMessage!,
                                              style: GoogleFonts.poppins(
                                                fontSize: 13,
                                                color: const Color(0xFFB71C1C),
                                                fontWeight: FontWeight.w500,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  SizedBox(height: shortScreen ? 16 : 20),
                                  _buildPrimaryCTA(),
                                  const SizedBox(height: 6),
                                  Center(
                                    child: TextButton(
                                      onPressed: () => context.push('/addresses'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(0xFF37474F),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      ),
                                      child: Text(
                                        'Enter address manually instead',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                          decorationColor: const Color(0xFF90A4AE),
                                          decorationThickness: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBrandingHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryGreen.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset('assets/icons/app_icon.png', fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Easy Basket',
          style: GoogleFonts.poppins(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1B5E20),
            letterSpacing: -0.6,
            height: 1.05,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Fresh groceries in minutes',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF78909C),
            height: 1.25,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPrimaryCTA() {
    final blocked = _isLoadingLocation || _isRequestingPermission;
    return Opacity(
      opacity: blocked ? 0.92 : 1,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.greenGlow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: blocked ? null : _handleAllowLocation,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isRequestingPermission)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(Icons.my_location_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Allow location access',
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // SCREEN 2: Skeleton Loading (simulates home screen)
  // ═══════════════════════════════════════

  Widget _buildSkeletonScreen() {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header skeleton (staggered — appears first) ───
            _shimmerWrap(
              period: 800,
              child: _skeletonHeader(),
            ),
            const SizedBox(height: 16),

            // ─── Search bar skeleton ───
            _shimmerWrap(
              period: 900,
              child: _skeletonBox(height: 48, radius: 14),
            ),
            const SizedBox(height: 20),

            // ─── "Detecting location" — REAL indicator (no shimmer) ───
            const _DetectingLocationIndicator(),
            const SizedBox(height: 20),

            // ─── Category chips skeleton (staggered — appears after header) ───
            _shimmerWrap(
              period: 1000,
              child: _skeletonCategoryChips(),
            ),
            const SizedBox(height: 22),

            // ─── Section title ───
            _shimmerWrap(
              period: 1100,
              child: _skeletonBox(width: 140, height: 18, radius: 6),
            ),
            const SizedBox(height: 14),

            // ─── Product grid (staggered — appears last) ───
            _shimmerWrap(
              period: 1200,
              child: _skeletonProductGrid(),
            ),
            const SizedBox(height: 22),

            _shimmerWrap(
              period: 1100,
              child: _skeletonBox(width: 120, height: 18, radius: 6),
            ),
            const SizedBox(height: 14),

            _shimmerWrap(
              period: 1300,
              child: _skeletonProductGrid(),
            ),
          ],
        ),
      ),
    );
  }

  /// Wrap a widget in its own Shimmer with custom period (staggered effect)
  Widget _shimmerWrap({required int period, required Widget child}) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE8E8E8),
      highlightColor: const Color(0xFFF8F8F8),
      period: Duration(milliseconds: period),
      child: child,
    );
  }

  /// Header — brand row + address bar
  Widget _skeletonHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: [
          Row(
            children: [
              _skeletonBox(width: 40, height: 40, radius: 12),
              const SizedBox(width: 10),
              _skeletonBox(width: 120, height: 20, radius: 6),
              const Spacer(),
              _skeletonCircle(36),
            ],
          ),
          const SizedBox(height: 14),
          _skeletonBox(height: 42, radius: 12),
        ],
      ),
    );
  }

  /// Category chips — horizontal row
  Widget _skeletonCategoryChips() {
    return SizedBox(
      height: 100,
      child: Row(
        children: List.generate(4, (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 3 ? 10 : 0),
            child: Column(
              children: [
                _skeletonBox(width: 60, height: 60, radius: 16),
                const SizedBox(height: 8),
                _skeletonBox(width: 50, height: 10, radius: 4),
              ],
            ),
          ),
        )),
      ),
    );
  }

  /// Product grid — 2 cards side by side
  Widget _skeletonProductGrid() {
    return Row(
      children: [
        Expanded(child: _skeletonProductCard()),
        const SizedBox(width: 12),
        Expanded(child: _skeletonProductCard()),
      ],
    );
  }

  /// Single product card skeleton
  Widget _skeletonProductCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _skeletonBox(height: 100, radius: 14),
          const SizedBox(height: 10),
          _skeletonBox(width: double.infinity, height: 12, radius: 4),
          const SizedBox(height: 6),
          _skeletonBox(width: 80, height: 10, radius: 4),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _skeletonBox(width: 50, height: 16, radius: 4),
              _skeletonBox(width: 56, height: 28, radius: 8),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Skeleton primitives ───

  Widget _skeletonBox({double? width, double height = 20, double radius = 8}) {
    return Container(
      width: width, height: height,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
    );
  }

  Widget _skeletonCircle(double size) {
    return Container(width: size, height: size, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle));
  }

  // ═══════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════

  Future<void> _handleAllowLocation() async {
    if (_isRequestingPermission || _isLoadingLocation) return;

    final locationProvider = Provider.of<LocationProvider>(context, listen: false);

    // Immediate feedback — work is async (no UI "freeze"), but button state shows we're handling the tap.
    setState(() {
      _errorMessage = null;
      _isRequestingPermission = true;
    });

    // Request permission — system dialog; awaits yield to the event loop (frames + animations keep running).
    final granted = await locationProvider.requestPermission();
    if (!mounted) return;

    if (!granted) {
      // Distinguish three failure modes so the user gets actionable guidance:
      //   1. OS-level location toggle is OFF        → "Turn on Location" + open device location settings
      //   2. Permission permanently denied          → open app settings (one-time grant won't work)
      //   3. Plain denied (or transient plugin)     → user can re-tap "Allow"
      final serviceOff = !(await Geolocator.isLocationServiceEnabled());
      if (!mounted) return;

      setState(() {
        _isRequestingPermission = false;
        if (serviceOff) {
          _errorMessage = 'Location is OFF on your phone. Turn it on to continue.';
        } else if (locationProvider.isPermissionPermanentlyDenied) {
          _errorMessage = 'Location permanently denied. Tap to open Settings.';
        } else {
          _errorMessage = 'Location permission is needed for delivery';
        }
      });

      if (serviceOff && mounted) {
        // Device GPS toggle is off — block with a dialog and send them to turn
        // it on. On return, [didChangeAppLifecycleState] auto-retries detection.
        await _showLocationOffDialog(locationProvider);
      } else if (locationProvider.isPermissionPermanentlyDenied && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please enable location in phone Settings'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'Open Settings',
              textColor: Colors.white,
              onPressed: () => locationProvider.openAppSettings(),
            ),
          ),
        );
      }
      return;
    }

    // Permission granted — skeleton + detecting copy while GPS / geocode runs (typically 2–4s).
    setState(() {
      _isRequestingPermission = false;
      _isLoadingLocation = true;
    });

    await locationProvider.detectLocation(force: true);

    if (!mounted) return;

    final partial = locationProvider.detectedAddress;
    final hasUsableLocation =
        partial != null || locationProvider.currentPosition != null;

    if (!hasUsableLocation) {
      // Detection failed — show error, allow retry
      setState(() {
        _isLoadingLocation = false;
        _isRequestingPermission = false;
        _errorMessage = 'Could not detect location. Please try again.';
      });
      return;
    }

    // Pincode-based serviceability check so unserviceable users don't land on /home
    // and only later discover "we don't deliver here" at checkout.
    if (partial?.pincode != null) {
      final serviceAreaProvider =
          Provider.of<ServiceAreaProvider>(context, listen: false);
      final isServiceable = await serviceAreaProvider.checkServiceAvailability(
        pincode: partial!.pincode!,
        country: 'India',
      );

      if (!mounted) return;

      if (!isServiceable) {
        context.go('/service-not-available', extra: {
          'pincode': partial.pincode,
          'city': partial.city,
          'state': partial.state,
          'country': 'India',
          'returnTo': '/home',
          'isOnboarding': true,
        });
        return;
      }
    }

    context.go('/home');
  }

  /// Blocking dialog shown when the phone's location (GPS) toggle is off.
  /// Not dismissible by tapping outside — the user must either turn location on
  /// or explicitly choose "Not now". "Turn on Location" opens system location
  /// settings; [didChangeAppLifecycleState] retries detection when they return.
  Future<void> _showLocationOffDialog(LocationProvider locationProvider) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: AppTheme.primaryGreen,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Location is off',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: const Text(
          "Turn on your phone's location to detect your delivery area. "
          'You can browse without it, but we need it to check if we deliver to you.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: TextButton.styleFrom(foregroundColor: AppTheme.grey),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // Flag so the app auto-retries detection when we come back.
              _awaitingLocationEnable = true;
              locationProvider.openLocationSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Turn on Location'),
          ),
        ],
      ),
    );
  }
}

/// Hero illustration: bottom-aligned + scaled so art meets the action sheet with little dead air.
class _LocationHeroIllustration extends StatelessWidget {
  const _LocationHeroIllustration({this.viewportHeight});

  /// Total screen body height — used to size the bloom vs small [Expanded] slots.
  final double? viewportHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final vh = viewportHeight ?? h;
        final bloomDiameter = (w * 1.35).clamp(280.0, vh * 0.72);

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              bottom: -h * 0.06,
              child: OverflowBox(
                maxWidth: bloomDiameter,
                maxHeight: bloomDiameter,
                alignment: Alignment.center,
                child: Container(
                  width: bloomDiameter,
                  height: bloomDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF66BB6A).withValues(alpha: 0.26),
                        const Color(0xFF81C784).withValues(alpha: 0.12),
                        const Color(0xFFA5D6A7).withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.4, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Transform.scale(
              scale: 1.22,
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(left: w * 0.01, right: w * 0.01, bottom: 4),
                child: Image.asset(
                  'assets/images/delivery.png',
                  fit: BoxFit.contain,
                  width: w * 1.2,
                  height: h * 0.94,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Custom wave clipper for bottom decoration
/// Animated "Detecting your location..." indicator with pulsing dots
class _DetectingLocationIndicator extends StatefulWidget {
  const _DetectingLocationIndicator();

  @override
  State<_DetectingLocationIndicator> createState() => _DetectingLocationIndicatorState();
}

class _DetectingLocationIndicatorState extends State<_DetectingLocationIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _dotCount = 1;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() => _dotCount = (_dotCount % 3) + 1);
          _controller.forward(from: 0);
        }
      });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * _dotCount;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppTheme.primaryGreen),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Detecting your location$dots',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.45);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.15, size.width * 0.5, size.height * 0.35);
    path.quadraticBezierTo(size.width * 0.75, size.height * 0.55, size.width, size.height * 0.25);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
