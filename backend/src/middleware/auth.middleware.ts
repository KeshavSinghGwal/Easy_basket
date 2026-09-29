import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { AppDataSource } from '../config/database';
import { JWT_SECRET } from '../config/jwt';
import { User } from '../entities/User';
import { RedisService } from '../services/redis.service';

export interface AuthRequest extends Request {
  user?: User;
}

/**
 * How long an authenticated identity may be served from Redis.
 *
 * Reading role and isActive from the DATABASE rather than the token is the right
 * call — it makes a ban or a role change take effect immediately instead of
 * waiting out the 15-minute access token. The cost was a full User row read on
 * every single authenticated request, uncached, against a 10-connection pool,
 * multiplied by order-tracking polling.
 *
 * 45s keeps revocation effectively immediate while removing that read from the
 * hot path. AdminController.changeUserRole and updateUser invalidate explicitly,
 * so a deliberate change is instant and this TTL is only the backstop for a
 * direct database edit.
 */
const AUTH_CACHE_TTL_SEC = 45;

const authCacheKey = (userId: number) => `auth:user:${userId}`;

/** Drop a user's cached identity. Call after ANY change to role or isActive. */
export async function invalidateCachedUser(userId: number): Promise<void> {
  try {
    await RedisService.del(authCacheKey(userId));
  } catch (err) {
    // Best-effort. A stale entry self-clears within AUTH_CACHE_TTL_SEC.
    console.warn(`[auth] could not invalidate cached user ${userId}`, (err as Error).message);
  }
}

export const authenticate = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const token = req.headers.authorization?.split(' ')[1];

    if (!token) {
      res.status(401).json({ message: 'Authentication required' });
      return;
    }

    const decoded = jwt.verify(token, JWT_SECRET) as {
      userId: number;
    };

    // Cached identity first. Only the fields any authorization decision actually
    // reads are cached — id, role, isActive, phoneNumber — never the whole row,
    // so nothing sensitive (fcmToken, email, birthday) sits in Redis.
    let user: User | null = null;
    const key = authCacheKey(decoded.userId);

    try {
      const cached = await RedisService.getJson<Pick<
        User,
        'id' | 'role' | 'isActive' | 'phoneNumber'
      >>(key);
      if (cached) {
        user = Object.assign(new User(), cached);
      }
    } catch {
      // Redis hiccup — fall through to the database. Never fail a request
      // because a cache is unavailable.
    }

    if (!user) {
      const userRepository = AppDataSource.getRepository(User);
      const fresh = await userRepository.findOneBy({ id: decoded.userId });

      if (!fresh || !fresh.isActive) {
        res.status(401).json({ message: 'Invalid or inactive user' });
        return;
      }

      user = fresh;
      // Best-effort write; a failure just means the next request reads the DB.
      RedisService.setJson(
        key,
        {
          id: fresh.id,
          role: fresh.role,
          isActive: fresh.isActive,
          phoneNumber: fresh.phoneNumber,
        },
        AUTH_CACHE_TTL_SEC
      ).catch(() => undefined);
    }

    // Also covers a cached entry written before a user was deactivated, in the
    // window before invalidateCachedUser or the TTL catches up.
    if (!user.isActive) {
      res.status(401).json({ message: 'Invalid or inactive user' });
      return;
    }

    req.user = user;
    next();
  } catch (error) {
    res.status(401).json({ message: 'Invalid token' });
  }
};

export const authorize = (...roles: string[]) => {
  return (req: AuthRequest, res: Response, next: NextFunction): void => {
    if (!req.user) {
      res.status(401).json({ message: 'Authentication required' });
      return;
    }

    if (!roles.includes(req.user.role)) {
      res.status(403).json({ message: 'Access denied' });
      return;
    }

    next();
  };
};
