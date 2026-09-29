import { Router } from 'express';
import { DeliveryController } from '../controllers/delivery.controller';
import { authenticate, authorize } from '../middleware/auth.middleware';

const router = Router();

router.use(authenticate);
router.use(authorize('delivery'));

// --- Existing endpoints (kept for backward compatibility) ---
router.get('/orders', DeliveryController.getAssignedOrders);
router.get('/orders/available', DeliveryController.getAvailableOrders);
router.post('/orders/:id/accept', DeliveryController.acceptOrder);
router.get('/orders/:id', DeliveryController.getOrderDetails);
// REMOVED: PUT /orders/:id/status — legacy free-form status setter that bypassed the
// delivery state machine (could mark 'delivered' with no OTP, no wallet debit → cash
// theft vector). Riders must use the state-machine endpoints below (start-delivery →
// arrived → collect-cash / mark-prepaid-delivered), which gate on OTP + wallet.
router.get('/stats', DeliveryController.getDeliveryStats);
router.get('/earnings', DeliveryController.getEarnings);

// --- Phase 1 state-machine endpoints ---
router.post('/availability', DeliveryController.setAvailability);
router.post('/location', DeliveryController.updateLocation);
router.get('/wallet', DeliveryController.getWallet);

router.post('/orders/:id/arrived-at-store', DeliveryController.arrivedAtStore);
router.post('/orders/:id/picked', DeliveryController.picked);
router.post('/orders/:id/start-delivery', DeliveryController.startDelivery);
router.post('/orders/:id/arrived', DeliveryController.arrived);
router.post('/orders/:id/collect-cash', DeliveryController.collectCash);
router.post('/orders/:id/mark-prepaid-delivered', DeliveryController.markPrepaidDelivered);
router.post('/orders/:id/switch-to-upi', DeliveryController.switchToUpi);
router.post('/orders/:id/report-issue', DeliveryController.reportIssue);

export default router;
