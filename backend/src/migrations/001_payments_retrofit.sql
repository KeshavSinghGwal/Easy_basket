-- ============================================================================
-- Migration 001: Payments retrofit
--
-- Additive only. Does not modify or drop existing columns/rows.
-- Safe to run on production: every statement is idempotent (IF NOT EXISTS).
--
-- Run with:
--   mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME < 001_payments_retrofit.sql
--
-- What it adds:
--   1. payments table        — one row per razorpay_order (payment attempt)
--   2. refunds table         — one row per refund request
--   3. webhook_events table  — idempotent audit log of razorpay webhooks
--   4. orders.payment_status — the 6-state payment machine, independent of orders.status
--   5. orders.idempotency_key — dedupe for double-tap checkouts
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) payments
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payments (
  id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_id            INT NOT NULL,
  user_id             INT NOT NULL,
  razorpay_order_id   VARCHAR(64)  NOT NULL,
  razorpay_payment_id VARCHAR(64)  NULL,
  amount_paise        BIGINT UNSIGNED NOT NULL,
  currency            CHAR(3)      NOT NULL DEFAULT 'INR',
  status              ENUM('initiated','success_unverified','paid','failed',
                           'refund_pending','refunded') NOT NULL DEFAULT 'initiated',
  failure_code        VARCHAR(64)  NULL,
  raw_webhook_json    JSON         NULL,
  version             INT UNSIGNED NOT NULL DEFAULT 0,
  created_at          DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at          DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                        ON UPDATE CURRENT_TIMESTAMP(3),

  UNIQUE KEY uniq_rzp_order   (razorpay_order_id),
  UNIQUE KEY uniq_rzp_payment (razorpay_payment_id),
  KEY idx_order               (order_id),
  KEY idx_user_status         (user_id, status),
  KEY idx_status_created      (status, created_at),

  CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES orders(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 2) refunds
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS refunds (
  id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  payment_id          BIGINT UNSIGNED NOT NULL,
  user_id             INT NOT NULL,
  razorpay_refund_id  VARCHAR(64)  NULL,
  amount_paise        BIGINT UNSIGNED NOT NULL,
  status              ENUM('pending','processed','failed') NOT NULL DEFAULT 'pending',
  reason              VARCHAR(255) NULL,
  idempotency_key     CHAR(64)     NOT NULL,
  created_at          DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at          DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                        ON UPDATE CURRENT_TIMESTAMP(3),

  UNIQUE KEY uniq_rzp_refund      (razorpay_refund_id),
  UNIQUE KEY uniq_payment_idem    (payment_id, idempotency_key),
  KEY idx_user                    (user_id),

  CONSTRAINT fk_refunds_payment FOREIGN KEY (payment_id) REFERENCES payments(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 3) webhook_events (atomic dedupe + audit)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS webhook_events (
  id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  event_id     VARCHAR(64) NOT NULL,
  event_type   VARCHAR(64) NOT NULL,
  payload      JSON        NOT NULL,
  processed_at DATETIME(3) NULL,
  received_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  UNIQUE KEY uniq_event (event_id),
  KEY idx_processed (processed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 4) orders.payment_status  (additive nullable column — existing rows get NULL)
-- ---------------------------------------------------------------------------
-- MySQL 8 supports `ADD COLUMN IF NOT EXISTS`; for 5.7 compat we use a guarded block.
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'payment_status'
);
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE orders ADD COLUMN payment_status
     ENUM(''initiated'',''success_unverified'',''paid'',''failed'',''refund_pending'',''refunded'')
     NULL DEFAULT NULL, ADD INDEX idx_payment_status (payment_status)',
  'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---------------------------------------------------------------------------
-- 5) orders.idempotency_key  (additive nullable + unique per user)
-- ---------------------------------------------------------------------------
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'idempotency_key'
);
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE orders ADD COLUMN idempotency_key CHAR(64) NULL DEFAULT NULL,
     ADD UNIQUE INDEX uniq_user_idem (userId, idempotency_key)',
  'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---------------------------------------------------------------------------
-- Done.  No data is mutated.  Rollback plan:
--   DROP TABLE refunds, payments, webhook_events;
--   ALTER TABLE orders DROP COLUMN payment_status, DROP COLUMN idempotency_key;
-- ---------------------------------------------------------------------------
