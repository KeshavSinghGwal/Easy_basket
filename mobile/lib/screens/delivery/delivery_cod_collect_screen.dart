import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../providers/delivery_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/order_model.dart';
import '../../utils/theme.dart';

/// COD Collection Screen
///
/// Shown when an order is `arrived` or `payment_pending` and `paymentMethod=cash`.
/// Big, low-cognitive-load UI:
///   - HUGE collect-amount up top (rider can read at arm's length)
///   - 6-digit OTP boxes (auto-advance, paste-friendly)
///   - One green "Payment Collected" button (primary action)
///   - Two secondary buttons: "Switch to UPI", "Report a Problem"
///
/// On success, transitions order to `delivered` and credits the rider's wallet.
class DeliveryCodCollectScreen extends StatefulWidget {
  final int orderId;

  const DeliveryCodCollectScreen({super.key, required this.orderId});

  @override
  State<DeliveryCodCollectScreen> createState() => _DeliveryCodCollectScreenState();
}

class _DeliveryCodCollectScreenState extends State<DeliveryCodCollectScreen>
    with SingleTickerProviderStateMixin {
  OrderModel? _order;
  bool _isLoadingOrder = true;
  bool _isSubmitting = false;

  // Success-view state. Once true, the form disappears, success view shows
  // for 3s, then we go(/delivery/dashboard) — go() replaces the stack so the
  // rider can't navigate back into the OTP form to re-submit and double-credit.
  bool _isCompleted = false;
  double _completedAmount = 0;
  late final AnimationController _checkController;
  late final Animation<double> _checkScale;

  // 6 single-digit boxes — easier to type with one thumb than a 6-char field.
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _checkScale = CurvedAnimation(parent: _checkController, curve: Curves.elasticOut);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOrder());
  }

  @override
  void dispose() {
    _checkController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final n in _otpFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOrder() async {
    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) return;
    final order = await Provider.of<DeliveryProvider>(context, listen: false)
        .getOrderDetails(widget.orderId, token: token);
    if (!mounted) return;
    setState(() {
      _order = order;
      _isLoadingOrder = false;
    });
  }

  String get _enteredOtp => _otpControllers.map((c) => c.text).join();

  Future<void> _callCustomer() async {
    final phone = _order?.user.phoneNumber;
    if (phone == null || phone.isEmpty) return;
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _submitCash() async {
    final order = _order;
    if (order == null) return;

    final otp = _enteredOtp;
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit OTP from the customer')),
      );
      return;
    }

    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) return;

    setState(() => _isSubmitting = true);
    try {
      // Branch on whether cash must still be collected: unpaid COD goes through
      // collect-cash (verifies amount, credits wallet); prepaid AND already-paid-COD
      // (paid online at the door) go through mark-prepaid-delivered (just OTP gate).
      if (order.needsCashCollection) {
        await Provider.of<DeliveryProvider>(context, listen: false).collectCash(
          token: token,
          orderId: order.id,
          amountPaise: (order.totalAmount * 100).round(),
          otp: otp,
        );
      } else {
        await Provider.of<DeliveryProvider>(context, listen: false).markPrepaidDelivered(
          token: token,
          orderId: order.id,
          otp: otp,
        );
      }
      if (!mounted) return;
      // Take over the screen with a success view so the rider can't tap the
      // button twice. After 3s we go() to the dashboard — go() replaces the
      // stack so back-button can't return here.
      setState(() {
        _isCompleted = true;
        _completedAmount = order.totalAmount;
        _isSubmitting = false;
      });
      _checkController.forward();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) context.go('/delivery/dashboard');
      });
      return;
    } catch (e) {
      if (!mounted) return;
      // Clear the OTP on failure so the rider doesn't accidentally retry the same wrong code.
      for (final c in _otpControllers) {
        c.clear();
      }
      _otpFocusNodes.first.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _switchToUpi() async {
    final order = _order;
    if (order == null) return;
    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await Provider.of<DeliveryProvider>(context, listen: false)
          .switchToUpi(token: token, orderId: order.id);
      if (!mounted) return;
      final rzpOrderId = result['razorpayOrderId'] as String?;
      // Show a small dialog the rider can let the customer scan / read aloud.
      // Real Razorpay SDK launch happens on the CUSTOMER's device, not rider's —
      // this dialog tells the rider "wait for the customer to pay".
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('UPI payment requested'),
          content: Text(
            'Razorpay order ID:\n$rzpOrderId\n\n'
            'Ask the customer to complete payment in their app. '
            'Once captured, the order will auto-deliver.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _reportIssue() async {
    final order = _order;
    if (order == null) return;
    final reasons = const [
      ('not_reachable', 'Customer not reachable', Icons.phone_disabled),
      ('customer_refused', 'Customer refused order', Icons.cancel_outlined),
      ('wrong_address', 'Wrong / unreachable address', Icons.wrong_location),
      ('damaged', 'Items damaged in transit', Icons.broken_image_outlined),
      ('other', 'Other', Icons.more_horiz),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text('What happened?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final r in reasons)
              ListTile(
                leading: Icon(r.$3),
                title: Text(r.$2),
                onTap: () => Navigator.pop(sheetCtx, r.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;

    final token = Provider.of<AuthProvider>(context, listen: false).accessToken;
    if (token == null) return;
    try {
      final result = await Provider.of<DeliveryProvider>(context, listen: false)
          .reportIssue(token: token, orderId: order.id, reason: selected);
      if (!mounted) return;
      final next = result['nextAction'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next == 'return_to_hub'
              ? 'Issue logged — return the order to the hub.'
              : 'Issue logged — try again later.'),
        ),
      );
      if (context.canPop()) context.pop(false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCompleted) {
      // Form is gone, OTP boxes unreachable, amount + auto-redirect visible.
      // PopScope blocks back-button so rider can't bounce back to the form.
      return PopScope(
        canPop: false,
        child: _buildSuccessView(),
      );
    }
    if (_isLoadingOrder) {
      return Scaffold(
        appBar: AppBar(title: const Text('Collect Cash')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final order = _order;
    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Collect Cash')),
        body: const Center(child: Text('Order not found')),
      );
    }

    final amountStr = NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(order.totalAmount);
    // Theme: red when cash must be collected, green for verify-only (prepaid or
    // COD already paid online at the door).
    final bool isCod = order.needsCashCollection;
    final accent = isCod ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32);
    final accentTint = isCod ? const Color(0xFFFFF5F5) : const Color(0xFFF1F8E9);
    final accentLight = isCod ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9);

    return Scaffold(
      backgroundColor: accentTint,
      appBar: AppBar(
        title: Text('Order #${order.id}'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Customer + call shortcut
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: accentLight,
                    foregroundColor: accent,
                    child: Text(
                      (order.user.name ?? '#').characters.first.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.user.name ?? 'Customer',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        Text(order.user.phoneNumber,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _callCustomer,
                    icon: const Icon(Icons.call),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Headline callout — COD shows "COLLECT ₹X", prepaid shows "PREPAID — verify OTP"
              Container(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      isCod ? 'COLLECT' : 'PREPAID — VERIFY',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isCod ? amountStr : 'OTP CHECK',
                      style: TextStyle(
                        fontSize: isCod ? 56 : 38,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isCod
                          ? 'in cash from ${order.user.name ?? 'customer'}'
                          : 'Order is paid online ($amountStr) — confirm with OTP',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // OTP entry
              const Text(
                'Customer\'s 6-digit OTP',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Ask them to read aloud the OTP from their notification',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _otpBox(i)),
              ),
              const SizedBox(height: 28),

              // Primary action — label changes based on payment method.
              SizedBox(
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitCash,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(
                          isCod ? Icons.payments_outlined : Icons.check_circle_outline,
                          size: 24),
                  label: Text(
                    _isSubmitting
                        ? 'Verifying…'
                        : (isCod ? 'Payment Collected' : 'Mark Delivered'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Secondary actions: "Switch to UPI" only relevant for COD
              // (prepaid is already paid online — no fallback needed).
              Row(
                children: [
                  if (isCod) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSubmitting ? null : _switchToUpi,
                        icon: const Icon(Icons.qr_code_scanner, size: 20),
                        label: const Text('Switch to UPI'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting ? null : _reportIssue,
                      icon: const Icon(Icons.error_outline, size: 20),
                      label: const Text('Problem'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Full-screen success takeover shown for ~3s after a successful collection.
  /// Mirrors the customer-side "Order Placed!" pattern so it feels familiar.
  Widget _buildSuccessView() {
    final amountStr =
        NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(_completedAmount);
    final wasCod = _order?.isCod ?? true;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _checkScale,
                  child: const Icon(
                    Icons.check_circle_rounded,
                    size: 96,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Delivery Completed',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  wasCod ? '$amountStr collected in cash' : 'Order delivered ($amountStr prepaid)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  wasCod ? 'Wallet has been credited' : 'Customer has received the order',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
                const SizedBox(height: 28),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Returning to dashboard…',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _otpBox(int index) {
    return SizedBox(
      width: 44,
      height: 56,
      child: TextField(
        controller: _otpControllers[index],
        focusNode: _otpFocusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        autofocus: index == 0,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 2),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _otpFocusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _otpFocusNodes[index - 1].requestFocus();
          }
          if (index == 5 && value.isNotEmpty && _enteredOtp.length == 6) {
            // Auto-submit when last digit entered? Risky — rider might want to
            // double-check. Keep submit explicit. Just unfocus the keyboard.
            FocusScope.of(context).unfocus();
          }
          setState(() {});
        },
      ),
    );
  }
}
