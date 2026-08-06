import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import '../../services/notification_service.dart';

enum PaymentStatus {
  success,
  failed,
  pending,
  orderPlaced,
}

class PaymentStatusScreen extends StatefulWidget {
  final PaymentStatus status;
  final String message;
  final int? orderId;

  const PaymentStatusScreen({
    super.key,
    required this.status,
    required this.message,
    this.orderId,
  });

  @override
  State<PaymentStatusScreen> createState() => _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends State<PaymentStatusScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _showNotificationPrompt = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _controller.forward();

    final isSuccess = widget.status == PaymentStatus.success ||
        widget.status == PaymentStatus.orderPlaced;

    if (!kIsWeb && isSuccess) {
      // Show in-app prompt after animation completes
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _showNotificationPrompt = true);
      });
    } else {
      _scheduleRedirect();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleRedirect() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _navigate();
    });
  }

  void _navigate() {
    final isSuccess = widget.status == PaymentStatus.success ||
        widget.status == PaymentStatus.orderPlaced;
    if (isSuccess && widget.orderId != null) {
      context.go('/order/${widget.orderId}');
    } else {
      context.go('/orders');
    }
  }

  void _onAllow() async {
    await NotificationService().requestNotificationPermission();
    if (mounted) {
      setState(() => _showNotificationPrompt = false);
      _navigate();
    }
  }

  void _onSkip() {
    setState(() => _showNotificationPrompt = false);
    _navigate();
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = widget.status == PaymentStatus.success ||
        widget.status == PaymentStatus.orderPlaced;
    final color =
        isSuccess ? const Color(0xFF2E7D32) : const Color(0xFFE53935);
    final icon = isSuccess ? Icons.check_circle_rounded : Icons.error_rounded;
    final title = isSuccess ? 'Order Placed!' : 'Payment Failed';

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
                  scale: _scaleAnimation,
                  child: Icon(icon, size: 80, color: color),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
                if (_showNotificationPrompt) ...[
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.notifications_active_rounded,
                            size: 36, color: Color(0xFF2E7D32)),
                        const SizedBox(height: 12),
                        const Text(
                          'Stay updated on your order!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Turn on notifications to receive real-time order updates & delivery alerts.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                              height: 1.4),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton(
                            onPressed: _onAllow,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Turn On Notifications',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: _onSkip,
                          child: Text(
                            'Maybe Later',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[400],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
