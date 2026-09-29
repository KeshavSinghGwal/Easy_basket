import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/service_area_provider.dart';
import '../../utils/theme.dart';
import 'map_address_picker_screen.dart';
import '../../l10n/app_localizations.dart';

/// Add Address Screen — Redesigned (Single page, clean form)
///
/// Features:
/// - "Use Current Location" button at top (GPS detect)
/// - "Pick on Map" button (map picker)
/// - Pre-detected location shown if available
/// - Clean form: House, Floor, Street, Landmark
/// - City, State, Pincode (auto-filled from GPS/map)
/// - Tag selector: Home / Office / Other
/// - Service area check before save
/// - Token refresh + retry on 401
class AddAddressScreen extends StatefulWidget {
  final Map<String, dynamic>? preFilledData;

  const AddAddressScreen({super.key, this.preFilledData});

  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends State<AddAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  final _houseController = TextEditingController();
  final _floorController = TextEditingController();
  final _streetController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();

  String _selectedTag = 'home';
  bool _isDefault = true;
  String? _latitude;
  String? _longitude;
  bool _isSaving = false;
  bool _isDetecting = false;
  bool _locationDetected = false;

  @override
  void initState() {
    super.initState();
    if (widget.preFilledData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _preFill(widget.preFilledData!);
      });
    }
  }

  void _preFill(Map<String, dynamic> data) {
    setState(() {
      if (data['addressLine1'] != null) _houseController.text = data['addressLine1'] as String;
      if (data['city'] != null) _cityController.text = data['city'] as String;
      if (data['state'] != null) _stateController.text = data['state'] as String;
      if (data['pincode'] != null) _pincodeController.text = data['pincode'] as String;
      if (data['latitude'] != null) _latitude = data['latitude'] as String;
      if (data['longitude'] != null) _longitude = data['longitude'] as String;
      if (data['tag'] != null) _selectedTag = data['tag'] as String;
      if (data['isDefault'] == true) _isDefault = true;
      _locationDetected = _latitude != null && _longitude != null;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.pop(),
        ),
        title:  Text(
          AppLocalizations.of(context).addressAddTitle,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 8),

            // Location buttons section
            _buildLocationSection(),

            const SizedBox(height: 8),

            // Detected location info (if available)
            if (_locationDetected) _buildDetectedInfo(),

            // Address form
            _buildFormSection(),

            const SizedBox(height: 80), // Space for bottom button
          ],
        ),
      ),
      // Save button — fixed at bottom
      bottomNavigationBar: _buildSaveButton(),
    );
  }

  /// Location section — Use Current Location + Pick on Map + Search
  Widget _buildLocationSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(14),
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
      child: Column(
        children: [
          // Use Current Location
          _buildLocationButton(
            icon: Icons.my_location_rounded,
            label: 'Use Current Location',
            sublabel: 'Detect your location via GPS',
            color: AppTheme.primaryGreen,
            isLoading: _isDetecting,
            onTap: _detectCurrentLocation,
          ),
          const Divider(height: 20),
          // Pick on Map
          _buildLocationButton(
            icon: Icons.map_rounded,
            label: 'Pick on Map',
            sublabel: 'Choose location from map',
            color: const Color(0xFF1565C0),
            onTap: _pickOnMap,
          ),
          const Divider(height: 20),
          // Search Address
          _buildLocationButton(
            icon: Icons.search_rounded,
            label: 'Search Address',
            sublabel: 'Search by area, street, sector',
            color: const Color(0xFFF57C00),
            onTap: () => context.push('/address/search'),
          ),
        ],
      ),
    );
  }

  /// Single location button row
  Widget _buildLocationButton({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(color)),
                  )
                : Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
                Text(sublabel, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
        ],
      ),
    );
  }

  /// Detected location info card
  Widget _buildDetectedInfo() {
    final city = _cityController.text;
    final state = _stateController.text;
    final pincode = _pincodeController.text;
    final display = [city, state, pincode].where((s) => s.isNotEmpty).join(', ');

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Location detected: $display',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Form section — all input fields in a card
  Widget _buildFormSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(16),
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
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.home_rounded, color: AppTheme.primaryGreen, size: 16),
                ),
                const SizedBox(width: 8),
                 Text(AppLocalizations.of(context).addressDetails, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 16),

            // House / Flat No (required)
            _buildField(controller: _houseController, label: 'House / Flat No *', required: true),
            const SizedBox(height: 12),

            // Floor (optional)
            _buildField(controller: _floorController, label: 'Floor (optional)'),
            const SizedBox(height: 12),

            // Street / Road (required)
            _buildField(controller: _streetController, label: 'Street / Road *', required: true),
            const SizedBox(height: 12),

            // Landmark (optional)
            _buildField(controller: _landmarkController, label: 'Landmark (optional)'),
            const SizedBox(height: 20),

            // Location section header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.location_on_rounded, color: Color(0xFF1565C0), size: 16),
                ),
                const SizedBox(width: 8),
                 Text(AppLocalizations.of(context).addressLocation, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 16),

            // City + State row
            Row(
              children: [
                Expanded(child: _buildField(controller: _cityController, label: 'City *', required: true)),
                const SizedBox(width: 12),
                Expanded(child: _buildField(controller: _stateController, label: 'State *', required: true)),
              ],
            ),
            const SizedBox(height: 12),

            // Pincode
            _buildField(
              controller: _pincodeController,
              label: 'Pincode *',
              required: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            ),
            const SizedBox(height: 20),

            // Tag selector — Home / Office / Other
             Text(AppLocalizations.of(context).addressSaveAs, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildTag('home', Icons.home_rounded, 'Home'),
                const SizedBox(width: 10),
                _buildTag('office', Icons.business_rounded, 'Office'),
                const SizedBox(width: 10),
                _buildTag('other', Icons.location_on_rounded, 'Other'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Styled input field
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    bool required = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
      decoration: InputDecoration(
        hintText: label,
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  /// Tag chip (Home / Office / Other)
  Widget _buildTag(String value, IconData icon, String label) {
    final isSelected = _selectedTag == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedTag = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : const Color(0xFFE0E0E0),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.grey[700])),
          ],
        ),
      ),
    );
  }

  /// Save button — fixed at bottom
  Widget _buildSaveButton() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, -2)),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: AppTheme.primaryGreen.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _isSaving ? null : _saveAddress,
                child: Center(
                  child: _isSaving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                      :  Text(AppLocalizations.of(context).addressSave, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════

  /// Detect current GPS location
  Future<void> _detectCurrentLocation() async {
    setState(() => _isDetecting = true);

    final locationProvider = Provider.of<LocationProvider>(context, listen: false);

    if (!locationProvider.isPermissionGranted) {
      final granted = await locationProvider.requestPermission();
      if (!granted) {
        setState(() => _isDetecting = false);
        if (locationProvider.isPermissionPermanentlyDenied && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text(AppLocalizations.of(context).locationEnableInSettings), backgroundColor: Colors.orange),
          );
          await locationProvider.openAppSettings();
        }
        return;
      }
    }

    locationProvider.reset();
    await locationProvider.detectLocation();

    if (!mounted) return;

    final partial = locationProvider.detectedAddress;
    if (partial != null) {
      setState(() {
        _latitude = partial.latitude.toString();
        _longitude = partial.longitude.toString();
        if (partial.city != null) _cityController.text = partial.city!;
        if (partial.state != null) _stateController.text = partial.state!;
        if (partial.pincode != null) _pincodeController.text = partial.pincode!;
        if (partial.area != null && _streetController.text.isEmpty) {
          _streetController.text = partial.area!;
        }
        _locationDetected = true;
        _isDetecting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(AppLocalizations.of(context).locationDetectedFillDetails), backgroundColor: AppTheme.primaryGreen, duration: Duration(seconds: 2)),
      );
    } else {
      setState(() => _isDetecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(AppLocalizations.of(context).locationCouldNotDetect), backgroundColor: Colors.orange),
        );
      }
    }
  }

  /// Open map picker
  Future<void> _pickOnMap() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => MapAddressPickerScreen(
          onLocationSelected: (lat, lng, address) {},
        ),
      ),
    );

    if (result != null && mounted) {
      final lat = result['latitude'];
      final lng = result['longitude'];

      setState(() {
        _latitude = lat is double ? lat.toString() : lat?.toString();
        _longitude = lng is double ? lng.toString() : lng?.toString();

        final addressLine1 = result['addressLine1'] as String?;
        final addressLine2 = result['addressLine2'] as String?;
        final city = result['city'] as String?;
        final state = result['state'] as String?;
        final pincode = result['pincode'] as String?;

        if (addressLine1 != null && addressLine1.isNotEmpty && _houseController.text.isEmpty) {
          _houseController.text = addressLine1;
        }
        if (addressLine2 != null && addressLine2.isNotEmpty && _streetController.text.isEmpty) {
          _streetController.text = addressLine2;
        }
        if (city != null && city.isNotEmpty) _cityController.text = city;
        if (state != null && state.isNotEmpty) _stateController.text = state;
        if (pincode != null && pincode.isNotEmpty) _pincodeController.text = pincode;
        _locationDetected = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(AppLocalizations.of(context).locationSelectedFillDetails), backgroundColor: AppTheme.primaryGreen, duration: Duration(seconds: 2)),
      );
    }
  }

  /// Save address with service check + token refresh
  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(AppLocalizations.of(context).locationSelectFirst), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final addressProvider = Provider.of<AddressProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final serviceAreaProvider = Provider.of<ServiceAreaProvider>(context, listen: false);

    // Service area check — prefer GPS coordinates (radius check); pincode fallback.
    final svcLat = double.tryParse(_latitude ?? '');
    final svcLng = double.tryParse(_longitude ?? '');
    final pincode = _pincodeController.text.trim().replaceAll(' ', '');
    if ((svcLat != null && svcLng != null) || pincode.isNotEmpty) {
      final isAvailable = await serviceAreaProvider.checkServiceAvailability(
        latitude: svcLat,
        longitude: svcLng,
        pincode: pincode,
        country: 'India',
      );
      if (!isAvailable) {
        setState(() => _isSaving = false);
        if (mounted) {
          context.push('/service-not-available', extra: {
            'pincode': pincode,
            'city': _cityController.text.trim(),
            'state': _stateController.text.trim(),
          });
        }
        return;
      }
    }

    String? token = authProvider.accessToken ?? authProvider.token;
    if (token == null) {
      setState(() => _isSaving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text(AppLocalizations.of(context).commonLoginFirst)));
      return;
    }

    // Build addressLine1 from house + floor
    String addressLine1 = _houseController.text.trim();
    final floor = _floorController.text.trim();
    if (floor.isNotEmpty) addressLine1 = '$addressLine1, Floor $floor';

    bool success = false;
    try {
      // Save via OrderProvider (backward compatible)
      success = await orderProvider.createAddress(
        token: token,
        addressLine1: addressLine1,
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

      // Also save via AddressProvider (new flow)
      if (success) {
        await addressProvider.fetchAddresses(token);
      }
    } catch (e) {
      final err = e.toString();
      if (err.contains('Invalid token') || err.contains('Authentication required') || err.contains('TokenExpiredException')) {
        // Token expired — refresh and retry
        if (authProvider.refreshToken != null) {
          try {
            final refreshed = await authProvider.refreshAccessToken();
            if (refreshed && mounted) {
              final newToken = authProvider.accessToken ?? authProvider.token;
              if (newToken != null) {
                success = await orderProvider.createAddress(
                  token: newToken,
                  addressLine1: addressLine1,
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
                if (success) await addressProvider.fetchAddresses(newToken);
              }
            }
          } catch (_) {
            // Refresh failed
          }
        }
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text(AppLocalizations.of(context).commonSessionExpired), backgroundColor: Colors.orange),
          );
        }
      }
    }

    setState(() => _isSaving = false);

    if (success && mounted) {
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
          content: Row(children: [Icon(Icons.check_circle, color: Colors.white), SizedBox(width: 8), Text(AppLocalizations.of(context).addressSaved)]),
          backgroundColor: AppTheme.primaryGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(orderProvider.error ?? 'Failed to save address'), backgroundColor: Colors.red),
      );
    }
  }
}
