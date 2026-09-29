-- ============================================================================
-- Migration 002: Delivery system retrofit (Phase 1)
--
-- Additive only. Does not modify or drop existing columns/rows.
-- Safe to run on production: every statement is guarded (IF NOT EXISTS / col check).
--
-- Run with:
--   mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME < 002_delivery_retrofit.sql
--
-- What it adds:
--   1. orders: delivery_status + timestamps + cash_collected_paise +
--              delivery_attempts + delivery_otp_hash
--   2. rider_profiles       — extends users (role='delivery') with availability,
--                             vehicle, last-known location, rating, stats
--   3. rider_wallets        — cash_in_hand + lifetime totals (one row per rider)
--   4. rider_cash_deposits  — hub-side cash deposit log (immutable, idempotent)
--   5. order_events         — append-only audit trail of every state change
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) orders — new columns (run as a guarded block, idempotent)
-- ---------------------------------------------------------------------------

SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'delivery_status');
SET @ddl := IF(@col = 0,
  'ALTER TABLE orders ADD COLUMN delivery_status ENUM(
     ''unassigned'',''assigned'',''at_store'',''picked'',''out_for_delivery'',
     ''arrived'',''payment_pending'',''delivered'',''rto_pending'',''rto_completed''
   ) NULL DEFAULT NULL,
   ADD INDEX idx_delivery_status (delivery_status),
   ADD INDEX idx_deliveryboy_status (deliveryBoyId, delivery_status)',
  'SELECT 1');
PREPARE s FROM @ddl; EXECUTE s; DEALLOCATE PREPARE s;

SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'delivery_assigned_at');
SET @ddl := IF(@col = 0,
  'ALTER TABLE orders
     ADD COLUMN delivery_assigned_at  DATETIME(3) NULL,
     ADD COLUMN delivery_picked_at    DATETIME(3) NULL,
     ADD COLUMN delivery_arrived_at   DATETIME(3) NULL,
     ADD COLUMN delivery_completed_at DATETIME(3) NULL',
  'SELECT 1');
PREPARE s FROM @ddl; EXECUTE s; DEALLOCATE PREPARE s;

SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'cash_collected_paise');
SET @ddl := IF(@col = 0,
  'ALTER TABLE orders
     ADD COLUMN cash_collected_paise BIGINT UNSIGNED NULL,
     ADD COLUMN delivery_attempts    TINYINT UNSIGNED NOT NULL DEFAULT 0,
     ADD COLUMN delivery_otp_hash    CHAR(64) NULL',
  'SELECT 1');
PREPARE s FROM @ddl; EXECUTE s; DEALLOCATE PREPARE s;

-- ---------------------------------------------------------------------------
-- 2) rider_profiles
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rider_profiles (
  id                   BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id              INT NOT NULL UNIQUE,
  availability         ENUM('offline','idle','busy') NOT NULL DEFAULT 'offline',
  vehicle_type         ENUM('bicycle','bike','scooter','car') NOT NULL DEFAULT 'bike',
  vehicle_number       VARCHAR(32) NULL,
  current_lat          DECIMAL(10,7) NULL,
  current_lng          DECIMAL(10,7) NULL,
  last_seen_at         DATETIME(3) NULL,
  rating               DECIMAL(3,2) NOT NULL DEFAULT 5.00,
  total_deliveries     INT UNSIGNED NOT NULL DEFAULT 0,
  total_cod_deliveries INT UNSIGNED NOT NULL DEFAULT 0,
  created_at           DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at           DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                         ON UPDATE CURRENT_TIMESTAMP(3),
  KEY idx_avail (availability, last_seen_at),
  KEY idx_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 3) rider_wallets
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rider_wallets (
  id                       BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  rider_id                 INT NOT NULL UNIQUE,
  cash_in_hand_paise       BIGINT NOT NULL DEFAULT 0,
  lifetime_collected_paise BIGINT UNSIGNED NOT NULL DEFAULT 0,
  lifetime_deposited_paise BIGINT UNSIGNED NOT NULL DEFAULT 0,
  pending_earnings_paise   BIGINT UNSIGNED NOT NULL DEFAULT 0,
  version                  INT UNSIGNED NOT NULL DEFAULT 0,
  created_at               DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at               DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                             ON UPDATE CURRENT_TIMESTAMP(3),
  KEY idx_rider (rider_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 4) rider_cash_deposits
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rider_cash_deposits (
  id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  rider_id        INT NOT NULL,
  admin_user_id   INT NOT NULL,
  amount_paise    BIGINT UNSIGNED NOT NULL,
  note            VARCHAR(255) NULL,
  idempotency_key CHAR(64) NOT NULL,
  created_at      DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY uniq_rider_idem (rider_id, idempotency_key),
  KEY idx_rider_date (rider_id, created_at),
  KEY idx_admin (admin_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 5) order_events — audit trail
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_events (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_id      INT NOT NULL,
  actor_user_id INT NULL,
  actor_role    ENUM('customer','admin','delivery','system') NOT NULL,
  event_type    VARCHAR(64) NOT NULL,
  from_state    VARCHAR(32) NULL,
  to_state      VARCHAR(32) NULL,
  payload       JSON NULL,
  created_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  KEY idx_order (order_id, created_at),
  KEY idx_event_type (event_type, created_at),
  CONSTRAINT fk_oe_order FOREIGN KEY (order_id) REFERENCES orders(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- Rollback plan (manual, if ever needed):
--   DROP TABLE order_events, rider_cash_deposits, rider_wallets, rider_profiles;
--   ALTER TABLE orders DROP COLUMN delivery_status, DROP COLUMN delivery_assigned_at,
--     DROP COLUMN delivery_picked_at, DROP COLUMN delivery_arrived_at,
--     DROP COLUMN delivery_completed_at, DROP COLUMN cash_collected_paise,
--     DROP COLUMN delivery_attempts, DROP COLUMN delivery_otp_hash;
-- ---------------------------------------------------------------------------
