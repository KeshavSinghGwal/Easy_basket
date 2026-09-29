import { Router } from 'express';
import { ServiceAreaController } from '../controllers/serviceArea.controller';
import { authenticate, authorize } from '../middleware/auth.middleware';

const router = Router();

// Public route - check service availability
router.get('/check', ServiceAreaController.checkAvailability);

// Admin routes - require authentication and admin role
router.use(authenticate);
router.use(authorize('admin'));

router.get('/', ServiceAreaController.getAllServiceAreas);
router.post('/', ServiceAreaController.createServiceArea);
router.put('/:id', ServiceAreaController.updateServiceArea);
router.delete('/:id', ServiceAreaController.deleteServiceArea);

export default router;
