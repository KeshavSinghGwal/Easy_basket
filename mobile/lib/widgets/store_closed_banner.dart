import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/store_status_model.dart';
import '../l10n/app_localizations.dart';

/// Full-width "store is closed" panel for the top of the home screen.
///
/// Deliberately NOT dismissible: if a user could swipe this away they'd hit a
/// dead Place Order button later with no explanation of why. It stays put, but
/// it's sized to leave the rest of home visible and scrollable — browsing is
/// still very much encouraged while we're shut.
class StoreClosedBanner extends StatelessWidget {
  const StoreClosedBanner({super.key, required this.status});

  final StoreStatusModel status;

  @override
  Widget build(BuildContext context) {
    if (status.isOpen) return const SizedBox.shrink();

    final reason = status.reason;
    final reopenText = _formatReopen(status.expectedReopenAt);

    return Semantics(
      liveRegion: true,
      label: 'Store closed. ${status.headline}. '
          '${reopenText ?? "We will reopen soon."} '
          'You can still browse products.',
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: reason.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: reason.gradient.last.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Reason-specific motion sits behind the text.
            Positioned.fill(child: _ClosedBannerAnimation(reason: reason)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(reason.icon, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child:  Text(
                          AppLocalizations.of(context).storeClosedCaps,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    status.headline,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status.subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (reopenText != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              reopenText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim inline version for the cart and checkout screens, where the full hero
/// panel would push the price summary off-screen.
class StoreClosedBar extends StatelessWidget {
  const StoreClosedBar({super.key, required this.status, this.margin});

  final StoreStatusModel status;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    if (status.isOpen) return const SizedBox.shrink();

    final reason = status.reason;
    final reopenText = _formatReopen(status.expectedReopenAt);

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: reason.gradient,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(reason.icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.headline,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reopenText ?? "You can't place orders until we reopen",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.9),
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

/// "Reopening around 6:00 PM" / "…tomorrow 9:00 AM" / "…on 3 Aug, 9:00 AM".
///
/// Returns null when no ETA was set, so callers can hide the chip entirely
/// rather than print a hollow "reopening soon" twice.
String? _formatReopen(DateTime? at) {
  if (at == null) return null;

  final now = DateTime.now();
  // Already past: the admin set a time and didn't reopen. Never claim a time
  // that has come and gone — the store only reopens by admin action.
  if (!at.isAfter(now)) return 'Reopening shortly';

  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(at.year, at.month, at.day);
  final daysAway = thatDay.difference(today).inDays;
  final time = DateFormat('h:mm a').format(at);

  if (daysAway == 0) return 'Reopening around $time';
  if (daysAway == 1) return 'Reopening tomorrow at $time';
  return 'Reopening ${DateFormat('d MMM').format(at)} at $time';
}

// ---------------------------------------------------------------------------
// Animation layer
// ---------------------------------------------------------------------------

/// Picks the motion for a reason. Rain gets real falling drops; every other
/// reason gets a slow drifting glow, which reads as "alive" without needing a
/// bespoke animation per enum value.
class _ClosedBannerAnimation extends StatefulWidget {
  const _ClosedBannerAnimation({required this.reason});

  final StoreClosedReason reason;

  @override
  State<_ClosedBannerAnimation> createState() => _ClosedBannerAnimationState();
}

class _ClosedBannerAnimationState extends State<_ClosedBannerAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.reason == StoreClosedReason.rain
          ? const Duration(milliseconds: 1400)
          : const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour the OS "reduce motion" setting — some users get motion sickness
    // from continuous animation, and this banner never stops on its own.
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final painter = widget.reason == StoreClosedReason.rain
        ? _RainPainter(progress: reduceMotion ? 0.35 : 0)
        : _GlowPainter(progress: 0, color: Colors.white);

    if (reduceMotion) {
      // Paint one frozen frame: the texture still communicates "rain" without
      // anything moving. Stop the ticker too — left repeating it would wake the
      // vsync callback every frame forever to drive nothing.
      if (_controller.isAnimating) _controller.stop();
      return IgnorePointer(child: CustomPaint(painter: painter));
    }

    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: widget.reason == StoreClosedReason.rain
                  ? _RainPainter(progress: _controller.value)
                  : _GlowPainter(progress: _controller.value, color: Colors.white),
            );
          },
        ),
      ),
    );
  }
}

/// Falling rain, drawn as slanted translucent streaks.
///
/// Built with a CustomPainter rather than a Lottie asset: no new dependency, no
/// asset to license, a few KB of code, and it renders identically on Flutter
/// web. Drop positions come from a seeded PRNG so the layout is stable across
/// rebuilds — a fresh Random() each frame would make the rain jitter sideways.
class _RainPainter extends CustomPainter {
  _RainPainter({required this.progress});

  /// 0→1, wraps continuously.
  final double progress;

  static const int _dropCount = 45;

  /// Fixed seed → identical layout every frame; only `progress` moves.
  static final List<_Drop> _drops = _generateDrops();

  static List<_Drop> _generateDrops() {
    final rng = math.Random(42);
    return List.generate(_dropCount, (_) {
      return _Drop(
        x: rng.nextDouble(),
        // Stagger start offsets so drops don't fall in visible ranks.
        phase: rng.nextDouble(),
        length: 8 + rng.nextDouble() * 14,
        speed: 0.7 + rng.nextDouble() * 0.6,
        opacity: 0.15 + rng.nextDouble() * 0.35,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4;

    // Slight slant so it reads as wind-driven rain rather than falling pins.
    const slant = 6.0;

    for (final drop in _drops) {
      // Each drop cycles independently; `% 1.0` wraps it back to the top.
      final t = (progress * drop.speed + drop.phase) % 1.0;

      // Travel beyond the bounds at both ends so drops enter and exit cleanly
      // instead of popping into existence at the edges.
      final y = t * (size.height + drop.length * 2) - drop.length;
      final x = drop.x * size.width;

      paint.color = Colors.white.withValues(alpha: drop.opacity);
      canvas.drawLine(
        Offset(x, y),
        Offset(x - slant, y + drop.length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RainPainter oldDelegate) => oldDelegate.progress != progress;
}

class _Drop {
  const _Drop({
    required this.x,
    required this.phase,
    required this.length,
    required this.speed,
    required this.opacity,
  });

  /// Horizontal position as a 0→1 fraction of width, so it survives resizes.
  final double x;
  final double phase;
  final double length;
  final double speed;
  final double opacity;
}

/// Soft drifting highlights for non-rain reasons — subtle enough to sit behind
/// text without hurting contrast.
class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final angle = progress * 2 * math.pi;

    for (var i = 0; i < 3; i++) {
      final offset = angle + (i * 2 * math.pi / 3);
      final cx = size.width * (0.5 + 0.34 * math.cos(offset));
      final cy = size.height * (0.5 + 0.42 * math.sin(offset * 0.7));
      final radius = size.height * (0.34 + 0.08 * math.sin(offset));

      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..color = color.withValues(alpha: 0.06)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
      );
    }
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => oldDelegate.progress != progress;
}
