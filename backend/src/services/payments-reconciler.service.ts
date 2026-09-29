import { LessThan, LessThanOrEqual, IsNull, In } from 'typeorm';
import { AppDataSource } from '../config/database';
import { Payment } from '../entities/Payment';
import { Refund } from '../entities/Refund';
import { RazorpayService } from './razorpay.service';
import { PaymentsV2Service } from './payments-v2.service';
import { LeaderElectionService } from './leader-election.service';

/**
 * Reconciliation worker — the final coarse safety net.
 *
 * Runs every 30 minutes, scanning for payments that might have drifted from Razorpay's
 * view of the world — e.g. webhook got lost, verify never called, refund never reached
 * terminal state. For each drift, we apply the same state-machine transition the webhook
 * would have, so the fix is idempotent and race-safe.
 *
 * The fast path is now the BullMQ payment-reconcile queue (per-payment checks with
 * backoff, ~20s when a webhook is missed). This sweep only catches the rare cases the
 * queue never saw — e.g. a crash between saving the payment and enqueuing its job, or a
 * job that exhausted its retries — and it survives a total Redis/queue outage because it
 * depends only on the DB + Razorpay. Hence the relaxed 30-min cadence.
 *
 * Interval is configurable via RECONCILER_INTERVAL_MINUTES (default 30).
 */
export class PaymentsReconcilerService {
  private static intervalId: NodeJS.Timeout | null = null;

  static start(): void {
    if (this.intervalId) return;
    const raw = process.env.RECONCILER_INTERVAL_MINUTES;
    const minutes = raw ? Number(raw) : 30;
    const safeMins = Number.isFinite(minutes) && minutes > 0 ? minutes : 30;
    const intervalMs = safeMins * 60 * 1000;

    console.log(`[Reconciler] starting — every ${safeMins} min`);

    this.intervalId = setInterval(() => {
      this.tick().catch((err) => console.error('[Reconciler] tick error', err));
    }, intervalMs);

    // Run once at startup after a short delay so DB is ready.
    setTimeout(() => {
      this.tick().catch((err) => console.error('[Reconciler] initial tick error', err));
    }, 15_000);
  }

  static stop(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  static async tick(): Promise<void> {
    // One sweeper across the whole fleet. Every PM2 worker and every EC2 box runs
    // start(), and each unguarded tick re-reads the same 200 rows and re-hits the
    // Razorpay API with identical fetches — pure duplicated quota. The per-payment
    // Redis lock keeps the WRITES safe either way; this stops the redundant READS.
    // TTL is 2.5x the default 30-min interval.
    const intervalMin = Number(process.env.RECONCILER_INTERVAL_MINUTES) || 30;
    const lead = await LeaderElectionService.isLeader(
      'payments-reconciler',
      Math.round(intervalMin * 60 * 2.5)
    );
    if (!lead) return;

    await this.reconcileStalePayments();
    await this.reconcilePendingRefunds();
  }

  /**
   * Payments still in {initiated, success_unverified} after 10 minutes are candidates
   * for drift. Pull authoritative state from Razorpay and correct the DB.
   */
  private static async reconcileStalePayments(): Promise<void> {
    const paymentRepo = AppDataSource.getRepository(Payment);
    const cutoff = new Date(Date.now() - 10 * 60 * 1000);

    const stale = await paymentRepo.find({
      where: {
        status: In(['initiated', 'success_unverified']),
        createdAt: LessThan(cutoff),
      },
      // Oldest first. An unordered LIMIT gives MySQL licence to return the same
      // arbitrary 200 rows every tick, so a backlog larger than the page could
      // starve indefinitely.
      order: { id: 'ASC' },
      take: 200,
    });

    if (stale.length === 0) return;
    console.log(`[Reconciler] ${stale.length} stale payments to check`);

    for (const p of stale) {
      try {
        await this.reconcileOnePayment(p);
      } catch (err) {
        console.error('[Reconciler] failed for payment', p.id, err);
      }
    }
  }

  /**
   * Reconcile a single payment against Razorpay's authoritative state.
   * Public so the BullMQ worker can reuse the exact same logic — one source of
   * truth for "ask Razorpay, then apply the transition."
   */
  static async reconcileOnePayment(p: Payment): Promise<void> {
    const rzp = (await RazorpayService.fetchPaymentsForOrder(p.razorpayOrderId)) as unknown as {
      items?: Array<Record<string, unknown>>;
    };
    const items = rzp.items ?? [];

    // Prefer a captured payment; else most recent.
    const captured = items.find((x) => x.status === 'captured');
    const authorized = items.find((x) => x.status === 'authorized');
    const failed = items.find((x) => x.status === 'failed');
    const latest = captured ?? authorized ?? failed ?? items[items.length - 1];

    if (!latest) {
      // No payment attempted at all — if row is very old, mark failed and release inventory.
      const ageMs = Date.now() - p.createdAt.getTime();
      if (ageMs > 60 * 60 * 1000) {
        await PaymentsV2Service.withPaymentLock(p.razorpayOrderId, () =>
          PaymentsV2Service.markPaymentFailed(p, 'RECONCILER_TIMEOUT')
        );
      }
      return;
    }

    const latestStatus = latest.status as string;
    const latestId = latest.id as string;
    const latestAmount = Number(latest.amount);

    if (latestStatus === 'captured') {
      // Explicit amount check at the reconciler layer — the source of truth for what
      // we expected is p.amountPaise (set at payment initiation from order.totalAmount).
      // If Razorpay captured a different amount, this is real fraud or a wiring bug:
      // fail the payment, release inventory, and let admin trigger a refund.
      if (latestAmount !== Number(p.amountPaise)) {
        console.error('[Reconciler] AMOUNT_MISMATCH', {
          rzpOrder: p.razorpayOrderId,
          expected: p.amountPaise,
          received: latestAmount,
        });
        const out = await PaymentsV2Service.withPaymentLock(p.razorpayOrderId, () =>
          PaymentsV2Service.markPaymentFailed(p, 'AMOUNT_MISMATCH')
        );
        if (!out.ran) {
          console.log(`[Reconciler] lock busy for ${p.razorpayOrderId}; will retry next tick`);
        }
        return;
      }

      const out = await PaymentsV2Service.withPaymentLock(p.razorpayOrderId, () =>
        PaymentsV2Service.markPaymentPaid(p, latestId)
      );
      if (out.ran) {
        console.log(`[Reconciler] fixed missing payment.captured for ${p.razorpayOrderId}`);
      } else {
        console.log(`[Reconciler] lock busy for ${p.razorpayOrderId}; will retry next tick`);
      }
      return;
    }

    if (latestStatus === 'failed') {
      const out = await PaymentsV2Service.withPaymentLock(p.razorpayOrderId, () =>
        PaymentsV2Service.markPaymentFailed(p, 'PAYMENT_FAILED')
      );
      if (out.ran) {
        console.log(`[Reconciler] marked failed for ${p.razorpayOrderId}`);
      } else {
        console.log(`[Reconciler] lock busy for ${p.razorpayOrderId}; will retry next tick`);
      }
      return;
    }

    // authorized / created / else — not terminal yet, leave for next tick.
  }

  /**
   * Refunds stuck in `pending` for >30 min — fetch state from Razorpay.
   */
  private static async reconcilePendingRefunds(): Promise<void> {
    const refundRepo = AppDataSource.getRepository(Refund);
    const cutoff = new Date(Date.now() - 30 * 60 * 1000);

    // Honour next_retry_at, which is what the column is FOR.
    //
    // This used to select purely on `createdAt < now - 30m`, so recordRefundOwed —
    // the Redis-down path, which writes next_retry_at = now precisely to mean "retry
    // immediately" — was ignored and every deferred refund waited a full 30 minutes.
    // Migration 006 added idx_refund_retry (status, next_retry_at) and documented it
    // as "the index the reconciler backstop scans on"; nothing scanned it until now.
    //
    // Rows with no next_retry_at (the normal success path) keep the old age rule.
    const pending = await refundRepo.find({
      where: [
        { status: 'pending', nextRetryAt: LessThanOrEqual(new Date()) },
        { status: 'pending', nextRetryAt: IsNull(), createdAt: LessThan(cutoff) },
      ],
      order: { id: 'ASC' },
      take: 200,
    });

    for (const r of pending) {
      try {
        // No Razorpay id means the API call never landed. This used to `continue`,
        // which is why such rows were never retried by anything — and because a
        // pending row still counts toward the active-refund cap, it permanently
        // blocked any further refund for that payment. Hand it to the same retry
        // path the queue uses; this is the backstop for a Redis/queue outage.
        if (!r.razorpayRefundId) {
          const result = await PaymentsV2Service.retryRefund({
            refundId: r.id,
            manual: false,
          });
          if (!result.ok && !('rescheduled' in result)) {
            console.warn(`[Reconciler] refund ${r.id} not retried: ${result.reason}`);
          }
          continue;
        }
        const rzpRefund = (await RazorpayService.fetchRefund(r.razorpayRefundId)) as {
          status?: string;
        };
        if (rzpRefund.status === 'processed') {
          r.status = 'processed';
          await refundRepo.save(r);
          // Delegated: handles idempotent state transition + FCM notification in one place.
          await PaymentsV2Service.markPaymentRefunded(r.paymentId);
        } else if (rzpRefund.status === 'failed') {
          r.status = 'failed';
          await refundRepo.save(r);
        }
      } catch (err) {
        console.error('[Reconciler] refund check failed', r.id, err);
      }
    }
  }
}

