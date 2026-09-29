import { Brackets } from 'typeorm';
import { AppDataSource } from '../config/database';
import { Order } from '../entities/Order';
import { FCMService } from './fcm.service';
import { OrderInventoryService } from './order-inventory.service';
import { LeaderElectionService } from './leader-election.service';

/**
 * Periodic job: pending orders that stay unaccepted past the configured window are cancelled
 * and reserved inventory is released (same rules as customer cancel).
 *
 * Window: ORDER_AUTO_CANCEL_MINUTES (default 30). Check interval: 1 minute.
 */
export class OrderAutoCancelService {
  private static intervalId: NodeJS.Timeout | null = null;
  private static readonly CHECK_INTERVAL_MS = 60 * 1000;
  private static readonly autoCancelAfterMs: number = OrderAutoCancelService.resolveAutoCancelMs();

  /**
   * Short window for online orders that were never paid for.
   *
   * An abandoned UPI checkout has nothing to wait for: the customer backed out
   * of the payment sheet and the app already showed them a "Payment failed"
   * screen. Holding its stock for the full 30 minutes served nobody. This is
   * deliberately still generous enough that a customer on a slow connection who
   * genuinely walks back to finish paying is not cut off mid-attempt — and it
   * sits inside initiatePayment's 15-minute reuse window, so a retry inside it
   * resumes the same Razorpay order rather than minting a second one.
   *
   * Orders at 'success_unverified' are deliberately NOT swept on this window —
   * the client reported success and the money may well be in. Those stay on the
   * long window below, by which time the reconciler has resolved them.
   */
  private static readonly unpaidAutoCancelAfterMs: number =
    OrderAutoCancelService.resolveUnpaidAutoCancelMs();

  private static resolveAutoCancelMs(): number {
    const raw = process.env.ORDER_AUTO_CANCEL_MINUTES;
    const minutes = raw !== undefined ? parseInt(raw, 10) : 30;
    const safe = Number.isFinite(minutes) && minutes > 0 ? minutes : 30;
    return safe * 60 * 1000;
  }

  private static resolveUnpaidAutoCancelMs(): number {
    const raw = process.env.ORDER_UNPAID_AUTO_CANCEL_MINUTES;
    const minutes = raw !== undefined ? parseInt(raw, 10) : 10;
    const safe = Number.isFinite(minutes) && minutes > 0 ? minutes : 10;
    return safe * 60 * 1000;
  }

  /**
   * True when this order is an online checkout the customer walked away from.
   *
   * Drives two things: the short sweep window, and suppressing the cancellation
   * notifications. Telling someone "your order was cancelled" ten minutes after
   * they deliberately backed out of paying — for an order the store never saw —
   * is noise about something that, from their side, never happened.
   */
  private static isAbandonedOnlinePayment(order: Order): boolean {
    if (order.paymentMethod == null || order.paymentMethod === 'cod') return false;
    return (
      order.paymentStatus == null ||
      order.paymentStatus === 'initiated' ||
      order.paymentStatus === 'failed'
    );
  }

  static start(): void {
    if (this.intervalId) {
      console.log('⚠️ [AutoCancel] Already running');
      return;
    }

    const mins = this.autoCancelAfterMs / 60_000;
    console.log(
      `🔄 [AutoCancel] Started — pending orders auto-cancel after ${mins} min (ORDER_AUTO_CANCEL_MINUTES)`
    );

    this.intervalId = setInterval(() => {
      this.checkAndCancelOrders();
    }, this.CHECK_INTERVAL_MS);

    // Pehli baar turant bhi check karo
    this.checkAndCancelOrders();
  }

  static stop(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
      console.log('⏹️ [AutoCancel] Stopped');
    }
  }

  private static async checkAndCancelOrders(): Promise<void> {
    try {
      // index.ts start()s this in every PM2 cluster worker and on every EC2 box,
      // so without a gate the sweep runs N times concurrently. TTL is 3x the
      // 60s interval so a slow tick never drops leadership mid-run.
      const lead = await LeaderElectionService.isLeader('order-auto-cancel', 180);
      if (!lead) return;

      const orderRepository = AppDataSource.getRepository(Order);

      const cutoffTime = new Date(Date.now() - this.autoCancelAfterMs);
      const unpaidCutoff = new Date(Date.now() - this.unpaidAutoCancelAfterMs);

      // Two windows on one pass:
      //   - an online order that was never paid for  -> the SHORT window
      //   - anything else still pending              -> the original long one
      //
      // Expressed as OR rather than two queries so the leader-election gate and
      // the atomic claim below still cover the whole sweep exactly as before.
      const staleOrders = await orderRepository
        .createQueryBuilder('order')
        .leftJoinAndSelect('order.user', 'user')
        .leftJoinAndSelect('order.items', 'items')
        .leftJoinAndSelect('items.product', 'product')
        .leftJoinAndSelect('items.variant', 'variant')
        .where('order.status = :pending', { pending: 'pending' })
        .andWhere(
          new Brackets((qb) => {
            qb.where(
              // NOTE: `payment_status`, not `paymentStatus`. The entity maps that
              // property to a snake_case column via @Column({ name: ... }), and
              // this is a RAW SQL fragment — tsc cannot check it, and a wrong
              // name here fails at runtime inside the sweep's catch, where it
              // would look like the job silently doing nothing. Same convention
              // AdminController.listRiders uses for `o.delivery_status`.
              `(order.paymentMethod IS NOT NULL
                AND order.paymentMethod != :cod
                AND (order.payment_status IS NULL OR order.payment_status IN (:...unpaidStatuses))
                AND order.createdAt < :unpaidCutoff)`,
              { cod: 'cod', unpaidStatuses: ['initiated', 'failed'], unpaidCutoff }
            ).orWhere('order.createdAt < :cutoffTime', { cutoffTime });
          })
        )
        .getMany();

      if (staleOrders.length === 0) return;

      console.log(`🔄 [AutoCancel] Found ${staleOrders.length} stale pending order(s)`);

      const windowMins = Math.round(this.autoCancelAfterMs / 60_000);

      for (const order of staleOrders) {
        // Atomic claim BEFORE restoring stock. Without it this was a plain
        // read-then-write: every PM2 cluster worker (instances: 'max') and every
        // EC2 box behind the ALB reads the same order as 'pending' and each one
        // calls restoreReservedStockForItems — crediting inventory N times for a
        // single cancellation. PaymentsV2Service.markPaymentFailed restores stock
        // under the identical `status === 'pending'` condition and races this too.
        //
        // Only the worker whose UPDATE actually flips the row does the restore.
        // Same pattern as AdminController.updateOrderStatus / approveCancellation.
        const claim = await orderRepository.update(
          { id: order.id, status: 'pending' },
          { status: 'cancelled' }
        );
        if (claim.affected !== 1) {
          // Someone else (another worker, a payment failure, an admin) already
          // moved this order out of 'pending'. They own the stock restore.
          continue;
        }

        await OrderInventoryService.restoreReservedStockForItems(order.items);
        order.status = 'cancelled';

        // An abandoned online checkout is cleaned up SILENTLY. The customer
        // deliberately backed out of the payment sheet and the app already told
        // them the payment did not go through; a push saying "your order was
        // cancelled" ten minutes later is noise about an order that, from both
        // their side and the store's, never existed. The store never saw it
        // either (getAllOrders hides unpaid online orders), so alerting admins
        // about its disposal is equally pointless.
        const abandoned = OrderAutoCancelService.isAbandonedOnlinePayment(order);
        const mins = Math.round(
          (abandoned ? this.unpaidAutoCancelAfterMs : this.autoCancelAfterMs) / 60_000
        );

        console.log(
          abandoned
            ? `🧹 [AutoCancel] Order #${order.id} discarded — payment never completed (> ${mins} min), stock restored, no notifications sent`
            : `❌ [AutoCancel] Order #${order.id} auto-cancelled (pending > ${mins} min), stock restored`
        );

        if (abandoned) continue;

        const oid = order.id;
        const userToken = order.user?.fcmToken;
        const customerId = order.user?.id;
        if (userToken && customerId != null) {
          FCMService.enqueue(
            () =>
              FCMService.sendNotification(
                userToken,
                '😔 Order Cancelled',
                `We're sorry! Your order #${oid} couldn't be processed this time. Please try again — we'd love to serve you! 🙏`,
                { orderId: oid.toString(), type: 'ORDER_CANCELLED' },
                `auto-cancel customerId=${customerId} order=#${oid}`,
                customerId
              ),
            `auto-cancel notify customer #${oid}`
          );
        }

        FCMService.enqueue(
          () =>
            FCMService.sendNotificationToRole(
              'admin',
              '⚠️ Order Auto-Cancelled',
              `⚠️ Order #${oid} auto-cancelled — was pending for ${windowMins} minutes`,
              { orderId: oid.toString(), type: 'ORDER_CANCELLED' }
            ),
          `auto-cancel notify admins #${oid}`
        );
      }
    } catch (error) {
      console.error('❌ [AutoCancel] Error:', error);
    }
  }
}
