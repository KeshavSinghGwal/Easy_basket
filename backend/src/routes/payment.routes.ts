import { Router } from 'express';
import { PaymentController } from '../controllers/payment.controller';
import { authenticate, authorize } from '../middleware/auth.middleware';

/**
 * NOTE: the webhook route is NOT registered here — it's mounted separately in index.ts
 * BEFORE the global express.json() middleware so that the HMAC verification can read
 * the raw request body byte-for-byte.  Do not add /webhook/razorpay to this router.
 */
const router = Router();

router.post('/create-order', authenticate, PaymentController.createRazorpayOrder);
router.post('/verify', authenticate, PaymentController.verifyPayment);
// Admin-only. A refund must never be self-service: the owner check that used to
// guard this endpoint always passed for the customer, so any authenticated user
// could refund their own DELIVERED order and bypass the "no refunds after packing"
// policy enforced in AdminController.approveCancellation.
router.post('/refund', authenticate, authorize('admin'), PaymentController.refund);

export default router;
