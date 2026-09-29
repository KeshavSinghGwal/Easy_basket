import { LessThan } from 'typeorm';
import { AppDataSource } from '../config/database';
import { Order } from '../entities/Order';
import { OrderEvent } from '../entities/OrderEvent';
import { FCMService } from './fcm.service';
import { LeaderElectionService } from './leader-election.service';
import { OrderEventsService } from './order-events.service';

/** Marker event. Its presence is what stops this order being alerted again. */
const ALERT_EVENT = 'acceptance_alert';

/**
 * Surfaces paid orders the store has not yet accepted.
 *
 * ALERTS ONLY. This service never changes an order's state — no cancel, no refund,
 * no status write of any kind. That is a deliberate decision: no automatic action is
 * taken on a non-terminal order. A human accepts or refuses; the system's only job
 * is to make sure nobody can quietly forget an order that has a customer's money in it.
 *
 * The trade-off being accepted: if nobody ever acts, the order stays in
 * `awaiting_acceptance` indefinitely and the money stays held. The alert is what
 * makes that a visible situation rather than a silent one.
 *
 * Threshold: ORDER_ACCEPTANCE_ALERT_MINUTES (default 10).
 */
export class OrderAcceptanceAlertService {
  private static intervalId: NodeJS.Timeout | null = null;
  private static readonly CHECK_INTERVAL_MS = 60 * 1000;

  private static resolveThresholdMs(): number {
    const raw = process.env.ORDER_ACCEPTANCE_ALERT_MINUTES;
    const minutes = raw !== undefined ? parseInt(raw, 10) : 10;
    const safe = Number.isFinite(minutes) && minutes > 0 ? minutes : 10;
    return safe * 60 * 1000;
  }

  static start(): void {
    if (this.intervalId) return;
    const mins = this.resolveThresholdMs() / 60_000;
    console.log(
      `🔔 [AcceptanceAlert] Started — flags paid orders unaccepted for ${mins} min (alerts only, never cancels)`
    );
    this.intervalId = setInterval(() => {
      this.sweep().catch((err) => console.error('[AcceptanceAlert] sweep error', err));
    }, this.CHECK_INTERVAL_MS);
  }

  static stop(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  private static async sweep(): Promise<void> {
    // Singleton across the PM2 cluster and both EC2 boxes, so one unaccepted order
    // produces one alert rather than one per worker. TTL is 3x the interval.
    if (!(await LeaderElectionService.isLeader('order-acceptance-alert', 180))) return;

    const orderRepo = AppDataSource.getRepository(Order);
    const eventRepo = AppDataSource.getRepository(OrderEvent);
    const cutoff = new Date(Date.now() - this.resolveThresholdMs());

    const stale = await orderRepo.find({
      where: { status: 'awaiting_acceptance', updatedAt: LessThan(cutoff) },
      relations: ['user'],
      order: { id: 'ASC' },
      take: 100,
    });
    if (stale.length === 0) return;

    for (const order of stale) {
      try {
        // This sweep runs every minute but an order stays unaccepted for as long as
        // the store ignores it. Without a durable marker the same order would alert
        // every 60 seconds forever, which trains everyone to ignore the alerts —
        // the precise opposite of the point. One alert per order, recorded in the
        // audit log so it survives restarts and Redis loss alike.
        const alreadyAlerted = await eventRepo.findOne({
          where: { orderId: order.id, eventType: ALERT_EVENT },
        });
        if (alreadyAlerted) continue;

        await OrderEventsService.log({
          orderId: order.id,
          actorUserId: null,
          actorRole: 'system',
          eventType: ALERT_EVENT,
          fromState: 'awaiting_acceptance',
          toState: 'awaiting_acceptance',
          payload: { unacceptedForMs: Date.now() - order.updatedAt.getTime() },
        });

        console.warn(
          `🔔 [AcceptanceAlert] Order #${order.id} paid but unaccepted — admins notified (state unchanged)`
        );

        this.notifyAdmins(order);
        this.notifyCustomer(order);
      } catch (err) {
        console.error(`[AcceptanceAlert] failed for order #${order.id}`, err);
      }
    }
  }

  /** The only people who can resolve this. */
  private static notifyAdmins(order: Order): void {
    const oid = order.id;
    const mins = Math.round(this.resolveThresholdMs() / 60_000);
    FCMService.enqueue(
      () =>
        FCMService.sendNotificationToRole(
          'admin',
          '⚠️ Paid order not accepted',
          `Order #${oid} was paid ${mins}+ minutes ago and still needs accepting or refusing.`,
          { orderId: String(oid), type: 'acceptance_alert' }
        ),
      `notify admins acceptance alert order=#${oid}`
    );
  }

  /**
   * Deliberately reassuring rather than alarming. The customer can do nothing about
   * this, and the order may well be accepted a minute later — so this acknowledges
   * the wait without promising a time or implying something has gone wrong.
   */
  private static notifyCustomer(order: Order): void {
    const userId = order.user?.id;
    if (userId == null) return;
    const oid = order.id;
    FCMService.enqueue(
      () =>
        FCMService.sendNotificationToUser(
          userId,
          '⏳ Confirming your order',
          `Your payment for order #${oid} went through and we're confirming it with the store. Thanks for bearing with us.`,
          { orderId: String(oid), type: 'acceptance_pending' }
        ),
      `notify customer acceptance pending order=#${oid}`
    );
  }
}
