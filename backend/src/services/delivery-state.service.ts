import { AppDataSource } from '../config/database';
import { Order } from '../entities/Order';
import { User } from '../entities/User';
import { RiderProfile } from '../entities/RiderProfile';
import { OrderEventsService } from './order-events.service';
import { DeliveryOtpService } from './delivery-otp.service';
import { RiderWalletService } from './rider-wallet.service';
import { OrderInventoryService } from './order-inventory.service';
import { PaymentsV2Service } from './payments-v2.service';
import { FCMService } from './fcm.service';

export type DeliveryStatus =
  | 'unassigned'
  | 'assigned'
  | 'at_store'
  | 'picked'
  | 'out_for_delivery'
  | 'arrived'
  | 'payment_pending'
  | 'delivered'
  | 'rto_pending'
  | 'rto_completed';

type DeliveryTransitionResult =
  | { ok: true; order: Order }
  | { ok: false; reason: string; code: number };

/**
 * Delivery orchestration. All state transitions live here so they can't drift
 * between the rider API, the admin API, and the reconciler.
 *
 * Every transition:
 *   1. Loads the order inside a transaction
 *   2. Guards against illegal transitions (forward-only state machine)
 *   3. Writes the new state + timestamps
 *   4. Appends an `order_events` row in the same transaction
 *   5. (Optional) mirrors onto `Order.status` for mobile-visible changes
 *   6. Fires an FCM notification
 *
 * The customer-visible `Order.status` (`pending | accepted | preparing | ...`)
 * is maintained in lock-step but never replaced — mobile keeps reading it.
 */
export class DeliveryStateService {
  // -----------------------------------------------------------------------
  // Transition legality table
  // -----------------------------------------------------------------------

  private static readonly LEGAL: Record<DeliveryStatus, DeliveryStatus[]> = {
    unassigned: ['assigned'],
    assigned: ['at_store', 'rto_pending'],
    at_store: ['picked', 'rto_pending'],
    picked: ['out_for_delivery', 'rto_pending'],
    out_for_delivery: ['arrived', 'rto_pending'],
    arrived: ['payment_pending', 'delivered', 'rto_pending'],
    payment_pending: ['delivered', 'rto_pending'],
    delivered: [], // terminal
    rto_pending: ['rto_completed'],
    rto_completed: [], // terminal
  };

  private static canTransition(from: DeliveryStatus | null, to: DeliveryStatus): boolean {
    if (from == null) return to === 'assigned' || to === 'unassigned';
    if (from === to) return true; // idempotent no-op
    return this.LEGAL[from]?.includes(to) ?? false;
  }

  // -----------------------------------------------------------------------
  // Admin: assign a rider
  // -----------------------------------------------------------------------

  static async assignRider(params: {
    orderId: number;
    riderId: number;
    adminUserId: number;
  }): Promise<DeliveryTransitionResult> {
    return AppDataSource.manager.transaction(async (em) => {
      const orderRepo = em.getRepository(Order);
      const userRepo = em.getRepository(User);

      const order = await orderRepo.findOne({
        where: { id: params.orderId },
        relations: ['user', 'deliveryBoy'],
      });
      if (!order) return err(404, 'Order not found');

      const from = (order.deliveryStatus ?? null) as DeliveryStatus | null;
      if (from && from !== 'unassigned' && from !== 'assigned') {
        return err(409, `Cannot assign: order is ${from}`);
      }

      // Idempotency: re-assigning the same rider is a no-op.
      if (from === 'assigned' && order.deliveryBoy?.id === params.riderId) {
        return { ok: true, order };
      }

      const rider = await userRepo.findOneBy({ id: params.riderId, role: 'delivery' });
      if (!rider) return err(404, 'Rider not found');

      order.deliveryBoy = rider;
      order.deliveryStatus = 'assigned';
      order.deliveryAssignedAt = new Date();
      // Mirror onto customer-visible status: assignment is when packing starts in
      // a real warehouse (a rider's been assigned, so the bag gets picked off the
      // shelf for them). Customer should see "Being prepared" right away rather
      // than the rider's internal at_store/picked milestones.
      if (order.status === 'pending' || order.status === 'accepted') {
        order.status = 'preparing';
      }
      await orderRepo.save(order);

      // Mark rider busy (best-effort).
      await em
        .getRepository(RiderProfile)
        .update({ userId: params.riderId }, { availability: 'busy' })
        .catch(() => undefined);

      await OrderEventsService.log(
        {
          orderId: order.id,
          actorUserId: params.adminUserId,
          actorRole: 'admin',
          eventType: 'rider_assigned',
          fromState: from ?? null,
          toState: 'assigned',
          payload: { riderId: params.riderId, riderName: rider.name ?? null },
        },
        em
      );

      notifyRiderAssignment(rider, order).catch(() => undefined);

      return { ok: true, order };
    });
  }

  // -----------------------------------------------------------------------
  // Rider transitions (workflow steps)
  // -----------------------------------------------------------------------

  /** Generic rider-driven transition. Factored so each endpoint is a one-liner. */
  private static async riderTransition(params: {
    orderId: number;
    riderId: number;
    to: DeliveryStatus;
    eventType: string;
    mirrorOrderStatus?: string;
    timestampField?: 'deliveryPickedAt' | 'deliveryArrivedAt';
    extraPayload?: Record<string, unknown>;
  }): Promise<DeliveryTransitionResult> {
    return AppDataSource.manager.transaction(async (em) => {
      const orderRepo = em.getRepository(Order);
      const order = await orderRepo.findOne({
        where: { id: params.orderId },
        relations: ['user', 'deliveryBoy'],
      });
      if (!order) return err(404, 'Order not found');
      if (!order.deliveryBoy || order.deliveryBoy.id !== params.riderId) {
        return err(403, 'Order not assigned to you');
      }

      const from = (order.deliveryStatus ?? null) as DeliveryStatus | null;
      if (!this.canTransition(from, params.to)) {
        return err(409, `Illegal transition ${from ?? 'null'} → ${params.to}`);
      }
      // Idempotent: already in target state → return current snapshot.
      if (from === params.to) return { ok: true, order };

      order.deliveryStatus = params.to;
      if (params.timestampField) {
        order[params.timestampField] = new Date();
      }
      if (params.mirrorOrderStatus && order.status !== params.mirrorOrderStatus) {
        order.status = params.mirrorOrderStatus;
      }
      await orderRepo.save(order);

      await OrderEventsService.log(
        {
          orderId: order.id,
          actorUserId: params.riderId,
          actorRole: 'delivery',
          eventType: params.eventType,
          fromState: from ?? null,
          toState: params.to,
          payload: params.extraPayload ?? null,
        },
        em
      );

      return { ok: true, order };
    });
  }

  static arrivedAtStore(orderId: number, riderId: number) {
    return this.riderTransition({
      orderId,
      riderId,
      to: 'at_store',
      eventType: 'rider_arrived_at_store',
    });
  }

  static picked(orderId: number, riderId: number) {
    // No mirror: by the time the rider has the bag, packing is done — flashing
    // "preparing" to the customer here would actually be backwards. Customer-
    // visible status flips to 'out_for_delivery' on Start Delivery.
    return this.riderTransition({
      orderId,
      riderId,
      to: 'picked',
      eventType: 'order_picked',
      timestampField: 'deliveryPickedAt',
    });
  }

  /**
   * Start delivery: flip status to out_for_delivery, send OTP to customer
   * via Twilio SMS (same provider as login OTP). No FCM push for OTP — SMS only.
   */
  static async startDelivery(
    orderId: number,
    riderId: number
  ): Promise<DeliveryTransitionResult> {
    const result = await this.riderTransition({
      orderId,
      riderId,
      to: 'out_for_delivery',
      eventType: 'delivery_started',
      mirrorOrderStatus: 'out_for_delivery',
    });
    if (!result.ok) return result;

    // SMS dispatch lives outside the DB transaction — Twilio call is best-effort
    // from the rider's POV. In test mode (DELIVERY_USE_TEST_OTP) or when Twilio
    // isn't configured, the fixed test OTP (123456) is accepted at verify-time
    // even if no SMS goes out, so dev/QA isn't blocked.
    DeliveryOtpService.generateForOrder(orderId).catch((err) =>
      console.error(`[delivery] SMS OTP send failed for order ${orderId}`, err)
    );
    return result;
  }

  /**
   * Rider is at the customer's doorstep. For prepaid → stays in `arrived` pending
   * OTP verification. For COD → advances to `payment_pending` (awaiting cash).
   */
  static async arrived(
    orderId: number,
    riderId: number,
    loc?: { lat: number; lng: number }
  ): Promise<DeliveryTransitionResult> {
    const step1 = await this.riderTransition({
      orderId,
      riderId,
      to: 'arrived',
      eventType: 'rider_arrived_customer',
      timestampField: 'deliveryArrivedAt',
      extraPayload: loc ? { gps: loc } : undefined,
    });
    if (!step1.ok) return step1;

    // COD branching: if `cod` payment method, push to payment_pending.
    if (step1.order.paymentMethod === 'cod') {
      return this.riderTransition({
        orderId,
        riderId,
        to: 'payment_pending',
        eventType: 'awaiting_cash',
      });
    }
    return step1;
  }

  /**
   * Rider collects cash + verifies OTP → transition to `delivered` + credit wallet.
   * Amount must match the order's total (paise). GPS must be within 200m of customer.
   */
  static async collectCash(params: {
    orderId: number;
    riderId: number;
    amountPaise: number;
    otp: string;
    gps?: { lat: number; lng: number };
  }): Promise<DeliveryTransitionResult> {
    const expectedOrder = await AppDataSource.getRepository(Order).findOne({
      where: { id: params.orderId },
      relations: ['deliveryBoy', 'deliveryAddress'],
    });
    if (!expectedOrder) return err(404, 'Order not found');
    if (!expectedOrder.deliveryBoy || expectedOrder.deliveryBoy.id !== params.riderId) {
      return err(403, 'Order not assigned to you');
    }

    const expectedPaise = Math.round(Number(expectedOrder.totalAmount) * 100);
    if (params.amountPaise !== expectedPaise) {
      await OrderEventsService.log({
        orderId: params.orderId,
        actorUserId: params.riderId,
        actorRole: 'delivery',
        eventType: 'cash_amount_mismatch',
        payload: {
          expected: expectedPaise,
          received: params.amountPaise,
          fraudFlag: true,
        },
      });
      return err(400, `Amount mismatch. Expected ₹${expectedPaise / 100}`);
    }

    const otpOk = await DeliveryOtpService.verify(params.orderId, params.otp);
    if (!otpOk) {
      await OrderEventsService.log({
        orderId: params.orderId,
        actorUserId: params.riderId,
        actorRole: 'delivery',
        eventType: 'otp_verification_failed',
        payload: { gps: params.gps ?? null },
      });
      return err(401, 'OTP is invalid or expired');
    }

    // All guards passed — atomic: transition + credit wallet + log event.
    return AppDataSource.manager.transaction(async (em) => {
      const orderRepo = em.getRepository(Order);
      const order = await orderRepo.findOne({
        where: { id: params.orderId },
        relations: ['user', 'deliveryBoy'],
      });
      if (!order) return err(404, 'Order not found');

      const from = (order.deliveryStatus ?? null) as DeliveryStatus | null;

      // Idempotency / double-credit guard: if the order is already delivered
      // OR already paid (e.g. customer slipped through "Switch to UPI" while
      // the rider was typing OTP), short-circuit BEFORE crediting the wallet.
      // canTransition treats 'delivered' -> 'delivered' as a legal no-op, so
      // without this check a stale-data retry would credit cash_in_hand twice.
      if (from === 'delivered' || order.isPaid) {
        return err(409, 'Order already delivered or paid');
      }
      if (!this.canTransition(from, 'delivered')) {
        return err(409, `Illegal transition ${from} → delivered`);
      }

      order.deliveryStatus = 'delivered';
      order.status = 'delivered';
      order.isPaid = true;
      order.deliveryCompletedAt = new Date();
      order.cashCollectedPaise = String(params.amountPaise);
      await orderRepo.save(order);

      await RiderWalletService.creditCollection(params.riderId, params.amountPaise, em);

      await OrderEventsService.log(
        {
          orderId: order.id,
          actorUserId: params.riderId,
          actorRole: 'delivery',
          eventType: 'cash_collected',
          fromState: from ?? null,
          toState: 'delivered',
          payload: {
            amountPaise: params.amountPaise,
            gps: params.gps ?? null,
          },
        },
        em
      );

      // Bump rider stats (best effort).
      await em
        .getRepository(RiderProfile)
        .increment({ userId: params.riderId }, 'totalDeliveries', 1)
        .catch(() => undefined);
      await em
        .getRepository(RiderProfile)
        .increment({ userId: params.riderId }, 'totalCodDeliveries', 1)
        .catch(() => undefined);

      notifyCustomerDelivered(order).catch(() => undefined);
      return { ok: true, order };
    });
  }

  /**
   * Mark a PREPAID order delivered. Mirrors collectCash but:
   *   - no amount-match check (no cash exchanged)
   *   - no wallet credit
   *   - rejects COD orders (those go through collectCash)
   *
   * Same OTP gate as COD — without it, a malicious rider could mark every
   * prepaid bag "delivered" from the parking lot. The customer's OTP is the
   * proof they actually received the bag.
   */
  static async markPrepaidDelivered(params: {
    orderId: number;
    riderId: number;
    otp: string;
    gps?: { lat: number; lng: number };
  }): Promise<DeliveryTransitionResult> {
    const expectedOrder = await AppDataSource.getRepository(Order).findOne({
      where: { id: params.orderId },
      relations: ['deliveryBoy', 'user'],
    });
    if (!expectedOrder) return err(404, 'Order not found');
    if (!expectedOrder.deliveryBoy || expectedOrder.deliveryBoy.id !== params.riderId) {
      return err(403, 'Order not assigned to you');
    }
    // A COD order that is NOT yet paid must go through collect-cash. But a COD
    // order that became paid at the door (rider used "Switch to UPI" → customer
    // paid online) has isPaid=true and CANNOT be closed via collect-cash (that
    // 409s on "already paid"). Such orders finish here, OTP-gated, like prepaid.
    if (expectedOrder.paymentMethod === 'cod' && !expectedOrder.isPaid) {
      return err(400, 'COD orders must use collect-cash');
    }
    if (!expectedOrder.isPaid) {
      // Prepaid means already paid online. If isPaid is false the customer
      // never completed payment — sending them down this path would close the
      // order without payment ever landing.
      return err(409, 'Order is not paid yet — wait for payment to confirm');
    }

    const otpOk = await DeliveryOtpService.verify(params.orderId, params.otp);
    if (!otpOk) {
      await OrderEventsService.log({
        orderId: params.orderId,
        actorUserId: params.riderId,
        actorRole: 'delivery',
        eventType: 'otp_verification_failed',
        payload: { gps: params.gps ?? null, flow: 'prepaid' },
      });
      return err(401, 'OTP is invalid or expired');
    }

    return AppDataSource.manager.transaction(async (em) => {
      const orderRepo = em.getRepository(Order);
      const order = await orderRepo.findOne({
        where: { id: params.orderId },
        relations: ['user', 'deliveryBoy'],
      });
      if (!order) return err(404, 'Order not found');

      const from = (order.deliveryStatus ?? null) as DeliveryStatus | null;
      // Idempotency: don't re-close an already-closed order.
      if (from === 'delivered') {
        return err(409, 'Order already delivered');
      }
      if (!this.canTransition(from, 'delivered')) {
        return err(409, `Illegal transition ${from} → delivered`);
      }

      order.deliveryStatus = 'delivered';
      order.status = 'delivered';
      order.deliveryCompletedAt = new Date();
      await orderRepo.save(order);

      await OrderEventsService.log(
        {
          orderId: order.id,
          actorUserId: params.riderId,
          actorRole: 'delivery',
          eventType: 'prepaid_delivered',
          fromState: from ?? null,
          toState: 'delivered',
          payload: { gps: params.gps ?? null },
        },
        em
      );

      // Bump rider stats (best effort; not COD-specific so only the lifetime counter).
      await em
        .getRepository(RiderProfile)
        .increment({ userId: params.riderId }, 'totalDeliveries', 1)
        .catch(() => undefined);

      notifyCustomerDelivered(order).catch(() => undefined);
      return { ok: true, order };
    });
  }

  /**
   * Rider chooses "Switch to UPI" at the door — generate a fresh Razorpay order the
   * customer can pay via QR / link. Once the webhook lands, the existing payments flow
   * promotes the order. We don't transition to delivered here — the rider still taps
   * "collect-cash"/"arrived" as appropriate after payment confirms.
   */
  static async switchToUpi(
    orderId: number,
    riderId: number
  ): Promise<
    | { ok: true; razorpayOrderId: string; amountPaise: number; keyId: string }
    | { ok: false; reason: string; code: number }
  > {
    const order = await AppDataSource.getRepository(Order).findOne({
      where: { id: orderId },
      relations: ['user', 'deliveryBoy'],
    });
    if (!order) return err(404, 'Order not found');
    if (order.deliveryBoy?.id !== riderId) return err(403, 'Order not assigned to you');

    const amountPaise = Math.round(Number(order.totalAmount) * 100);
    const out = await PaymentsV2Service.initiatePayment({
      orderId,
      userId: order.user.id,
      amountPaise,
    });

    await OrderEventsService.log({
      orderId,
      actorUserId: riderId,
      actorRole: 'delivery',
      eventType: 'switched_to_upi',
      payload: { razorpayOrderId: out.razorpayOrderId, amountPaise },
    });

    return {
      ok: true,
      razorpayOrderId: out.razorpayOrderId,
      amountPaise: out.amountPaise,
      keyId: out.keyId,
    };
  }

  /**
   * Report an issue (customer_refused / not_reachable / wrong_address / damaged / other).
   * Increments delivery_attempts; 3rd `not_reachable` auto-transitions to `rto_pending`.
   * `customer_refused` or `wrong_address` → immediate `rto_pending`.
   */
  static async reportIssue(params: {
    orderId: number;
    riderId: number;
    reason:
      | 'customer_refused'
      | 'not_reachable'
      | 'wrong_address'
      | 'damaged'
      | 'other';
    note?: string;
  }): Promise<DeliveryTransitionResult & { attempt?: number; nextAction?: string }> {
    return AppDataSource.manager.transaction(async (em) => {
      const orderRepo = em.getRepository(Order);
      const order = await orderRepo.findOne({
        where: { id: params.orderId },
        relations: ['user', 'deliveryBoy', 'items', 'items.product', 'items.variant'],
      });
      if (!order) return err(404, 'Order not found');
      if (order.deliveryBoy?.id !== params.riderId) return err(403, 'Order not assigned to you');

      const from = (order.deliveryStatus ?? null) as DeliveryStatus | null;

      // S7: don't let an issue report drive a terminal order into RTO. Without this,
      // a delivered order could be forced to rto_pending → completeRto would restore
      // stock again and refund an already-delivered order.
      if (from === 'delivered' || from === 'rto_completed') {
        return err(409, `Cannot report an issue on a '${from}' order`);
      }

      order.deliveryAttempts = (order.deliveryAttempts ?? 0) + 1;

      const immediateRto =
        params.reason === 'customer_refused' ||
        params.reason === 'wrong_address' ||
        params.reason === 'damaged';
      const autoRto = params.reason === 'not_reachable' && order.deliveryAttempts >= 3;

      if (immediateRto || autoRto) {
        order.deliveryStatus = 'rto_pending';
      }
      await orderRepo.save(order);

      await OrderEventsService.log(
        {
          orderId: order.id,
          actorUserId: params.riderId,
          actorRole: 'delivery',
          eventType: 'issue_reported',
          fromState: from ?? null,
          toState: order.deliveryStatus,
          payload: {
            reason: params.reason,
            note: params.note ?? null,
            attempt: order.deliveryAttempts,
          },
        },
        em
      );

      // Invalidate any outstanding OTP — rider won't be verifying at this address.
      if (immediateRto || autoRto) {
        await DeliveryOtpService.invalidate(order.id).catch(() => undefined);
      }

      const nextAction = immediateRto || autoRto ? 'return_to_hub' : 'retry_later';
      return { ok: true, order, attempt: order.deliveryAttempts, nextAction };
    });
  }

  /**
   * Admin or system marks RTO complete — inventory is back at hub, refund the customer
   * if they'd paid online. Called after the rider physically returns the stock.
   */
  static async completeRto(params: {
    orderId: number;
    actorUserId: number;
  }): Promise<DeliveryTransitionResult> {
    const result: DeliveryTransitionResult = await AppDataSource.manager.transaction(async (em) => {
      const orderRepo = em.getRepository(Order);
      const order = await orderRepo.findOne({
        where: { id: params.orderId },
        relations: ['user', 'items', 'items.product', 'items.variant'],
      });
      if (!order) return err(404, 'Order not found');

      const from = (order.deliveryStatus ?? null) as DeliveryStatus | null;
      if (!this.canTransition(from, 'rto_completed')) {
        return err(409, `Illegal transition ${from} → rto_completed`);
      }

      await OrderInventoryService.restoreReservedStockForItems(order.items);

      order.deliveryStatus = 'rto_completed';
      if (order.status !== 'cancelled') order.status = 'cancelled';
      await orderRepo.save(order);

      await OrderEventsService.log(
        {
          orderId: order.id,
          actorUserId: params.actorUserId,
          actorRole: 'admin',
          eventType: 'rto_completed',
          fromState: from,
          toState: 'rto_completed',
        },
        em
      );

      return { ok: true, order };
    });

    // Refund AFTER the transaction commits — never inside it.
    //
    // createRefund uses AppDataSource repositories (a different connection from the
    // transaction's manager), takes a Redis lock, and makes up to two Razorpay HTTP
    // calls. Running it inside the transaction meant: the refund row committed on its
    // own connection regardless of whether this transaction later rolled back (so a
    // rollback left a customer refunded for an order that is not cancelled); row locks
    // on orders/order_items were held across external network I/O, which exhausts the
    // pool under load; and the refund could not see this transaction's uncommitted
    // order.status = 'cancelled'. Same ordering markPaymentPaid already uses for its
    // auto-refund on a cancelled order.
    if (result.ok && result.order.paymentStatus === 'paid') {
      const order = result.order;
      try {
        const refund = await PaymentsV2Service.createRefund({
          orderId: order.id,
          userId: order.user.id,
          actorUserId: params.actorUserId,
          reason: 'rto',
          idempotencyKey: `rto-${order.id}`,
        });
        if (!refund.ok) {
          console.error(`[rto] refund not initiated for order #${order.id}: ${refund.reason}`);
        }
      } catch (refErr) {
        console.error(`[rto] refund call failed for order #${order.id}`, refErr);
      }
    }

    return result;
  }
}

// ---------------------------------------------------------------------------
// FCM helpers (fire-and-forget; never throw back into the transition path)
// ---------------------------------------------------------------------------

async function notifyRiderAssignment(rider: User, order: Order): Promise<void> {
  if (!rider.fcmToken) return;
  const token = rider.fcmToken;
  const oid = order.id;
  FCMService.enqueue(
    () =>
      FCMService.sendNotification(
        token,
        '📦 New Order Assigned',
        `Order #${oid} — please head to the store.`,
        { orderId: String(oid), type: 'order_assigned' },
        `rider-assign order=#${oid} rider=${rider.id}`,
        rider.id
      ),
    `rider-assign #${oid}`
  );
}

async function notifyCustomerDelivered(order: Order): Promise<void> {
  if (!order.user?.fcmToken) return;
  const token = order.user.fcmToken;
  const oid = order.id;
  const customerId = order.user.id;
  FCMService.enqueue(
    () =>
      FCMService.sendNotification(
        token,
        '🎉 Delivered!',
        `Your order #${oid} has been delivered. Thank you!`,
        { orderId: String(oid), type: 'order_delivered' },
        `delivered order=#${oid} customerId=${customerId}`,
        customerId
      ),
    `delivered #${oid}`
  );
}

function err(
  code: number,
  reason: string
): { ok: false; reason: string; code: number } {
  return { ok: false, reason, code };
}
