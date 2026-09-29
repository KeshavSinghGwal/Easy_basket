import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme.dart';

/// Admin: Riders dashboard.
///
/// Shows every delivery user with availability + active-order count + last-seen,
/// optionally filtered. Tap a row → wallet sheet with deposit form.
///
/// Backend endpoints used:
///   - GET  /api/admin/riders[?availability=]
///   - GET  /api/admin/riders/:id/wallet
///   - POST /api/admin/riders/:id/deposit (Idempotency-Key required)
class AdminRidersScreen extends StatefulWidget {
  const AdminRidersScreen({super.key});

  @override
  State<AdminRidersScreen> createState() => _AdminRidersScreenState();
}

class _AdminRidersScreenState extends State<AdminRidersScreen> {
  String _filter = 'all'; // all | idle | busy | offline

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) return;
    final filter = _filter == 'all' ? null : _filter;
    await Provider.of<AdminProvider>(context, listen: false)
        .fetchRiders(token: token, availability: filter);
  }

  Future<void> _openWallet(Map<String, dynamic> rider) async {
    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) return;
    final riderId = rider['riderId'] as int;
    final wallet = await Provider.of<AdminProvider>(context, listen: false)
        .fetchRiderWallet(token: token, riderId: riderId);
    if (!mounted) return;
    if (wallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load wallet')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WalletSheet(rider: rider, wallet: wallet, onDepositRecorded: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminProvider = Provider.of<AdminProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riders'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/dashboard'),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          // Availability filter row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                for (final f in const ['all', 'idle', 'busy', 'offline'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f.toUpperCase()),
                      selected: _filter == f,
                      onSelected: (_) {
                        setState(() => _filter = f);
                        _load();
                      },
                      selectedColor: AppTheme.primaryGreen,
                      labelStyle: TextStyle(
                        color: _filter == f ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: adminProvider.isLoading && adminProvider.riders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : adminProvider.riders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delivery_dining, size: 64, color: AppTheme.grey),
                            const SizedBox(height: 16),
                            Text(
                              'No riders found',
                              style: TextStyle(fontSize: 18, color: AppTheme.grey),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: adminProvider.riders.length,
                          itemBuilder: (_, i) => _RiderCard(
                            rider: adminProvider.riders[i],
                            onTap: () => _openWallet(adminProvider.riders[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _RiderCard extends StatelessWidget {
  final Map<String, dynamic> rider;
  final VoidCallback onTap;
  const _RiderCard({required this.rider, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final availability = rider['availability'] as String? ?? 'offline';
    final color = switch (availability) {
      'idle' => Colors.green,
      'busy' => Colors.orange,
      _ => Colors.grey,
    };
    final activeCount = rider['activeOrderCount'] as int? ?? 0;
    final name = rider['name'] as String? ?? 'Rider';
    final phone = rider['phoneNumber'] as String? ?? '';
    final lastSeen = rider['lastSeenAt'] as String?;
    final rating = rider['rating'];
    final ratingNum = rating is num ? rating.toDouble() : 5.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                availability.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(phone, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.local_shipping_outlined, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text('$activeCount active', style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 12),
                  Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                  const SizedBox(width: 2),
                  Text(ratingNum.toStringAsFixed(1), style: const TextStyle(fontSize: 12)),
                  if (lastSeen != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.schedule, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 3),
                    Text(_formatLastSeen(lastSeen),
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ],
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  String _formatLastSeen(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }
}

class _WalletSheet extends StatefulWidget {
  final Map<String, dynamic> rider;
  final Map<String, dynamic> wallet;
  final Future<void> Function() onDepositRecorded;
  const _WalletSheet({
    required this.rider,
    required this.wallet,
    required this.onDepositRecorded,
  });

  @override
  State<_WalletSheet> createState() => _WalletSheetState();
}

class _WalletSheetState extends State<_WalletSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isSubmitting = false;
  late Map<String, dynamic> _wallet;

  @override
  void initState() {
    super.initState();
    _wallet = Map<String, dynamic>.from(widget.wallet);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitDeposit() async {
    final raw = _amountController.text.trim();
    final rupees = double.tryParse(raw);
    if (rupees == null || rupees <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount in rupees')),
      );
      return;
    }
    final paise = (rupees * 100).round();
    final cashInHand = (_wallet['cashInHandPaise'] as num?)?.toInt() ?? 0;
    if (paise > cashInHand) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Deposit exceeds cash-in-hand'),
          content: Text(
            'Recording ₹${rupees.toStringAsFixed(0)} but rider only owes ₹${(cashInHand / 100).toStringAsFixed(0)}. Proceed?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = true);
    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) {
      setState(() => _isSubmitting = false);
      return;
    }
    final result = await Provider.of<AdminProvider>(context, listen: false).recordRiderDeposit(
      token: token,
      riderId: widget.rider['riderId'] as int,
      amountPaise: paise,
      note: _noteController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Provider.of<AdminProvider>(context, listen: false).error ??
              'Deposit failed'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    final updated = result['wallet'] as Map<String, dynamic>?;
    if (updated != null) setState(() => _wallet = updated);
    _amountController.clear();
    _noteController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Deposit recorded'),
        backgroundColor: Color(0xFF2E7D32),
      ),
    );
    await widget.onDepositRecorded();
  }

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final cashInHand = ((_wallet['cashInHandPaise'] as num?)?.toInt() ?? 0) / 100;
    final lifetimeCollected = ((_wallet['lifetimeCollectedPaise'] as num?)?.toInt() ?? 0) / 100;
    final lifetimeDeposited = ((_wallet['lifetimeDepositedPaise'] as num?)?.toInt() ?? 0) / 100;
    final name = widget.rider['name'] as String? ?? 'Rider';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('$name — Wallet',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),

            // Cash-in-hand banner — the number admin actually cares about.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cashInHand > 0 ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cashInHand > 0 ? Colors.orange.shade300 : Colors.green.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    cashInHand > 0 ? Icons.account_balance_wallet : Icons.check_circle,
                    color: cashInHand > 0 ? Colors.orange.shade800 : Colors.green.shade700,
                    size: 32,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Cash in hand',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(
                          f.format(cashInHand),
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Lifetime totals — for context
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Collected',
                    value: f.format(lifetimeCollected),
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatTile(
                    label: 'Deposited',
                    value: f.format(lifetimeDeposited),
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Deposit form
            const Text('Record Cash Deposit',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                prefixIcon: Icon(Icons.currency_rupee),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. EOD shift 1',
                border: OutlineInputBorder(),
              ),
              maxLength: 100,
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitDeposit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.savings_outlined),
                label: Text(_isSubmitting ? 'Recording…' : 'Record Deposit',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
