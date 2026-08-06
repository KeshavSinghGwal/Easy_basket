import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/service_area_provider.dart';
import '../../models/address_model.dart';
import '../../services/notification_service.dart';
import '../../utils/theme.dart';

/// Edit Address Screen — Single page, matches AddressCompletionSheet design
///
/// Clean, modern form. No wizard steps. Edit → Save → Done.
class EditAddressScreen extends StatefulWidget {
  final AddressModel address;

  const EditAddressScreen({super.key, required this.address});

  @override
  State<EditAddressScreen> createState() => _EditAddressScreenState();
}

class _EditAddressScreenState extends State<EditAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  final _houseController = TextEditingController();
  final _streetController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();

  String _selectedTag = 'home';
  String? _latitude;
  String? _longitude;
  bool _isDefault = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final a = widget.address;
    _houseController.text = a.addressLine1;
    _streetController.text = a.addressLine2 ?? '';
    _cityController.text = a.city;
    _stateController.text = a.state;
    _pincodeController.text = a.pincode;
    _landmarkController.text = a.landmark ?? '';
    _latitude = a.latitude;
    _longitude = a.longitude;
    _selectedTag = a.tag ?? 'home';
    _isDefault = a.isDefault;
  }

  @override
  void dispose() {
    _houseController.dispose();
    _streetController.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  bool get _hasDetected => _cityController.text.isNotEmpty || _pincodeController.text.isNotEmpty;

  String get _detectedText {
    final parts = [_cityController.text, _stateController.text, _pincodeController.text]
        .where((s) => s.isNotEmpty);
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Edit Address',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          // ─── Scrollable form ───
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Detected location chip
                    if (_hasDetected)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.12)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on_rounded, color: AppTheme.primaryGreen, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _detectedText,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Error / not serviceable message
                    if (_errorMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFE082)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFF57C00), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFF57C00)),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _errorMessage = null),
                              child: Icon(Icons.close, size: 14, color: Colors.grey[400]),
                            ),
                          ],
                        ),
                      ),

                    // House + Street
                    _buildField(controller: _houseController, hint: 'House / Flat No, Building *', required: true),
                    const SizedBox(height: 10),
                    _buildField(controller: _streetController, hint: 'Street / Road *', required: true),
                    const SizedBox(height: 10),

                    // Landmark
                    _buildField(controller: _landmarkController, hint: 'Landmark (optional)'),
                    const SizedBox(height: 10),

                    // City + State
                    Row(
                      children: [
                        Expanded(child: _buildField(controller: _cityController, hint: 'City *', required: true)),
                        const SizedBox(width: 10),
                        Expanded(child: _buildField(controller: _stateController, hint: 'State *', required: true)),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Pincode
                    SizedBox(
                      width: 140,
                      child: _buildField(
                        controller: _pincodeController,
                        hint: 'Pincode *',
                        required: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tag selector
                    Row(
                      children: [
                        _buildTag('home', Icons.home_rounded, 'Home'),
                        const SizedBox(width: 8),
                        _buildTag('office', Icons.business_rounded, 'Office'),
                        const SizedBox(width: 8),
                        _buildTag('other', Icons.location_on_rounded, 'Other'),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Default toggle
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                      ),
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                        title: const Text('Set as default address', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        value: _isDefault,
                        onChanged: (v) => setState(() => _isDefault = v),
                        activeThumbColor: AppTheme.primaryGreen,
                activeTrackColor: AppTheme.primaryGreen.withValues(alpha: 0.4),
                        dense: true,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Delete address
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),

          // ─── Save button ───
          Container(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF43A047)]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: AppTheme.primaryGreen.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _isSaving ? null : _saveAddress,
                      child: Center(
                        child: _isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                            : const Text('Save Address', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Field widget — matches AddressCompletionSheet ───
  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    bool required = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? '' : null : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.grey[400]),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        errorStyle: const TextStyle(height: 0, fontSize: 0),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      ),
    );
  }

  // ─── Tag chip — matches AddressCompletionSheet ───
  Widget _buildTag(String value, IconData icon, String label) {
    final isSelected = _selectedTag == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedTag = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : Colors.grey.withValues(alpha: 0.2),
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppTheme.primaryGreen.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.grey[500]),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  // ─── Save logic ───
  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final addressProvider = Provider.of<AddressProvider>(context, listen: false);
    final serviceAreaProvider = Provider.of<ServiceAreaProvider>(context, listen: false);

    String? token = authProvider.accessToken ?? authProvider.token;
    if (token == null) {
      setState(() => _isSaving = false);
      return;
    }

    // Check service availability — prefer GPS coordinates (radius); pincode fallback.
    final svcLat = double.tryParse(_latitude ?? '');
    final svcLng = double.tryParse(_longitude ?? '');
    final pincode = _pincodeController.text.trim();
    if ((svcLat != null && svcLng != null) || pincode.isNotEmpty) {
      final ok = await serviceAreaProvider.checkServiceAvailability(
        latitude: svcLat,
        longitude: svcLng,
        pincode: pincode,
        country: 'India',
      );
      if (!ok && mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = "We don't deliver to ${_cityController.text.isNotEmpty ? _cityController.text : pincode} yet";
        });
        return;
      }
    }

    try {
      final success = await orderProvider.updateAddress(
        token: token,
        addressId: widget.address.id,
        addressLine1: _houseController.text.trim(),
        addressLine2: _streetController.text.trim().isEmpty ? null : _streetController.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        pincode: pincode,
        landmark: _landmarkController.text.trim().isEmpty ? null : _landmarkController.text.trim(),
        isDefault: _isDefault,
        latitude: _latitude,
        longitude: _longitude,
        tag: _selectedTag,
      );

      if (success) {
        // Refresh both providers
        await addressProvider.fetchAddresses(token);
        final updated = addressProvider.defaultAddress;
        if (updated != null) addressProvider.selectAddress(updated);

        // Update FCM topic if pincode changed
        if (pincode != widget.address.pincode) {
          NotificationService().switchPincodeTopic(pincode);
        }
      }

      setState(() => _isSaving = false);
      if (success && mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Address updated'),
            ]),
            backgroundColor: AppTheme.primaryGreen,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      } else if (mounted) {
        setState(() => _errorMessage = orderProvider.error ?? 'Failed to update address');
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = 'Something went wrong. Try again.';
      });
    }
  }

}
