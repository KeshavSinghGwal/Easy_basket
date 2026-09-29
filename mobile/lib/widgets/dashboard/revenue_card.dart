import 'package:flutter/material.dart';
import 'dashboard_theme.dart';

class RevenueCard extends StatelessWidget {
  final String amount;

  const RevenueCard({
    super.key,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xff0F9D58),
            Color(0xff16A34A),
            Color(0xff22C55E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(.25),
            blurRadius: 25,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Icon(
              Icons.currency_rupee,
              size: 120,
              color: Colors.white.withOpacity(.08),
            ),
          ),

          Positioned(
            left: 24,
            top: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Today's Revenue",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  amount,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 42,
                  ),
                ),

                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "No sales yet today",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                )
              ],
            ),
          ),

          Positioned(
            left: 20,
            right: 20,
            bottom: 18,
            child: SizedBox(
              height: 45,
              child: CustomPaint(
                painter: _GraphPainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(.35)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final path = Path();

    path.moveTo(0, size.height * .7);

    path.quadraticBezierTo(
        size.width * .15,
        size.height * .2,
        size.width * .30,
        size.height * .6);

    path.quadraticBezierTo(
        size.width * .45,
        size.height,
        size.width * .60,
        size.height * .45);

    path.quadraticBezierTo(
        size.width * .75,
        size.height * .1,
        size.width,
        size.height * .55);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}