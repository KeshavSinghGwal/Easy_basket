import { Router } from 'express';
import { SupportController } from '../controllers/support.controller';
import { authenticate, authorize } from '../middleware/auth.middleware';

const router = Router();

router.use(authenticate);

// User — any authenticated customer may raise a request.
router.post('/', SupportController.create);

// Admin. SupportController.list/updateStatus each re-check the role internally,
// which is correct but invisible from the route table and one edit away from
// being dropped. Declaring authorize('admin') here makes the access model
// readable where every other admin route states it.
router.get('/', authorize('admin'), SupportController.list);
router.patch('/:id/status', authorize('admin'), SupportController.updateStatus);

export default router;