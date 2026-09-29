import crypto from 'crypto';
import Razorpay from 'razorpay';

/**
 * Thin wrapper around the Razorpay SDK.
 *
 * Two separate secrets:
 *   - RAZORPAY_KEY_SECRET    → signs the client-side verify callback
 *   - RAZORPAY_WEBHOOK_SECRET → signs server→server webhook POSTs
 *
 * Never log either.
 */
export class RazorpayService {
  private static instance: Razorpay | null = null;

  /**
   * Lazily construct the SDK client on first use.
   *
   * This used to be an eager `RazorpayService.init()` at the bottom of this module.
   * That ran at import time — and because TypeScript emits every `import` as a
   * `require` hoisted above the first statement, it executed BEFORE index.ts called
   * `dotenv.config()`. The keys were therefore always undefined at init, and the
   * whole thing only worked in production by accident: ecosystem.config.js happens
   * to inject RAZORPAY_KEY_ID/SECRET into the PM2 env. Run `npm start` directly, or
   * trim that allowlist, and every payment threw 'Razorpay not initialized'.
   *
   * Reading env on first call instead makes the module load-order-independent.
   */
  static client(): Razorpay {
    if (!this.instance) {
      const id = process.env.RAZORPAY_KEY_ID;
      const secret = process.env.RAZORPAY_KEY_SECRET;
      if (!id || !secret) {
        throw new Error('Razorpay not initialized (missing RAZORPAY_KEY_ID/RAZORPAY_KEY_SECRET)');
      }
      this.instance = new Razorpay({ key_id: id, key_secret: secret });
      console.log('[Razorpay] client initialized');
    }
    return this.instance;
  }

  /** Returns the Razorpay order object. amountPaise must be an integer. */
  static async createOrder(params: {
    amountPaise: number;
    currency?: string;
    receipt: string;
    notes?: Record<string, string>;
  }) {
    return this.client().orders.create({
      amount: params.amountPaise,
      currency: params.currency ?? 'INR',
      receipt: params.receipt,
      notes: params.notes,
      // Force auto-capture so a payment can't settle as 'authorized' but never
      // 'captured' (which would leave the order unconfirmed until it auto-cancels).
      // Belt-and-suspenders alongside the account-level auto-capture setting.
      payment_capture: true,
    });
  }

  /** Paginated fetch of all payments attempted against a Razorpay order. */
  static async fetchPaymentsForOrder(razorpayOrderId: string) {
    return this.client().orders.fetchPayments(razorpayOrderId);
  }

  static async fetchPayment(razorpayPaymentId: string) {
    return this.client().payments.fetch(razorpayPaymentId);
  }

  static async fetchRefund(razorpayRefundId: string) {
    return this.client().refunds.fetch(razorpayRefundId);
  }

  /**
   * All refunds Razorpay holds against a payment.
   *
   * This is what makes retrying a refund safe. `receipt` is NOT an idempotency
   * key on Razorpay's side (it is free-text), so if our POST timed out *after*
   * Razorpay created the refund, blindly retrying would issue a SECOND real
   * refund. Callers must check here first and adopt any existing refund that
   * carries our refund id in `notes.refund_id`.
   */
  static async fetchRefundsForPayment(razorpayPaymentId: string) {
    return this.client().payments.fetchMultipleRefund(razorpayPaymentId);
  }

  static async createRefund(params: {
    razorpayPaymentId: string;
    amountPaise: number;
    notes?: Record<string, string>;
    idempotencyKey: string;
  }) {
    // Razorpay supports speed 'normal' by default. Pass notes for our refund id.
    return this.client().payments.refund(params.razorpayPaymentId, {
      amount: params.amountPaise,
      notes: params.notes,
      // receipt acts like an idempotency hint on Razorpay side
      receipt: params.idempotencyKey,
    } as unknown as Parameters<Razorpay['payments']['refund']>[1]);
  }

  /**
   * Verify the signature returned to the client after checkout:
   *   HMAC_SHA256(razorpay_order_id + "|" + razorpay_payment_id, key_secret)
   * Constant-time compare — never use ===.
   */
  static verifyCheckoutSignature(params: {
    razorpayOrderId: string;
    razorpayPaymentId: string;
    signature: string;
  }): boolean {
    const secret = process.env.RAZORPAY_KEY_SECRET;
    if (!secret) return false;
    const expected = crypto
      .createHmac('sha256', secret)
      .update(`${params.razorpayOrderId}|${params.razorpayPaymentId}`)
      .digest('hex');
    return safeEqualHex(expected, params.signature);
  }

  /**
   * Verify the X-Razorpay-Signature header on an incoming webhook.
   * Requires the RAW request body (string or Buffer) — parsed JSON will NOT match.
   */
  static verifyWebhookSignature(rawBody: string | Buffer, signatureHeader: string): boolean {
    const secret = process.env.RAZORPAY_WEBHOOK_SECRET;
    if (!secret || !signatureHeader) return false;
    const body = Buffer.isBuffer(rawBody) ? rawBody : Buffer.from(rawBody, 'utf8');
    const expected = crypto.createHmac('sha256', secret).update(body).digest('hex');
    return safeEqualHex(expected, signatureHeader);
  }
}

function safeEqualHex(a: string, b: string): boolean {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  if (a.length !== b.length) return false;
  try {
    return crypto.timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
  } catch {
    return false;
  }
}
