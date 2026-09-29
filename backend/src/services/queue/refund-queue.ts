import { Queue } from 'bullmq';
import { buildBullConnection } from './connection';

export const REFUND_QUEUE_NAME = 'refund-retry';

export interface RefundRetryJobData {
  refundId: string;
  /** Razorpay order id of the parent payment — used to take the shared payment lock. */
  razorpayOrderId: string;
}

/**
 * Automatic retry for refunds whose Razorpay call did not succeed.
 *
 * Policy (see PaymentsV2Service.attemptRazorpayRefund):
 *   attempt 1  inline, during createRefund
 *   attempt 2  here, ~30s later
 *   exhausted  refund row parked at status='failed' → admin "Retry refund" button
 *
 * Jobs live in Redis so a restart doesn't lose a scheduled retry. The 30-min
 * reconciler sweep remains the backstop for a total Redis/queue outage, since
 * it depends only on the DB + Razorpay.
 */
export const refundQueue = new Queue<RefundRetryJobData>(REFUND_QUEUE_NAME, {
  connection: buildBullConnection(),
});

/** Delay before the single automatic retry. */
export const REFUND_RETRY_DELAY_MS = Number(process.env.REFUND_RETRY_DELAY_MS) || 30_000;

/**
 * Delay used when a job could not acquire the payment lock. This is a
 * reschedule, NOT a refund attempt — attempt_count is not incremented, so a
 * busy lock can never consume the customer's one automatic retry.
 */
export const REFUND_RESCHEDULE_DELAY_MS =
  Number(process.env.REFUND_RESCHEDULE_DELAY_MS) || 300_000;

/**
 * Schedule the automatic retry for a refund.
 *
 * `jobId` is deterministic per refund+attempt so that two callers racing to
 * schedule the same retry (e.g. the inline failure path and a webhook-driven
 * one) produce a single job rather than two competing attempts.
 */
export async function enqueueRefundRetry(
  refundId: string,
  razorpayOrderId: string,
  attemptNumber: number,
  delayMs: number = REFUND_RETRY_DELAY_MS
): Promise<void> {
  await refundQueue.add(
    'retry',
    { refundId, razorpayOrderId },
    {
      jobId: `refund-retry-${refundId}-${attemptNumber}`,
      delay: delayMs,
      // One BullMQ attempt only. Our own attempt_count is the source of truth
      // for retry budget, so BullMQ must not silently multiply it.
      attempts: 1,
      removeOnComplete: true,
      removeOnFail: 1000,
    }
  );
}
