import { Queue } from 'bullmq';
import { buildBullConnection } from './connection';

export const PAYMENT_QUEUE_NAME = 'payment-reconcile';

export interface PaymentReconcileJobData {
  paymentId: string;
  razorpayOrderId: string;
}

/**
 * Fast, restart-proof fallback for confirming payments when the Razorpay webhook
 * is missed. Jobs live in Redis, so a server restart doesn't lose scheduled
 * checks (unlike the in-memory setInterval reconciler, which stays as the final
 * coarse safety net).
 */
export const paymentQueue = new Queue<PaymentReconcileJobData>(PAYMENT_QUEUE_NAME, {
  connection: buildBullConnection(),
});

const FIRST_DELAY_MS = Number(process.env.PAYMENT_RECONCILE_FIRST_DELAY_MS) || 20_000;
const ATTEMPTS = Number(process.env.PAYMENT_RECONCILE_ATTEMPTS) || 8;

/**
 * Schedule a fallback check for a freshly-created payment. The webhook still
 * confirms first when it arrives; the worker only acts if it didn't. Idempotent
 * per payment via a deterministic jobId, so re-initiating the same payment
 * (the 15-min reuse path) won't create a duplicate job.
 */
export async function enqueuePaymentCheck(
  paymentId: string,
  razorpayOrderId: string
): Promise<void> {
  await paymentQueue.add(
    'reconcile',
    { paymentId, razorpayOrderId },
    {
      jobId: `reconcile-${paymentId}`,
      delay: FIRST_DELAY_MS,
      attempts: ATTEMPTS,
      backoff: { type: 'exponential', delay: FIRST_DELAY_MS },
      removeOnComplete: true,
      removeOnFail: 1000,
    }
  );
}
