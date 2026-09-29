import { Router } from 'express';
import { CategoryController } from '../controllers/category.controller';
import { authenticate, authorize } from '../middleware/auth.middleware';

const router = Router();

// Public routes
router.get('/', CategoryController.getAllCategories);
router.get('/:id', CategoryController.getCategoryById);
router.get('/:id/subcategories', CategoryController.getSubcategories);

// Admin routes
router.post('/', authenticate, authorize('admin'), CategoryController.createCategory);
router.put('/:id', authenticate, authorize('admin'), CategoryController.updateCategory);
router.delete('/:id', authenticate, authorize('admin'), CategoryController.deleteCategory);

export default router;
