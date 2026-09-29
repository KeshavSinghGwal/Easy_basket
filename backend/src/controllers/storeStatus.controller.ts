import * as admin from 'firebase-admin';
import { Request, Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { StoreStatusService } from '../services/store-status.service';

/** Topic every app instance subscribes to on FCM init. */
const ALL_USERS_TOPIC = 'all_users';

export class StoreStatusController {
  /**
   * GET /api/store/status — PUBLIC.
   *
   * Unauthenticated on purpose: guests browse before logging in and must see
   * the closed banner too. Marked no-store so no CDN or proxy between us and
   * the app can pin a stale "open" past the service's own short TTL.
   */
  static async getStatus(_req: Request, res: Response): Promise<void> {
    try {
      const status = await StoreStatusService.get();
      res.set('Cache-Control', 'no-store');
      res.json(status);
    } catch (error) {
      console.error('[store-status] getStatus error', error);
      // Fail open — a broken status read must never block browsing or checkout.
      res.set('Cache-Control', 'no-store');
      res.json({
        isOpen: true,
        closedReason: null,
        customMessage: null,
        expectedReopenAt: null,
        closedAt: null,
      });
    }
  }

  /**
   * PUT /api/admin/store/status — admin only (router applies authenticate +
   * authorize('admin')).
   *
   * Body: { isOpen, closedReason?, customMessage?, expectedReopenAt?, notifyOnReopen? }
   *
   * Closing gates NEW orders only. Existing orders, riders and admin actions
   * are untouched by design.
   */
  static async updateStatus(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { isOpen, closedReason, customMessage, expectedReopenAt, notifyOnReopen } =
        req.body as {
          isOpen?: unknown;
          closedReason?: unknown;
          customMessage?: unknown;
          expectedReopenAt?: unknown;
          notifyOnReopen?: unknown;
        };

      if (typeof isOpen !== 'boolean') {
        res.status(400).json({ message: 'isOpen (boolean) is required' });
        return;
      }

      if (!isOpen && closedReason != null && !StoreStatusService.isValidReason(closedReason)) {
        res.status(400).json({
          message:
            'Invalid closedReason. Allowed: rain, holiday, maintenance, high_demand, out_of_hours, other.',
        });
        return;
      }

      if (typeof customMessage === 'string' && customMessage.length > 280) {
        res.status(400).json({ message: 'customMessage must be 280 characters or fewer' });
        return;
      }

      // Parse the display-only ETA. Reject garbage rather than silently
      // dropping it — an admin who typed a time deserves to know it was lost.
      let reopenAt: Date | null = null;
      if (!isOpen && expectedReopenAt != null && expectedReopenAt !== '') {
        const parsed = new Date(String(expectedReopenAt));
        if (Number.isNaN(parsed.getTime())) {
          res.status(400).json({ message: 'expectedReopenAt must be a valid ISO-8601 date' });
          return;
        }
        reopenAt = parsed;
      }

      const { status, didReopen } = await StoreStatusService.set({
        isOpen,
        closedReason: StoreStatusService.isValidReason(closedReason) ? closedReason : null,
        customMessage: typeof customMessage === 'string' ? customMessage : null,
        expectedReopenAt: reopenAt,
        adminUserId: req.user?.id,
      });

      console.log(
        `🏪 [store-status] ${isOpen ? 'OPENED' : `CLOSED (${status.closedReason})`} by userId=${req.user?.id ?? 'unknown'}`
      );

      // Only broadcast on an actual closed → open transition, so re-saving an
      // already-open store can't spam every device.
      let pushSent = false;
      if (didReopen && notifyOnReopen === true) {
        pushSent = await StoreStatusController.broadcastReopen();
      }

      res.json({ success: true, status, pushSent });
    } catch (error) {
      console.error('[store-status] updateStatus error', error);
      res.status(500).json({ message: 'Error updating store status' });
    }
  }

  /**
   * Fire-and-report the "we're back" push. Never throws — a failed broadcast
   * must not fail the reopen itself; the store is already open in the database
   * by the time this runs.
   */
  private static async broadcastReopen(): Promise<boolean> {
    try {
      await admin.messaging().send({
        topic: ALL_USERS_TOPIC,
        notification: {
          title: "We're open! 🛒",
          body: 'Easy Basket is back online. Your cart is waiting — order now!',
        },
        data: { type: 'STORE_REOPENED' },
      });
      console.log(`✅ [store-status] reopen push sent to topic: ${ALL_USERS_TOPIC}`);
      return true;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error(`❌ [store-status] reopen push failed: ${msg}`);
      return false;
    }
  }
}
