-- ---------------------------------------------------------------------------
-- 006_refund_retries.sql
--
-- Adds automatic-retry bookkeeping to the refunds table.
--
-- Background: when the Razorpay refund call threw, createRefund swallowed the
-- error and left the row at status='pending' with razorpay_refund_id=NULL. The
-- 30-min reconciler explicitly skips those rows (`if (!r.razorpayRefundId)
-- continue`), so nothing ever retried them — and because the dead row still
-- counts toward the "active refunds" cap, it permanently blocked any further
-- refund for that payment.
--
-- These columns let a refund be retried a bounded number of times and then
-- parked in a state an admin can act on:
--
--   attempt_count   number of times we have actually POSTed to Razorpay.
--                   Only a real API call increments this — a job that could not
--                   acquire the payment lock reschedules without burning one.
--   last_error      short reason for the most recent failure, surfaced to admin.
--   next_retry_at   when the automatic retry is due (NULL = none scheduled).
--   last_attempt_at timestamp of the most recent POST, for support/debugging.
--
-- A refund needing manual intervention is exactly `status = 'failed'`, which is
-- what drives the admin "Retry refund" button.
--
-- Idempotent: safe to re-run. MySQL 5.7-compatible guarded ALTERs.
-- ---------------------------------------------------------------------------

-- 1) refunds.attempt_count
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'refunds'
    AND COLUMN_NAME = 'attempt_count'
);
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE refunds ADD COLUMN attempt_count INT UNSIGNED NOT NULL DEFAULT 0',
  'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 2) refunds.last_error
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'refunds'
    AND COLUMN_NAME = 'last_error'
);
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE refunds ADD COLUMN last_error VARCHAR(255) NULL DEFAULT NULL',
  'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 3) refunds.next_retry_at  (+ index: the reconciler backstop scans on it)
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'refunds'
    AND COLUMN_NAME = 'next_retry_at'
);
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE refunds ADD COLUMN next_retry_at DATETIME(3) NULL DEFAULT NULL,
     ADD INDEX idx_refund_retry (status, next_retry_at)',
  'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 4) refunds.last_attempt_at
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'refunds'
    AND COLUMN_NAME = 'last_attempt_at'
);
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE refunds ADD COLUMN last_attempt_at DATETIME(3) NULL DEFAULT NULL',
  'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---------------------------------------------------------------------------
-- 5) Backfill existing rows. FIRST RUN ONLY.
--
-- Rows already in flight before this migration have made exactly one attempt.
-- Marking them 1 means a stuck row gets its one automatic retry after deploy
-- rather than being treated as never-attempted.
--
-- This MUST NOT run twice. The file's header promises it is safe to re-run, and
-- the unguarded `WHERE attempt_count = 0` broke that promise: on a second run it
-- silently burns one of the two automatic attempts belonging to every genuinely
-- new refund. PaymentsV2Service.recordRefundOwed writes rows at exactly
-- attempt_count = 0, so those legitimately-fresh rows were the ones hit.
--
-- Guarded on the marker table below, which only this migration writes.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
  name       VARCHAR(128) NOT NULL PRIMARY KEY,
  applied_at DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET @already := (
  SELECT COUNT(*) FROM schema_migrations WHERE name = '006_refund_retries_backfill'
);

SET @ddl := IF(@already = 0,
  'UPDATE refunds SET attempt_count = 1 WHERE attempt_count = 0',
  'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @ddl := IF(@already = 0,
  'UPDATE refunds SET next_retry_at = NOW(3) WHERE status = ''pending'' AND razorpay_refund_id IS NULL',
  'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

INSERT IGNORE INTO schema_migrations (name) VALUES ('006_refund_retries_backfill');

-- (The "schedule pre-existing orphans for immediate retry" statement that used to
-- live here is now part of the guarded first-run block above, for the same reason:
-- re-running it would reset next_retry_at on refunds that are legitimately waiting
-- out their backoff, collapsing the retry spacing.)

-- ---------------------------------------------------------------------------
-- Rollback:
--   ALTER TABLE refunds
--     DROP INDEX idx_refund_retry,
--     DROP COLUMN attempt_count,
--     DROP COLUMN last_error,
--     DROP COLUMN next_retry_at,
--     DROP COLUMN last_attempt_at;
-- ---------------------------------------------------------------------------
