import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../services/notification_service.dart';
import '../../core/session.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/theme.dart';

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
                    authProvider.user?.name ?? AppLocalizations.of(context).profileCustomer,
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
                    AppLocalizations.of(context).profileOrders,
                    '${orderProvider.orders.length}',
                    const Color(0xFFE8F5E9),
                    AppTheme.primaryGreen,
                  ),
                  Container(width: 1, height: 36, color: const Color(0xFFF0F0F0)),
                  _buildStatItem(
                    Icons.location_on_rounded,
                    AppLocalizations.of(context).profileAddresses,
                    '${orderProvider.addresses.length}',
                    const Color(0xFFE3F2FD),
                    Colors.blue,
                  ),
                  Container(width: 1, height: 36, color: const Color(0xFFF0F0F0)),
                  _buildStatItem(
                    Icons.star_rounded,
                    AppLocalizations.of(context).profileRating,
                    '4.8',
                    const Color(0xFFFFF3E0),
                    Colors.orange,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Account Section ──
            _buildSectionLabel(AppLocalizations.of(context).profileAccount),
            const SizedBox(height: 8),
            _buildTile(
              context,
              icon: Icons.person_outline_rounded,
              title: AppLocalizations.of(context).profileEditProfile,
              bgColor: const Color(0xFFE8F5E9),
              iconColor: AppTheme.primaryGreen,
              onTap: () => context.push('/profile/edit'),
            ),
            _buildTile(
              context,
              icon: Icons.shopping_bag_outlined,
              title: AppLocalizations.of(context).profileMyOrders,
              bgColor: const Color(0xFFF3E5F5),
              iconColor: Colors.purple,
              onTap: () => context.push('/orders'),
            ),
            _buildTile(
              context,
              icon: Icons.location_on_outlined,
              title: AppLocalizations.of(context).profileMyAddresses,
              bgColor: const Color(0xFFE3F2FD),
              iconColor: Colors.blue,
              onTap: () => context.push('/addresses'),
            ),

            const SizedBox(height: 20),

            // ── Preferences Section ──
            _buildSectionLabel(AppLocalizations.of(context).profilePreferences),
            const SizedBox(height: 8),
            const _NotificationToggleTile(),
            _buildTile(
              context,
              icon: Icons.language_outlined,
              title: AppLocalizations.of(context).languageTitle,
              bgColor: const Color(0xFFE0F2F1),
              iconColor: Colors.teal,
              onTap: () => context.push('/language'),
            ),

            const SizedBox(height: 20),

            // ── Support Section ──
            _buildSectionLabel(AppLocalizations.of(context).profileSupport),
            const SizedBox(height: 8),
            _buildTile(
              context,
              icon: Icons.help_outline_rounded,
              title: AppLocalizations.of(context).profileHelpSupport,
              bgColor: const Color(0xFFE8EAF6),
              iconColor: Colors.indigo,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(content: Text(AppLocalizations.of(context).profileHelpComingSoon)),
                );
              },
            ),
            _buildTile(
              context,
              icon: Icons.info_outline_rounded,
              title: AppLocalizations.of(context).profileAbout,
              bgColor: const Color(0xFFF5F5F5),
              iconColor: AppTheme.grey,
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title:  Text(AppLocalizations.of(context).profileAboutApp),
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
                        title:  Text(
                          AppLocalizations.of(context).profileLogout,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        content:  Text(AppLocalizations.of(context).profileLogoutConfirm),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child:  Text(AppLocalizations.of(context).commonCancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child:  Text(AppLocalizations.of(context).profileLogout),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      // Single teardown path — see core/session.dart. This used
                      // to reset Location/Address/Proximity but leave the cart
                      // and order list behind for the next user of the device.
                      await endSession(context);
                      if (context.mounted) context.go('/login');
                    }
                  },
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label:  Text(
                    AppLocalizations.of(context).profileLogout,
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

/// Notifications on/off toggle for the profile Preferences section.
/// Off by default for guests (not logged in); for logged-in users with no saved
/// preference it reflects the actual OS permission. Turning it on requests
/// permission; turning it off unsubscribes from push topics. The choice is
/// persisted so it sticks across sessions.
class _NotificationToggleTile extends StatefulWidget {
  const _NotificationToggleTile();

  @override
  State<_NotificationToggleTile> createState() =>
      _NotificationToggleTileState();
}

class _NotificationToggleTileState extends State<_NotificationToggleTile> {
  static const _prefKey = 'notifications_enabled';
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Read auth synchronously before any await (no context across async gaps).
    final isAuth =
        Provider.of<AuthProvider>(context, listen: false).isAuthenticated;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_prefKey);
    if (stored != null) {
      if (mounted) setState(() => _enabled = stored);
      return;
    }
    // No saved preference → OFF by default for guests; for logged-in users
    // reflect the real OS permission so the switch matches reality.
    var defaultOn = false;
    if (isAuth) {
      defaultOn = await NotificationService().areNotificationsEnabled();
    }
    if (mounted) setState(() => _enabled = defaultOn);
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final prefs = await SharedPreferences.getInstance();
    final service = NotificationService();

    if (value) {
      final granted = await service.requestNotificationPermission();
      await prefs.setBool(_prefKey, granted);
      if (!mounted) return;
      if (!granted) {
        // OS permission denied — can't enable; keep off and guide the user.
        setState(() {
          _enabled = false;
          _busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text(
                AppLocalizations.of(context).profileEnableNotifHint),
          ),
        );
        return;
      }
      setState(() {
        _enabled = true;
        _busy = false;
      });
    } else {
      await service.unsubscribeCurrentTopic();
      await prefs.setBool(_prefKey, false);
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.notifications_outlined,
                    color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 14),
               Expanded(
                child: Text(
                  AppLocalizations.of(context).profileNotifications,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.black,
                  ),
                ),
              ),
              Switch(
                value: _enabled,
                onChanged: _busy ? null : _toggle,
                activeThumbColor: AppTheme.primaryGreen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
