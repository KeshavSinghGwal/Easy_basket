import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/campaign_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';

/// Admin Campaign List — View all campaigns, create new, edit, delete
class CampaignListScreen extends StatefulWidget {
  const CampaignListScreen({super.key});

  @override
  State<CampaignListScreen> createState() => _CampaignListScreenState();
}

class _CampaignListScreenState extends State<CampaignListScreen> {
  List<CampaignModel> _campaigns = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCampaigns();
  }

  Future<void> _fetchCampaigns() async {
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final token = auth.accessToken ?? auth.token;
      final api = sharedApiService;
      final response = await api.get('/campaigns/admin', token: token);
      if (response is List && mounted) {
        setState(() {
          _campaigns = response.map((e) => CampaignModel.fromJson(e as Map<String, dynamic>)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('❌ Campaign fetch error: $e');
    }
  }

  Future<void> _deleteCampaign(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Campaign?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final token = auth.accessToken ?? auth.token;
      final api = sharedApiService;
      await api.delete('/campaigns/admin/$id', token: token);
      _fetchCampaigns();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _sendPush(CampaignModel campaign) async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final token = auth.accessToken ?? auth.token;
      final api = sharedApiService;
      final response = await api.post('/campaigns/admin/${campaign.id}/push', {}, token: token);
      if (mounted) {
        final sent = response['sent'] ?? 0;
        final total = response['totalTopics'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Push sent: $sent/$total topics'), backgroundColor: AppTheme.primaryGreen),
        );
        _fetchCampaigns();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Push error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F3),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF4F8F3),
        title: const Text('Campaigns', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.black87),
            onPressed: _fetchCampaigns,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/admin/campaigns/create');
          _fetchCampaigns(); // Refresh after creating
        },
        backgroundColor: AppTheme.primaryGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Campaign', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.primaryGreen)))
          : _campaigns.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.campaign_rounded, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('No campaigns yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[400])),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchCampaigns,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 80),
                    itemCount: _campaigns.length,
                    itemBuilder: (context, index) => _buildCampaignCard(_campaigns[index]),
                  ),
                ),
    );
  }

  Widget _buildCampaignCard(CampaignModel campaign) {
    final now = DateTime.now();
    final isExpired = campaign.expiresAt.isBefore(now);
    final isScheduled = campaign.startsAt.isAfter(now);
    final isLive = !isExpired && !isScheduled && campaign.isActive;

    final statusColor = isLive ? AppTheme.primaryGreen : isScheduled ? Colors.orange : Colors.red;
    final statusText = isLive ? 'LIVE' : isScheduled ? 'SCHEDULED' : isExpired ? 'EXPIRED' : 'INACTIVE';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image (if exists)
          if (campaign.imageUrl != null && campaign.imageUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.network(campaign.imageUrl!, height: 120, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status + placement row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(6)),
                      child: Text(campaign.placement.replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey[600])),
                    ),
                    if (campaign.pushSent) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(6)),
                        child: const Text('PUSH SENT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF1565C0))),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),

                // Title
                Text(campaign.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (campaign.subtitle != null && campaign.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(campaign.subtitle!, style: TextStyle(fontSize: 13, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 8),

                // Pincodes
                if (campaign.targetPincodes.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: campaign.targetPincodes.map((p) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.primaryGreen.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
                      child: Text(p, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen)),
                    )).toList(),
                  )
                else
                  Text('All pincodes (global)', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                const SizedBox(height: 10),

                // Action buttons
                Row(
                  children: [
                    // Edit
                    _actionButton(Icons.edit_rounded, 'Edit', Colors.blue, () async {
                      await context.push('/admin/campaigns/edit', extra: campaign);
                      _fetchCampaigns();
                    }),
                    const SizedBox(width: 8),
                    // Push
                    if (!campaign.pushSent && isLive)
                      _actionButton(Icons.notifications_active_rounded, 'Push', Colors.orange, () => _sendPush(campaign)),
                    if (!campaign.pushSent && isLive) const SizedBox(width: 8),
                    // Delete
                    _actionButton(Icons.delete_rounded, 'Delete', Colors.red, () => _deleteCampaign(campaign.id)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}
