import { Request, Response } from "express";
import { In } from "typeorm";
import { AppDataSource } from "../config/database";
import { MissingTranslation } from "../entities/MissingTranslation";
import { Translation } from "../entities/Translation";
import { TranslationService } from "../services/translation.service";
import { MissingTranslationService } from "../services/missing-translation.service";
import {
    buildTranslationKey,
    normalizeText,
} from "../utils/translation-key.util";
import { parseCsv, toCsv, UTF8_BOM } from "../utils/csv.util";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

const MAX_BULK_ROWS = 5000;

const CSV_COLUMNS = ["id", "type", "en", "hi", "pa"];

/** One validated row ready to be written. */
interface BulkItem {
    row: number;
    key: string;
    en: string;
    type: string;
    hi: string | null;
    pa: string | null;
    missingId: number | null;
}

/** Treat undefined / null / blank alike. */
function cleanValue(input: unknown): string | null {

    if (typeof input !== "string")
        return null;

    const trimmed = input.trim();

    return trimmed.length ? trimmed : null;
}

export class MissingTranslationController {

    /**
     * Get missing translations
     *
     * GET /api/admin/missing-translations
     *     ?status=pending|completed|all
     *     &page=1&limit=50
     */
    static async getMissingTranslations(
        req: Request,
        res: Response
    ) {

        try {

            const repository =
                AppDataSource.getRepository(MissingTranslation);

            const status =
                String(req.query.status || "pending").toLowerCase();

            const page =
                Math.max(1, Number(req.query.page) || 1);

            const limit =
                Math.min(
                    MAX_LIMIT,
                    Math.max(1, Number(req.query.limit) || DEFAULT_LIMIT)
                );

            const where =
                status === "all"
                    ? {}
                    : { status };

            const [rows, total] =
                await repository.findAndCount({
                    where,
                    order: {
                        createdAt: "ASC",
                    },
                    skip: (page - 1) * limit,
                    take: limit,
                });

            return res.json({
                success: true,
                count: rows.length,
                total,
                page,
                limit,
                data: rows,
            });

        } catch (error) {

            console.error(
                "Error fetching missing translations:",
                error
            );

            return res.status(500).json({
                success: false,
                message: "Error fetching missing translations",
            });
        }
    }

    /**
     * Add translation for a missing entry
     *
     * PUT /api/admin/missing-translations/:id
     *
     * Body:
     * {
     *   "hi": "ताज़ा दूध",
     *   "pa": "ਤਾਜ਼ਾ ਦੁੱਧ"
     * }
     *
     * The entry is only marked "completed" once BOTH languages are
     * present, so a half-filled row stays visible to the admin.
     */
    static async completeMissingTranslation(
        req: Request,
        res: Response
    ) {

        try {

            const id = Number(req.params.id);

            if (!Number.isInteger(id) || id <= 0) {

                return res.status(400).json({
                    success: false,
                    message: "Invalid translation id",
                });
            }

            const hi = cleanValue(req.body?.hi);
            const pa = cleanValue(req.body?.pa);

            /*
             * At least one language should be provided.
             */
            if (!hi && !pa) {

                return res.status(400).json({
                    success: false,
                    message: "Provide Hindi or Punjabi translation",
                });
            }

            const missingRepository =
                AppDataSource.getRepository(MissingTranslation);

            const translationRepository =
                AppDataSource.getRepository(Translation);

            const missing =
                await missingRepository.findOne({
                    where: {
                        id,
                    },
                });

            if (!missing) {

                return res.status(404).json({
                    success: false,
                    message: "Missing translation not found",
                });
            }

            /*
             * Check whether translation already exists.
             */
            let translation =
                await translationRepository.findOne({
                    where: {
                        key: missing.key,
                    },
                });

            if (!translation) {

                translation =
                    translationRepository.create({
                        key: missing.key,
                        en: missing.en,
                        hi: null,
                        pa: null,
                        type: missing.type,
                    });
            }

            /*
             * Only overwrite a language that was actually supplied, so a
             * second call adding Punjabi does not wipe existing Hindi.
             */
            if (hi)
                translation.hi = hi;

            if (pa)
                translation.pa = pa;

            translation.en = missing.en;
            translation.type = missing.type;

            await translationRepository.save(translation);

            /*
             * Complete only when both languages are filled in.
             */
            missing.status =
                translation.hi && translation.pa
                    ? "completed"
                    : "pending";

            await missingRepository.save(missing);

            /*
             * Update this process's cache immediately, then tell every
             * other process to reload. No server restart required.
             */
            TranslationService.addToCache(translation);

            MissingTranslationService.forget(missing.key);

            await TranslationService.bumpVersion();

            return res.json({
                success: true,
                message:
                    missing.status === "completed"
                        ? "Translation completed successfully"
                        : "Translation saved. Still awaiting the other language.",
                data: {
                    missingTranslation: missing,
                    translation,
                },
            });

        } catch (error) {

            console.error(
                "Error completing missing translation:",
                error
            );

            return res.status(500).json({
                success: false,
                message: "Error completing missing translation",
            });
        }
    }

    /**
     * Export the queue as a CSV for offline translation.
     *
     * GET /api/admin/missing-translations/export?status=pending
     *
     * Columns: id,type,en,hi,pa
     * Any translation already captured is pre-filled so partially
     * completed rows are not retyped.
     */
    static async exportCsv(
        req: Request,
        res: Response
    ) {

        try {

            const status =
                String(req.query.status || "pending").toLowerCase();

            const missingRepository =
                AppDataSource.getRepository(MissingTranslation);

            const rows =
                await missingRepository.find({
                    where: status === "all" ? {} : { status },
                    order: { createdAt: "ASC" },
                });

            /*
             * Pre-fill from any translation that already exists.
             */
            const existing = new Map<string, Translation>();

            if (rows.length) {

                const found =
                    await AppDataSource.getRepository(Translation).find({
                        where: { key: In(rows.map(r => r.key)) },
                    });

                for (const t of found)
                    existing.set(t.key, t);
            }

            const csv = toCsv([
                CSV_COLUMNS,
                ...rows.map(r => {
                    const t = existing.get(r.key);
                    return [r.id, r.type, r.en, t?.hi ?? "", t?.pa ?? ""];
                }),
            ]);

            res.setHeader("Content-Type", "text/csv; charset=utf-8");
            res.setHeader(
                "Content-Disposition",
                `attachment; filename="missing-translations-${status}.csv"`
            );

            /*
             * res.send, not res.json - this must not pass through the
             * response translator, and Excel needs the BOM to read UTF-8.
             */
            return res.send(UTF8_BOM + csv);

        } catch (error) {

            console.error("Error exporting missing translations:", error);

            return res.status(500).json({
                success: false,
                message: "Error exporting missing translations",
            });
        }
    }

    /**
     * Apply many translations at once.
     *
     * POST /api/admin/missing-translations/bulk
     *
     * Accepts either the edited CSV (Content-Type: text/csv) or
     * JSON: { "items": [{ "id": 1, "hi": "...", "pa": "..." }],
     *         "dryRun": true }
     *
     * Rows may be identified by `id` (a queue row) or by `en` (free
     * seeding). Invalid rows are reported and skipped; valid rows are
     * applied together in one transaction.
     */
    static async bulkComplete(
        req: Request,
        res: Response
    ) {

        try {

            const isCsv = typeof req.body === "string";

            const dryRun =
                isCsv
                    ? String(req.query.dryRun || "") === "true"
                    : req.body?.dryRun === true;

            const rawItems: any[] =
                isCsv
                    ? MissingTranslationController.csvToItems(req.body)
                    : Array.isArray(req.body?.items)
                        ? req.body.items
                        : [];

            if (!rawItems.length) {
                return res.status(400).json({
                    success: false,
                    message:
                        "No rows supplied. Send CSV as text/csv, or JSON { items: [...] }.",
                });
            }

            if (rawItems.length > MAX_BULK_ROWS) {
                return res.status(400).json({
                    success: false,
                    message: `Too many rows (${rawItems.length}). Maximum is ${MAX_BULK_ROWS}.`,
                });
            }

            /* ---------------------------------------------------------
             * Resolve queue rows referenced by id
             * --------------------------------------------------------- */

            const missingRepository =
                AppDataSource.getRepository(MissingTranslation);

            const ids = rawItems
                .map(i => Number(i?.id))
                .filter(n => Number.isInteger(n) && n > 0);

            const missingById = new Map<number, MissingTranslation>();

            if (ids.length) {
                const found =
                    await missingRepository.find({
                        where: { id: In(ids) },
                    });

                for (const m of found)
                    missingById.set(m.id, m);
            }

            /* ---------------------------------------------------------
             * Validate
             * --------------------------------------------------------- */

            const items: BulkItem[] = [];
            const errors: Array<{ row: number; reason: string }> = [];

            rawItems.forEach((raw, index) => {

                const row = index + 1;

                const hi = cleanValue(raw?.hi);
                const pa = cleanValue(raw?.pa);

                if (!hi && !pa) {
                    errors.push({ row, reason: "No Hindi or Punjabi supplied" });
                    return;
                }

                const id = Number(raw?.id);

                if (Number.isInteger(id) && id > 0) {

                    const missing = missingById.get(id);

                    if (!missing) {
                        errors.push({ row, reason: `No queue row with id ${id}` });
                        return;
                    }

                    items.push({
                        row,
                        key: missing.key,
                        en: missing.en,
                        type: missing.type,
                        hi,
                        pa,
                        missingId: missing.id,
                    });

                    return;
                }

                const en = cleanValue(raw?.en);

                if (!en) {
                    errors.push({ row, reason: "Needs either an id or English text" });
                    return;
                }

                const source = normalizeText(en);
                const key = buildTranslationKey(source);

                if (!key) {
                    errors.push({ row, reason: "English text is blank" });
                    return;
                }

                items.push({
                    row,
                    key,
                    en: source,
                    type: cleanValue(raw?.type) || "content",
                    hi,
                    pa,
                    missingId: null,
                });
            });

            if (dryRun) {
                return res.json({
                    success: true,
                    dryRun: true,
                    wouldApply: items.length,
                    skipped: errors.length,
                    errors,
                });
            }

            if (!items.length) {
                return res.status(400).json({
                    success: false,
                    message: "No valid rows to apply",
                    skipped: errors.length,
                    errors,
                });
            }

            /* ---------------------------------------------------------
             * Apply
             * --------------------------------------------------------- */

            const keys = [...new Set(items.map(i => i.key))];

            const saved: Translation[] = [];
            let completed = 0;

            await AppDataSource.transaction(async manager => {

                const existing =
                    await manager.find(Translation, {
                        where: { key: In(keys) },
                    });

                const byKey = new Map<string, Translation>();

                for (const t of existing)
                    byKey.set(t.key, t);

                const queueRows =
                    await manager.find(MissingTranslation, {
                        where: { key: In(keys) },
                    });

                const queueByKey = new Map<string, MissingTranslation>();

                for (const m of queueRows)
                    queueByKey.set(m.key, m);

                const toSave: Translation[] = [];
                const queueToSave: MissingTranslation[] = [];

                for (const item of items) {

                    let translation = byKey.get(item.key);

                    if (!translation) {
                        translation = manager.create(Translation, {
                            key: item.key,
                            en: item.en,
                            hi: null,
                            pa: null,
                            type: item.type,
                        });
                        byKey.set(item.key, translation);
                    }

                    /*
                     * Only overwrite a language actually supplied, so a
                     * Punjabi-only pass does not wipe existing Hindi.
                     */
                    if (item.hi)
                        translation.hi = item.hi;

                    if (item.pa)
                        translation.pa = item.pa;

                    translation.en = item.en;
                    translation.type = item.type;

                    toSave.push(translation);

                    const queueRow = queueByKey.get(item.key);

                    if (queueRow) {
                        const done = !!(translation.hi && translation.pa);
                        queueRow.status = done ? "completed" : "pending";
                        if (done) completed++;
                        queueToSave.push(queueRow);
                    }
                }

                await manager.save(Translation, toSave);

                if (queueToSave.length)
                    await manager.save(MissingTranslation, queueToSave);

                saved.push(...toSave);
            });

            /* ---------------------------------------------------------
             * Refresh caches - local now, other instances within 30s
             * --------------------------------------------------------- */

            for (const translation of saved) {
                TranslationService.addToCache(translation);
                MissingTranslationService.forget(translation.key);
            }

            await TranslationService.bumpVersion();

            return res.json({
                success: true,
                applied: saved.length,
                completed,
                skipped: errors.length,
                errors,
            });

        } catch (error) {

            console.error("Error applying bulk translations:", error);

            return res.status(500).json({
                success: false,
                message: "Error applying bulk translations",
            });
        }
    }

    /**
     * Turn an uploaded CSV into the same shape the JSON body uses.
     * Header names are matched case-insensitively and may be in any order.
     */
    private static csvToItems(body: string): any[] {

        const rows = parseCsv(body);

        if (rows.length < 2)
            return [];

        const header = rows[0].map(h => h.trim().toLowerCase());

        return rows.slice(1).map(cells => {

            const item: Record<string, string> = {};

            header.forEach((name, i) => {
                if (CSV_COLUMNS.includes(name))
                    item[name] = cells[i] ?? "";
            });

            return item;
        });
    }
}
