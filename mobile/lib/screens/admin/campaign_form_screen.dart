import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/campaign_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';

/// Admin Create/Edit Campaign Screen
class CampaignFormScreen extends StatefulWidget {
  final CampaignModel? campaign; // null = create, non-null = edit

  const CampaignFormScreen({super.key, this.campaign});

  @override
  State<CampaignFormScreen> createState() => _CampaignFormScreenState();
}

class _CampaignFormScreenState extends State<CampaignFormScreen> {
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _ctaTextController = TextEditingController();
  final _ctaLinkController = TextEditingController();
  final _pincodeController = TextEditingController();

  final List<String> _pincodes = [];
  String _placement = 'hero_banner';
  int _priority = 0;
  bool _pushEnabled = false;
  bool _isSaving = false;
  DateTime _startsAt = DateTime.now();
  DateTime _expiresAt = DateTime.now().add(const Duration(days: 7));

  bool get _isEditing => widget.campaign != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final c = widget.campaign!;
      _titleController.text = c.title;
      _subtitleController.text = c.subtitle ?? '';
      _imageUrlController.text = c.imageUrl ?? '';
      _ctaTextController.text = c.ctaText ?? 'Shop Now';
      _ctaLinkController.text = c.ctaLink ?? '';
      _pincodes.addAll(c.targetPincodes);
      _placement = c.placement;
      _priority = c.priority;
      _pushEnabled = c.pushEnabled;
      _startsAt = c.startsAt;
      _expiresAt = c.expiresAt;
    } else {
      _ctaTextController.text = 'Shop Now';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _imageUrlController.dispose();
    _ctaTextController.dispose();
    _ctaLinkController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  void _addPincode() {
    final pin = _pincodeController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (pin.length == 6 && !_pincodes.contains(pin)) {
      setState(() {
        _pincodes.add(pin);
        _pincodeController.clear();
      });
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _startsAt : _expiresAt,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (time != null && mounted) {
        final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        setState(() {
          if (isStart) _startsAt = dt; else _expiresAt = dt;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title required'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final token = auth.accessToken ?? auth.token;
      final api = sharedApiService;

      final data = {
        'title': _titleController.text.trim(),
        'subtitle': _subtitleController.text.trim().isEmpty ? null : _subtitleController.text.trim(),
        'imageUrl': _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
        'ctaText': _ctaTextController.text.trim().isEmpty ? 'Shop Now' : _ctaTextController.text.trim(),
        'ctaLink': _ctaLinkController.text.trim().isEmpty ? null : _ctaLinkController.text.trim(),
        'targetPincodes': _pincodes,
        'targetCities': <String>[],
        'placement': _placement,
        'priority': _priority,
        'startsAt': _startsAt.toIso8601String(),
        'expiresAt': _expiresAt.toIso8601String(),
        'pushEnabled': _pushEnabled,
      };

      if (_isEditing) {
        await api.put('/campaigns/admin/${widget.campaign!.id}', data, token: token);
      } else {
        await api.post('/campaigns/admin', data, token: token);
      }

      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? 'Campaign updated!' : 'Campaign created!'), backgroundColor: AppTheme.primaryGreen),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
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
        title: Text(_isEditing ? 'Edit Campaign' : 'Create Campaign', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        child: Column(
          children: [
            // Content section
            _card(
              icon: Icons.edit_rounded,
              color: AppTheme.primaryGreen,
              title: 'Content',
              children: [
                _field(_titleController, 'Title *'),
                const SizedBox(height: 10),
                _field(_subtitleController, 'Subtitle'),
                const SizedBox(height: 10),
                _field(_imageUrlController, 'Image URL (optional)'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _field(_ctaTextController, 'Button text')),
                    const SizedBox(width: 10),
                    Expanded(child: _field(_ctaLinkController, 'Link (e.g. /category/5)')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Targeting
            _card(
              icon: Icons.location_on_rounded,
              color: const Color(0xFF1565C0),
              title: 'Targeting',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pincodeController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        decoration: _inputDeco('Add pincode (empty = all)'),
                        onSubmitted: (_) => _addPincode(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _addPincode,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppTheme.primaryGreen, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.add, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
                if (_pincodes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: _pincodes.map((p) => Chip(
                      label: Text(p, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () => setState(() => _pincodes.remove(p)),
                      backgroundColor: AppTheme.primaryGreen.withValues(alpha: 0.08),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    )).toList(),
                  ),
                ],
                if (_pincodes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('No pincodes = shows to ALL users', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Placement + Priority
            _card(
              icon: Icons.dashboard_rounded,
              color: Colors.purple,
              title: 'Placement',
              children: [
                DropdownButtonFormField<String>(
                  value: _placement,
                  decoration: _inputDeco('Placement'),
                  items: const [
                    DropdownMenuItem(value: 'hero_banner', child: Text('Hero Banner (top carousel)')),
                    DropdownMenuItem(value: 'category_strip', child: Text('Category Strip')),
                    DropdownMenuItem(value: 'product_spotlight', child: Text('Product Spotlight')),
                    DropdownMenuItem(value: 'bottom_banner', child: Text('Bottom Banner')),
                  ],
                  onChanged: (v) => setState(() => _placement = v!),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: _priority,
                  decoration: _inputDeco('Priority'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('0 — Highest')),
                    DropdownMenuItem(value: 1, child: Text('1 — High')),
                    DropdownMenuItem(value: 2, child: Text('2 — Medium')),
                    DropdownMenuItem(value: 3, child: Text('3 — Low')),
                  ],
                  onChanged: (v) => setState(() => _priority = v!),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Schedule
            _card(
              icon: Icons.schedule_rounded,
              color: Colors.orange,
              title: 'Schedule',
              children: [
                _dateRow('Starts', _startsAt, () => _pickDate(true)),
                const SizedBox(height: 10),
                _dateRow('Expires', _expiresAt, () => _pickDate(false)),
              ],
            ),
            const SizedBox(height: 12),

            // Push notification
            _card(
              icon: Icons.notifications_active_rounded,
              color: Colors.red,
              title: 'Push Notification',
              children: [
                SwitchListTile(
                  value: _pushEnabled,
                  onChanged: (v) => setState(() => _pushEnabled = v),
                  title: const Text('Send push notification', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(_pushEnabled ? 'Will send to targeted pincodes on create' : 'No push notification', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  activeColor: AppTheme.primaryGreen,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF43A047)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: AppTheme.primaryGreen.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _isSaving ? null : _save,
                    child: Center(
                      child: _isSaving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                          : Text(_isEditing ? 'Update Campaign' : 'Create Campaign', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required IconData icon, required Color color, required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 16)),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      decoration: _inputDeco(hint),
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _dateRow(String label, DateTime date, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 16, color: Colors.grey[500]),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
            const Spacer(),
            Text(
              '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
