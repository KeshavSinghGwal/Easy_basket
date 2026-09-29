import { AppDataSource } from "../config/database";
import { MissingTranslation } from "../entities/MissingTranslation";
import {
    buildTranslationKey,
    normalizeText,
} from "../utils/translation-key.util";

/**
 * Keys this process has already pushed to missing_translations.
 *
 * Without this, every cache miss costs a SELECT + INSERT. A 50-product
 * listing translating name + description would issue 100 queries per
 * request, on every request, for as long as the translation is missing.
 */
const seen = new Set<string>();

/**
 * Safety valve so a hostile or very large catalogue cannot grow the
 * dedupe set without bound.
 */
const MAX_SEEN_KEYS = 50_000;

export class MissingTranslationService {

    static async record(
        key: string,
        type: string = "content"
    ): Promise<void> {

        if (!key)
            return;

        const value = normalizeText(key);

        if (!value)
            return;

        const normalizedKey = buildTranslationKey(value);

        if (!normalizedKey)
            return;

        /*
         * Already recorded by this process - nothing to do.
         */
        if (seen.has(normalizedKey))
            return;

        try {
            const repository =
                AppDataSource.getRepository(MissingTranslation);

            /*
             * INSERT ... ON DUPLICATE KEY IGNORE.
             *
             * Replaces the previous find-then-save, which raced when two
             * requests missed the same key at the same time and reset
             * nothing when the row already existed.
             */
            await repository
                .createQueryBuilder()
                .insert()
                .into(MissingTranslation)
                .values({
                    key: normalizedKey,
                    en: value,
                    type,
                    status: "pending",
                })
                .orIgnore()
                .execute();

            if (seen.size >= MAX_SEEN_KEYS)
                seen.clear();

            seen.add(normalizedKey);

            console.log(
                `🌐 Missing translation recorded [${type}]: ${value.slice(0, 80)}`
            );

        } catch (error: any) {
            console.error(
                `⚠️ Could not record missing translation: ${value.slice(0, 80)}`,
                error?.message || error
            );
        }
    }

    /**
     * Called once a translation is completed so the key can be recorded
     * again if it ever goes missing later.
     */
    static forget(
        key: string
    ): void {

        seen.delete(
            buildTranslationKey(key)
        );
    }
}
