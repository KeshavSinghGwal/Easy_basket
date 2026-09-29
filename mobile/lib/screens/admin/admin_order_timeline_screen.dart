import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme.dart';

/// Admin: chronological audit log of every state change on an order.
///
/// Reads `GET /api/admin/orders/:id/events` — append-only log written by every
/// state-machine transition. Useful for:
///   - "where is my order stuck and why?"
///   - "did the rider actually collect cash, or did they fake it?"
///   - dispute resolution + compliance
class AdminOrderTimelineScreen extends StatefulWidget {
  final int orderId;
  const AdminOrderTimelineScreen({super.key, required this.orderId});

  @override
  State<AdminOrderTimelineScreen> createState() => _AdminOrderTimelineScreenState();
}

class _AdminOrderTimelineScreenState extends State<AdminOrderTimelineScreen> {
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) {
      setState(() {
        _error = 'Authentication required';
        _isLoading = false;
      });
      return;
    }
    try {
      final events = await Provider.of<AdminProvider>(context, listen: false)
          .fetchOrderEvents(token: token, orderId: widget.orderId);
      if (!mounted) return;
      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Order #${widget.orderId} timeline'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : _events.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_toggle_off,
                              size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(
                            'No events yet',
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'State changes will show up here once they happen.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _events.length,
                        itemBuilder: (_, i) => _EventTile(
                          event: _events[i],
                          isFirst: i == 0,
                          isLast: i == _events.length - 1,
                        ),
                      ),
                    ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  final bool isFirst;
  final bool isLast;
  const _EventTile({required this.event, required this.isFirst, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final eventType = event['eventType'] as String? ?? 'unknown';
    final actorRole = event['actorRole'] as String? ?? 'system';
    final fromState = event['fromState'] as String?;
    final toState = event['toState'] as String?;
    final createdAt = event['createdAt'] as String?;
    final payload = event['payload'];

    final color = _colorForRole(actorRole);
    final icon = _iconForEvent(eventType);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail with dot
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst ? Colors.transparent : Colors.grey.shade300,
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : Colors.grey.shade300,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 4),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _humanizeEvent(eventType),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            actorRole.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: color,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (fromState != null && toState != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(fromState,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.arrow_right_alt, size: 14),
                          ),
                          Text(toState,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                    if (createdAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _formatTime(createdAt),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                    if (payload != null) ...[
                      const SizedBox(height: 8),
                      _PayloadView(payload: payload),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForRole(String role) {
    switch (role) {
      case 'customer':
        return Colors.blue.shade700;
      case 'admin':
        return Colors.purple.shade700;
      case 'delivery':
        return Colors.orange.shade800;
      default:
        return Colors.grey.shade600;
    }
  }

  IconData _iconForEvent(String type) {
    if (type.contains('cash')) return Icons.payments_outlined;
    if (type.contains('refund')) return Icons.replay;
    if (type.contains('rider_assigned')) return Icons.person_add_alt_1;
    if (type.contains('arrived')) return Icons.flag;
    if (type.contains('picked')) return Icons.shopping_bag_outlined;
    if (type.contains('delivery_started')) return Icons.local_shipping_outlined;
    if (type.contains('issue')) return Icons.error_outline;
    if (type.contains('rto')) return Icons.assignment_return;
    if (type.contains('otp')) return Icons.password;
    if (type.contains('fraud')) return Icons.warning_amber;
    if (type.contains('mismatch')) return Icons.warning_amber;
    return Icons.fiber_manual_record;
  }

  String _humanizeEvent(String type) {
    return type
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('dd MMM yyyy, hh:mm:ss a').format(dt);
    } catch (_) {
      return iso;
    }
  }
}

class _PayloadView extends StatelessWidget {
  final dynamic payload;
  const _PayloadView({required this.payload});

  @override
  Widget build(BuildContext context) {
    String pretty;
    try {
      const encoder = JsonEncoder.withIndent('  ');
      pretty = encoder.convert(payload);
    } catch (_) {
      pretty = payload.toString();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SelectableText(
        pretty,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: AppTheme.black,
        ),
      ),
    );
  }
}
