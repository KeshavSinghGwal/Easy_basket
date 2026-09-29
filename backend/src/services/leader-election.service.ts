import crypto from 'crypto';
import { RedisService } from './redis.service';

/**
 * Cheap Redis leader election for interval-driven singleton sweeps.
 *
 * Why this exists: PM2 runs `instances: 'max'` in cluster mode and the HA guide puts
 * two EC2 boxes behind an ALB, so index.ts's `start()` calls execute in EVERY process.
 * That means N copies of the auto-cancel sweep and N copies of the payments reconciler,
 * each pulling the same rows and hitting the Razorpay API with the same reads — wasted
 * quota at best, and duplicated side effects wherever a sweep is not perfectly guarded.
 *
 * NODE_APP_INSTANCE would only disambiguate within one host: both EC2 boxes have an
 * instance 0. A Redis key is the only thing all processes actually share.
 *
 * Leadership is sticky and self-healing: the holder re-extends its own TTL on each
 * tick, and if it dies the key simply expires and the next process to ask takes over.
 * Pass a TTL comfortably larger than the caller's interval so a slow tick does not
 * hand leadership away mid-run.
 *
 * This is an optimisation, not a correctness mechanism. Anything that mutates money
 * or stock must still be individually safe (atomic claims, the per-payment lock) —
 * a network partition can always produce two leaders for one TTL window.
 */
export class LeaderElectionService {
  /** Identifies THIS process. Regenerated on restart, which is what we want. */
  private static readonly token = crypto.randomBytes(12).toString('hex');

  /**
   * True if this process holds (or has just taken) leadership for `name`.
   * Safe to call on every tick — it renews rather than thrashing.
   *
   * Fails OPEN: if Redis is unreachable we return true so the sweep still runs.
   * A missed safety-net sweep is worse than a duplicated one, and the sweeps'
   * own guards are what actually prevent double side effects.
   */
  static async isLeader(name: string, ttlSeconds: number): Promise<boolean> {
    const key = `leader:${name}`;
    try {
      const client = await RedisService.getClient();

      const acquired = await client.set(key, this.token, { NX: true, EX: ttlSeconds });
      if (acquired === 'OK') {
        console.log(`[leader] acquired '${name}' (ttl ${ttlSeconds}s)`);
        return true;
      }

      // Held by someone. If that someone is us, extend and keep going.
      const holder = await client.get(key);
      if (holder === this.token) {
        await client.expire(key, ttlSeconds);
        return true;
      }

      return false;
    } catch (err) {
      console.warn(
        `[leader] Redis unavailable while checking '${name}' — running anyway`,
        (err as Error).message
      );
      return true;
    }
  }
}
