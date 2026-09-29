export class OTPService {
  private static otpStore: Map<string, { otp: string; expiresAt: number }> = new Map();
  private static OTP_EXPIRY_TIME = 5 * 60 * 1000; // 5 minutes

  static generateOTP(): string {
    // Generate 6-digit OTP
    return Math.floor(100000 + Math.random() * 900000).toString();
  }

  static storeOTP(phoneNumber: string, otp: string): void {
    const expiresAt = Date.now() + this.OTP_EXPIRY_TIME;
    this.otpStore.set(phoneNumber, { otp, expiresAt });

    // Clean up expired OTPs
    setTimeout(() => {
      this.otpStore.delete(phoneNumber);
    }, this.OTP_EXPIRY_TIME);
  }

  static verifyOTP(phoneNumber: string, otp: string): boolean {
    const stored = this.otpStore.get(phoneNumber);

    if (!stored) {
      return false;
    }

    if (Date.now() > stored.expiresAt) {
      this.otpStore.delete(phoneNumber);
      return false;
    }

    if (stored.otp !== otp) {
      return false;
    }

    // OTP verified, remove it
    this.otpStore.delete(phoneNumber);
    return true;
  }

  // For development/testing - accept '1234' as valid OTP
  static verifyOTPDev(phoneNumber: string, otp: string): boolean {
    // In development mode (or when NODE_ENV is not production), accept '1234' as valid OTP
    if (process.env.NODE_ENV !== 'production' && otp === '1234') {
      return true;
    }
    return this.verifyOTP(phoneNumber, otp);
  }
}
