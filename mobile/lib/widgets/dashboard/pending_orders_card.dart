import 'package:flutter/material.dart';
import '../../models/order_model.dart';
import 'package:go_router/go_router.dart';

class PendingOrdersCard extends StatelessWidget {
  final OrderModel order;

  const PendingOrdersCard({
    super.key,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [

            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.orange.shade100,
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: Colors.orange,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Text(
                    "Order #${order.id}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    order.user.name ?? "Customer",
                  ),

                  const SizedBox(height: 4),

                  Text(
  "₹${order.totalAmount}",
  style: const TextStyle(
    fontWeight: FontWeight.w600,
  ),
),

const SizedBox(height: 6),

Container(
  padding: const EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 4,
  ),
  decoration: BoxDecoration(
    color: order.status == "pending"
        ? Colors.orange.shade100
        : order.status == "accepted"
            ? Colors.blue.shade100
            : Colors.purple.shade100,
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    order.status.toUpperCase().replaceAll('_', ' '),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
    ),
  ),
),

const SizedBox(height: 6),

Container(
  padding: const EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 3,
  ),
  decoration: BoxDecoration(
    color: order.isPaid
        ? Colors.green.shade100
        : Colors.orange.shade100,
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    order.isPaid ? "PAID" : "COD",
  ),
),
                ],
              ),
            ),

            ElevatedButton(
  onPressed: () {
    context.push('/admin/orders/${order.id}');
  },
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.green,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 10,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    ),
  ),
  child: const Text("View"),
),
          ],
        ),
      ),
    );
  }
}