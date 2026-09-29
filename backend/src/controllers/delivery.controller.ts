import { AppDataSource } from '../config/database';
import { AuthRequest } from '../middleware/auth.middleware';
import { FCMService } from '../services/fcm.service';
import { Order } from '../entities/Order';
import { User } from '../entities/User';
import { IsNull } from 'typeorm';
import { Response } from 'express';
import { DeliveryStateService } from '../services/delivery-state.service';
import { RiderWalletService } from '../services/rider-wallet.service';
import { RiderProfile } from '../entities/RiderProfile';

export class DeliveryController {
  static async getAssignedOrders(req: AuthRequest, res: Response): Promise<void> {
    try {
      const deliveryBoyId = req.user?.id;

      if (!deliveryBoyId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      const { status } = req.query;
      const orderRepository = AppDataSource.getRepository(Order);
      const queryBuilder = orderRepository
        .createQueryBuilder('order')
        .leftJoinAndSelect('order.user', 'user')
        .leftJoinAndSelect('order.items', 'items')
        .leftJoinAndSelect('items.product', 'product')
        .leftJoinAndSelect('items.variant', 'variant')
        .leftJoinAndSelect('order.deliveryAddress', 'deliveryAddress')
        .leftJoinAndSelect('order.deliveryBoy', 'deliveryBoy')
        .where('order.deliveryBoyId = :deliveryBoyId', { deliveryBoyId })
        .orderBy('order.createdAt', 'DESC');

      if (status) {
        queryBuilder.andWhere('order.status = :status', { status });
      }

      const orders = await queryBuilder.getMany();
      console.log(`✅ Delivery agent ${deliveryBoyId} has ${orders.length} assigned orders`);
      if (orders.length > 0) {
        console.log(`   Orders: ${orders.map((o) => `#${o.id} (${o.status})`).join(', ')}`);
      }
      res.json(orders);
    } catch (error) {
      console.error('❌ Error fetching assigned orders:', error);
      res.status(500).json({ message: 'Error fetching orders' });
    }
  }

  static async updateOrderStatus(req: AuthRequest, res: Response): Promise<void> {
    try {
      const deliveryBoyId = req.user?.id;
      const { id } = req.params;
      const { status } = req.body;

      if (!deliveryBoyId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      if (!status) {
        res.status(400).json({ message: 'Status is required' });
        return;
      }

      // Allow delivery agents to update status: accepted -> preparing -> out_for_delivery -> delivered
      const validStatuses = ['accepted', 'preparing', 'out_for_delivery', 'delivered'];
      if (!validStatuses.includes(status)) {
        res.status(400).json({
          message: 'Invalid status. Allowed: accepted, preparing, out_for_delivery, delivered',
        });
        return;
      }

      const orderRepository = AppDataSource.getRepository(Order);
      const order = await orderRepository.findOne({
        where: { id: Number(id), deliveryBoy: { id: deliveryBoyId } },
        relations: ['user'],
      });

      if (!order) {
        res.status(404).json({ message: 'Order not found or not assigned to you' });
        return;
      }

      order.status = status;
      await orderRepository.save(order);

      // Notify customer
      if (order.user.fcmToken) {
        let notificationTitle = 'Order Update';
        let notificationBody = `Your order #${order.id} status: ${status}`;

        if (status === 'preparing') {
          notificationTitle = '📦 Packing Your Order';
          notificationBody = `Your order #${order.id} is being carefully packed 📦 Sit tight, almost ready!`;
        } else if (status === 'out_for_delivery') {
          notificationTitle = '🚚 On The Way!';
          notificationBody = `Your order #${order.id} is on its way! 🚚 Our delivery partner is heading to you`;
        } else if (status === 'delivered') {
          notificationTitle = '🎉 Delivered!';
          notificationBody = `Your order #${order.id} has been delivered! 🎉 Enjoy your fresh groceries. Thank you for choosing Easy Basket!`;
        }

        const token = order.user.fcmToken;
        const customerId = order.user.id;
        const oid = order.id;
        FCMService.enqueue(
          () =>
            FCMService.sendNotification(
              token,
              notificationTitle,
              notificationBody,
              {
                orderId: oid.toString(),
                status,
                type: 'order_status_update',
              },
              `delivery-status order=#${oid} customerId=${customerId}`,
              customerId
            ),
          `notify customer delivery status #${oid}`
        );
      }

      const oid = order.id;
      FCMService.enqueue(
        () =>
          FCMService.sendNotificationToRole(
            'admin',
            '📦 Order Update',
            `Order #${oid} → ${status} (updated by delivery partner)`,
            { orderId: oid.toString(), status, type: 'order_status_update' }
          ),
        `notify admins delivery status #${oid}`
      );

      res.json(order);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error updating order status' });
    }
  }

  static async getDeliveryStats(req: AuthRequest, res: Response): Promise<void> {
    try {
      const deliveryBoyId = req.user?.id;

      if (!deliveryBoyId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      const orderRepository = AppDataSource.getRepository(Order);

      const [totalDeliveries, pendingDeliveries, todayDeliveries, completedDeliveries] =
        await Promise.all([
          orderRepository.count({ where: { deliveryBoy: { id: deliveryBoyId } } }),
          orderRepository.count({
            where: { deliveryBoy: { id: deliveryBoyId }, status: 'out_for_delivery' },
          }),
          orderRepository
            .createQueryBuilder('order')
            .where('order.deliveryBoyId = :deliveryBoyId', { deliveryBoyId })
            .andWhere('DATE(order.createdAt) = CURDATE()')
            .getCount(),
          orderRepository.count({
            where: { deliveryBoy: { id: deliveryBoyId }, status: 'delivered' },
          }),
        ]);

      res.json({
        total: totalDeliveries,
        pending: pendingDeliveries,
        today: todayDeliveries,
        completed: completedDeliveries,
      });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching delivery stats' });
    }
  }

  static async getOrderDetails(req: AuthRequest, res: Response): Promise<void> {
    try {
      const deliveryBoyId = req.user?.id;
      const { id } = req.params;

      if (!deliveryBoyId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      const orderRepository = AppDataSource.getRepository(Order);
      const order = await orderRepository.findOne({
        where: { id: Number(id), deliveryBoy: { id: deliveryBoyId } },
        relations: ['user', 'deliveryAddress', 'items', 'items.product', 'deliveryBoy'],
      });

      if (!order) {
        res.status(404).json({ message: 'Order not found or not assigned to you' });
        return;
      }

      res.json(order);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching order details' });
    }
  }

  // Get available orders (accepted/preparing without delivery boy assigned)
  static async getAvailableOrders(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { status } = req.query;
      const orderRepository = AppDataSource.getRepository(Order);
      const queryBuilder = orderRepository
        .createQueryBuilder('order')
        .leftJoinAndSelect('order.user', 'user')
        .leftJoinAndSelect('order.items', 'items')
        .leftJoinAndSelect('items.product', 'product')
        .leftJoinAndSelect('order.deliveryAddress', 'deliveryAddress')
        .where('order.deliveryBoyId IS NULL')
        .andWhere('order.status IN (:...statuses)', { statuses: ['accepted', 'preparing'] })
        .orderBy('order.createdAt', 'DESC');

      if (status) {
        queryBuilder.andWhere('order.status = :status', { status });
      }

      const orders = await queryBuilder.getMany();
      res.json(orders);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching available orders' });
    }
  }

  // Accept/claim an available order
  static async acceptOrder(req: AuthRequest, res: Response): Promise<void> {
    try {
      const deliveryBoyId = req.user?.id;
      const { id } = req.params;

      if (!deliveryBoyId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      const orderRepository = AppDataSource.getRepository(Order);
      const order = await orderRepository.findOne({
        where: {
          id: Number(id),
          deliveryBoy: IsNull(), // Only unassigned orders
          status: 'accepted', // Only accepted orders can be claimed
        },
        relations: ['user', 'deliveryBoy'],
      });

      if (!order) {
        res.status(404).json({ message: 'Order not found or already assigned' });
        return;
      }

      // Assign order to delivery boy
      const userRepository = AppDataSource.getRepository(User);
      const deliveryBoy = await userRepository.findOneBy({ id: deliveryBoyId, role: 'delivery' });

      if (!deliveryBoy) {
        res.status(404).json({ message: 'Delivery boy not found' });
        return;
      }

      order.deliveryBoy = deliveryBoy;
      await orderRepository.save(order);

      if (order.user.fcmToken) {
        const token = order.user.fcmToken;
        const customerId = order.user.id;
        const oid = order.id;
        FCMService.enqueue(
          () =>
            FCMService.sendNotification(
              token,
              'Order Assigned',
              `Order #${oid} has been assigned to a delivery agent`,
              { orderId: oid.toString(), type: 'order_assigned' },
              `delivery-claim customerId=${customerId} order=#${oid}`,
              customerId
            ),
          `notify customer order assigned #${oid}`
        );
      }

      const oid = order.id;
      FCMService.enqueue(
        () =>
          FCMService.sendNotificationToRole(
            'admin',
            'Order Accepted by Delivery Agent',
            `Order #${oid} has been accepted by delivery agent`,
            { orderId: oid.toString(), type: 'order_accepted_by_delivery' }
          ),
        `notify admins delivery accepted #${oid}`
      );

      res.json(order);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error accepting order' });
    }
  }

  static async getEarnings(req: AuthRequest, res: Response): Promise<void> {
    try {
      const deliveryBoyId = req.user?.id;

      if (!deliveryBoyId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      const { period } = req.query; // today, week, month, all
      const orderRepository = AppDataSource.getRepository(Order);

      let queryBuilder = orderRepository
        .createQueryBuilder('order')
        .where('order.deliveryBoyId = :deliveryBoyId', { deliveryBoyId })
        .andWhere('order.status = :status', { status: 'delivered' });

      const now = new Date();
      if (period === 'today') {
        queryBuilder.andWhere('DATE(order.updatedAt) = CURDATE()');
      } else if (period === 'week') {
        const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
        queryBuilder.andWhere('order.updatedAt >= :weekAgo', { weekAgo });
      } else if (period === 'month') {
        const monthAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
        queryBuilder.andWhere('order.updatedAt >= :monthAgo', { monthAgo });
      }

      const deliveredOrders = await queryBuilder.getMany();

      // Calculate earnings (assuming ₹20 per delivery or 5% commission)
      const totalDeliveries = deliveredOrders.length;
      const earningsPerDelivery = 20; // Fixed amount per delivery
      const totalEarnings = totalDeliveries * earningsPerDelivery;

      // Get today's earnings
      const todayOrders = deliveredOrders.filter(
        (order) => new Date(order.updatedAt).toDateString() === now.toDateString()
      );
      const todayEarnings = todayOrders.length * earningsPerDelivery;

      res.json({
        totalEarnings,
        todayEarnings,
        totalDeliveries,
        todayDeliveries: todayOrders.length,
        earningsPerDelivery,
        period: period || 'all',
      });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching earnings' });
    }
  }

  // =========================================================================
  // Phase 1 additions — state-machine-driven endpoints
  // =========================================================================

  static async setAvailability(req: AuthRequest, res: Response): Promise<void> {
    try {
      const riderId = req.user?.id;
      if (!riderId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }
      const { availability } = req.body as {
        availability?: 'offline' | 'idle' | 'busy';
      };
      if (availability !== 'offline' && availability !== 'idle' && availability !== 'busy') {
        res.status(400).json({ message: "availability must be 'offline'|'idle'|'busy'" });
        return;
      }

      const repo = AppDataSource.getRepository(RiderProfile);
      let profile = await repo.findOne({ where: { userId: riderId } });
      if (!profile) {
        profile = repo.create({ userId: riderId, availability });
      } else {
        profile.availability = availability;
      }
      profile.lastSeenAt = new Date();
      await repo.save(profile);
      res.json({ availability: profile.availability, lastSeenAt: profile.lastSeenAt });
    } catch (error) {
      console.error('[delivery] setAvailability error', error);
      res.status(500).json({ message: 'Error updating availability' });
    }
  }

  static async updateLocation(req: AuthRequest, res: Response): Promise<void> {
    try {
      const riderId = req.user?.id;
      if (!riderId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }
      const { lat, lng } = req.body as { lat?: number; lng?: number };
      if (typeof lat !== 'number' || typeof lng !== 'number') {
        res.status(400).json({ message: 'lat and lng (numbers) are required' });
        return;
      }
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        res.status(400).json({ message: 'lat/lng out of range' });
        return;
      }

      const repo = AppDataSource.getRepository(RiderProfile);
      let profile = await repo.findOne({ where: { userId: riderId } });
      if (!profile) {
        profile = repo.create({ userId: riderId, availability: 'idle' });
      }
      profile.currentLat = lat.toFixed(7);
      profile.currentLng = lng.toFixed(7);
      profile.lastSeenAt = new Date();
      await repo.save(profile);
      res.json({ ok: true });
    } catch (error) {
      console.error('[delivery] updateLocation error', error);
      res.status(500).json({ message: 'Error updating location' });
    }
  }

  static async arrivedAtStore(req: AuthRequest, res: Response): Promise<void> {
    await respond(req, res, (orderId, riderId) =>
      DeliveryStateService.arrivedAtStore(orderId, riderId)
    );
  }

  static async picked(req: AuthRequest, res: Response): Promise<void> {
    await respond(req, res, (orderId, riderId) =>
      DeliveryStateService.picked(orderId, riderId)
    );
  }

  static async startDelivery(req: AuthRequest, res: Response): Promise<void> {
    try {
      const riderId = req.user?.id;
      if (!riderId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }
      const orderId = Number(req.params.id);
      if (!Number.isFinite(orderId)) {
        res.status(400).json({ message: 'Invalid order id' });
        return;
      }
      const result = await DeliveryStateService.startDelivery(orderId, riderId);
      if (!result.ok) {
        res.status(result.code).json({ message: result.reason });
        return;
      }
      // OTP is sent via Twilio SMS; nothing useful to return to the rider here.
      res.json({ deliveryStatus: result.order.deliveryStatus });
    } catch (error) {
      console.error('[delivery] startDelivery error', error);
      res.status(500).json({ message: 'Error starting delivery' });
    }
  }

  static async arrived(req: AuthRequest, res: Response): Promise<void> {
    try {
      const riderId = req.user?.id;
      if (!riderId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }
      const orderId = Number(req.params.id);
      if (!Number.isFinite(orderId)) {
        res.status(400).json({ message: 'Invalid order id' });
        return;
      }
      const { lat, lng } = req.body as { lat?: number; lng?: number };
      const loc =
        typeof lat === 'number' && typeof lng === 'number' ? { lat, lng } : undefined;
      const result = await DeliveryStateService.arrived(orderId, riderId, loc);
      if (!result.ok) {
        res.status(result.code).json({ message: result.reason });
        return;
      }
      res.json({
        deliveryStatus: result.order.deliveryStatus,
        paymentMethod: result.order.paymentMethod,
        amountDuePaise: Math.round(Number(result.order.totalAmount) * 100),
      });
    } catch (error) {
      console.error('[delivery] arrived error', error);
      res.status(500).json({ message: 'Error marking arrived' });
    }
  }

  static async collectCash(req: AuthRequest, res: Response): Promise<void> {
    try {
      const riderId = req.user?.id;
      if (!riderId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }
      const orderId = Number(req.params.id);
      if (!Number.isFinite(orderId)) {
        res.status(400).json({ message: 'Invalid order id' });
        return;
      }
      const { amountPaise, otp, lat, lng } = req.body as {
        amountPaise?: number;
        otp?: string;
        lat?: number;
        lng?: number;
      };
      if (typeof amountPaise !== 'number' || !otp) {
        res.status(400).json({ message: 'amountPaise (number) and otp are required' });
        return;
      }
      const gps = typeof lat === 'number' && typeof lng === 'number' ? { lat, lng } : undefined;
      const result = await DeliveryStateService.collectCash({
        orderId,
        riderId,
        amountPaise,
        otp,
        gps,
      });
      if (!result.ok) {
        res.status(result.code).json({ message: result.reason });
        return;
      }

      const wallet = await RiderWalletService.getWallet(riderId);
      res.json({
        deliveryStatus: result.order.deliveryStatus,
        cashCollectedPaise: Number(result.order.cashCollectedPaise ?? 0),
        wallet: {
          cashInHandPaise: Number(wallet.cashInHandPaise),
          lifetimeCollectedPaise: Number(wallet.lifetimeCollectedPaise),
        },
      });
    } catch (error) {
      console.error('[delivery] collectCash error', error);
      res.status(500).json({ message: 'Error collecting cash' });
    }
  }

  static async markPrepaidDelivered(req: AuthRequest, res: Response): Promise<void> {
    try {
      const riderId = req.user?.id;
      if (!riderId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }
      const orderId = Number(req.params.id);
      if (!Number.isFinite(orderId)) {
        res.status(400).json({ message: 'Invalid order id' });
        return;
      }
      const { otp, lat, lng } = req.body as {
        otp?: string;
        lat?: number;
        lng?: number;
      };
      if (!otp) {
        res.status(400).json({ message: 'otp is required' });
        return;
      }
      const gps = typeof lat === 'number' && typeof lng === 'number' ? { lat, lng } : undefined;
      const result = await DeliveryStateService.markPrepaidDelivered({
        orderId,
        riderId,
        otp,
        gps,
      });
      if (!result.ok) {
        res.status(result.code).json({ message: result.reason });
        return;
      }
      res.json({ deliveryStatus: result.order.deliveryStatus });
    } catch (error) {
      console.error('[delivery] markPrepaidDelivered error', error);
      res.status(500).json({ message: 'Error marking delivered' });
    }
  }

  static async switchToUpi(req: AuthRequest, res: Response): Promise<void> {
    try {
      const riderId = req.user?.id;
      if (!riderId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }
      const orderId = Number(req.params.id);
      if (!Number.isFinite(orderId)) {
        res.status(400).json({ message: 'Invalid order id' });
        return;
      }
      const result = await DeliveryStateService.switchToUpi(orderId, riderId);
      if (!result.ok) {
        res.status(result.code).json({ message: result.reason });
        return;
      }
      res.json({
        razorpayOrderId: result.razorpayOrderId,
        amountPaise: result.amountPaise,
        key: result.keyId,
      });
    } catch (error) {
      console.error('[delivery] switchToUpi error', error);
      res.status(500).json({ message: 'Error switching to UPI' });
    }
  }

  static async reportIssue(req: AuthRequest, res: Response): Promise<void> {
    try {
      const riderId = req.user?.id;
      if (!riderId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }
      const orderId = Number(req.params.id);
      if (!Number.isFinite(orderId)) {
        res.status(400).json({ message: 'Invalid order id' });
        return;
      }
      const { reason, note } = req.body as { reason?: string; note?: string };
      const validReasons = ['customer_refused', 'not_reachable', 'wrong_address', 'damaged', 'other'];
      if (!reason || !validReasons.includes(reason)) {
        res.status(400).json({ message: `reason must be one of ${validReasons.join(', ')}` });
        return;
      }
      const result = await DeliveryStateService.reportIssue({
        orderId,
        riderId,
        reason: reason as 'customer_refused' | 'not_reachable' | 'wrong_address' | 'damaged' | 'other',
        note,
      });
      if (!result.ok) {
        res.status(result.code).json({ message: result.reason });
        return;
      }
      res.json({
        deliveryStatus: result.order.deliveryStatus,
        attempt: result.attempt,
        nextAction: result.nextAction,
      });
    } catch (error) {
      console.error('[delivery] reportIssue error', error);
      res.status(500).json({ message: 'Error reporting issue' });
    }
  }

  static async getWallet(req: AuthRequest, res: Response): Promise<void> {
    try {
      const riderId = req.user?.id;
      if (!riderId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }
      const wallet = await RiderWalletService.getWallet(riderId);
      res.json({
        cashInHandPaise: Number(wallet.cashInHandPaise),
        lifetimeCollectedPaise: Number(wallet.lifetimeCollectedPaise),
        lifetimeDepositedPaise: Number(wallet.lifetimeDepositedPaise),
        pendingEarningsPaise: Number(wallet.pendingEarningsPaise),
      });
    } catch (error) {
      console.error('[delivery] getWallet error', error);
      res.status(500).json({ message: 'Error fetching wallet' });
    }
  }
}

/** Small helper so state-transition handlers are one-liners. */
async function respond(
  req: AuthRequest,
  res: Response,
  fn: (orderId: number, riderId: number) => Promise<
    | { ok: true; order: Order }
    | { ok: false; reason: string; code: number }
  >
): Promise<void> {
  try {
    const riderId = req.user?.id;
    if (!riderId) {
      res.status(401).json({ message: 'Authentication required' });
      return;
    }
    const orderId = Number(req.params.id);
    if (!Number.isFinite(orderId)) {
      res.status(400).json({ message: 'Invalid order id' });
      return;
    }
    const result = await fn(orderId, riderId);
    if (!result.ok) {
      res.status(result.code).json({ message: result.reason });
      return;
    }
    res.json({ deliveryStatus: result.order.deliveryStatus });
  } catch (error) {
    console.error('[delivery] transition error', error);
    res.status(500).json({ message: 'Error updating delivery status' });
  }
}
