import express, { Router } from 'express';
import { AdminController } from '../controllers/admin.controller';
import { StoreStatusController } from '../controllers/storeStatus.controller';
import { authenticate, authorize } from '../middleware/auth.middleware';
import { RedisService } from '../services/redis.service';
import { MissingTranslationController } from '../controllers/missingTranslation.controller';
import { UploadController } from '../controllers/upload.controller';
import { uploadSingle } from '../middleware/upload.middleware';

const router = Router();

router.use(authenticate);
router.use(authorize('admin'));

// Admin: flush Redis cache (use to invalidate stale cached responses)
router.post('/cache/flush', async (_req, res) => {
  try {
    const deleted = await RedisService.deleteKeysMatching('cache:*');
    res.json({ success: true, keysDeleted: deleted });
  } catch (e) {
    res.status(500).json({ success: false, error: String(e) });
  }
});

router.get('/dashboard', AdminController.getDashboardStats);
router.get('/orders', AdminController.getAllOrders);
router.get('/orders/:id', AdminController.getOrderById);
router.put('/orders/:id/status', AdminController.updateOrderStatus);
router.get('/users', AdminController.getAllUsers);
router.get('/delivery-agents', AdminController.getDeliveryAgents);
router.put('/users/:id', AdminController.updateUser);
router.post('/users/:id/role', AdminController.changeUserRole);
router.get('/products', AdminController.getAllProducts);
router.post('/products', AdminController.createProduct);
router.put('/products/:id', AdminController.updateProduct);
router.delete('/products/:id', AdminController.deleteProduct);
router.get('/missing-translations',MissingTranslationController.getMissingTranslations);

// Static segments must be declared before the ':id' route below.
router.get('/missing-translations/export', MissingTranslationController.exportCsv);

router.post(
  '/missing-translations/bulk',
  // Global express.json() ignores text/csv, so parse the raw CSV here.
  express.text({ type: ['text/csv', 'text/plain'], limit: '5mb' }),
  MissingTranslationController.bulkComplete
);

router.put('/missing-translations/:id',MissingTranslationController.completeMissingTranslation);
router.post('/notifications/send', AdminController.sendPromoNotification);

// --- Phase 1: rider management + delivery-aware order actions ---
router.get('/riders', AdminController.listRiders);
router.get('/riders/:id/wallet', AdminController.getRiderWallet);
router.post('/riders/:id/deposit', AdminController.recordRiderDeposit);
router.post('/orders/:id/assign-rider', AdminController.assignRiderToOrder);
router.post('/orders/:id/complete-rto', AdminController.completeRto);
router.post('/orders/:id/approve-cancellation', AdminController.approveCancellation);
router.post('/orders/:id/reject-cancellation', AdminController.rejectCancellation);
router.get('/orders/:id/events', AdminController.getOrderEvents);
router.get('/orders/:id/refund', AdminController.getOrderRefund);
router.post('/orders/:id/retry-refund', AdminController.retryRefund);

// --- Store open/closed ---
// Read is also exposed publicly at GET /api/store/status; this admin copy lets
// the panel read back the authoritative state without a second base URL.
router.get('/store/status', StoreStatusController.getStatus);
router.put('/store/status', StoreStatusController.updateStatus);

// --- Image upload ---
// Moved here from the former upload.routes.ts, which index.ts mounted as a
// SECOND router on '/api/admin'. A request for /api/admin/upload-image matched
// no route in this router, ran its authenticate + authorize, fell through, and
// then ran that router's identical pair again — two JWT verifications and two
// user lookups per upload. URLs are unchanged: the mobile client still calls
// /api/admin/upload-image.
router.post('/upload-image', uploadSingle, UploadController.uploadImage);
router.delete('/delete-image', UploadController.deleteImage);

export default router;
