import { RedisService } from './redis.service';

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetInSec: number;
}

/**
 * Fixed-window rate limiter backed by Redis. INCRs `key` and sets a TTL on the
 * first hit of a window; subsequent calls in the same window reuse the TTL.
 *
 * Blocked calls still count toward the window — this keeps a sustained burst
 * blocked for the full window rather than letting an attacker probe the
 * boundary every second.
 */
export class RateLimitService {
  static async checkAndIncrement(
    key: string,
    limit: number,
    windowSec: number
  ): Promise<RateLimitResult> {
    const count = await RedisService.incr(key);
    if (count === 1) {
      await RedisService.expire(key, windowSec);
    }
    if (count > limit) {
      const ttl = await RedisService.ttl(key);
      return { allowed: false, remaining: 0, resetInSec: ttl > 0 ? ttl : windowSec };
    }
    return { allowed: true, remaining: limit - count, resetInSec: -1 };
  }
}
