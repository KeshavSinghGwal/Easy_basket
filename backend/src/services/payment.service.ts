import { AppDataSource } from '../config/database';
import { Order } from '../entities/Order';
import { PaymentsV2Service } from './payments-v2.service';
import { RazorpayService } from './razorpay.service';

/**
 * Backward-compatibility facade.
 *
 * Older code (e.g. OrderController.createOrder) calls PaymentService.createOrder(rupees, currency, receipt)
 * and expects a Razorpay-shaped order object. We keep that signature but route through
 * PaymentsV2Service.initiatePayment so a Payment row is persisted and the state machine stays coherent.
 *
 * New code should call PaymentsV2Service directly.
 */
export class PaymentService {
  static initialize(): void {
    // No-op: RazorpayService builds its SDK client lazily on first use, so there is
    // nothing to initialize here. Kept for callers that relied on the side effect.
  }

  static async createOrder(
    amountRupees: number,
    currency: string = 'INR',
    receipt: string
  ): Promise<{ id: string; amount: number; currency: string }> {
    const orderId = parseOrderIdFromReceipt(receipt);
    if (orderId == null) {
      // Legacy / unknown receipt format — fall back to a raw Razorpay order so we don't break callers.
      const amountPaise = Math.round(amountRupees * 100);
      const rzp = await RazorpayService.createOrder({ amountPaise, currency, receipt });
      return { id: rzp.id, amount: Number(rzp.amount), currency: rzp.currency };
    }

    const order = await AppDataSource.getRepository(Order).findOne({
      where: { id: orderId },
      relations: ['user'],
    });
    if (!order) throw new Error(`Order ${orderId} not found`);

    const amountPaise = PaymentsV2Service.toPaise(amountRupees);
    const out = await PaymentsV2Service.initiatePayment({
      orderId,
      userId: order.user.id,
      amountPaise,
    });

    return {
      id: out.razorpayOrderId,
      amount: out.amountPaise,
      currency: out.currency,
    };
  }

  /**
   * @deprecated Use PaymentsV2Service.handleVerify (goes through the full state machine
   * and returns a structured result). Kept only for any external callers.
   */
  static async verifyPayment(
    paymentId: string,
    razorpayOrderId: string,
    signature: string
  ): Promise<boolean> {
    return RazorpayService.verifyCheckoutSignature({
      razorpayOrderId,
      razorpayPaymentId: paymentId,
      signature,
    });
  }
}

function parseOrderIdFromReceipt(receipt: string): number | null {
  const m = /^(?:ORDER_|order_)(\d+)$/.exec(receipt);
  if (!m) return null;
  const n = parseInt(m[1], 10);
  return Number.isFinite(n) ? n : null;
}

// Preserve the module-load side effect the old file had so importers don't regress.
PaymentService.initialize();
