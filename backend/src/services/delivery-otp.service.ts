import crypto from 'crypto';
import { AppDataSource } from '../config/database';
import { Order } from '../entities/Order';
import { TwilioService } from './twilio.service';

/**
 * Delivery-doorstep OTP — delegated to Twilio Verify (the same provider used
 * for login OTP). Twilio holds the verification state for us; we never see the
 * plaintext code. The customer receives it via SMS to the phone on their account.
 *
 * Three operating modes (mirrors the login flow in auth.controller.ts):
 *
 *   A. Real Twilio (production)
 *        Twilio is configured AND DELIVERY_USE_TEST_OTP is unset/false.
 *        Real SMS sent, Twilio verifies the typed code.
 *
 *   B. Test mode (dev/QA — saves SMS cost)
 *        Twilio configured BUT DELIVERY_USE_TEST_OTP=true.
 *        No SMS dispatched. Only DELIVERY_TEST_OTP_VALUE (`123456`) is accepted.
 *
 *   C. Twilio not configured (fallback)
 *        Auto-accepts DELIVERY_TEST_OTP_VALUE so dev doesn't get blocked when
 *        Twilio keys aren't set.
 *
 * No FCM push for OTP — SMS only. (Customer apps that need a "delivery started"
 * nudge can subscribe to a separate non-OTP push.)
 */
export class DeliveryOtpService {
  private static readonly DELIVERY_TEST_OTP_VALUE = '123456';

  /**
   * Test-mode toggle. Mirrors auth.controller.isLoginTestOtpEnabled — when on,
   * every order's OTP step accepts only DELIVERY_TEST_OTP_VALUE and no SMS goes out.
   */
  private static isDeliveryTestOtpEnabled(): boolean {
    const v = process.env.DELIVERY_USE_TEST_OTP?.trim().toLowerCase();
    return v === 'true' || v === '1' || v === 'yes';
  }

  /**
   * Send the OTP via Twilio SMS to the customer phone on the order.
   * Skips SMS in test mode and when Twilio isn't configured.
   */
  static async generateForOrder(orderId: number): Promise<{ phoneNumber: string }> {
    const order = await AppDataSource.getRepository(Order).findOne({
      where: { id: orderId },
      relations: ['user'],
      select: { id: true, user: { id: true, phoneNumber: true } },
    });
    const phone = order?.user?.phoneNumber;
    if (!phone) {
      throw new Error(`Cannot send OTP: customer phone not found for order ${orderId}`);
    }

    const useTestOtp = this.isDeliveryTestOtpEnabled();

    if (TwilioService.isConfigured() && !useTestOtp) {
      // Mode A: real SMS.
      await TwilioService.sendVerification(phone, 'sms');
      console.log(`Delivery OTP sent via Twilio for order ${orderId} (${phone})`);
    } else if (TwilioService.isConfigured() && useTestOtp) {
      // Mode B: test mode — skip SMS.
      console.log(
        `Delivery OTP test mode (DELIVERY_USE_TEST_OTP) for order ${orderId}; ` +
          `SMS not sent. Use ${this.DELIVERY_TEST_OTP_VALUE}.`
      );
    } else {
      // Mode C: Twilio not configured.
      console.log(
        `Delivery OTP request for order ${orderId}. Twilio not configured. ` +
          `Use OTP: ${this.DELIVERY_TEST_OTP_VALUE}`
      );
    }
    return { phoneNumber: phone };
  }

  /**
   * Verify an OTP supplied by the rider.
   *
   *   Mode A: ask Twilio.
   *   Mode B: accept only DELIVERY_TEST_OTP_VALUE.
   *   Mode C: accept only DELIVERY_TEST_OTP_VALUE.
   */
  static async verify(orderId: number, code: string): Promise<boolean> {
    if (!/^\d{6}$/.test(code)) return false;

    const useTestOtp = this.isDeliveryTestOtpEnabled();
    const expectedTest = this.DELIVERY_TEST_OTP_VALUE;

    if (TwilioService.isConfigured()) {
      if (useTestOtp) {
        // Mode B: only the test value is accepted; no Twilio call.
        return constantTimeStringEqual(code, expectedTest);
      }
      // Mode A: real Twilio verification against the customer's phone.
      const order = await AppDataSource.getRepository(Order).findOne({
        where: { id: orderId },
        relations: ['user'],
        select: { id: true, user: { id: true, phoneNumber: true } },
      });
      const phone = order?.user?.phoneNumber;
      if (!phone) return false;
      try {
        return await TwilioService.checkVerification(phone, code);
      } catch (e) {
        console.error(`[OTP] Twilio check failed for order ${orderId}`, e);
        return false;
      }
    }

    // Mode C: Twilio not configured — accept only the test value.
    return constantTimeStringEqual(code, expectedTest);
  }

  /**
   * No-op kept for callers that invalidate on RTO/cancel. Twilio Verify
   * expires its own pending verifications; nothing to clear server-side.
   */
  static async invalidate(_orderId: number): Promise<void> {
    return;
  }
}

/** Constant-time compare for plain (non-hex) strings. */
function constantTimeStringEqual(a: string, b: string): boolean {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  try {
    return crypto.timingSafeEqual(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'));
  } catch {
    return false;
  }
}
