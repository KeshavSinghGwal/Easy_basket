import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/proximity_provider.dart';
import '../../services/notification_service.dart';
import '../../utils/theme.dart';
import '../../providers/language_provider.dart';
import '../../generated/app_localizations.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final orderProvider = Provider.of<OrderProvider>(context);
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.white),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Header ──
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: topPadding + kToolbarHeight + 8,
                bottom: 28,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  // Avatar
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 33,
                      backgroundColor: AppTheme.primaryGreen.withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 36,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Name
                  Text(
                    authProvider.user?.name ?? 'Customer',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Phone
                  Text(
                    authProvider.user?.phoneNumber ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Stats Card ──
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _buildStatItem(
                    Icons.shopping_bag_rounded,
                    'Orders',
                    '${orderProvider.orders.length}',
                    const Color(0xFFE8F5E9),
                    AppTheme.primaryGreen,
                  ),
                  Container(width: 1, height: 36, color: const Color(0xFFF0F0F0)),
                  _buildStatItem(
                    Icons.location_on_rounded,
                    'Addresses',
                    '${orderProvider.addresses.length}',
                    const Color(0xFFE3F2FD),
                    Colors.blue,
                  ),
                  Container(width: 1, height: 36, color: const Color(0xFFF0F0F0)),
                  _buildStatItem(
                    Icons.star_rounded,
                    'Rating',
                    '4.8',
                    const Color(0xFFFFF3E0),
                    Colors.orange,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Account Section ──
            _buildSectionLabel('Account'),
            const SizedBox(height: 8),
            _buildTile(
              context,
              icon: Icons.person_outline_rounded,
              title: 'Edit Profile',
              bgColor: const Color(0xFFE8F5E9),
              iconColor: AppTheme.primaryGreen,
              onTap: () => context.push('/profile/edit'),
            ),
            _buildTile(
              context,
              icon: Icons.shopping_bag_outlined,
              title: 'My Orders',
              bgColor: const Color(0xFFF3E5F5),
              iconColor: Colors.purple,
              onTap: () => context.push('/orders'),
            ),
            _buildTile(
              context,
              icon: Icons.location_on_outlined,
              title: 'My Addresses',
              bgColor: const Color(0xFFE3F2FD),
              iconColor: Colors.blue,
              onTap: () => context.push('/addresses'),
            ),

            const SizedBox(height: 20),

            // ── Preferences Section ──
            _buildSectionLabel('Preferences'),
            const SizedBox(height: 8),
            _buildTile(
              context,
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              bgColor: const Color(0xFFFFF3E0),
              iconColor: Colors.orange,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notifications coming soon')),
                );
              },
            ),
            _buildTile(
  context,
  icon: Icons.language_outlined,
  title: 'Language',
  bgColor: const Color(0xFFE0F2F1),
  iconColor: Colors.teal,
  onTap: () {
    _showLanguageDialog(context);
  },
),

            const SizedBox(height: 20),

            // ── Support Section ──
            _buildSectionLabel('Support'),
            const SizedBox(height: 8),
            _buildTile(
              context,
              icon: Icons.help_outline_rounded,
              title: 'Help & Support',
              bgColor: const Color(0xFFE8EAF6),
              iconColor: Colors.indigo,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Help & Support coming soon')),
                );
              },
            ),
            _buildTile(
              context,
              icon: Icons.info_outline_rounded,
              title: 'About',
              bgColor: const Color(0xFFF5F5F5),
              iconColor: AppTheme.grey,
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Text('About Easy Basket'),
                    content: const Text(
                      'Easy Basket - Instant Grocery Delivery\n\nVersion ${AppConfig.appVersion}\n\nYour trusted partner for quick grocery delivery.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // ── Logout Button ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: const Text(
                          'Logout',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        content: const Text('Are you sure you want to logout?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Logout'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      // Reset all providers + unsubscribe notification topic
                      Provider.of<LocationProvider>(context, listen: false).reset();
                      Provider.of<AddressProvider>(context, listen: false).reset();
                      Provider.of<ProximityProvider>(context, listen: false).reset();
                      NotificationService().unsubscribeCurrentTopic();
                      await authProvider.logout();
                      if (context.mounted) context.go('/login');
                    }
                  },
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: const Text(
                    'Logout',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── App Version ──
            Text(
              'v${AppConfig.appVersion}',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.grey.withValues(alpha: 0.6),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──
  void _showLanguageDialog(BuildContext context) {
  final languageProvider =
      Provider.of<LanguageProvider>(context, listen: false);

  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            const SizedBox(height: 15),

            const Text(
              "Choose Language",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            ListTile(
              leading: const Text(
                "🇬🇧",
                style: TextStyle(fontSize: 24),
              ),
              title: const Text("English"),
              onTap: () async {
                await languageProvider.changeLanguage("en");

                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
            ),

            ListTile(
              leading: const Text(
                "🇮🇳",
                style: TextStyle(fontSize: 24),
              ),
              title: const Text("हिन्दी"),
              onTap: () async {
                await languageProvider.changeLanguage("hi");

                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
            ),

            ListTile(
              leading: const Text(
                "🇮🇳",
                style: TextStyle(fontSize: 24),
              ),
              title: const Text("ਪੰਜਾਬੀ"),
              onTap: () async {
                await languageProvider.changeLanguage("pa");

                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
            ),

            const SizedBox(height: 20),
          ],
        ),
      );
    },
  );
}

  Widget _buildStatItem(
    IconData icon,
    String label,
    String value,
    Color bgColor,
    Color iconColor,
  ) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.black,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.grey.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.grey.withValues(alpha: 0.8),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            splashColor: iconColor.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.black,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.grey.withValues(alpha: 0.4),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
