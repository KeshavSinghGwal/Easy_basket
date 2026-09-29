-- ============================================================================
-- Migration 004: Missing translations queue
--
-- Stores text that was requested for translation but was not found
-- in the translations table.
--
-- The admin can review these entries later and add the approved
-- translations to the translations table.
-- ============================================================================

CREATE TABLE IF NOT EXISTS missing_translations (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `key`       VARCHAR(255) NOT NULL,
  en          TEXT NOT NULL,
  type        VARCHAR(50) NOT NULL DEFAULT 'product',
  status      ENUM('pending','completed') NOT NULL DEFAULT 'pending',

  created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
              ON UPDATE CURRENT_TIMESTAMP(3),

  UNIQUE KEY uniq_missing_translation_key (`key`),
  KEY idx_missing_translation_status (status),
  KEY idx_missing_translation_type (type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;