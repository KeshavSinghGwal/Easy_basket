import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/api_service.dart';
import '../../config/app_config.dart';

class AdminSupportRequestsScreen extends StatefulWidget {
  const AdminSupportRequestsScreen({super.key});

  @override
  State<AdminSupportRequestsScreen> createState() =>
      _AdminSupportRequestsScreenState();
}

class _AdminSupportRequestsScreenState
    extends State<AdminSupportRequestsScreen> {
  final ApiService _apiService = sharedApiService;

  List<dynamic> _requests = [];
  bool _loading = true;
  String? _error;

  final List<String> _statuses = [
    'open',
    'in_progress',
    'resolved',
    'closed',
  ];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // ApiService automatically uses the authenticated session/token.
      final response = await _apiService.get('/support');

      if (!mounted) return;

      setState(() {
        _requests = response['requests'] ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(
    int requestId,
    String status,
  ) async {
    try {
      await _apiService.patch(
        '/support/$requestId/status',
        {'status': status},
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Support request updated'),
        ),
      );

      await _loadRequests();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update request: $e'),
        ),
      );
    }
  }

  String _customerName(Map<String, dynamic> request) {
    final user = request['user'];

    if (user is Map<String, dynamic>) {
      return user['name']?.toString() ??
          user['phoneNumber']?.toString() ??
          'Customer';
    }

    return 'Customer';
  }

  String _orderText(Map<String, dynamic> request) {
    final order = request['order'];

    if (order is Map<String, dynamic>) {
      return 'Order #${order['id']}';
    }

    return 'No order linked';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return 'In Progress';
      case 'open':
        return 'Open';
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Requests'),
        actions: [
          IconButton(
            onPressed: _loadRequests,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 50,
              ),
              const SizedBox(height: 12),
              const Text(
                'Unable to load support requests',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadRequests,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_requests.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadRequests,
        child: ListView(
          children: const [
            SizedBox(height: 180),
            Icon(
              Icons.support_agent,
              size: 60,
            ),
            SizedBox(height: 16),
            Center(
              child: Text(
                'No support requests',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        itemBuilder: (context, index) {
          final request =
              Map<String, dynamic>.from(_requests[index] as Map);

          final id = request['id'] as int;
          final category =
              request['category']?.toString() ?? 'Other';
          final description =
              request['description']?.toString() ?? '';
          final status =
              request['status']?.toString() ?? 'open';

          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '#$id  $category',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _StatusChip(
                        status: _statusLabel(status),
                        color: _statusColor(status),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Text(
                    _customerName(request),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    _orderText(request),
                    style: TextStyle(
                      color: Colors.grey.shade700,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(description),

                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    initialValue: _statuses.contains(status)
                        ? status
                        : 'open',
                    decoration: const InputDecoration(
                      labelText: 'Update Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _statuses.map((value) {
                      return DropdownMenuItem(
                        value: value,
                        child: Text(_statusLabel(value)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null && value != status) {
                        _updateStatus(id, value);
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final Color color;

  const _StatusChip({
    required this.status,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}