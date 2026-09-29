import { Request, Response } from 'express';
import crypto from 'crypto';
import { In } from 'typeorm';
import { AppDataSource } from '../config/database';
import { Order } from '../entities/Order';
import { OrderEvent } from '../entities/OrderEvent';
import { Payment } from '../entities/Payment';
import { PaymentsV2Service } from '../services/payments-v2.service';
import { RazorpayService } from '../services/razorpay.service';
import { AuthRequest } from '../middleware/auth.middleware';
import { RateLimitService } from '../services/rate-limit.service';

/**
 * Per-user rate limits for the payment endpoints.
 *
 * None of these were limited before, though RateLimitService already existed (used
 * only for OTP send). create-order issues a real Razorpay API call per request, so
 * an authenticated loop burns the account's API quota and fills the payments table;
 * verify is otherwise a free signature-checking oracle. The ceilings are set well
 * above what a human retrying a stuck checkout would ever produce.
 */
const PAYMENT_RATE_LIMITS = {
  createOrder: { limit: 10, windowSec: 60 },
  verify: { limit: 20, windowSec: 60 },
  refund: { limit: 20, windowSec: 60 },
} as const;

/** Returns true if the request may proceed; writes the 429 itself if not. */
async function withinRateLimit(
  res: Response,
  bucket: keyof typeof PAYMENT_RATE_LIMITS,
  userId: number
): Promise<boolean> {
  const { limit, windowSec } = PAYMENT_RATE_LIMITS[bucket];
  try {
    const out = await RateLimitService.checkAndIncrement(
      `rl:payment:${bucket}:${userId}`,
      limit,
      windowSec
    );
    if (!out.allowed) {
      res
        .status(429)
        .json({ message: 'Too many payment requests. Please wait a moment and try again.' });
      return false;
    }
    return true;
  } catch (err) {
    // Redis down. Fail OPEN — blocking checkout entirely is worse than the abuse
    // this guards against, and the endpoints remain authenticated regardless.
    console.warn(`[payment] rate limit check failed for ${bucket}`, (err as Error).message);
    return true;
  }
}

export class PaymentController {
  /**
   * POST /api/payment/create-order
   * Authenticated. Creates (or returns the existing in-flight) Razorpay order for a given
   * internal order id. Server prices the order — the amount on the request is ignored.
   */
  static async createRazorpayOrder(req: AuthRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      const { orderId } = req.body as { orderId?: string | number };
      if (orderId == null) {
        res.status(400).json({ message: 'orderId is required' });
        return;
      }

      const orderIdNum = typeof orderId === 'number' ? orderId : parseInt(String(orderId), 10);
      if (!Number.isFinite(orderIdNum)) {
        res.status(400).json({ message: 'Invalid orderId' });
        return;
      }

      const order = await AppDataSource.getRepository(Order).findOne({
        where: { id: orderIdNum },
        relations: ['user'],
      });

      if (!order || order.user.id !== userId) {
        res.status(404).json({ message: 'Order not found' });
        return;
      }

      if (order.status === 'cancelled' || order.status === 'delivered') {
        res.status(409).json({ message: `Cannot pay for order in status ${order.status}` });
        return;
      }

      // Refuse to mint a second Razorpay order for an order that has already been
      // paid for.
      //
      // The status guard above only rejects 'cancelled' and 'delivered'. An order
      // in 'awaiting_acceptance' or 'accepted' — which is exactly what a PAID
      // order looks like — sailed straight through, and initiatePayment then found
      // no fresh `initiated` row (it only ever looks for that one status) and
      // created a brand-new Razorpay order. The customer could pay twice.
      //
      // applyCapture does catch the duplicate afterwards and auto-refunds it as
      // DUPLICATE_PAYMENT_FOR_ORDER, but the money really leaves the customer's
      // account and takes 2-7 working days to come back. That is a recovery path
      // being used as a control. This is the same sibling lookup applyCapture
      // performs, applied as a precondition instead.
      const settledPayment = await AppDataSource.getRepository(Payment).findOne({
        where: {
          orderId: orderIdNum,
          status: In(['paid', 'refund_pending', 'refunded']),
        },
      });
      if (settledPayment) {
        res.status(409).json({
          message: 'This order has already been paid for.',
          code: 'ALREADY_PAID',
        });
        return;
      }

      if (!(await withinRateLimit(res, 'createOrder', userId))) return;

      // A COD order is not payable online by default. Nothing checked paymentMethod
      // here before, so a COD order could be pushed through the online flow and then
      // ALSO have cash collected at the door. The rider's "Switch to UPI" flow is the
      // one legitimate exception, and it records a `switched_to_upi` order event —
      // which is what we look for rather than mutating order.paymentMethod, so the
      // rider can still fall back to cash if the customer never completes the payment.
      if (order.paymentMethod === 'cod') {
        const switched = await AppDataSource.getRepository(OrderEvent).findOne({
          where: { orderId: orderIdNum, eventType: 'switched_to_upi' },
        });
        if (!switched) {
          res.status(409).json({
            message: 'This is a cash-on-delivery order. Ask the delivery partner to switch it to UPI.',
          });
          return;
        }
      }

      const amountPaise = PaymentsV2Service.toPaise(order.totalAmount);
      const out = await PaymentsV2Service.initiatePayment({
        orderId: orderIdNum,
        userId,
        amountPaise,
      });

      res.json({
        razorpayOrderId: out.razorpayOrderId,
        amount: out.amountPaise,
        currency: out.currency,
        key: out.keyId,
      });
    } catch (error) {
      console.error('[payment] createRazorpayOrder error', error);
      res.status(500).json({ message: 'Error creating payment order' });
    }
  }

  /**
   * POST /api/payment/verify
   * Authenticated. Verifies the HMAC signature Razorpay returns to the client after
   * Checkout succeeds, then advances payment state to `success_unverified`.
   * The webhook (or reconciler) is what finally promotes it to `paid`.
   */
  static async verifyPayment(req: AuthRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      if (!(await withinRateLimit(res, 'verify', userId))) return;

      const body = req.body as {
        razorpayOrderId?: string;
        razorpayPaymentId?: string;
        razorpaySignature?: string;
        // legacy param names from the old mobile client
        paymentId?: string;
        signature?: string;
        orderId?: number | string;
      };

      const razorpayOrderId = body.razorpayOrderId;
      const razorpayPaymentId = body.razorpayPaymentId ?? body.paymentId;
      const signature = body.razorpaySignature ?? body.signature;

      if (!razorpayOrderId || !razorpayPaymentId || !signature) {
        res.status(400).json({
          message: 'razorpayOrderId, razorpayPaymentId and signature are required',
        });
        return;
      }

      const result = await PaymentsV2Service.handleVerify({
        userId,
        razorpayOrderId,
        razorpayPaymentId,
        signature,
      });

      if (!result.ok) {
        res.status(result.code).json({ message: result.reason });
        return;
      }

      res.json({ message: 'Payment verified', paymentStatus: result.status });
    } catch (error) {
      console.error('[payment] verifyPayment error', error);
      res.status(500).json({ message: 'Error verifying payment' });
    }
  }

  /**
   * POST /api/payment/webhook/razorpay
   * Unauthenticated from client POV — the X-Razorpay-Signature header is the auth.
   * IMPORTANT: this route MUST be mounted with express.raw({ type: 'application/json' })
   * BEFORE the global express.json() middleware, otherwise signature verification fails.
   * See index.ts.
   */
  static async razorpayWebhook(req: Request, res: Response): Promise<void> {
    try {
      const sig = req.header('x-razorpay-signature') ?? '';
      const rawBody: Buffer = Buffer.isBuffer(req.body)
        ? req.body
        : Buffer.from(typeof req.body === 'string' ? req.body : JSON.stringify(req.body), 'utf8');

      if (!RazorpayService.verifyWebhookSignature(rawBody, sig)) {
        console.warn('[webhook] signature verification FAILED');
        res.status(401).json({ message: 'Invalid signature' });
        return;
      }

      const parsed = JSON.parse(rawBody.toString('utf8')) as {
        event?: string;
        payload?: unknown;
      };
      const eventType = parsed.event;
      if (!eventType) {
        res.status(400).json({ message: 'Missing event' });
        return;
      }

      // Prefer Razorpay's event id if present; fall back to a stable hash of the body.
      const eventId =
        (req.header('x-razorpay-event-id') as string | undefined) ??
        deriveEventIdFromBody(rawBody);

      const result = await PaymentsV2Service.handleWebhook({
        eventId,
        eventType,
        payload: parsed as unknown as Record<string, unknown>,
      });

      // A busy payment lock means we did NOT process this event. Answering 200 would
      // retire it from Razorpay's retry schedule and lose it, so ask to be retried.
      if (result.retryable) {
        res.status(503).json({ received: false, ...result });
        return;
      }

      // Otherwise 200 — the event was processed, or safely deduped as a replay.
      res.status(200).json({ received: true, ...result });
    } catch (error) {
      console.error('[webhook] handler error', error);
      // Return 500 so Razorpay retries; our dedupe ensures safety.
      res.status(500).json({ message: 'Webhook processing error' });
    }
  }

  /**
   * POST /api/payment/refund
   * ADMIN ONLY. Refunds are never self-service — the customer-facing route to a
   * refund is requesting a cancellation, which AdminController.approveCancellation
   * grants only before the order is packed.
   * Idempotency-Key header required.
   */
  static async refund(req: AuthRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      if (!userId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      if (!(await withinRateLimit(res, 'refund', userId))) return;

      const { orderId, reason } = req.body as { orderId?: number; reason?: string };
      const idem = (req.header('idempotency-key') ?? '').trim();
      if (!orderId || !idem) {
        res.status(400).json({ message: 'orderId and Idempotency-Key header are required' });
        return;
      }
      if (!/^[A-Za-z0-9_\-:]{8,64}$/.test(idem)) {
        res.status(400).json({ message: 'Invalid Idempotency-Key' });
        return;
      }

      const order = await AppDataSource.getRepository(Order).findOne({
        where: { id: orderId },
        relations: ['user'],
      });
      if (!order) {
        res.status(404).json({ message: 'Order not found' });
        return;
      }

      // Route is already gated by authorize('admin'); assert it here too so the
      // handler stays safe if it is ever remounted somewhere less strict.
      if (req.user?.role !== 'admin') {
        res.status(403).json({ message: 'Forbidden' });
        return;
      }

      const result = await PaymentsV2Service.createRefund({
        orderId,
        userId: order.user.id,
        actorUserId: userId,
        reason,
        idempotencyKey: idem,
      });

      if (!result.ok) {
        res.status(result.code).json({ message: result.reason });
        return;
      }

      res.json({
        refundId: result.refundId,
        razorpayRefundId: result.razorpayRefundId,
        status: 'pending',
      });
    } catch (error) {
      console.error('[payment] refund error', error);
      res.status(500).json({ message: 'Error processing refund' });
    }
  }
}

function deriveEventIdFromBody(buf: Buffer): string {
  // Fallback when Razorpay doesn't send x-razorpay-event-id. Hash of body is stable per event.
  return 'derived:' + crypto.createHash('sha256').update(buf).digest('hex').slice(0, 48);
}
