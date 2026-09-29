import { Router } from 'express';
import { CampaignController } from '../controllers/campaign.controller';
import { authenticate, authorize } from '../middleware/auth.middleware';

const router = Router();

// Public — fetch campaigns for homepage (no auth needed)
router.get('/', CampaignController.getCampaigns);

// Admin only — CRUD + push
router.get('/admin', authenticate, authorize('admin'), CampaignController.getAllCampaigns);
router.post('/admin', authenticate, authorize('admin'), CampaignController.createCampaign);
router.put('/admin/:id', authenticate, authorize('admin'), CampaignController.updateCampaign);
router.delete('/admin/:id', authenticate, authorize('admin'), CampaignController.deleteCampaign);
router.post('/admin/:id/push', authenticate, authorize('admin'), CampaignController.sendCampaignPush);

export default router;
