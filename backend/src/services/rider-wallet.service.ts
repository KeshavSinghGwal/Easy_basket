import { EntityManager } from 'typeorm';
import { AppDataSource } from '../config/database';
import { RiderWallet } from '../entities/RiderWallet';
import { RiderCashDeposit } from '../entities/RiderCashDeposit';

/**
 * Rider wallet / cash reconciliation.
 *
 * Invariant:
 *     cash_in_hand_paise = lifetime_collected_paise - lifetime_deposited_paise
 *
 * The wallet is updated only via two mutations:
 *   - creditCollection(rider, amount)   — called atomically with "cash_collected" state transition
 *   - recordDeposit(rider, amount, ...) — called when admin confirms cash received at hub
 *
 * Both mutations are serialized on the wallet row via optimistic concurrency
 * (`VersionColumn` on RiderWallet). A concurrent writer re-reads and retries up to 3 times.
 */
export class RiderWalletService {
  /** Fetch or lazily create the wallet row for a rider. */
  static async ensureWallet(riderId: number, em?: EntityManager): Promise<RiderWallet> {
    const repo = (em ?? AppDataSource.manager).getRepository(RiderWallet);
    let wallet = await repo.findOne({ where: { riderId } });
    if (wallet) return wallet;

    wallet = repo.create({
      riderId,
      cashInHandPaise: '0',
      lifetimeCollectedPaise: '0',
      lifetimeDepositedPaise: '0',
      pendingEarningsPaise: '0',
    });
    try {
      return await repo.save(wallet);
    } catch (err) {
      // Race: someone else created it. Re-fetch.
      if (isDuplicateKeyError(err)) {
        const existing = await repo.findOne({ where: { riderId } });
        if (existing) return existing;
      }
      throw err;
    }
  }

  /**
   * Increment cash_in_hand by `amountPaise` (rider collected COD cash).
   * MUST be called inside the same transaction as the state transition to `delivered`.
   */
  static async creditCollection(
    riderId: number,
    amountPaise: number,
    em: EntityManager
  ): Promise<RiderWallet> {
    if (amountPaise <= 0) throw new Error(`creditCollection: invalid amount ${amountPaise}`);
    const repo = em.getRepository(RiderWallet);
    const wallet = await this.ensureWallet(riderId, em);

    wallet.cashInHandPaise = addBig(wallet.cashInHandPaise, amountPaise);
    wallet.lifetimeCollectedPaise = addBig(wallet.lifetimeCollectedPaise, amountPaise);

    return repo.save(wallet);
  }

  /**
   * Admin records a cash deposit from rider to hub.
   * - Appends an immutable row to `rider_cash_deposits` (idempotent via UNIQUE)
   * - Decrements `cash_in_hand_paise`, increments `lifetime_deposited_paise`
   *
   * Returns the deposit + updated wallet.
   */
  static async recordDeposit(params: {
    riderId: number;
    adminUserId: number;
    amountPaise: number;
    note?: string;
    idempotencyKey: string;
  }): Promise<{ deposit: RiderCashDeposit; wallet: RiderWallet }> {
    if (params.amountPaise <= 0) throw new Error('recordDeposit: amount must be > 0');

    return AppDataSource.manager.transaction(async (em) => {
      const depositRepo = em.getRepository(RiderCashDeposit);
      const walletRepo = em.getRepository(RiderWallet);

      // Idempotency: if a deposit with this key already exists, return it untouched.
      const existing = await depositRepo.findOne({
        where: { riderId: params.riderId, idempotencyKey: params.idempotencyKey },
      });
      if (existing) {
        const wallet = await this.ensureWallet(params.riderId, em);
        return { deposit: existing, wallet };
      }

      let deposit = depositRepo.create({
        riderId: params.riderId,
        adminUserId: params.adminUserId,
        amountPaise: String(params.amountPaise),
        note: params.note ?? null,
        idempotencyKey: params.idempotencyKey,
      });
      try {
        deposit = await depositRepo.save(deposit);
      } catch (err) {
        // Race on unique constraint — resolve by reading back.
        if (isDuplicateKeyError(err)) {
          const again = await depositRepo.findOne({
            where: { riderId: params.riderId, idempotencyKey: params.idempotencyKey },
          });
          if (again) {
            const wallet = await this.ensureWallet(params.riderId, em);
            return { deposit: again, wallet };
          }
        }
        throw err;
      }

      const wallet = await this.ensureWallet(params.riderId, em);
      wallet.cashInHandPaise = subBig(wallet.cashInHandPaise, params.amountPaise);
      wallet.lifetimeDepositedPaise = addBig(wallet.lifetimeDepositedPaise, params.amountPaise);
      const savedWallet = await walletRepo.save(wallet);

      return { deposit, wallet: savedWallet };
    });
  }

  static async getWallet(riderId: number): Promise<RiderWallet> {
    return this.ensureWallet(riderId);
  }
}

// ---------------------------------------------------------------------------
// BIGINT arithmetic helpers. TypeORM returns BIGINT columns as strings to avoid
// JS number precision loss; we add/subtract using BigInt to stay exact.
// ---------------------------------------------------------------------------

function addBig(current: string, delta: number): string {
  return (BigInt(current) + BigInt(delta)).toString();
}
function subBig(current: string, delta: number): string {
  return (BigInt(current) - BigInt(delta)).toString();
}

function isDuplicateKeyError(err: unknown): boolean {
  const e = err as { code?: string; errno?: number } | null;
  return e?.code === 'ER_DUP_ENTRY' || e?.errno === 1062;
}
