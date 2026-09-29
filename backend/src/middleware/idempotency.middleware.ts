import { Response, NextFunction } from 'express';
import crypto from 'crypto';
import { RedisService } from '../services/redis.service';
import { AuthRequest } from './auth.middleware';

/**
 * Fast-path idempotency using Redis SET NX.
 * Permanent idempotency is enforced by the UNIQUE constraint on (user_id, idempotency_key)
 * in the orders / refunds tables — this middleware just short-circuits repeat requests
 * that arrive within the TTL window, so the client sees a stable response.
 *
 * Client provides the key via header:  Idempotency-Key: <uuid>
 *
 * If the key is absent, we fall back to a request fingerprint so that double-taps from
 * an unmodified mobile client are still deduped (weaker, but better than nothing).
 *
 * Usage:
 *   router.post('/', idempotency('order-create', 60), OrderController.createOrder)
 *
 * After the route handler completes successfully, call `idempotency.store(req, res.locals.idempotency)`
 * from the handler to persist the response body for 24h.
 */
export function idempotency(scope: string, ttlSeconds = 60) {
  return async (req: AuthRequest, res: Response, next: NextFunction): Promise<void> => {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: 'Authentication required' });
      return;
    }

    const clientKey =
      (req.headers['idempotency-key'] as string | undefined)?.trim() ||
      fingerprint(userId, req.body);

    if (!/^[A-Za-z0-9_\-:]{8,128}$/.test(clientKey)) {
      res.status(400).json({ message: 'Invalid Idempotency-Key' });
      return;
    }

    const redisKey = `idem:${scope}:${userId}:${clientKey}`;

    try {
      const client = await RedisService.getClient();

      // Try to claim the key. If it already exists, return its stored body or a 409.
      const claimed = await client.set(redisKey, 'IN_PROGRESS', { NX: true, EX: ttlSeconds });
      if (claimed !== 'OK') {
        const existing = await client.get(redisKey);
        if (existing && existing !== 'IN_PROGRESS') {
          try {
            const cached = JSON.parse(existing) as { status: number; body: unknown };
            res.status(cached.status).json(cached.body);
            return;
          } catch {
            // fallthrough to 409
          }
        }
        res.status(409).json({
          message: 'Duplicate request in progress — please retry in a moment',
        });
        return;
      }

      // Expose hooks on res.locals so the controller can finalize the cache entry.
      res.locals.idempotency = {
        redisKey,
        clientKey,
        ttlSeconds: 24 * 60 * 60,
      };

      // Patch res.json to auto-store the response body.
      const origJson = res.json.bind(res);
      res.json = ((body: unknown) => {
        const entry = res.locals.idempotency as
          | { redisKey: string; ttlSeconds: number }
          | undefined;
        if (entry && res.statusCode < 500) {
          // Best-effort cache write — do not block the response.
          RedisService.set(
            entry.redisKey,
            JSON.stringify({ status: res.statusCode, body }),
            entry.ttlSeconds
          ).catch((err) => console.warn('[idempotency] cache write failed', err));
        } else if (entry) {
          // 5xx → release the lock so retries can proceed immediately.
          RedisService.del(entry.redisKey).catch(() => undefined);
        }
        return origJson(body);
      }) as typeof res.json;

      next();
    } catch (err) {
      console.error('[idempotency] redis error; failing open', err);
      // Fail open: DB unique constraint is still the source of truth.
      next();
    }
  };
}

/** Scope-aware attribute names exposed on the request body. */
export function idempotencyKeyFromReq(req: AuthRequest): string | null {
  const hdr = (req.headers['idempotency-key'] as string | undefined)?.trim();
  return hdr || null;
}

function fingerprint(userId: number, body: unknown): string {
  const hash = crypto.createHash('sha256');
  hash.update(String(userId));
  hash.update('|');
  hash.update(stableStringify(body));
  // Coarse 60-second bucket: genuine retries fingerprint the same key;
  // genuine new orders placed a minute apart do not collide.
  hash.update('|');
  hash.update(String(Math.floor(Date.now() / 60_000)));
  return `fp:${hash.digest('hex')}`;
}

function stableStringify(v: unknown): string {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + v.map(stableStringify).join(',') + ']';
  const obj = v as Record<string, unknown>;
  const keys = Object.keys(obj).sort();
  return '{' + keys.map((k) => JSON.stringify(k) + ':' + stableStringify(obj[k])).join(',') + '}';
}
