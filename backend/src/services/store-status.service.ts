import { AppDataSource } from '../config/database';
import { StoreStatus, StoreClosedReason, STORE_CLOSED_REASONS } from '../entities/StoreStatus';
import { User } from '../entities/User';

/** The singleton row's primary key. See migration 004. */
const ROW_ID = 1;

/**
 * How long a cached status may be served to *browsing* traffic. The status
 * endpoint is public and polled by every app on launch/resume, so an
 * uncached primary-key read per request is wasteful — but a long TTL would
 * mean an admin closes the store and users keep seeing "open" for minutes.
 *
 * 5s is the compromise. Note we run multiple instances behind the ALB, so an
 * in-process cache cannot be invalidated cluster-wide by one instance's write:
 * the real bound on staleness is this TTL, not `invalidate()`. Order creation
 * deliberately bypasses all of it (see `isAcceptingOrders`).
 */
const CACHE_TTL_MS = 5_000;

export interface StoreStatusView {
  isOpen: boolean;
  closedReason: StoreClosedReason | null;
  customMessage: string | null;
  /** ISO-8601 UTC. Display only — never auto-reopens the store. */
  expectedReopenAt: string | null;
  closedAt: string | null;
}

/** Served when the row or table is missing (e.g. migration 004 not yet run). */
const FALLBACK_OPEN: StoreStatusView = {
  isOpen: true,
  closedReason: null,
  customMessage: null,
  expectedReopenAt: null,
  closedAt: null,
};

let cached: { value: StoreStatusView; at: number } | null = null;

function toView(row: StoreStatus): StoreStatusView {
  return {
    isOpen: !!row.isOpen,
    closedReason: row.isOpen ? null : row.closedReason,
    customMessage: row.isOpen ? null : row.customMessage,
    expectedReopenAt: row.isOpen ? null : (row.expectedReopenAt?.toISOString() ?? null),
    closedAt: row.isOpen ? null : (row.closedAt?.toISOString() ?? null),
  };
}

export class StoreStatusService {
  static isValidReason(value: unknown): value is StoreClosedReason {
    return typeof value === 'string' && (STORE_CLOSED_REASONS as readonly string[]).includes(value);
  }

  /** Drop the in-process cache. Only affects THIS instance — see CACHE_TTL_MS. */
  static invalidate(): void {
    cached = null;
  }

  /**
   * Read the singleton row straight from the database, no cache.
   *
   * Fails OPEN on any error. A database blip must not silently shut the shop
   * down — the visible failure mode of "took an order we couldn't fulfil" is
   * far cheaper to fix than "rejected every order for an hour and nobody
   * noticed".
   */
  private static async readThrough(): Promise<StoreStatusView> {
    try {
      const row = await AppDataSource.getRepository(StoreStatus).findOneBy({ id: ROW_ID });
      if (!row) {
        console.warn('[store-status] singleton row missing — run migration 004. Serving OPEN.');
        return FALLBACK_OPEN;
      }
      return toView(row);
    } catch (err) {
      console.error('[store-status] read failed, serving OPEN:', err);
      return FALLBACK_OPEN;
    }
  }

  /**
   * Status for display (home banner, checkout UI). Cached for CACHE_TTL_MS.
   * Do NOT use this to authorise an order — use `isAcceptingOrders`.
   */
  static async get(): Promise<StoreStatusView> {
    const now = Date.now();
    if (cached && now - cached.at < CACHE_TTL_MS) {
      return cached.value;
    }
    const value = await this.readThrough();
    cached = { value, at: now };
    return value;
  }

  /**
   * Authoritative check used by the order-creation guard. Always hits the
   * database — order creation is low-volume next to status polling, and it is
   * the one place where being 5 seconds stale actually costs money.
   */
  static async isAcceptingOrders(): Promise<StoreStatusView> {
    return this.readThrough();
  }

  /**
   * Flip the store open/closed. Returns the new state plus whether this call
   * was the transition from closed → open (the caller uses that to decide
   * whether to fire the "we're back" push — so a no-op re-save never spams).
   */
  static async set(params: {
    isOpen: boolean;
    closedReason?: StoreClosedReason | null;
    customMessage?: string | null;
    expectedReopenAt?: Date | null;
    adminUserId?: number;
  }): Promise<{ status: StoreStatusView; didReopen: boolean }> {
    const repo = AppDataSource.getRepository(StoreStatus);

    // The migration seeds this row, but tolerate its absence so a fresh
    // environment self-heals instead of 500-ing.
    let row = await repo.findOneBy({ id: ROW_ID });
    if (!row) {
      row = repo.create({ id: ROW_ID, isOpen: true });
    }

    const wasOpen = !!row.isOpen;
    const didReopen = !wasOpen && params.isOpen;

    row.isOpen = params.isOpen;

    if (params.isOpen) {
      // Clear the closure context on reopen so a future close can't inherit
      // last week's "heavy rain" message.
      row.closedReason = null;
      row.customMessage = null;
      row.expectedReopenAt = null;
      row.closedAt = null;
    } else {
      row.closedReason = params.closedReason ?? 'other';
      row.customMessage = params.customMessage?.trim() || null;
      row.expectedReopenAt = params.expectedReopenAt ?? null;
      // Preserve the original closedAt when editing the message of an
      // already-closed store — "closed since 2pm" shouldn't reset to now.
      row.closedAt = wasOpen ? new Date() : (row.closedAt ?? new Date());
    }

    if (params.adminUserId != null) {
      row.updatedBy = { id: params.adminUserId } as User;
    }

    await repo.save(row);
    this.invalidate();

    return { status: toView(row), didReopen };
  }
}
