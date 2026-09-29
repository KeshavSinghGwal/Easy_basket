/**
 * Boot-time validation of the three Razorpay secrets.
 *
 * Mirrors config/jwt.ts: fail the process at startup rather than at request time.
 *
 * The one that bites hardest is RAZORPAY_WEBHOOK_SECRET. It is read lazily inside
 * RazorpayService.verifyWebhookSignature, which returns `false` when it is missing —
 * so an unset secret does not throw, it just makes EVERY webhook 401. Since the
 * webhook is the authoritative confirmation path (client verify only reaches
 * `success_unverified`), that silently demotes the whole system to its fallbacks:
 * payments confirm late via the BullMQ sweep, refund.processed is never seen, and
 * refund.failed never feeds the retry budget. It looks fine in a demo and behaves
 * badly under load. Refusing to boot is the only way that stays visible.
 *
 * Must be require()d AFTER dotenv.config() — see index.ts.
 */
function required(name: string): string {
  const v = process.env[name];
  if (!v || v.trim() === '') {
    console.error(`❌ ${name} is not set. Refusing to start.`);
    console.error(
      '💡 RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET come from Razorpay Dashboard → Settings → API Keys.'
    );
    console.error(
      '💡 RAZORPAY_WEBHOOK_SECRET is the secret you typed when creating the webhook under Settings → Webhooks. It is NOT the API key secret.'
    );
    process.exit(1);
  }
  return v.trim();
}

export const RAZORPAY_KEY_ID: string = required('RAZORPAY_KEY_ID');
export const RAZORPAY_KEY_SECRET: string = required('RAZORPAY_KEY_SECRET');
export const RAZORPAY_WEBHOOK_SECRET: string = required('RAZORPAY_WEBHOOK_SECRET');
