import Twilio from 'twilio';

/**
 * Twilio Verify service for OTP send and verify.
 * Uses Twilio Verify API v2 – no need to store OTP; Twilio manages verification state.
 */
export class TwilioService {
  private static client: Twilio.Twilio | null = null;
  private static verifyServiceSid: string | null = null;

  static isConfigured(): boolean {
    const accountSid = process.env.TWILIO_ACCOUNT_SID;
    const authToken = process.env.TWILIO_AUTH_TOKEN;
    const sid = process.env.TWILIO_VERIFY_SERVICE_SID;
    return !!(accountSid && authToken && sid);
  }

  private static getClient(): Twilio.Twilio {
    if (!TwilioService.client) {
      const accountSid = process.env.TWILIO_ACCOUNT_SID;
      const authToken = process.env.TWILIO_AUTH_TOKEN;
      if (!accountSid || !authToken) {
        throw new Error(
          'Twilio credentials not configured (TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)'
        );
      }
      TwilioService.client = Twilio(accountSid, authToken);
      TwilioService.verifyServiceSid = process.env.TWILIO_VERIFY_SERVICE_SID || null;
    }
    return TwilioService.client;
  }

  private static getVerifyServiceSid(): string {
    const sid = TwilioService.verifyServiceSid ?? process.env.TWILIO_VERIFY_SERVICE_SID;
    if (!sid) {
      throw new Error('TWILIO_VERIFY_SERVICE_SID is not set');
    }
    return sid;
  }

  /**
   * Normalize phone to E.164 for Twilio (e.g. 9876543210 -> +919876543210).
   * Default country code is India (+91) if not present.
   */
  static normalizePhoneToE164(phoneNumber: string, defaultCountryCode = '91'): string {
    const digits = phoneNumber.replace(/\D/g, '');
    if (digits.length === 0) {
      return phoneNumber;
    }
    if (digits.startsWith('0')) {
      return `+${defaultCountryCode}${digits.slice(1)}`;
    }
    if (digits.length === 10 && defaultCountryCode === '91') {
      return `+91${digits}`;
    }
    if (digits.length >= 10 && !digits.startsWith('91')) {
      return `+${defaultCountryCode}${digits}`;
    }
    if (digits.startsWith('91') && digits.length === 12) {
      return `+${digits}`;
    }
    return digits.startsWith('+') ? phoneNumber : `+${digits}`;
  }

  /**
   * Send OTP via Twilio Verify (SMS). Phone number is normalized to E.164.
   */
  static async sendVerification(
    phoneNumber: string,
    channel: 'sms' | 'call' = 'sms'
  ): Promise<void> {
    const client = TwilioService.getClient();
    const serviceSid = TwilioService.getVerifyServiceSid();
    const to = TwilioService.normalizePhoneToE164(phoneNumber);

    await client.verify.v2.services(serviceSid).verifications.create({ to, channel });
  }

  /**
   * Verify the OTP code with Twilio. Returns true if valid.
   */
  static async checkVerification(phoneNumber: string, code: string): Promise<boolean> {
    const client = TwilioService.getClient();
    const serviceSid = TwilioService.getVerifyServiceSid();
    const to = TwilioService.normalizePhoneToE164(phoneNumber);

    const check = await client.verify.v2
      .services(serviceSid)
      .verificationChecks.create({ to, code });

    return check.status === 'approved';
  }
}
