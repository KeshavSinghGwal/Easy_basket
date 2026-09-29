import { Router } from 'express';
import { ProductController } from '../controllers/product.controller';
import { authenticate, authorize } from '../middleware/auth.middleware';

const router = Router();

// Public routes
router.get('/suggestions', ProductController.getSuggestions);
router.get('/', ProductController.getAllProducts);
router.get('/:id', ProductController.getProductById);

// Admin routes
router.post('/', authenticate, authorize('admin'), ProductController.createProduct);
router.put('/:id', authenticate, authorize('admin'), ProductController.updateProduct);
router.delete('/:id', authenticate, authorize('admin'), ProductController.deleteProduct);

export default router;
