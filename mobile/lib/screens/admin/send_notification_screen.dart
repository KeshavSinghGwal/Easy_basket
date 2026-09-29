import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';

/// Admin Send Notification Screen
///
/// Admin selects pincodes → types title + message → sends
/// Backend sends to FCM topic → all subscribers receive
class SendNotificationScreen extends StatefulWidget {
  const SendNotificationScreen({super.key});

  @override
  State<SendNotificationScreen> createState() => _SendNotificationScreenState();
}

class _SendNotificationScreenState extends State<SendNotificationScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _pincodeController = TextEditingController();
  final List<String> _pincodes = [];
  bool _isSending = false;
  String? _resultMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  void _addPincode() {
    final pin = _pincodeController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (pin.length == 6 && !_pincodes.contains(pin)) {
      setState(() {
        _pincodes.add(pin);
        _pincodeController.clear();
        _resultMessage = null;
      });
    }
  }

  void _removePincode(String pin) {
    setState(() {
      _pincodes.remove(pin);
      _resultMessage = null;
    });
  }

  Future<void> _sendNotification() async {
    if (_pincodes.isEmpty) {
      setState(() {
        _resultMessage = 'Add at least 1 pincode';
        _isSuccess = false;
      });
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      setState(() {
        _resultMessage = 'Title is required';
        _isSuccess = false;
      });
      return;
    }
    if (_bodyController.text.trim().isEmpty) {
      setState(() {
        _resultMessage = 'Message is required';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isSending = true;
      _resultMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.accessToken ?? authProvider.token;

      if (token == null) {
        setState(() {
          _isSending = false;
          _resultMessage = 'Not authenticated';
          _isSuccess = false;
        });
        return;
      }

      final apiService = sharedApiService;
      final response = await apiService.post(
        '/admin/notifications/send',
        {
          'pincodes': _pincodes,
          'title': _titleController.text.trim(),
          'body': _bodyController.text.trim(),
        },
        token: token,
      );

      final sent = response['sent'] ?? 0;
      final totalPincodes = response['totalPincodes'] ?? _pincodes.length;

      setState(() {
        _isSending = false;
        _isSuccess = true;
        _resultMessage = 'Sent to $sent/$totalPincodes pincodes successfully!';
      });
    } catch (e) {
      setState(() {
        _isSending = false;
        _isSuccess = false;
        _resultMessage = 'Error: ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F3),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF4F8F3),
        title: const Text('Send Notification', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pincode input section
            _buildCard(
              icon: Icons.location_on_rounded,
              iconColor: AppTheme.primaryGreen,
              title: 'Select Pincodes',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pincode input row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pincodeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                          decoration: InputDecoration(
                            hintText: 'Enter 6-digit pincode',
                            hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          onSubmitted: (_) => _addPincode(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _addPincode,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.add, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Pincode chips
                  if (_pincodes.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _pincodes.map((pin) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(pin, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen)),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _removePincode(pin),
                              child: const Icon(Icons.close, size: 14, color: AppTheme.primaryGreen),
                            ),
                          ],
                        ),
                      )).toList(),
                    ),

                  if (_pincodes.isEmpty)
                    Text('No pincodes added yet', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Notification content
            _buildCard(
              icon: Icons.edit_rounded,
              iconColor: const Color(0xFF1565C0),
              title: 'Notification Content',
              child: Column(
                children: [
                  // Title
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      hintText: 'Notification title (e.g., 50% Off!)',
                      hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Body
                  TextField(
                    controller: _bodyController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Notification message...',
                      hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Preview
            if (_titleController.text.isNotEmpty || _bodyController.text.isNotEmpty)
              _buildCard(
                icon: Icons.visibility_rounded,
                iconColor: Colors.orange,
                title: 'Preview',
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset('assets/icons/app_icon.png', fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _titleController.text.isEmpty ? 'Title' : _titleController.text,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _bodyController.text.isEmpty ? 'Message' : _bodyController.text,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 14),

            // Result message
            if (_resultMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isSuccess ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
                      color: _isSuccess ? AppTheme.primaryGreen : Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _resultMessage!,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _isSuccess ? AppTheme.primaryGreen : Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Send button
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
                    onTap: _isSending ? null : _sendNotification,
                    child: Center(
                      child: _isSending
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Send to ${_pincodes.length} pincode${_pincodes.length != 1 ? 's' : ''}',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ],
                            ),
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

  Widget _buildCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
