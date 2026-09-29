import { createHash } from "crypto";

/**
 * Widest value the `key` column can hold (VARCHAR(255)).
 *
 * Anything longer is stored as a hash so that long product
 * descriptions cannot overflow the column and fail silently.
 */
export const MAX_INLINE_KEY_LENGTH = 255;

/**
 * Collapse a piece of source text into its canonical form.
 *
 * Trailing/leading whitespace and repeated inner whitespace are
 * removed so that "Fresh  Milk " and "Fresh Milk" resolve to the
 * same translation.
 */
export function normalizeText(raw: string): string {

    return raw
        .trim()
        .replace(/\s+/g, " ");
}

/**
 * Build the lookup key for a piece of source text.
 *
 * MUST be the only place a key is derived. TranslationService and
 * MissingTranslationService both call this, otherwise a value can be
 * recorded under one key and looked up under another - which makes the
 * translation permanently unreachable and re-records it on every request.
 */
export function buildTranslationKey(raw: string): string {

    const normalized =
        normalizeText(raw).toLowerCase();

    if (!normalized)
        return "";

    if (normalized.length <= MAX_INLINE_KEY_LENGTH)
        return normalized;

    /*
     * Long text (product descriptions) is keyed by digest.
     * The readable original still lives in the `en` column.
     */
    const digest =
        createHash("sha256")
            .update(normalized)
            .digest("hex");

    return `sha256:${digest}`;
}
