import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../models/campaign_model.dart';
import '../utils/theme.dart';

/// Hero Banner Carousel — auto-sliding promo banners on homepage
/// Shows campaigns with placement = hero_banner
class HeroBannerCarousel extends StatefulWidget {
  final List<CampaignModel> banners;

  const HeroBannerCarousel({super.key, required this.banners});

  @override
  State<HeroBannerCarousel> createState() => _HeroBannerCarouselState();
}

class _HeroBannerCarouselState extends State<HeroBannerCarousel> {
  final PageController _pageController = PageController();
  Timer? _autoSlideTimer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    if (widget.banners.length > 1) {
      _autoSlideTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        _currentPage = (_currentPage + 1) % widget.banners.length;
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        // Banner carousel
        SizedBox(
          height: 160,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.banners.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final banner = widget.banners[index];
              return _buildBannerCard(banner);
            },
          ),
        ),

        // Dots indicator
        if (widget.banners.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.banners.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _currentPage ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _currentPage ? AppTheme.primaryGreen : Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildBannerCard(CampaignModel banner) {
    final image = (banner.imageUrl != null && banner.imageUrl!.isNotEmpty)
        ? CachedNetworkImage(
            imageUrl: banner.imageUrl!,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            placeholder: (_, __) => Image.asset('assets/images/promo_boy.png', fit: BoxFit.contain),
            errorWidget: (_, __, ___) => Image.asset('assets/images/promo_boy.png', fit: BoxFit.contain),
          )
        : Image.asset('assets/images/promo_boy.png', fit: BoxFit.contain);

    return GestureDetector(
      onTap: () {
        if (banner.ctaLink != null && banner.ctaLink!.isNotEmpty) {
          context.push(banner.ctaLink!);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(left: 14, right: 14, top: 50),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Background card — gradient
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFCCE8C5), Color(0xFFDBF0D4), Color(0xFFEDF7E8), Color(0xFFF6FBF4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: [0.0, 0.3, 0.65, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),

            // Shop Now — bottom right, below the image
            Positioned(
              right: 12,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  banner.ctaText ?? 'Shop Now',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),

            // Image — right side, overflows top, flush bottom, large
            Positioned(
              right: -80,
              bottom: 0,
              top: -80,
              width: 320,
              child: image,
            ),

            // Text — left side
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 0, 14),
                child: FractionallySizedBox(
                  widthFactor: 0.55,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        banner.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1B5E20),
                          fontStyle: FontStyle.italic,
                          height: 1.15,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (banner.subtitle != null && banner.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          banner.subtitle!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2E7D32),
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
