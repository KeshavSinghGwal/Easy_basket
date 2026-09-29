import 'package:flutter/material.dart';

/// Promo Banner Widget — Full-width animated banner for homepage
///
/// Slides in from left with fade on first render
/// Used for launch offers, hero promos, seasonal campaigns
class PromoBannerWidget extends StatefulWidget {
  final String imagePath;
  final VoidCallback? onTap;

  const PromoBannerWidget({
    super.key,
    required this.imagePath,
    this.onTap,
  });

  @override
  State<PromoBannerWidget> createState() => _PromoBannerWidgetState();
}

class _PromoBannerWidgetState extends State<PromoBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // Slide from fully off-screen left — bike riding in feel
    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1.2, 0), // 120% off from left (fully hidden)
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart, // fast start, smooth stop — like bike braking
    ));

    // Fade in — starts after slight delay
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut), // quick fade
    ));

    // Start animation after frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: GestureDetector(
          onTap: widget.onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = constraints.maxWidth;
              // Scale height based on screen width — 100px at 360px width, scales proportionally
              final height = (screenWidth * 0.28).clamp(80.0, 140.0);
              return SizedBox(
                width: double.infinity,
                height: height,
                child: Image.asset(
                  widget.imagePath,
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
