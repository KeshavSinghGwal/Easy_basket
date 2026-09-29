-- ============================================================================
-- Migration 005: Translations table
--
-- Holds the approved Hindi / Punjabi text for catalogue content.
-- `key` is the canonical form of the English source text
-- (see src/utils/translation-key.util.ts). Text longer than 255
-- characters is keyed as "sha256:<digest>".
--
-- NOTE: column names are camelCase to match the TypeORM entity, which
-- uses bare @CreateDateColumn()/@UpdateDateColumn(). This differs from
-- missing_translations, which maps explicitly to snake_case.
-- ============================================================================

CREATE TABLE IF NOT EXISTS translations (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  `key`       VARCHAR(255) NOT NULL,
  en          TEXT NOT NULL,
  hi          TEXT NULL,
  pa          TEXT NULL,
  type        VARCHAR(50) NOT NULL DEFAULT 'content',

  createdAt   DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updatedAt   DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
              ON UPDATE CURRENT_TIMESTAMP(6),

  UNIQUE KEY uniq_translation_key (`key`),
  KEY idx_translation_type (type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- If the table was created by hand earlier with VARCHAR columns, widen them.
-- These are safe to re-run.
-- ----------------------------------------------------------------------------
ALTER TABLE translations MODIFY en TEXT NOT NULL;
ALTER TABLE translations MODIFY hi TEXT NULL;
ALTER TABLE translations MODIFY pa TEXT NULL;

-- ----------------------------------------------------------------------------
-- missing_translations.en must hold the same long text.
-- Already TEXT in 004; this is a no-op there but corrects hand-made tables.
-- ----------------------------------------------------------------------------
ALTER TABLE missing_translations MODIFY en TEXT NOT NULL;
