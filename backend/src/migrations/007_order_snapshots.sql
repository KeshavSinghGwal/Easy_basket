-- ===========================================================================
-- 007_order_snapshots.sql
--
-- Makes an order's record of WHAT was bought and WHERE it was going immutable.
--
-- Today both are read through live foreign keys:
--   orders.deliveryAddressId  -> address        (ManyToOne, no snapshot)
--   order_item.productId      -> product        (price IS snapshotted, name is not)
--
-- So editing a product's name rewrites every historical order containing it, and
-- editing an address rewrites the delivery address on orders already placed —
-- including, in the worst case, one currently out with a rider, who then sees a
-- different door than the one they were sent to.
--
-- Adds a third column for address soft-delete, because a hard DELETE on a row an
-- order references raises ER_ROW_IS_REFERENCED_2 and surfaces to the customer as
-- a generic 500. Archiving is only safe once orders no longer read through to
-- the row, which is what the snapshot above provides.
--
-- ---------------------------------------------------------------------------
-- DELIBERATELY ADDITIVE ONLY. No UPDATE, no DELETE, no backfill.
-- ---------------------------------------------------------------------------
-- A backfill would copy TODAY'S address into the snapshot for existing orders.
-- But the bug being fixed is that the fuzzy duplicate-merge in
-- AddressController.createAddress overwrote address rows in place — so for any
-- order affected by a past merge, today's value is ALREADY the wrong address,
-- and the original is unrecoverable. Backfilling would cement that mistake into
-- history permanently, and there is no way to identify which rows are affected.
--
-- Instead these columns stay NULL for pre-migration rows and the application
-- falls back to the live relation when the snapshot is absent. Old orders behave
-- exactly as they do now; every order placed after this migration gets the
-- guarantee. Nothing is rewritten and nothing can be made worse.
--
-- ---------------------------------------------------------------------------
-- DEPLOY ORDER MATTERS
-- ---------------------------------------------------------------------------
-- Run this BEFORE deploying the code that adds the matching @Column decorators.
-- The DataSource runs with synchronize:false, and TypeORM selects every mapped
-- column by name — so an entity declaring a column the database does not have
-- breaks EVERY query on that entity, not just the ones touching the new field.
--
-- Safe because all three columns are nullable-or-defaulted and unread until the
-- code ships: applying this migration to the CURRENT running code is a no-op.
--
-- Verified against the live schema (SHOW TABLES): the tables are `orders`,
-- `order_item` and `address`. Note `user` is singular and a stray legacy `order`
-- table also exists — neither is touched here.
--
-- MySQL 8 supports `ADD COLUMN IF NOT EXISTS`; for 5.7 compatibility every step
-- below is guarded on information_schema, so re-running is a no-op.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1) orders.delivery_address_snapshot
-- ---------------------------------------------------------------------------
-- JSON rather than nine discrete columns: a delivery address is always read as
-- a block (rider sheet, order detail, admin panel) and never filtered on. Same
-- choice already made for payments.raw_webhook_json.
--
-- Shape written by the application:
--   {"addressLine1":..,"addressLine2":..,"city":..,"state":..,"pincode":..,
--    "landmark":..,"latitude":..,"longitude":..,"tag":..}
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'delivery_address_snapshot'
);
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE orders ADD COLUMN delivery_address_snapshot JSON NULL DEFAULT NULL',
  'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ---------------------------------------------------------------------------
-- 2) order_item.product_name
-- ---------------------------------------------------------------------------
-- order_item already snapshots price, total, unit and displayLabel. The product
-- NAME was the one field still read through the live relation, which is what
-- let a catalogue rename rewrite order history.
--
-- VARCHAR(255) matches product.name (@Column() default length).
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'order_item'
    AND COLUMN_NAME = 'product_name'
);
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE order_item ADD COLUMN product_name VARCHAR(255) NULL DEFAULT NULL',
  'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ---------------------------------------------------------------------------
-- 3) order_item.product_image_url
-- ---------------------------------------------------------------------------
-- Stored as the path-only key the rest of the system persists (see
-- normalizeMediaForStorage), NOT a full URL, so it survives a bucket or CDN
-- rename exactly as product.imageUrl does. 512 to leave headroom over the 255
-- product.imageUrl uses today.
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'order_item'
    AND COLUMN_NAME = 'product_image_url'
);
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE order_item ADD COLUMN product_image_url VARCHAR(512) NULL DEFAULT NULL',
  'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ---------------------------------------------------------------------------
-- 4) address.is_archived
-- ---------------------------------------------------------------------------
-- NOT NULL DEFAULT 0 is safe additive: every existing row becomes 0 (visible),
-- which is exactly today's behaviour.
--
-- No index. Addresses per user are a handful, and the lookup is already narrowed
-- by the userId foreign-key index.
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'address'
    AND COLUMN_NAME = 'is_archived'
);
SET @ddl := IF(@col_exists = 0,
  'ALTER TABLE address ADD COLUMN is_archived TINYINT(1) NOT NULL DEFAULT 0',
  'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ---------------------------------------------------------------------------
-- Marker. Consistent with 006_refund_retries.sql; nothing here is guarded on it
-- (every step above is individually idempotent) but it records that this ran.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
  name       VARCHAR(128) NOT NULL PRIMARY KEY,
  applied_at DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO schema_migrations (name) VALUES ('007_order_snapshots');


-- ===========================================================================
-- Done. No rows were read, written or deleted.
--
-- Rollback (safe at any time — the application treats all three as optional):
--   ALTER TABLE orders     DROP COLUMN delivery_address_snapshot;
--   ALTER TABLE order_item DROP COLUMN product_name, DROP COLUMN product_image_url;
--   ALTER TABLE address    DROP COLUMN is_archived;
--   DELETE FROM schema_migrations WHERE name = '007_order_snapshots';
-- ===========================================================================
