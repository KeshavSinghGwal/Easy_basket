-- ============================================================================
-- Migration 004: Store open/closed status
--
-- Additive only. Idempotent (guarded existence checks). Safe to run on
-- production, and safe to run twice.
--
-- Run with:
--   mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME < 004_store_status.sql
--
-- What it adds:
--   store_status — SINGLETON table (exactly one row, id = 1) holding whether
--                  the store is currently accepting NEW orders.
--
-- Columns:
--   is_open             — false blocks order CREATION only
--   closed_reason       — enum; drives which visual the app renders
--   custom_message      — admin-authored headline shown to users
--   expected_reopen_at  — DISPLAY ONLY, never auto-reopens the store (UTC)
--   updated_by_id       — which admin last flipped it (audit)
--   closed_at           — when it was last closed (audit)
--
-- IMPORTANT: closing the store does NOT touch existing orders. Riders keep
-- delivering, admins keep managing, customers keep cancelling. It is purely a
-- gate on new order creation.
--
-- The row is seeded OPEN so deploying this migration cannot accidentally shut
-- the shop down.
-- ============================================================================

CREATE TABLE IF NOT EXISTS store_status (
  id                 INT NOT NULL,
  is_open            TINYINT(1) NOT NULL DEFAULT 1,
  closed_reason      ENUM('rain','holiday','maintenance','high_demand','out_of_hours','other')
                       NULL DEFAULT NULL,
  custom_message     VARCHAR(280) NULL DEFAULT NULL,
  expected_reopen_at TIMESTAMP NULL DEFAULT NULL,
  updated_by_id      INT NULL DEFAULT NULL,
  closed_at          TIMESTAMP NULL DEFAULT NULL,
  updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed the singleton row as OPEN. INSERT IGNORE so re-running the migration
-- never resets a store the admin has deliberately closed.
INSERT IGNORE INTO store_status (id, is_open) VALUES (1, 1);

-- FK to the user table for the audit column. Added separately and guarded,
-- because that table already exists and CREATE TABLE IF NOT EXISTS would skip
-- an inline constraint on a second run.
--
-- NOTE: `user`, singular. This said `users(id)` and therefore always failed —
-- MySQL cannot add a constraint against a table that does not exist. The table
-- and its seed row survived because both run BEFORE this step and DDL commits
-- as it goes, so store open/close has worked all along; only this audit
-- constraint was missing. Re-running the migration now adds it.
SET @fk := (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'store_status'
    AND CONSTRAINT_NAME = 'FK_store_status_updated_by');
SET @ddl := IF(@fk = 0,
  'ALTER TABLE store_status
     ADD CONSTRAINT FK_store_status_updated_by
     FOREIGN KEY (updated_by_id) REFERENCES user(id) ON DELETE SET NULL',
  'SELECT 1');
PREPARE s FROM @ddl; EXECUTE s; DEALLOCATE PREPARE s;
