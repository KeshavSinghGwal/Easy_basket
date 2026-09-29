import * as admin from 'firebase-admin';
import { AppDataSource } from '../config/database';
import { AuthRequest, invalidateCachedUser } from '../middleware/auth.middleware';
import { Category } from '../entities/Category';
import { FCMService } from '../services/fcm.service';
import { Order } from '../entities/Order';
import { Product } from '../entities/Product';
import { Response } from 'express';
import { User } from '../entities/User';
import { Brackets, In, Not } from 'typeorm';
import { ProductController } from './product.controller';
import { mapOrderPublic, mapProductPublic, normalizeMediaForStorage } from '../utils/media-url.util';
import { OrderInventoryService } from '../services/order-inventory.service';
import { PaymentsV2Service } from '../services/payments-v2.service';
import { DeliveryStateService } from '../services/delivery-state.service';
import { RiderWalletService } from '../services/rider-wallet.service';
import { OrderEventsService } from '../services/order-events.service';
import { RiderProfile } from '../entities/RiderProfile';
import { RoleChangeAudit } from '../entities/RoleChangeAudit';
import { isUserRole } from '../constants/roles';

export class AdminController {
  static async getAllOrders(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { status } = req.query;
      const page = parseInt(req.query.page as string) || 1;
      const limit = parseInt(req.query.limit as string) || 20;
      const skip = (page - 1) * limit;

      const orderRepository = AppDataSource.getRepository(Order);
      const queryBuilder = orderRepository
        .createQueryBuilder('order')
        .leftJoinAndSelect('order.user', 'user')
        .leftJoinAndSelect('order.items', 'items')
        .leftJoinAndSelect('items.product', 'product')
        .leftJoinAndSelect('items.variant', 'variant')
        .leftJoinAndSelect('order.deliveryAddress', 'deliveryAddress')
        .leftJoinAndSelect('order.deliveryBoy', 'deliveryBoy')
        .orderBy('order.createdAt', 'DESC');

      if (status === 'awaiting_payment') {
        // Explicit opt-in view (D-06). Everything hidden by the default filter
        // below, surfaced deliberately: an unpaid online order still exists, still
        // holds stock, and a customer whose payment is stuck WILL ring up asking
        // where it is. Support needs to be able to find it in one place.
        queryBuilder
          .where('order.status = :pending', { pending: 'pending' })
          .andWhere('(order.paymentMethod IS NOT NULL AND order.paymentMethod != :cod)', {
            cod: 'cod',
          });
      } else if (status) {
        queryBuilder.where('order.status = :status', { status });
      } else {
        // Default list (D-05): hide online orders that have not been paid for.
        //
        // An online order at 'pending' is UNPAID — the customer may still be on the
        // payment sheet, or may have abandoned it entirely. Showing those to the
        // store means acting on orders that may never exist. Once payment is
        // confirmed the order moves to 'awaiting_acceptance' and appears here.
        //
        // COD is exempt: it has no payment to wait for, so a COD order is real the
        // moment it is placed.
        // NOTE the explicit NULL arm. paymentMethod is nullable, and in SQL
        // `NULL = 'cod'` is NULL, not false — so `(status != 'pending' OR
        // paymentMethod = 'cod')` evaluates to NULL for a legacy pending order with
        // no payment method, and the row is dropped. That would silently hide real
        // orders from the store.
        //
        // Unknown method is therefore treated as visible. When in doubt, show the
        // order: an admin can judge it, but nobody can act on what they cannot see.
        queryBuilder.where(
          '(order.status != :pending OR order.paymentMethod IS NULL OR order.paymentMethod = :cod)',
          { pending: 'pending', cod: 'cod' }
        );
      }

      const [orders, total] = await queryBuilder.skip(skip).take(limit).getManyAndCount();

      // One extra query for the whole page (not per order) so the list can flag
      // orders whose refund failed and needs an admin to retry it.
      const refundFlags = await PaymentsV2Service.getRefundFlagsForOrders(
        orders.map((o) => o.id)
      );

      res.json({
        orders: orders.map((o) => ({
          ...mapOrderPublic(o),
          ...(refundFlags.get(o.id) ?? {}),
        })),
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
          hasMore: page * limit < total,
        },
      });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching orders' });
    }
  }

  static async getOrderById(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { id } = req.params;

      const orderRepository = AppDataSource.getRepository(Order);
      const order = await orderRepository.findOne({
        where: { id: Number(id) },
        relations: [
          'user',
          'items',
          'items.product',
          'items.variant',
          'deliveryAddress',
          'deliveryBoy',
        ],
      });

      if (!order) {
        res.status(404).json({ message: 'Order not found' });
        return;
      }

      res.json(mapOrderPublic(order));
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching order' });
    }
  }

  static async updateOrderStatus(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const { status, deliveryBoyId, notes, cancellationReason } = req.body;

      if (!status) {
        res.status(400).json({ message: 'Status is required' });
        return;
      }

      const validStatuses = [
        'pending',
        // Paid, waiting for the store to accept or refuse. Reachable only from a
        // confirmed payment, which is what structurally closes the old hole where an
        // admin could accept an UNPAID order and strand its stock forever.
        'awaiting_acceptance',
        'accepted',
        'preparing',
        'out_for_delivery',
        'delivered',
        'cancelled',
      ];
      if (!validStatuses.includes(status)) {
        res.status(400).json({ message: 'Invalid status' });
        return;
      }

      const orderRepository = AppDataSource.getRepository(Order);
      const order = await orderRepository.findOne({
        where: { id: Number(id) },
        relations: ['user', 'deliveryBoy', 'items', 'items.product', 'items.variant'],
      });

      if (!order) {
        res.status(404).json({ message: 'Order not found' });
        return;
      }

      // Guard (S4): never transition OUT of a terminal state. Moving a cancelled
      // order (stock already restored, refund already issued) to delivered/preparing,
      // or a delivered order back to pending, silently desyncs inventory + refunds.
      if (
        (order.status === 'cancelled' || order.status === 'delivered') &&
        status !== order.status
      ) {
        res
          .status(400)
          .json({ message: `Cannot change a '${order.status}' order to '${status}'.` });
        return;
      }

      // The terminal guard above only stopped an order LEAVING cancelled/delivered.
      // Every other pair was a free-form assignment from the whitelist, so
      // out_for_delivery could be pushed back to pending, re-firing customer
      // notifications and desyncing the delivery state machine (_isForward below
      // protects delivery_status, but nothing protected `status` itself).
      if (status !== order.status) {
        const allowed = ALLOWED_ORDER_TRANSITIONS[order.status] ?? [];
        if (!allowed.includes(status)) {
          res.status(400).json({
            message: `Cannot move an order from '${order.status}' to '${status}'.`,
            code: 'INVALID_STATUS_TRANSITION',
          });
          return;
        }
      }

      // An online order may only be accepted once its payment has landed —
      // which is the whole reason 'awaiting_acceptance' exists. Nothing enforced
      // it, so an admin could accept, pack and dispatch an order that was never
      // paid for.
      //
      // Scoped to paymentMethod === 'upi' rather than !== 'cod' on purpose:
      // paymentMethod is nullable on legacy rows, and blocking those would hide
      // real orders from the store. Same "when in doubt, let the admin act"
      // reasoning getAllOrders applies to its NULL arm.
      if (
        status === 'accepted' &&
        order.paymentMethod === 'upi' &&
        order.paymentStatus !== 'paid'
      ) {
        res.status(409).json({
          message: 'This order has not been paid for yet. Wait for the payment to confirm.',
          code: 'ORDER_NOT_PAID',
        });
        return;
      }

      // Admin-cancel hooks: restore inventory + refund any paid amount.
      // Runs only on the transition INTO 'cancelled', and only once per order
      // (idempotent via status guard + UNIQUE(payment_id, idempotency_key) on refunds).
      let refundInitiated = false;
      if (status === 'cancelled') {
        // Atomic claim: only the request that actually flips the order out of a
        // non-cancelled state runs the restore + refund, so concurrent cancels
        // (admin double-click / customer-approve race) can't double-restore stock.
        const claim = await orderRepository.update(
          { id: order.id, status: Not('cancelled') },
          { status: 'cancelled' }
        );
        if (claim.affected === 1) {
          try {
            await OrderInventoryService.restoreReservedStockForItems(order.items);
          } catch (invErr) {
            console.error(`[admin-cancel] inventory restore failed for order #${order.id}`, invErr);
          }

          if (order.paymentStatus === 'paid') {
            try {
              const result = await PaymentsV2Service.createRefund({
                orderId: order.id,
                userId: order.user.id,
                actorUserId: req.user?.id ?? order.user.id,
                reason: 'admin_cancelled',
                idempotencyKey: `admin-cancel-${order.id}`,
              });
              refundInitiated = result.ok;
              if (!result.ok) {
                console.warn(
                  `[admin-cancel] refund not initiated for order #${order.id}: ${result.reason}`
                );
              }
            } catch (refErr) {
              console.error(`[admin-cancel] refund call failed for order #${order.id}`, refErr);
            }
          }
        }
      }

      // Atomic transition claim.
      //
      // Everything above this point validated against the row as it was READ,
      // and the write below is a plain save(). Order carries no @VersionColumn,
      // so between the findOne and the save the customer can cancel out from
      // under us: the sweep or requestCancellation flips the row to 'cancelled'
      // and restores its stock, then save() writes 'accepted' straight over the
      // top — resurrecting a cancelled order whose inventory has already been
      // given back, i.e. sold twice.
      //
      // The transition matrix above cannot catch this; it only ever saw the
      // stale status. Claiming the transition conditionally is what makes it
      // safe, and it is the same pattern cancelOrder, approveCancellation and
      // OrderAutoCancelService already use.
      //
      // 'cancelled' is excluded because that branch performs its own claim above
      // (and owns the stock restore that follows it).
      if (status !== order.status && status !== 'cancelled') {
        const transitionClaim = await orderRepository.update(
          { id: order.id, status: order.status },
          { status }
        );
        if (transitionClaim.affected !== 1) {
          res.status(409).json({
            message:
              'This order changed while you were viewing it — most likely the customer cancelled it. Refresh and try again.',
            code: 'ORDER_CHANGED',
          });
          return;
        }
      }

      order.status = status;

      if (notes) {
        order.notes = notes;
      }

      // Why the store refused / cancelled. Stored on every cancel, but it is the
      // refusal path (D-12) that makes it matter: without a recorded reason,
      // "the store refuses orders when it feels like it" stays an anecdote instead
      // of a number somebody can be shown. Reuses the existing
      // orders.cancellation_reason column.
      if (status === 'cancelled' && typeof cancellationReason === 'string') {
        order.cancellationReason = cancellationReason.trim().slice(0, 255) || null;
      }

      // Allow assigning delivery boy when accepting, preparing, or out_for_delivery
      const isFirstAssignment =
        deliveryBoyId &&
        order.deliveryBoy?.id !== deliveryBoyId &&
        ['accepted', 'preparing', 'out_for_delivery'].includes(status);

      if (deliveryBoyId && ['accepted', 'preparing', 'out_for_delivery'].includes(status)) {
        const userRepository = AppDataSource.getRepository(User);
        const deliveryBoy = await userRepository.findOneBy({
          id: deliveryBoyId,
          role: 'delivery',
        });

        if (!deliveryBoy) {
          res.status(404).json({ message: 'Delivery boy not found' });
          return;
        }

        order.deliveryBoy = deliveryBoy;

        // Notify delivery boy
        if (deliveryBoy.fcmToken) {
          const token = deliveryBoy.fcmToken;
          const oid = order.id;
          const deliveryUserId = deliveryBoy.id;
          FCMService.enqueue(
            () =>
              FCMService.sendNotification(
                token,
                '📍 New Delivery',
                `New delivery assigned! 📍 Order #${oid} — Pick up now`,
                { orderId: oid.toString(), type: 'order_assigned' },
                `admin-assign-delivery order=#${oid} deliveryUserId=${deliveryUserId}`,
                deliveryUserId
              ),
            `notify delivery boy assignment order #${oid}`
          );
        }
      }

      // ──────────────────────────────────────────────────────────────────────
      // Backfill the new state machine.
      //
      // The legacy admin UI calls this endpoint with status + deliveryBoyId.
      // Without this block, `delivery_status` stays NULL, so the rider's app
      // falls into the legacy button path and never enters the new flow
      // (no OTP, no wallet credit). We mirror legacy status onto delivery_status
      // here so EVERY assignment, legacy or new, transparently gets the state
      // machine + audit log.
      // ──────────────────────────────────────────────────────────────────────
      const fromDeliveryState = order.deliveryStatus;
      let newDeliveryState: typeof order.deliveryStatus = order.deliveryStatus;

      if (isFirstAssignment && !order.deliveryStatus) {
        newDeliveryState = 'assigned';
        order.deliveryAssignedAt = new Date();
      }
      // Map legacy status → state-machine state, but never go backwards.
      const legacyMap: Record<string, typeof order.deliveryStatus> = {
        out_for_delivery: 'out_for_delivery',
        delivered: 'delivered',
      };
      const fwd = legacyMap[status];
      if (fwd && order.deliveryBoy && (newDeliveryState === null || _isForward(newDeliveryState, fwd))) {
        newDeliveryState = fwd;
        if (fwd === 'out_for_delivery' && !order.deliveryPickedAt) order.deliveryPickedAt = new Date();
        if (fwd === 'delivered') order.deliveryCompletedAt = new Date();
      }
      order.deliveryStatus = newDeliveryState;

      // createRefund (admin-cancel path above) already persisted
      // paymentStatus='refund_pending'; mirror it so this save() doesn't
      // overwrite it back to the stale in-memory 'paid'.
      if (refundInitiated) order.paymentStatus = 'refund_pending';

      // S1: an admin status change supersedes any pending customer cancellation
      // request — clear it so the customer/admin UIs don't show a stale "awaiting
      // approval" banner/card on an order that's already been advanced or cancelled.
      if (order.cancelRequestStatus === 'requested') order.cancelRequestStatus = 'none';

      await orderRepository.save(order);

      // Audit: write an order_events row for the assignment so the timeline
      // reflects who assigned the rider and when.
      if (isFirstAssignment) {
        await OrderEventsService.log({
          orderId: order.id,
          actorUserId: req.user?.id ?? null,
          actorRole: 'admin',
          eventType: 'rider_assigned',
          fromState: fromDeliveryState ?? null,
          toState: 'assigned',
          payload: { riderId: deliveryBoyId, via: 'legacy_status_endpoint' },
        }).catch((e) => console.warn('[admin-assign] order_events write failed', e));
      }

      if (order.user.fcmToken) {
        let notificationTitle = 'Order Update';
        let notificationBody = `Your order #${order.id} status: ${status}`;

        if (status === 'accepted') {
          notificationTitle = '✅ Order Confirmed';
          notificationBody = `Great news! Your order #${order.id} is confirmed. We're getting it ready for you! ✅`;
        } else if (status === 'preparing') {
          notificationTitle = '📦 Packing Your Order';
          notificationBody = `Your order #${order.id} is being carefully packed 📦 Sit tight, almost ready!`;
        } else if (status === 'out_for_delivery') {
          notificationTitle = '🚚 On The Way!';
          notificationBody = `Your order #${order.id} is on its way! 🚚 Our delivery partner is heading to you`;
        } else if (status === 'delivered') {
          notificationTitle = '🎉 Delivered!';
          notificationBody = `Your order #${order.id} has been delivered! 🎉 Enjoy your fresh groceries. Thank you for choosing Easy Basket!`;
        } else if (status === 'cancelled') {
          notificationTitle = '😔 Order Cancelled';
          notificationBody = refundInitiated
            ? `Your order #${order.id} has been cancelled. Refund is being processed — the amount will reach your account in 2–7 working days. 🙏`
            : `We're sorry! Your order #${order.id} has been cancelled. Please try again — we'd love to serve you! 🙏`;
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
              `admin-order-status order=#${oid} customerId=${customerId} → ${status}`,
              customerId
            ),
          `notify customer order status #${oid} → ${status}`
        );
      }

      res.json(order);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error updating order status' });
    }
  }

  static async getAllUsers(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { role } = req.query;
      const page = parseInt(req.query.page as string) || 1;
      const limit = parseInt(req.query.limit as string) || 20;
      const skip = (page - 1) * limit;

      const userRepository = AppDataSource.getRepository(User);
      const queryBuilder = userRepository
        .createQueryBuilder('user')
        .where('user.isActive = :isActive', { isActive: true });

      if (role) {
        queryBuilder.andWhere('user.role = :role', { role });
      }

      const [users, total] = await queryBuilder.skip(skip).take(limit).getManyAndCount();

      res.json({
        users,
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
          hasMore: page * limit < total,
        },
      });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching users' });
    }
  }

  static async updateUser(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const { name, email, isActive } = req.body;

      const userRepository = AppDataSource.getRepository(User);
      const user = await userRepository.findOneBy({ id: Number(id) });

      if (!user) {
        res.status(404).json({ message: 'User not found' });
        return;
      }

      if (name) user.name = name;
      if (email) user.email = email;
      if (isActive !== undefined) user.isActive = isActive;

      await userRepository.save(user);
      // isActive is an authorization input, and auth.middleware caches it. Drop
      // the cached identity so a deactivation takes effect on the next request
      // rather than up to AUTH_CACHE_TTL_SEC later.
      await invalidateCachedUser(user.id);
      res.json(user);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error updating user' });
    }
  }

  /**
   * Dedicated, audited role-change endpoint.
   * Rejects unknown roles, blocks self-edits, and writes a row to role_change_audit
   * for every successful change. Keep this endpoint separate from updateUser so role
   * transitions can be reviewed/gated independently of routine profile edits.
   */
  static async changeUserRole(req: AuthRequest, res: Response): Promise<void> {
    try {
      const actor = req.user;
      if (!actor) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      const targetId = Number(req.params.id);
      const newRole = req.body?.role;

      if (!Number.isFinite(targetId)) {
        res.status(400).json({ message: 'Invalid user id' });
        return;
      }
      if (!isUserRole(newRole)) {
        res.status(400).json({ message: 'Invalid role. Allowed: customer, admin, delivery' });
        return;
      }
      if (actor.id === targetId) {
        res.status(403).json({ message: 'You cannot change your own role' });
        return;
      }

      const userRepository = AppDataSource.getRepository(User);
      const target = await userRepository.findOneBy({ id: targetId });
      if (!target) {
        res.status(404).json({ message: 'User not found' });
        return;
      }

      if (target.role === newRole) {
        res.json({ message: 'Role unchanged', user: target });
        return;
      }

      const previousRole = target.role;
      target.role = newRole;
      await userRepository.save(target);
      // Role drives every authorize() check and is cached by auth.middleware.
      // Invalidate immediately so a demotion cannot be outlived by a cached
      // entry still carrying the old role.
      await invalidateCachedUser(target.id);

      const auditRepo = AppDataSource.getRepository(RoleChangeAudit);
      await auditRepo.save(
        auditRepo.create({
          actorUserId: actor.id,
          targetUserId: target.id,
          fromRole: previousRole,
          toRole: newRole,
          ip: req.ip ?? null,
          userAgent: req.headers['user-agent']?.slice(0, 512) ?? null,
        })
      );

      console.log(
        `[ROLE_CHANGE] actor=${actor.id} target=${target.id} ${previousRole} -> ${newRole}`
      );

      res.json({ message: 'Role updated', user: target });
    } catch (error) {
      console.error('Error changing user role:', error);
      res.status(500).json({ message: 'Error changing user role' });
    }
  }

  static async getDashboardStats(req: AuthRequest, res: Response): Promise<void> {
    try {
      const orderRepository = AppDataSource.getRepository(Order);
      const userRepository = AppDataSource.getRepository(User);
      const productRepository = AppDataSource.getRepository(Product);

      const [totalOrders, pendingOrders, todayOrders, totalUsers, totalProducts, lowStockProducts] =
        await Promise.all([
          orderRepository.count(),
          orderRepository.count({ where: { status: 'pending' } }),
          orderRepository
            .createQueryBuilder('order')
            .where('DATE(order.createdAt) = CURDATE()')
            .getCount(),
          userRepository.count({ where: { isActive: true } }),
          productRepository.count({ where: { isAvailable: true } }),
          productRepository
            .createQueryBuilder('product')
            .where('product.stock < :stock', { stock: 10 })
            .andWhere('product.isAvailable = :isAvailable', { isAvailable: true })
            .getCount(),
        ]);

      // Calculate today's revenue
      const todayRevenueResult = await orderRepository
        .createQueryBuilder('order')
        .select('SUM(order.totalAmount)', 'total')
        .where('DATE(order.createdAt) = CURDATE()')
        .andWhere('order.status = :status', { status: 'delivered' })
        .getRawOne();

      const todayRevenue = todayRevenueResult?.total || 0;

      res.json({
        orders: {
          total: totalOrders,
          pending: pendingOrders,
          today: todayOrders,
        },
        users: {
          total: totalUsers,
        },
        products: {
          total: totalProducts,
          lowStock: lowStockProducts,
        },
        revenue: {
          today: parseFloat(todayRevenue),
        },
      });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching dashboard stats' });
    }
  }

  static async getAllProducts(req: AuthRequest, res: Response): Promise<void> {
    try {
      const page = parseInt(req.query.page as string) || 1;
      const limit = parseInt(req.query.limit as string) || 20;
      const skip = (page - 1) * limit;
      const { categoryId, search } = req.query;

      const productRepository = AppDataSource.getRepository(Product);
      const queryBuilder = productRepository
        .createQueryBuilder('product')
        .leftJoinAndSelect('product.category', 'category')
        .leftJoinAndSelect('product.variants', 'variants');

      // Filter by category if provided
      if (categoryId) {
        queryBuilder.andWhere('product.categoryId = :categoryId', {
          categoryId: Number(categoryId),
        });
      }

      // Filter by search query if provided - use Full-Text Search like user app
      if (search && String(search).trim().length > 0) {
        const searchTerm = String(search).trim();

        // Use Full-Text Search with Boolean Mode for better matching
        // Split query into words and require all of them (AND logic)
        // e.g. "Chia Seeds" -> "+Chia* +Seeds*"
        const searchTerms = searchTerm
          .split(/\s+/)
          .map((term) => {
            // If term is very short, don't force it with + as it might not be indexed
            return term.length <= 2 ? `${term}*` : `+${term}*`;
          })
          .join(' ');

        // Combine FTS with LIKE to catch short words/numbers (e.g., "1L") that FTS might miss
        queryBuilder.andWhere(
          new Brackets((qb) => {
            qb.where(
              `MATCH(product.name, product.tags, product.description) AGAINST(:search IN BOOLEAN MODE)`,
              { search: searchTerms }
            )
              .orWhere('product.name LIKE :likeSearch', { likeSearch: `%${searchTerm}%` })
              .orWhere('product.description LIKE :likeSearch', { likeSearch: `%${searchTerm}%` })
              .orWhere('product.tags LIKE :likeSearch', { likeSearch: `%${searchTerm}%` });
          })
        );
      }

      queryBuilder.orderBy('product.createdAt', 'DESC').skip(skip).take(limit);

      const [products, total] = await queryBuilder.getManyAndCount();

      res.json({
        products: products.map(mapProductPublic),
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
          hasMore: page * limit < total,
        },
      });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching products' });
    }
  }

  static async createProduct(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { name, description, price, imageUrl, categoryId, stock, unit, tags } = req.body;

      if (!name || !price || !categoryId) {
        res.status(400).json({ message: 'Name, price, and category are required' });
        return;
      }

      const categoryRepository = AppDataSource.getRepository(Category);
      const category = await categoryRepository.findOneBy({ id: categoryId });

      if (!category) {
        res.status(404).json({ message: 'Category not found' });
        return;
      }

      const productRepository = AppDataSource.getRepository(Product);
      const product = productRepository.create({
        name,
        description,
        price,
        imageUrl: normalizeMediaForStorage(imageUrl),
        category,
        stock: stock || 0,
        unit: unit || 'piece',
        isAvailable: true,
        tags,
      });

      await productRepository.save(product);
      await ProductController.invalidateProductListCache();
      res.status(201).json(mapProductPublic(product));
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error creating product' });
    }
  }

  static async updateProduct(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const { name, description, price, imageUrl, categoryId, stock, unit, isAvailable, tags } =
        req.body;

      const productRepository = AppDataSource.getRepository(Product);
      const product = await productRepository.findOne({
        where: { id: Number(id) },
        relations: ['category'],
      });

      if (!product) {
        res.status(404).json({ message: 'Product not found' });
        return;
      }

      if (name) product.name = name;
      if (description !== undefined) product.description = description;
      if (price) product.price = price;
      if (imageUrl !== undefined)
        product.imageUrl = normalizeMediaForStorage(imageUrl) ?? '';
      if (stock !== undefined) product.stock = stock;
      if (unit) product.unit = unit;
      if (isAvailable !== undefined) product.isAvailable = isAvailable;
      if (tags !== undefined) product.tags = tags;

      if (categoryId) {
        const categoryRepository = AppDataSource.getRepository(Category);
        const category = await categoryRepository.findOneBy({ id: categoryId });
        if (category) {
          product.category = category;
        }
      }

      await productRepository.save(product);
      await ProductController.invalidateProductListCache();
      res.json(mapProductPublic(product));
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error updating product' });
    }
  }

  static async deleteProduct(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const productRepository = AppDataSource.getRepository(Product);
      const product = await productRepository.findOneBy({ id: Number(id) });

      if (!product) {
        res.status(404).json({ message: 'Product not found' });
        return;
      }

      // Soft delete - set isAvailable to false instead of deleting
      product.isAvailable = false;
      await productRepository.save(product);

      await ProductController.invalidateProductListCache();
      res.json({ message: 'Product deleted successfully' });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error deleting product' });
    }
  }

  // Get list of delivery agents for assignment
  static async getDeliveryAgents(req: AuthRequest, res: Response): Promise<void> {
    try {
      const userRepository = AppDataSource.getRepository(User);

      // Use query builder for more control and better null handling
      // MySQL doesn't support NULLS LAST, so we use ISNULL to put nulls at the end
      const deliveryAgents = await userRepository
        .createQueryBuilder('user')
        .select(['user.id', 'user.name', 'user.phoneNumber', 'user.email'])
        .where('user.role = :role', { role: 'delivery' })
        .andWhere('user.isActive = :isActive', { isActive: true })
        .orderBy('ISNULL(user.name)', 'ASC') // NULLs will be last (ISNULL returns 1 for null, 0 for not null)
        .addOrderBy('user.name', 'ASC')
        .addOrderBy('user.phoneNumber', 'ASC')
        .getMany();

      console.log(`✅ Found ${deliveryAgents.length} active delivery agents`);

      if (deliveryAgents.length === 0) {
        console.log('⚠️ No active delivery agents found. Checking all users with delivery role...');
        const allDeliveryUsers = await userRepository.find({
          where: { role: 'delivery' },
          select: ['id', 'name', 'phoneNumber', 'email', 'isActive'],
        });
        console.log(`📊 Total users with delivery role: ${allDeliveryUsers.length}`);
        if (allDeliveryUsers.length > 0) {
          console.log('Delivery users found:');
          allDeliveryUsers.forEach((user) => {
            console.log(
              `  - ID: ${user.id}, Phone: ${user.phoneNumber}, Name: ${user.name || 'N/A'}, Active: ${user.isActive}`
            );
          });
          console.log('💡 Tip: Make sure isActive = true for delivery agents');
        } else {
          console.log('❌ No users found with role="delivery"');
          console.log('💡 Tip: Update user role to "delivery" in database or via Admin Dashboard');
        }
      } else {
        deliveryAgents.forEach((agent) => {
          console.log(`  ✓ ${agent.name || 'N/A'} (${agent.phoneNumber})`);
        });
      }

      res.json(deliveryAgents);
    } catch (error) {
      console.error('❌ Error fetching delivery agents:', error);
      res.status(500).json({
        message: 'Error fetching delivery agents',
        error: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  }

  /// Send promo notification to users by pincode (FCM topic-based)
  /// POST /api/admin/notifications/send
  /// Body: { pincodes: ["243003", "243005"], title: "...", body: "..." }
  static async sendPromoNotification(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { pincodes, title, body } = req.body;

      if (!pincodes || !Array.isArray(pincodes) || pincodes.length === 0) {
        res.status(400).json({ message: 'pincodes array required' });
        return;
      }
      if (!title || !body) {
        res.status(400).json({ message: 'title and body required' });
        return;
      }

      let sent = 0;
      const errors: string[] = [];

      for (const pincode of pincodes) {
        const topic = `pincode_${pincode}`;
        try {
          await admin.messaging().send({
            topic,
            notification: { title, body },
            data: { type: 'PROMO_OFFER', pincode: String(pincode) },
          });
          sent++;
          console.log(`✅ [PROMO] Notification sent to topic: ${topic}`);
        } catch (error: unknown) {
          const msg = error instanceof Error ? error.message : String(error);
          errors.push(`${topic}: ${msg}`);
          console.error(`❌ [PROMO] Failed to send to topic ${topic}: ${msg}`);
        }
      }

      res.json({
        success: true,
        totalPincodes: pincodes.length,
        sent,
        failed: pincodes.length - sent,
        errors: errors.length > 0 ? errors : undefined,
      });
    } catch (error) {
      console.error('❌ Error sending promo notification:', error);
      res.status(500).json({
        message: 'Error sending notification',
        error: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  }

  // =========================================================================
  // Phase 1 additions — rider management
  // =========================================================================

  /**
   * GET /api/admin/riders
   * Query: ?availability=idle|busy|offline (optional)
   *
   * Returns every user with role='delivery', plus their profile (availability,
   * current lat/lng, last seen) and active order count.
   */
  static async listRiders(req: AuthRequest, res: Response): Promise<void> {
    try {
      const userRepo = AppDataSource.getRepository(User);
      const orderRepo = AppDataSource.getRepository(Order);
      const profileRepo = AppDataSource.getRepository(RiderProfile);

      const users = await userRepo.find({ where: { role: 'delivery', isActive: true } });
      const userIds = users.map((u) => u.id);
      if (userIds.length === 0) {
        res.json([]);
        return;
      }

      const [profiles, activeCounts] = await Promise.all([
        profileRepo
          .createQueryBuilder('p')
          .where('p.userId IN (:...ids)', { ids: userIds })
          .getMany(),
        orderRepo
          .createQueryBuilder('o')
          .select('o.deliveryBoyId', 'riderId')
          .addSelect('COUNT(*)', 'activeCount')
          .where('o.deliveryBoyId IN (:...ids)', { ids: userIds })
          .andWhere(
            "(o.delivery_status IS NOT NULL AND o.delivery_status NOT IN ('delivered','rto_completed')) OR o.status = 'out_for_delivery'"
          )
          .groupBy('o.deliveryBoyId')
          .getRawMany<{ riderId: number; activeCount: string }>(),
      ]);

      const profileByUser = new Map(profiles.map((p) => [p.userId, p]));
      const activeByUser = new Map(activeCounts.map((r) => [Number(r.riderId), Number(r.activeCount)]));

      const availabilityFilter = req.query.availability as string | undefined;
      const rows = users
        .map((u) => {
          const p = profileByUser.get(u.id);
          return {
            riderId: u.id,
            name: u.name,
            phoneNumber: u.phoneNumber,
            availability: p?.availability ?? 'offline',
            vehicleType: p?.vehicleType ?? 'bike',
            currentLat: p?.currentLat ? Number(p.currentLat) : null,
            currentLng: p?.currentLng ? Number(p.currentLng) : null,
            lastSeenAt: p?.lastSeenAt ?? null,
            rating: p?.rating ? Number(p.rating) : 5.0,
            activeOrderCount: activeByUser.get(u.id) ?? 0,
          };
        })
        .filter((r) => !availabilityFilter || r.availability === availabilityFilter);

      res.json(rows);
    } catch (error) {
      console.error('[admin] listRiders error', error);
      res.status(500).json({ message: 'Error listing riders' });
    }
  }

  /**
   * POST /api/admin/orders/:id/assign-rider
   * Body: { riderId }
   * Idempotent: assigning the same rider twice returns 200 with current state.
   */
  static async assignRiderToOrder(req: AuthRequest, res: Response): Promise<void> {
    try {
      const adminUserId = req.user?.id;
      if (!adminUserId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }
      const orderId = Number(req.params.id);
      const { riderId } = req.body as { riderId?: number };
      if (!Number.isFinite(orderId) || typeof riderId !== 'number') {
        res.status(400).json({ message: 'Invalid orderId or riderId' });
        return;
      }

      const result = await DeliveryStateService.assignRider({ orderId, riderId, adminUserId });
      if (!result.ok) {
        res.status(result.code).json({ message: result.reason });
        return;
      }
      res.json({
        orderId: result.order.id,
        riderId,
        deliveryStatus: result.order.deliveryStatus,
        assignedAt: result.order.deliveryAssignedAt,
      });
    } catch (error) {
      console.error('[admin] assignRiderToOrder error', error);
      res.status(500).json({ message: 'Error assigning rider' });
    }
  }

  /**
   * GET /api/admin/riders/:id/wallet
   */
  static async getRiderWallet(req: AuthRequest, res: Response): Promise<void> {
    try {
      const riderId = Number(req.params.id);
      if (!Number.isFinite(riderId)) {
        res.status(400).json({ message: 'Invalid rider id' });
        return;
      }
      const wallet = await RiderWalletService.getWallet(riderId);
      res.json({
        riderId,
        cashInHandPaise: Number(wallet.cashInHandPaise),
        lifetimeCollectedPaise: Number(wallet.lifetimeCollectedPaise),
        lifetimeDepositedPaise: Number(wallet.lifetimeDepositedPaise),
        pendingEarningsPaise: Number(wallet.pendingEarningsPaise),
      });
    } catch (error) {
      console.error('[admin] getRiderWallet error', error);
      res.status(500).json({ message: 'Error fetching wallet' });
    }
  }

  /**
   * POST /api/admin/riders/:id/deposit
   * Header: Idempotency-Key (required)
   * Body: { amountPaise, note? }
   *
   * Records the rider depositing cash at the hub. Debits cash_in_hand and
   * credits lifetime_deposited. Idempotent per (riderId, idempotencyKey).
   */
  static async recordRiderDeposit(req: AuthRequest, res: Response): Promise<void> {
    try {
      const adminUserId = req.user?.id;
      if (!adminUserId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }
      const riderId = Number(req.params.id);
      if (!Number.isFinite(riderId)) {
        res.status(400).json({ message: 'Invalid rider id' });
        return;
      }
      const idem = (req.header('idempotency-key') ?? '').trim();
      const { amountPaise, note } = req.body as { amountPaise?: number; note?: string };
      if (!idem) {
        res.status(400).json({ message: 'Idempotency-Key header is required' });
        return;
      }
      if (!/^[A-Za-z0-9_\-:]{8,64}$/.test(idem)) {
        res.status(400).json({ message: 'Invalid Idempotency-Key' });
        return;
      }
      if (typeof amountPaise !== 'number' || amountPaise <= 0) {
        res.status(400).json({ message: 'amountPaise must be a positive number' });
        return;
      }

      const result = await RiderWalletService.recordDeposit({
        riderId,
        adminUserId,
        amountPaise,
        note,
        idempotencyKey: idem,
      });

      res.json({
        depositId: result.deposit.id,
        riderId,
        amountPaise,
        wallet: {
          cashInHandPaise: Number(result.wallet.cashInHandPaise),
          lifetimeCollectedPaise: Number(result.wallet.lifetimeCollectedPaise),
          lifetimeDepositedPaise: Number(result.wallet.lifetimeDepositedPaise),
        },
      });
    } catch (error) {
      console.error('[admin] recordRiderDeposit error', error);
      res.status(500).json({ message: 'Error recording deposit' });
    }
  }

  /**
   * GET /api/admin/orders/:id/events
   * Full audit trail for an order.
   */
  static async getOrderEvents(req: AuthRequest, res: Response): Promise<void> {
    try {
      const orderId = Number(req.params.id);
      if (!Number.isFinite(orderId)) {
        res.status(400).json({ message: 'Invalid order id' });
        return;
      }
      const events = await OrderEventsService.listForOrder(orderId);
      res.json(events);
    } catch (error) {
      console.error('[admin] getOrderEvents error', error);
      res.status(500).json({ message: 'Error fetching order events' });
    }
  }

  /**
   * GET /api/admin/orders/:id/refund
   * Refund state for one order — drives the admin refund badge and the
   * enabled/disabled state of the "Retry refund" button.
   */
  static async getOrderRefund(req: AuthRequest, res: Response): Promise<void> {
    try {
      const orderId = parseInt(req.params.id, 10);
      if (!Number.isFinite(orderId)) {
        res.status(400).json({ message: 'Invalid order id' });
        return;
      }
      res.json({ refund: await PaymentsV2Service.getRefundStateForOrder(orderId) });
    } catch (error) {
      console.error('[admin] getOrderRefund error', error);
      res.status(500).json({ message: 'Error fetching refund state' });
    }
  }

  /**
   * POST /api/admin/orders/:id/retry-refund
   * Manually re-attempt a refund that exhausted its automatic retries.
   *
   * One click = one attempt. The underlying retry takes the shared payment lock
   * and asks Razorpay whether a refund already exists for this row before
   * creating one, so repeated clicks cannot double-refund the customer.
   */
  static async retryRefund(req: AuthRequest, res: Response): Promise<void> {
    try {
      const orderId = parseInt(req.params.id, 10);
      if (!Number.isFinite(orderId)) {
        res.status(400).json({ message: 'Invalid order id' });
        return;
      }

      const state = await PaymentsV2Service.getRefundStateForOrder(orderId);
      if (!state) {
        res.status(404).json({ message: 'No refund exists for this order' });
        return;
      }
      if (state.status === 'processed') {
        // Already done — nothing to retry. The UI disables the button on this state.
        res.json({ message: 'Refund already completed', refund: state });
        return;
      }

      const result = await PaymentsV2Service.retryRefund({
        refundId: state.refundId,
        manual: true,
      });

      const refund = await PaymentsV2Service.getRefundStateForOrder(orderId);

      if (!result.ok) {
        const rescheduled = 'rescheduled' in result;
        res.status(rescheduled ? 202 : result.code).json({ message: result.reason, refund });
        return;
      }

      console.log(
        `[admin] manual refund retry for order #${orderId} by user ${req.user?.id} → ${result.status}`
      );
      res.json({
        message:
          result.status === 'processed'
            ? 'Refund completed'
            : 'Refund re-submitted to Razorpay',
        refund,
      });
    } catch (error) {
      console.error('[admin] retryRefund error', error);
      res.status(500).json({ message: 'Error retrying refund' });
    }
  }

  /**
   * POST /api/admin/orders/:id/approve-cancellation
   * Approve a customer's cancellation request → cancel the order, restore stock,
   * and initiate a full refund (if prepaid). Mirrors the admin-cancel hooks.
   */
  static async approveCancellation(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const orderRepository = AppDataSource.getRepository(Order);
      const order = await orderRepository.findOne({
        where: { id: Number(id) },
        relations: ['user', 'items', 'items.product', 'items.variant'],
      });

      if (!order) {
        res.status(404).json({ message: 'Order not found' });
        return;
      }
      if (order.cancelRequestStatus !== 'requested') {
        res.status(400).json({ message: 'No pending cancellation request for this order' });
        return;
      }
      // Policy: refund-on-cancel is only for orders NOT yet packed. If the admin
      // advanced the order past 'accepted', approving here would refund a packed
      // order (violates the "after packing, no refund" rule).
      if (
        order.status !== 'pending' &&
        order.status !== 'awaiting_acceptance' &&
        order.status !== 'accepted'
      ) {
        res.status(400).json({
          message: `Cannot approve refund — order is already '${order.status}'. Refunds are only allowed before packing.`,
        });
        return;
      }

      // Atomic claim: only ONE concurrent approve flips the request + status, so a
      // race (e.g. admin double-tap) can't restore stock / refund twice.
      const claim = await orderRepository.update(
        {
          id: order.id,
          cancelRequestStatus: 'requested',
          status: In(['pending', 'awaiting_acceptance', 'accepted']),
        },
        { cancelRequestStatus: 'none', status: 'cancelled' }
      );
      if (claim.affected !== 1) {
        res.status(409).json({ message: 'Cancellation already processed' });
        return;
      }

      try {
        await OrderInventoryService.restoreReservedStockForItems(order.items);
      } catch (invErr) {
        console.error(`[approve-cancel] inventory restore failed for order #${order.id}`, invErr);
      }

      let refundInitiated = false;
      if (order.paymentStatus === 'paid') {
        try {
          const result = await PaymentsV2Service.createRefund({
            orderId: order.id,
            userId: order.user.id,
            actorUserId: req.user?.id ?? order.user.id,
            reason: 'customer_cancel_approved',
            idempotencyKey: `cust-cancel-${order.id}`,
          });
          refundInitiated = result.ok;
          if (!result.ok) {
            console.warn(
              `[approve-cancel] refund not initiated for order #${order.id}: ${result.reason}`
            );
          }
        } catch (refErr) {
          console.error(`[approve-cancel] refund call failed for order #${order.id}`, refErr);
        }
      }

      order.status = 'cancelled';
      order.cancelRequestStatus = 'none';
      // createRefund already persisted paymentStatus='refund_pending'; mirror it
      // on the in-memory entity so this save() doesn't clobber it back to 'paid'.
      if (refundInitiated) order.paymentStatus = 'refund_pending';
      await orderRepository.save(order);

      if (order.user.fcmToken) {
        const token = order.user.fcmToken;
        const oid = order.id;
        const customerId = order.user.id;
        const body = refundInitiated
          ? `Your cancellation for order #${oid} is approved. Refund is being processed — the amount will reach your account in 2–7 working days. 🙏`
          : `Your cancellation for order #${oid} is approved. 🙏`;
        FCMService.enqueue(
          () =>
            FCMService.sendNotification(
              token,
              '✅ Cancellation Approved',
              body,
              { orderId: oid.toString(), type: 'refund_approved' },
              `refund approved order=#${oid} customerId=${customerId}`,
              customerId
            ),
          `notify customer refund approved #${oid}`
        );
      }

      res.json({ message: 'Cancellation approved', refundInitiated, order });
    } catch (error) {
      console.error('[admin] approveCancellation error', error);
      res.status(500).json({ message: 'Error approving cancellation' });
    }
  }

  /**
   * POST /api/admin/orders/:id/reject-cancellation
   * Decline a customer's cancellation request — the order stays active.
   */
  static async rejectCancellation(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const orderRepository = AppDataSource.getRepository(Order);
      const order = await orderRepository.findOne({
        where: { id: Number(id) },
        relations: ['user'],
      });

      if (!order) {
        res.status(404).json({ message: 'Order not found' });
        return;
      }
      if (order.cancelRequestStatus !== 'requested') {
        res.status(400).json({ message: 'No pending cancellation request for this order' });
        return;
      }

      order.cancelRequestStatus = 'rejected';
      await orderRepository.save(order);

      if (order.user.fcmToken) {
        const token = order.user.fcmToken;
        const oid = order.id;
        const customerId = order.user.id;
        FCMService.enqueue(
          () =>
            FCMService.sendNotification(
              token,
              'Cancellation Declined',
              `Your cancellation request for order #${oid} was declined. Your order is still on its way.`,
              { orderId: oid.toString(), type: 'refund_declined' },
              `refund declined order=#${oid} customerId=${customerId}`,
              customerId
            ),
          `notify customer refund declined #${oid}`
        );
      }

      res.json({ message: 'Cancellation request declined', order });
    } catch (error) {
      console.error('[admin] rejectCancellation error', error);
      res.status(500).json({ message: 'Error rejecting cancellation' });
    }
  }

  /**
   * POST /api/admin/orders/:id/complete-rto
   * After the rider physically returns stock to the hub. Restores inventory and
   * initiates refund if the order was prepaid.
   */
  static async completeRto(req: AuthRequest, res: Response): Promise<void> {
    try {
      const adminUserId = req.user?.id;
      if (!adminUserId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }
      const orderId = Number(req.params.id);
      if (!Number.isFinite(orderId)) {
        res.status(400).json({ message: 'Invalid order id' });
        return;
      }
      const result = await DeliveryStateService.completeRto({ orderId, actorUserId: adminUserId });
      if (!result.ok) {
        res.status(result.code).json({ message: result.reason });
        return;
      }
      res.json({
        orderId: result.order.id,
        deliveryStatus: result.order.deliveryStatus,
        status: result.order.status,
        paymentStatus: result.order.paymentStatus,
      });
    } catch (error) {
      console.error('[admin] completeRto error', error);
      res.status(500).json({ message: 'Error completing RTO' });
    }
  }
}

/**
 * Which order statuses may follow which, for AdminController.updateOrderStatus.
 *
 * Deliberately shaped like DeliveryStateService.canTransition, which the delivery
 * flow has had all along — the order status simply never got an equivalent, so a
 * whitelist of *valid* values was standing in for a matrix of valid *moves*.
 *
 * Cancellation is reachable from every non-terminal state (the admin-cancel hooks
 * that restore stock and refund live on that edge). Both terminal states are dead
 * ends, which the guard above already enforces separately.
 */
const ALLOWED_ORDER_TRANSITIONS: Record<string, string[]> = {
  pending: ['awaiting_acceptance', 'accepted', 'cancelled'],
  awaiting_acceptance: ['accepted', 'cancelled'],
  accepted: ['preparing', 'out_for_delivery', 'cancelled'],
  preparing: ['out_for_delivery', 'cancelled'],
  out_for_delivery: ['delivered', 'cancelled'],
  delivered: [],
  cancelled: [],
};

/**
 * Forward-only delivery_status check. Used by the legacy admin updateOrderStatus
 * to avoid writing a state that's "behind" the order's current state when the
 * admin sets a status out of order (e.g. retroactively setting 'preparing' on
 * an order already 'delivered').
 */
const _DS_RANK: Record<string, number> = {
  unassigned: 0,
  assigned: 1,
  at_store: 2,
  picked: 3,
  out_for_delivery: 4,
  arrived: 5,
  payment_pending: 6,
  delivered: 7,
  rto_pending: 8,
  rto_completed: 9,
};
function _isForward(from: string | null | undefined, to: string): boolean {
  const f = from ? _DS_RANK[from] ?? -1 : -1;
  const t = _DS_RANK[to] ?? -1;
  return t >= f;
}
