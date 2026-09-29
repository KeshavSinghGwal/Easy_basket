import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/store_status_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/store_status_provider.dart';
import '../../utils/theme.dart';

/// Admin: open or close the store.
///
/// Closing gates NEW orders only — existing orders, riders and admin actions
/// carry on. That promise is stated on screen, because an admin who thinks
/// closing cancels in-flight deliveries will hesitate to use this at all.
class StoreStatusScreen extends StatefulWidget {
  const StoreStatusScreen({super.key});

  @override
  State<StoreStatusScreen> createState() => _StoreStatusScreenState();
}

class _StoreStatusScreenState extends State<StoreStatusScreen> {
  StoreClosedReason _reason = StoreClosedReason.rain;
  final _messageController = TextEditingController();
  DateTime? _expectedReopenAt;
  bool _notifyOnReopen = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = Provider.of<StoreStatusProvider>(context, listen: false);
      await provider.refresh(force: true);
      if (!mounted) return;
      // Seed the form from the live state so editing a closed store shows the
      // reason and message already in effect rather than blank defaults.
      final status = provider.status;
      if (!status.isOpen) {
        setState(() {
          _reason = status.reason;
          _messageController.text = status.customMessage ?? '';
          _expectedReopenAt = status.expectedReopenAt;
        });
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightGrey,
      appBar: AppBar(
        title: const Text('Store Status'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: Consumer<StoreStatusProvider>(
        builder: (context, provider, _) {
          final status = provider.status;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusHeaderCard(status: status),
              const SizedBox(height: 20),
              if (status.isOpen) ..._buildCloseForm(context) else _buildReopenCard(context, status),
              const SizedBox(height: 24),
              const _ScopeNote(),
            ],
          );
        },
      ),
    );
  }

  // ── Store is open → offer to close it ──

  List<Widget> _buildCloseForm(BuildContext context) {
    return [
      const Text('Why are you closing?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
        'This picks the artwork customers see on the home screen.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      const SizedBox(height: 12),
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: RadioGroup<StoreClosedReason>(
          groupValue: _reason,
          onChanged: (v) => setState(() => _reason = v ?? _reason),
          child: Column(
            children: StoreClosedReason.values.map((reason) {
              return RadioListTile<StoreClosedReason>(
                value: reason,
                dense: true,
                title: Row(
                  children: [
                    Icon(reason.icon, size: 18, color: reason.gradient.first),
                    const SizedBox(width: 10),
                    Text(reason.adminLabel),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
      const SizedBox(height: 20),
      const Text('Message to customers',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
        'Optional. Leave blank to use: "${_reason.defaultHeadline}"',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _messageController,
        maxLength: 280,
        maxLines: 2,
        decoration: InputDecoration(
          hintText: 'e.g. Heavy rain in Bareilly — riders are off the road',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 8),
      _buildReopenPicker(context),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : () => _confirmClose(context),
          icon: _isSaving
              ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.pause_circle_filled_rounded),
          label: Text(_isSaving ? 'Closing…' : 'Close the store'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ];
  }

  Widget _buildReopenPicker(BuildContext context) {
    final label = _expectedReopenAt == null
        ? 'Set expected reopen time (optional)'
        : DateFormat('d MMM, h:mm a').format(_expectedReopenAt!);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickReopenTime(context),
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: Text(label, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        if (_expectedReopenAt != null)
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() => _expectedReopenAt = null),
          ),
      ],
    );
  }

  Future<void> _pickReopenTime(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expectedReopenAt ?? now.add(const Duration(hours: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expectedReopenAt ?? now.add(const Duration(hours: 2))),
    );
    if (time == null) return;

    setState(() {
      _expectedReopenAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  // ── Store is closed → offer to reopen ──

  Widget _buildReopenCard(BuildContext context, StoreStatusModel status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SwitchListTile(
            value: _notifyOnReopen,
            onChanged: (v) => setState(() => _notifyOnReopen = v),
            activeThumbColor: AppTheme.primaryGreen,
            title: const Text('Notify customers', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(
              'Send a push telling everyone we\'re back online',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : () => _submit(context, isOpen: true),
          icon: _isSaving
              ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.play_circle_fill_rounded),
          label: Text(_isSaving ? 'Opening…' : 'Reopen the store'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isSaving ? null : () => _editClosure(context, status),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit the closed message'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  /// Re-save the closure with edited reason/message, without reopening.
  Future<void> _editClosure(BuildContext context, StoreStatusModel status) async {
    setState(() {
      _reason = status.reason;
      _messageController.text = status.customMessage ?? '';
      _expectedReopenAt = status.expectedReopenAt;
    });

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 20, 16, MediaQuery.of(sheetContext).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Update closed message',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            StatefulBuilder(
              builder: (context, setSheetState) => DropdownButtonFormField<StoreClosedReason>(
                initialValue: _reason,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: StoreClosedReason.values
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.adminLabel)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setSheetState(() => _reason = v);
                  setState(() => _reason = v ?? _reason);
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              maxLength: 280,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Message (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );

    if (saved == true && context.mounted) {
      await _submit(context, isOpen: false);
    }
  }

  // ── Submit ──

  /// Closing stops all incoming revenue, so it goes through a confirmation.
  /// Reopening does not — that direction is always safe.
  Future<void> _confirmClose(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close the store?'),
        content: Text(
          'Customers will be able to browse and add to cart, but nobody will be '
          'able to place a new order until you reopen.\n\n'
          'Reason: ${_reason.adminLabel}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Close store'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _submit(context, isOpen: false);
    }
  }

  Future<void> _submit(BuildContext context, {required bool isOpen}) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<StoreStatusProvider>(context, listen: false);
    // Captured before the await — resolving it afterwards would be reading a
    // BuildContext across an async gap.
    final messenger = ScaffoldMessenger.of(context);
    final token = auth.token;

    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Session expired — please log in again')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final error = await provider.updateStatus(
      token: token,
      isOpen: isOpen,
      closedReason: isOpen ? null : _reason,
      customMessage: isOpen ? null : _messageController.text,
      expectedReopenAt: isOpen ? null : _expectedReopenAt,
      notifyOnReopen: isOpen && _notifyOnReopen,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ?? (isOpen ? 'Store is now OPEN' : 'Store is now CLOSED'),
        ),
        backgroundColor: error != null
            ? Colors.red.shade700
            : (isOpen ? AppTheme.primaryGreen : Colors.orange.shade800),
      ),
    );
  }
}

/// Big unmissable current-state card. Deliberately loud: an admin should never
/// have to hunt for whether the shop is currently taking orders.
class _StatusHeaderCard extends StatelessWidget {
  const _StatusHeaderCard({required this.status});

  final StoreStatusModel status;

  @override
  Widget build(BuildContext context) {
    final isOpen = status.isOpen;
    final colors = isOpen
        ? [const Color(0xFF2E7D32), const Color(0xFF4CAF50)]
        : status.reason.gradient;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOpen ? Icons.storefront_rounded : status.reason.icon,
                color: Colors.white,
                size: 26,
              ),
              const SizedBox(width: 12),
              Text(
                isOpen ? 'OPEN' : 'CLOSED',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isOpen ? 'Accepting new orders' : status.headline,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 14,
            ),
          ),
          if (!isOpen && status.closedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Closed since ${DateFormat('d MMM, h:mm a').format(status.closedAt!)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
              ),
            ),
          ],
          if (!isOpen && status.expectedReopenAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Told customers: reopening ${DateFormat('d MMM, h:mm a').format(status.expectedReopenAt!)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScopeNote extends StatelessWidget {
  const _ScopeNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Closing the store only blocks NEW orders.\n\n'
              'Orders already placed are unaffected — riders keep delivering, '
              'you can still manage and cancel orders, and customers can still '
              'browse products and fill their cart.',
              style: TextStyle(fontSize: 12, height: 1.5, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }
}
