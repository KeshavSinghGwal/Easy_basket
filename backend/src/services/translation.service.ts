import { AppDataSource } from "../config/database";
import { Translation } from "../entities/Translation";
import { RedisService } from "./redis.service";
import { MissingTranslationService } from "./missing-translation.service";
import { buildTranslationKey } from "../utils/translation-key.util";

export type SupportedLanguage = "en" | "hi" | "pa";

/**
 * Bumped in Redis whenever an admin saves a translation.
 *
 * Every API process polls this. Without it, an admin edit only reaches
 * the single process that served the write - the other instances behind
 * the load balancer keep serving English until they restart.
 */
const VERSION_KEY = "i18n:translations:version";

const SYNC_INTERVAL_MS = 30_000;

export class TranslationService {

    /**
     * Memory Cache
     *
     * key -> Translation Entity
     */
    private static cache = new Map<string, Translation>();

    private static knownVersion: string | null = null;

    private static syncTimer: NodeJS.Timeout | null = null;

    /**
     * Load all translations from database
     */
    static async loadCache(): Promise<void> {

        const repository = AppDataSource.getRepository(Translation);

        const translations = await repository.find();

        this.cache.clear();

        for (const translation of translations) {

            this.cache.set(
                buildTranslationKey(translation.key),
                translation
            );

        }

        this.knownVersion = await this.readVersion();

        console.log(
            `🌍 Translation Cache Loaded (${this.cache.size} entries)`
        );
    }

    /**
     * Reload cache
     */
    static async reloadCache(): Promise<void> {
        await this.loadCache();
    }

    /**
     * Add / Update one translation in cache
     */
    static addToCache(
        translation: Translation
    ): void {

        this.cache.set(
            buildTranslationKey(translation.key),
            translation
        );
    }

    /**
     * Remove translation from cache
     */
    static removeFromCache(
        key: string
    ): void {

        this.cache.delete(
            buildTranslationKey(key)
        );
    }

    /* --------------------------------------------------------------
     * Cross-process cache invalidation
     * -------------------------------------------------------------- */

    private static async readVersion(): Promise<string | null> {

        if (!RedisService.isConfigured())
            return null;

        try {
            return await RedisService.get(VERSION_KEY);
        } catch {
            return null;
        }
    }

    /**
     * Signal every process that the translations table changed.
     */
    static async bumpVersion(): Promise<void> {

        if (!RedisService.isConfigured())
            return;

        try {
            const next = await RedisService.incr(VERSION_KEY);
            this.knownVersion = String(next);
        } catch (error: any) {
            console.warn(
                "⚠️ Could not bump translation version:",
                error?.message || error
            );
        }
    }

    /**
     * Poll for translation changes made by other processes.
     */
    static startCacheSync(
        intervalMs: number = SYNC_INTERVAL_MS
    ): void {

        if (this.syncTimer || !RedisService.isConfigured())
            return;

        this.syncTimer = setInterval(async () => {

            try {
                const current = await this.readVersion();

                if (current !== null && current !== this.knownVersion) {
                    console.log(
                        "🔄 Translation change detected - reloading cache"
                    );
                    await this.loadCache();
                }
            } catch {
                /* transient Redis failure - retry on next tick */
            }

        }, intervalMs);

        /*
         * Do not hold the event loop open on shutdown.
         */
        this.syncTimer.unref?.();
    }

    static stopCacheSync(): void {

        if (this.syncTimer) {
            clearInterval(this.syncTimer);
            this.syncTimer = null;
        }
    }

    /* --------------------------------------------------------------
     * Translation
     * -------------------------------------------------------------- */

    /**
     * Translate a single value
     */
    static translate(
        value: string,
        language: SupportedLanguage,
        type: string = "content"
    ): string {

        if (!value)
            return value;

        /*
         * English is the source language.
         * No translation lookup is required.
         */
        if (language === "en")
            return value;

        const key = buildTranslationKey(value);

        if (!key)
            return value;

        const translation = this.cache.get(key);

        /*
         * Translation does not exist.
         *
         * Record it in the missing_translations table
         * without blocking the API response.
         */
        if (!translation) {

            void MissingTranslationService.record(value, type);

            return value;
        }

        switch (language) {

            case "hi":
                return translation.hi || translation.en;

            case "pa":
                return translation.pa || translation.en;

            default:
                return translation.en;
        }
    }

    /**
     * Translate an object.
     */
    static translateObject<T extends Record<string, any>>(
        object: T,
        fields: string[],
        language: SupportedLanguage,
        type: string = "content"
    ): T {

        const translated = { ...object } as Record<string, any>;

        for (const field of fields) {

            if (
                translated[field] &&
                typeof translated[field] === "string"
            ) {

                translated[field] =
                    this.translate(
                        translated[field],
                        language,
                        type
                    );
            }
        }

        return translated as T;
    }

    /**
     * Translate list of objects
     */
    static translateArray<T extends Record<string, any>>(
        data: T[],
        fields: string[],
        language: SupportedLanguage,
        type: string = "content"
    ): T[] {

        return data.map(item =>
            this.translateObject(
                item,
                fields,
                language,
                type
            )
        );
    }

    /**
     * Check whether translation exists
     */
    static hasTranslation(
        key: string
    ): boolean {

        return this.cache.has(
            buildTranslationKey(key)
        );
    }

    /**
     * Cache size
     */
    static cacheSize(): number {

        return this.cache.size;
    }
}
