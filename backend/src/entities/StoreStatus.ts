import { Entity, PrimaryColumn, Column, UpdateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
import { User } from './User';

/**
 * Reasons a store can be closed. The enum drives the *visual* the app shows
 * (rain animation, holiday icon, …) — a free-text reason could not, which is
 * why this is a closed set rather than a string. `customMessage` carries the
 * words; this carries the pixels.
 */
export const STORE_CLOSED_REASONS = [
  'rain',
  'holiday',
  'maintenance',
  'high_demand',
  'out_of_hours',
  'other',
] as const;

export type StoreClosedReason = (typeof STORE_CLOSED_REASONS)[number];

/**
 * StoreStatus — whether the store is accepting NEW orders.
 *
 * SINGLETON: exactly one row, pinned to id = 1 (see migration 004). It is not
 * append-only on purpose — with a log table every reader would have to agree on
 * what "current" means (max id? max updatedAt?) and a clock skew or a
 * concurrent insert could resolve two different answers. One row, last write
 * wins, no ambiguity. History lives in the app log, not here.
 *
 * Scope of `isOpen: false` — it gates ORDER CREATION ONLY. Existing orders,
 * rider deliveries, admin actions, cancellations and refunds are all
 * deliberately unaffected: a customer who already paid must still get their
 * groceries, whatever the weather.
 */
@Entity({ name: 'store_status' })
export class StoreStatus {
  /** Always 1. Not generated — the row is seeded by the migration. */
  @PrimaryColumn({ type: 'int' })
  id!: number;

  @Column({ name: 'is_open', type: 'boolean', default: true })
  isOpen!: boolean;

  // ── Why it's closed (only meaningful when isOpen = false) ──

  @Column({
    name: 'closed_reason',
    type: 'enum',
    enum: STORE_CLOSED_REASONS,
    nullable: true,
  })
  closedReason!: StoreClosedReason | null;

  /**
   * Admin-authored headline shown to users, e.g. "Heavy rain in Bareilly".
   * Optional — the app falls back to a sensible default per reason.
   */
  @Column({ name: 'custom_message', type: 'varchar', length: 280, nullable: true })
  customMessage!: string | null;

  /**
   * Expected reopen time, DISPLAY ONLY. The store never reopens on its own when
   * this passes — reopening is always a deliberate admin action, so we can't end
   * up accepting orders at 6am with nobody at the counter. Stored UTC (the RDS
   * connection is `timezone: 'Z'`), rendered in IST by the client.
   */
  @Column({ name: 'expected_reopen_at', type: 'timestamp', nullable: true })
  expectedReopenAt!: Date | null;

  // ── Audit: who flipped it, and when ──

  @ManyToOne(() => User, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'updated_by_id' })
  updatedBy!: User | null;

  @Column({ name: 'closed_at', type: 'timestamp', nullable: true })
  closedAt!: Date | null;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt!: Date;
}
