import { Router } from 'express';
import { StoreStatusController } from '../controllers/storeStatus.controller';

const router = Router();

// PUBLIC — no `authenticate`. Guests browse before logging in and must see the
// closed banner too. The admin write lives on /api/admin/store/status instead,
// behind that router's authenticate + authorize('admin').
router.get('/status', StoreStatusController.getStatus);

export default router;
