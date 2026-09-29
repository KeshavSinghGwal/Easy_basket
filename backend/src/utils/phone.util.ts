/**
 * Validate and canonicalize an Indian mobile number to its 10-digit form.
 * Accepts variants like "9876543210", "+919876543210", "91 9876543210",
 * "098-7654-3210". Returns the 10-digit canonical string, or null if the
 * input doesn't match a valid Indian mobile (10 digits starting 6-9).
 */
export function canonicalizeIndianMobile(input: unknown): string | null {
  if (typeof input !== 'string') return null;

  let digits = input.replace(/[\s\-()]/g, '');
  if (digits.startsWith('+')) digits = digits.slice(1);
  if (digits.startsWith('0')) digits = digits.slice(1);
  if (digits.length === 12 && digits.startsWith('91')) digits = digits.slice(2);

  return /^[6-9]\d{9}$/.test(digits) ? digits : null;
}
