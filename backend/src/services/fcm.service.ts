import * as admin from 'firebase-admin';
import * as fs from 'fs';
import * as util from 'util';
import { AppDataSource } from '../config/database';
import { User } from '../entities/User';
import { UserRole } from '../constants/roles';

/** PM2 / aggregators sometimes hide stderr; mirror critical lines to stdout too. */
function fcmEmitFailureLine(context: string, detail: string): void {
  const line = `[FCM][SEND_FAILED] ${context} | ${detail}`;
  process.stdout.write(`${line}\n`);
  process.stderr.write(`${line}\n`);
  console.error(line);
}

function formatFcmError(error: unknown): string {
  try {
    if (error instanceof Error) {
      return `${error.name}: ${error.message}${error.stack ? ` | ${error.stack}` : ''}`;
    }
    if (typeof error === 'object' && error !== null) {
      const o = error as Record<string, unknown>;
      const code = o.code != null ? String(o.code) : '';
      const msg = o.message != null ? String(o.message) : '';
      const details = o.errorInfo ?? o.httpErrorCode ?? '';
      return (
        JSON.stringify({ code, message: msg, details }) +
        util.inspect(error, { depth: 3, breakLength: 120 })
      );
    }
    return String(error);
  } catch {
    return util.inspect(error, { depth: 2 });
  }
}

/**
 * Token is not valid for this Firebase project (stale app install, wrong project, or truncated token).
 * Safe to clear DB token so the next app open registers a new one.
 */
function isPermanentFcmTokenFailure(error: unknown): boolean {
  const o =
    typeof error === 'object' && error !== null
      ? (error as { code?: string; message?: string })
      : null;
  const code = o?.code ?? '';
  const msg = (o?.message ?? (error instanceof Error ? error.message : String(error))) as string;
  if (code === 'messaging/registration-token-not-registered') return true;
  if (code === 'messaging/invalid-registration-token') return true;
  if (code === 'messaging/unregistered') return true;
  // HTTP NOT_FOUND from FCM — common text when token does not exist for this sender/project
  if (/requested entity was not found/i.test(msg)) return true;
  if (/not a valid fcm registration token/i.test(msg)) return true;
  return false;
}

/**
 * Resolve the Firebase service account credential.
 *
 * Preferred:  FIREBASE_SERVICE_ACCOUNT_PATH=/abs/path/to/service-account.json
 *             (file should be chmod 0600 and owned by the runtime user)
 * Legacy:     FIREBASE_SERVICE_ACCOUNT=<inline JSON> — readable by anyone with
 *             shell access via `pm2 env <id>` or /proc/<pid>/environ. A warning
 *             is emitted when this path is taken; migrate to the file form.
 *
 * Returns null when neither is configured. Throws nothing — all I/O and parse
 * errors are swallowed and surfaced as a generic warning so the JSON contents
 * (including the private key) never leak into logs.
 */
function loadFirebaseServiceAccount(): admin.ServiceAccount | null {
  const filePath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH?.trim();
  if (filePath) {
    try {
      const raw = fs.readFileSync(filePath, 'utf8');
      return JSON.parse(raw) as admin.ServiceAccount;
    } catch {
      console.error(
        `[FCM] Failed to read or parse service account at FIREBASE_SERVICE_ACCOUNT_PATH. Check file exists, is valid JSON, and is readable by the runtime user.`
      );
      return null;
    }
  }

  const inline = process.env.FIREBASE_SERVICE_ACCOUNT?.trim();
  if (inline) {
    console.warn(
      '[FCM] Loading service account from FIREBASE_SERVICE_ACCOUNT env var. ' +
        'This is readable via `pm2 env <id>` and /proc/<pid>/environ — migrate ' +
        'to FIREBASE_SERVICE_ACCOUNT_PATH (chmod 0600 file) to keep the key off the env.'
    );
    try {
      return JSON.parse(inline) as admin.ServiceAccount;
    } catch {
      console.error('[FCM] FIREBASE_SERVICE_ACCOUNT is not valid JSON.');
      return null;
    }
  }

  return null;
}

async function clearStoredFcmTokenIfMatches(userId: number, rawToken: string): Promise<void> {
  const userRepository = AppDataSource.getRepository(User);
  const u = await userRepository.findOneBy({ id: userId });
  if (!u?.fcmToken || u.fcmToken.trim() !== rawToken.trim()) return;
  const phone = u.phoneNumber;
  u.fcmToken = null;
  await userRepository.save(u);
  console.warn(
    `[FCM] Cleared dead fcmToken for user ${userId} (${phone}) — open app again to register push. If this repeats, verify google-services.json project_id matches server FIREBASE_SERVICE_ACCOUNT.`
  );
}

export class FCMService {
  private static initialized = false;

  /**
   * Run notification I/O off the request path. Failures are logged only and never reject callers.
   */
  static enqueue(task: () => Promise<unknown>, label: string): void {
    void Promise.resolve()
      .then(task)
      .catch((error) => {
        console.error(`❌ [FCM] Background task failed [${label}]: ${formatFcmError(error)}`);
      });
  }

  static initialize(): void {
    if (this.initialized) {
      return;
    }

    const serviceAccount = loadFirebaseServiceAccount();
    if (!serviceAccount) {
      console.warn(
        'Firebase service account not configured (set FIREBASE_SERVICE_ACCOUNT_PATH). FCM notifications will be disabled.'
      );
      return;
    }

    try {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      this.initialized = true;
      console.log('Firebase Admin initialized');
    } catch {
      // Intentionally swallow error details. The credential object contains the
      // RSA private key, and firebase-admin's init error messages have leaked
      // raw key material into stacks before. A generic line is enough for ops.
      console.error(
        '[FCM] Firebase Admin initialization failed. Verify FIREBASE_SERVICE_ACCOUNT_PATH points to a valid service-account JSON.'
      );
    }
  }

  /**
   * Low-level send; returns error object on failure so callers can clear stale DB tokens.
   */
  private static async deliverToToken(
    fcmToken: string,
    title: string,
    body: string,
    data?: Record<string, string>,
    context?: string
  ): Promise<{ ok: true } | { ok: false; error: unknown }> {
    const ctx = context ? `[${context}] ` : '';

    if (!this.initialized) {
      const msg = 'FCM not initialized (check FIREBASE_SERVICE_ACCOUNT on this PM2 instance)';
      console.warn(`⚠️ [FCM] ${ctx}${msg}`);
      fcmEmitFailureLine(ctx.trim() || 'send', msg);
      return { ok: false, error: new Error(msg) };
    }

    const token = fcmToken.trim();
    if (token.length < 120) {
      console.warn(
        `⚠️ [FCM] ${ctx}tokenLen=${token.length} is unusually short (typical FCM token ~140–180). Check MySQL column for fcmToken (use VARCHAR(512)+utf8mb4) — truncation causes Send failed.`
      );
    }
    if (token.length !== fcmToken.length) {
      console.warn(`⚠️ [FCM] ${ctx}Token had leading/trailing whitespace; trimmed before send`);
    }
    if (token.length < 10) {
      const msg = `token empty/invalid (len=${token.length})`;
      fcmEmitFailureLine(ctx.trim() || 'send', msg);
      return { ok: false, error: new Error(msg) };
    }

    const tokenPreview = token.length >= 20 ? `${token.substring(0, 20)}...` : token;

    try {
      console.log(
        `📤 [FCM] ${ctx}Sending notification tokenLen=${token.length} preview=${tokenPreview}`
      );
      const response = await admin.messaging().send({
        token,
        notification: {
          title,
          body,
        },
        data: data || {},
      });
      console.log(`✅ [FCM] ${ctx}Notification sent successfully. Message ID: ${response}`);
      return { ok: true };
    } catch (error: unknown) {
      const detail = formatFcmError(error);
      fcmEmitFailureLine(ctx.trim() || 'send', detail);
      return { ok: false, error };
    }
  }

  /**
   * @param userIdForStaleTokenCleanup When set and FCM returns a permanent token error, that user's stored token is cleared so the next login refreshes it.
   */
  static async sendNotification(
    fcmToken: string,
    title: string,
    body: string,
    data?: Record<string, string>,
    context?: string,
    userIdForStaleTokenCleanup?: number
  ): Promise<boolean> {
    const r = await this.deliverToToken(fcmToken, title, body, data, context);
    if (!r.ok && userIdForStaleTokenCleanup != null && isPermanentFcmTokenFailure(r.error)) {
      try {
        await clearStoredFcmTokenIfMatches(userIdForStaleTokenCleanup, fcmToken);
      } catch (e) {
        console.error('[FCM] Failed to clear stale fcmToken:', e);
      }
    }
    return r.ok;
  }

  static async sendNotificationToUser(
    userId: number,
    title: string,
    body: string,
    data?: Record<string, string>
  ): Promise<boolean> {
    const userRepository = AppDataSource.getRepository(User);
    const user = await userRepository.findOneBy({ id: userId });

    if (!user || !user.fcmToken) {
      return false;
    }

    return this.sendNotification(user.fcmToken, title, body, data, `userId=${userId}`, userId);
  }

  static async sendNotificationToRole(
    role: UserRole,
    title: string,
    body: string,
    data?: Record<string, string>
  ): Promise<number> {
    console.log(`📤 [FCM] Sending notification to role: ${role}`);
    console.log(`📤 [FCM] Title: ${title}, Body: ${body}`);

    if (!this.initialized) {
      console.warn('⚠️ [FCM] FCM not initialized, skipping notification');
      return 0;
    }

    const userRepository = AppDataSource.getRepository(User);
    const users = await userRepository.find({
      where: { role, isActive: true },
    });

    console.log(`📤 [FCM] Found ${users.length} ${role} users`);

    const tokensSeen = new Set<string>();
    let successCount = 0;
    let tokenCount = 0;

    for (const user of users) {
      if (user.fcmToken) {
        tokenCount++;
        if (tokensSeen.has(user.fcmToken)) {
          console.warn(
            `⚠️ [FCM] User ${user.id} (${user.phoneNumber}) shares the same FCM token as another admin — stale logins or test accounts; only one device will get pushes.`
          );
        }
        tokensSeen.add(user.fcmToken);
        console.log(
          `📤 [FCM] Sending to user ${user.id} (${user.phoneNumber}), token: ${user.fcmToken.substring(0, 20)}...`
        );
        const rawToken = user.fcmToken;
        const result = await this.deliverToToken(
          rawToken,
          title,
          body,
          data,
          `role=${role} userId=${user.id}`
        );
        if (result.ok) {
          successCount++;
          console.log(`✅ [FCM] Notification sent successfully to user ${user.id}`);
        } else {
          if (isPermanentFcmTokenFailure(result.error)) {
            try {
              await clearStoredFcmTokenIfMatches(user.id, rawToken);
            } catch (e) {
              console.error('[FCM] Failed to clear stale fcmToken:', e);
            }
          }
          const hint =
            'See [FCM][SEND_FAILED] above. "Requested entity was not found" = token invalid for this Firebase project or stale; re-login on device or fix project mismatch.';
          console.error(
            `❌ [FCM] Notification failed for user ${user.id} (${user.phoneNumber}) — ${hint}`
          );
          process.stdout.write(
            `[FCM][USER_FAIL] userId=${user.id} phone=${user.phoneNumber} | ${hint}\n`
          );
        }
      } else {
        console.warn(`⚠️ [FCM] User ${user.id} (${user.phoneNumber}) has no FCM token`);
      }
    }

    console.log(`📤 [FCM] Summary: ${successCount}/${tokenCount} notifications sent successfully`);
    return successCount;
  }
}

// Initialize on module load
FCMService.initialize();
