import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/address_provider.dart';
import '../providers/order_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/service_area_provider.dart';
import '../services/notification_service.dart';
import '../utils/theme.dart';
import '../l10n/app_localizations.dart';

/// Universal Address Form Bottom Sheet — Premium, Blinkit style
///
/// Used everywhere — GPS, Map, Search, Checkout, Manual.
/// Pre-fills whatever data is available, user fills the rest.
class AddressCompletionSheet extends StatefulWidget {
  final Map<String, dynamic> preFilledData;
  final VoidCallback onSaved;

  const AddressCompletionSheet({
    super.key,
    required this.preFilledData,
    required this.onSaved,
  });

  static void show({
    required BuildContext context,
    Map<String, dynamic> preFilledData = const {},
    required VoidCallback onSaved,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Stack(
        clipBehavior: Clip.none,
        children: [
          // Sheet
          AddressCompletionSheet(preFilledData: preFilledData, onSaved: onSaved),
          // Cross button — outside, centered above sheet
          Positioned(
            top: -44,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEEEEE),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Icon(Icons.close_rounded, color: Colors.grey[600], size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  State<AddressCompletionSheet> createState() => _AddressCompletionSheetState();
}

class _AddressCompletionSheetState extends State<AddressCompletionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _houseController = TextEditingController();
  final _floorController = TextEditingController();
  final _streetController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();

  String _selectedTag = 'home';
  String? _latitude;
  String? _longitude;
  bool _isSaving = false;
  String? _errorMessage;
  bool _notifyMeClicked = false;

  @override
  void initState() {
    super.initState();
    final d = widget.preFilledData;
    if (d['addressLine1'] != null) _houseController.text = d['addressLine1'] as String;
    if (d['area'] != null && _streetController.text.isEmpty) _streetController.text = d['area'] as String;
    if (d['city'] != null) _cityController.text = d['city'] as String;
    if (d['state'] != null) _stateController.text = d['state'] as String;
    if (d['pincode'] != null) _pincodeController.text = d['pincode'] as String;
    _latitude = d['latitude']?.toString();
    _longitude = d['longitude']?.toString();
    if (d['tag'] != null) _selectedTag = d['tag'] as String;
  }

  @override
  void dispose() {
    _houseController.dispose();
    _floorController.dispose();
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      // Reduced height — 75% instead of 88%
      constraints: BoxConstraints(maxHeight: screenHeight * 0.75),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── Drag handle ───
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ─── Header ───
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 14, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add_location_alt_rounded, color: AppTheme.primaryGreen, size: 16),
                ),
                const SizedBox(width: 10),
                 Text(AppLocalizations.of(context).addressAdd, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87)),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ─── Form ───
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18),
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
                            Icon(Icons.location_on_rounded, color: AppTheme.primaryGreen, size: 16),
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

                    // Error message — yellow strip
                    if (_errorMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: _notifyMeClicked ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _notifyMeClicked ? AppTheme.primaryGreen.withValues(alpha: 0.3) : const Color(0xFFFFE082),
                          ),
                        ),
                        child: _notifyMeClicked
                            // After clicking Notify Me — green confirmation
                            ? Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen, size: 18),
                                  const SizedBox(width: 8),
                                   Expanded(
                                    child: Text(
                                      AppLocalizations.of(context).addressWillNotify,
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryGreen),
                                    ),
                                  ),
                                ],
                              )
                            // Before clicking — yellow warning + Notify Me button
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
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
                                  const SizedBox(height: 8),
                                  GestureDetector(
                                    onTap: () {
                                      // TODO: Save user's interest for this location via API
                                      setState(() => _notifyMeClicked = true);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF57C00),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child:  Text(
                                        AppLocalizations.of(context).addressNotifyMe,
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),

                    // House + Floor in row (compact)
                    Row(
                      children: [
                        Expanded(flex: 3, child: _buildField(controller: _houseController, hint: 'House / Flat No *', required: true)),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: _buildField(controller: _floorController, hint: 'Floor')),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Street
                    _buildField(controller: _streetController, hint: 'Street / Road *', required: true),
                    const SizedBox(height: 10),

                    // Landmark
                    _buildField(controller: _landmarkController, hint: 'Landmark'),
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
                    const SizedBox(height: 14),

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
                  ],
                ),
              ),
            ),
          ),

          // ─── Save button ───
          Container(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
            ),
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
                          :  Text(AppLocalizations.of(context).addressSave, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
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

  // ─── Field widget ───
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
        errorStyle: const TextStyle(height: 0, fontSize: 0), // Hide error text, just show border
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      ),
    );
  }

  // ─── Tag chip ───
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

    final pincode = _pincodeController.text.trim();
    if (pincode.isNotEmpty) {
      // Coordinates first (from the GPS partial that pre-filled this sheet);
      // pincode remains the fallback for coord-less entries.
      final ok = await serviceAreaProvider.checkServiceAvailability(
        latitude: double.tryParse(_latitude ?? ''),
        longitude: double.tryParse(_longitude ?? ''),
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

    String addressLine1 = _houseController.text.trim();
    final floor = _floorController.text.trim();
    if (floor.isNotEmpty) addressLine1 = '$addressLine1, Floor $floor';

    try {
      final success = await orderProvider.createAddress(
        token: token,
        addressLine1: addressLine1,
        addressLine2: _streetController.text.trim().isEmpty ? null : _streetController.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        pincode: pincode,
        landmark: _landmarkController.text.trim().isEmpty ? null : _landmarkController.text.trim(),
        isDefault: true,
        latitude: _latitude,
        longitude: _longitude,
        tag: _selectedTag,
      );

      if (success) {
        await addressProvider.fetchAddresses(token);
        final newDefault = addressProvider.defaultAddress;
        if (newDefault != null) addressProvider.selectAddress(newDefault);
      }

      setState(() => _isSaving = false);
      if (success && mounted) {
        // Subscribe to pincode topic for promo notifications
        NotificationService().subscribeToPincode(pincode);

        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).commonError(e.toString())), backgroundColor: Colors.red));
      }
    }
  }
}
