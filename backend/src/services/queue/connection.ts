import IORedis from 'ioredis';
import type { ConnectionOptions } from 'bullmq';

/**
 * Dedicated ioredis connection factory for BullMQ.
 *
 * BullMQ cannot reuse the node-redis client held by RedisService, so we build
 * our own connection from the SAME environment variables (REDIS_URL, or the
 * discrete REDIS_HOST/REDIS_PORT/REDIS_USERNAME/REDIS_PASSWORD/REDIS_TLS set).
 *
 * Each call returns a NEW connection on purpose: BullMQ wants a dedicated
 * (blocking) connection per Worker, and the Queue gets its own too.
 *
 * `maxRetriesPerRequest: null` is REQUIRED by BullMQ.
 *
 * The `as unknown as ConnectionOptions` cast bridges a type-only quirk: BullMQ
 * bundles its own copy of ioredis, so a top-level ioredis instance is not
 * nominally assignable to BullMQ's expected type even though it is the exact
 * same library at runtime.
 */
export function buildBullConnection(): ConnectionOptions {
  const base = { maxRetriesPerRequest: null, enableReadyCheck: false } as const;

  const url = process.env.REDIS_URL?.trim();
  const client = url
    ? new IORedis(url, base)
    : new IORedis({
        host: process.env.REDIS_HOST?.trim(),
        port: Number(process.env.REDIS_PORT),
        username: process.env.REDIS_USERNAME?.trim() || 'default',
        password: process.env.REDIS_PASSWORD,
        ...(process.env.REDIS_TLS === 'true' ? { tls: {} } : {}),
        ...base,
      });

  return client as unknown as ConnectionOptions;
}
