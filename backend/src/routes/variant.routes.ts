import { Router } from 'express';
import { VariantController } from '../controllers/variant.controller';
import { authenticate, authorize } from '../middleware/auth.middleware';

const router = Router();

// Public route - get variants for a product
router.get('/products/:productId/variants', VariantController.getProductVariants);

// Admin routes - manage variants (require authentication and admin role)
router.post(
  '/products/:productId/variants',
  authenticate,
  authorize('admin'),
  VariantController.createVariant
);
router.put('/variants/:id', authenticate, authorize('admin'), VariantController.updateVariant);
router.delete('/variants/:id', authenticate, authorize('admin'), VariantController.deleteVariant);

export default router;
