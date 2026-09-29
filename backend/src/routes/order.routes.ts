import { Router } from 'express';
import { OrderController } from '../controllers/order.controller';
import { authenticate } from '../middleware/auth.middleware';
import { idempotency } from '../middleware/idempotency.middleware';

const router = Router();

// All routes require authentication. `/status/:id` was previously public but
// allowed enumeration of order totals and timestamps via sequential IDs.
router.use(authenticate);

router.get('/status/:id', OrderController.getOrderStatus);
router.post('/', idempotency('order-create', 60), OrderController.createOrder);
router.get('/', OrderController.getUserOrders);
router.get('/:id', OrderController.getOrderById);
router.put('/:id/cancel', OrderController.cancelOrder);
router.post('/:id/request-cancellation', OrderController.requestCancellation);

export default router;
