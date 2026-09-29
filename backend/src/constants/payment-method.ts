export const PAYMENT_METHODS = ['upi', 'cod'] as const;
export type PaymentMethod = (typeof PAYMENT_METHODS)[number];

/**
 * Maps various spellings clients may send (UPI, upi, Cash, cash, COD, Cod, ...)
 * to a single canonical lowercase token. Keep this table tight — adding a new
 * alias here is the only place that controls what the rest of the system accepts.
 */
const ALIASES: Record<string, PaymentMethod> = {
  upi: 'upi',
  cod: 'cod',
  cash: 'cod',
  razorpay: 'upi', // mobile sends 'razorpay' for the online-payment tile
};

/**
 * Normalize a client-supplied paymentMethod to its canonical form.
 *
 * - `null` / `undefined` / empty string → defaults to `'upi'` (preserves legacy
 *   behavior where the controller's `paymentMethod || 'UPI'` chose UPI as the
 *   fallback for missing values).
 * - Recognized aliases → mapped to `'upi'` or `'cod'`.
 * - Anything else → `null`, signalling "reject with 400".
 */
export function normalizePaymentMethod(input: unknown): PaymentMethod | null {
  if (input == null) return 'upi';
  if (typeof input !== 'string') return null;
  const key = input.trim().toLowerCase();
  if (key === '') return 'upi';
  return ALIASES[key] ?? null;
}
