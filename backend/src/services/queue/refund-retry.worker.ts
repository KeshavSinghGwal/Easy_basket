import { Worker, type Job } from 'bullmq';
import { PaymentsV2Service } from '../payments-v2.service';
import { buildBullConnection } from './connection';
import { REFUND_QUEUE_NAME, type RefundRetryJobData } from './refund-queue';

const CONCURRENCY = Number(process.env.REFUND_WORKER_CONCURRENCY) || 3;

/**
 * BullMQ worker that performs the single automatic refund retry.
 *
 * All the real logic lives in PaymentsV2Service.retryRefund — the same entry
 * point the admin "Retry refund" button uses — so manual and automatic retries
 * cannot diverge. That method takes the shared per-payment Redis lock and does
 * the adopt-before-create check against Razorpay, so this worker racing a live
 * webhook cannot produce a duplicate refund.
 *
 * The job does not throw on a failed attempt: retry budget is tracked in
 * `refunds.attempt_count`, not by BullMQ, so letting BullMQ retry on its own
 * would multiply attempts past the configured maximum. A busy payment lock is
 * rescheduled by retryRefund itself without consuming an attempt.
 */
export function startRefundWorker(): Worker<RefundRetryJobData> {
  const worker = new Worker<RefundRetryJobData>(
    REFUND_QUEUE_NAME,
    async (job: Job<RefundRetryJobData>) => {
      const { refundId } = job.data;
      const result = await PaymentsV2Service.retryRefund({ refundId, manual: false });

      if (result.ok) {
        console.log(`[refund-worker] refund ${refundId} → ${result.status}`);
        return;
      }
      if ('rescheduled' in result) {
        console.log(`[refund-worker] refund ${refundId} rescheduled — lock busy`);
        return;
      }
      // Attempt genuinely failed and was recorded on the row (status='failed' once
      // the budget is spent). Nothing more for the queue to do — admin takes over.
      console.warn(`[refund-worker] refund ${refundId} not retried: ${result.reason}`);
    },
    { connection: buildBullConnection(), concurrency: CONCURRENCY }
  );

  worker.on('failed', (job, err) =>
    console.error(`[refund-worker] job ${job?.id} failed: ${err.message}`)
  );

  console.log(`[refund-worker] started (concurrency=${CONCURRENCY})`);
  return worker;
}
