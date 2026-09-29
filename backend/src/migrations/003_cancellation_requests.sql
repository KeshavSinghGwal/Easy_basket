-- ============================================================================
-- Migration 003: Customer cancellation / refund requests
--
-- Additive only. Idempotent (guarded column-existence checks).
-- Safe to run on production.
--
-- Run with:
--   mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME < 003_cancellation_requests.sql
--
-- What it adds (on `orders`):
--   cancel_request_status     — 'none' | 'requested' | 'rejected'
--   cancellation_reason       — free-text reason supplied by the customer
--   cancellation_requested_at — when the customer raised the request
--
-- Policy these support:
--   Before 'preparing' → customer raises a cancellation/refund REQUEST; admin
--   approves (→ cancel + full refund) or rejects. After 'preparing' → customer
--   cancels directly with NO refund (no request row needed).
-- ============================================================================

SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'cancel_request_status');
SET @ddl := IF(@col = 0,
  'ALTER TABLE orders ADD COLUMN cancel_request_status
     ENUM(''none'',''requested'',''rejected'') NOT NULL DEFAULT ''none''',
  'SELECT 1');
PREPARE s FROM @ddl; EXECUTE s; DEALLOCATE PREPARE s;

SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'cancellation_reason');
SET @ddl := IF(@col = 0,
  'ALTER TABLE orders ADD COLUMN cancellation_reason VARCHAR(255) NULL DEFAULT NULL',
  'SELECT 1');
PREPARE s FROM @ddl; EXECUTE s; DEALLOCATE PREPARE s;

SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'cancellation_requested_at');
SET @ddl := IF(@col = 0,
  'ALTER TABLE orders ADD COLUMN cancellation_requested_at DATETIME(3) NULL DEFAULT NULL',
  'SELECT 1');
PREPARE s FROM @ddl; EXECUTE s; DEALLOCATE PREPARE s;
