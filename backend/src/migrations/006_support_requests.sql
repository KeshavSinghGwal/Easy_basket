-- ============================================================================
-- Migration 006: Support requests
--
-- REWRITTEN. The original version of this file never applied anywhere — its
-- CREATE TABLE carried an inline foreign key to `users(id)`, and this schema's
-- user table is `user` (singular). MySQL rejects the whole statement when the
-- referenced table does not exist, so the table was never created, the three
-- CREATE INDEX statements after it failed too, and the Help & Support feature
-- has been dead since it was written.
--
-- Rewritten in place rather than superseded by a 008: the original demonstrably
-- never succeeded in any environment (the table is absent under either name), so
-- there is no database where a corrected version could diverge from an applied
-- one. Leaving a known-broken migration in the repo is its own landmine.
--
-- ----------------------------------------------------------------------------
-- The original also disagreed with the entity in three further ways
-- ----------------------------------------------------------------------------
-- SupportRequest uses a bare @Entity() with no explicit name mappings, so
-- TypeORM derives every identifier. The original migration was written in the
-- snake_case style of the newer tables (payments, refunds, order_events), which
-- those entities opt into explicitly via @Column({ name: ... }). This one does
-- not, so it needs TypeORM's defaults:
--
--     was (never worked)          entity actually requires
--     ------------------          ------------------------
--     support_requests            support_request
--     user_id                     userId
--     order_id                    orderId
--     created_at / updated_at     createdAt / updatedAt
--     REFERENCES users(id)        REFERENCES user(id)
--
-- Matching the entity keeps this to one file and zero code churn. Changing the
-- entity to snake_case instead would be more consistent with the newer tables,
-- but touches running code to fix a table that does not exist yet.
--
-- datetime(6) because @CreateDateColumn()/@UpdateDateColumn() with no explicit
-- precision map to datetime(6) on MySQL. The payments-era tables use (3) only
-- because their entities ask for it.
--
-- Additive and idempotent. Safe to run on production, and safe to run twice.
--
-- Run with:
--   mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME < 006_support_requests.sql
-- ============================================================================

CREATE TABLE IF NOT EXISTS support_request (
    id          INT NOT NULL AUTO_INCREMENT PRIMARY KEY,

    -- @ManyToOne(() => User) — not nullable on the entity.
    userId      INT NOT NULL,
    -- @ManyToOne(() => Order, { nullable: true }) — a request need not concern
    -- a specific order.
    orderId     INT NULL DEFAULT NULL,

    category    VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    status      VARCHAR(255) NOT NULL DEFAULT 'open',

    createdAt   DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updatedAt   DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                  ON UPDATE CURRENT_TIMESTAMP(6),

    -- onDelete matches the entity decorators exactly: CASCADE on user,
    -- SET NULL on order.
    CONSTRAINT fk_support_request_user
        FOREIGN KEY (userId) REFERENCES user(id) ON DELETE CASCADE,

    CONSTRAINT fk_support_request_order
        FOREIGN KEY (orderId) REFERENCES orders(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- No additional indexes. MySQL creates one automatically for each foreign-key
-- column, which covers userId and orderId. SupportController.list currently
-- reads every row ordered by createdAt with no status filter, so an index on
-- status would sit unused — add one when a query actually needs it.

-- ----------------------------------------------------------------------------
-- Marker, consistent with 006_refund_retries.sql / 007_order_snapshots.sql.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
  name       VARCHAR(128) NOT NULL PRIMARY KEY,
  applied_at DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO schema_migrations (name) VALUES ('006_support_requests');

-- ============================================================================
-- Done. Creates one empty table; no existing row is read or written.
--
-- Rollback:
--   DROP TABLE support_request;
--   DELETE FROM schema_migrations WHERE name = '006_support_requests';
-- ============================================================================
