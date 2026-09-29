import { Request, Response } from 'express';
import { AppDataSource } from '../config/database';
import { Category } from '../entities/Category';
import { RedisService } from '../services/redis.service';
import { mapCategoryPublic, normalizeMediaForStorage } from '../utils/media-url.util';

/** Home / listing API — cache static-ish category trees in Redis */
const CATEGORY_LIST_CACHE_PREFIX = 'cache:categories:list:';
const CATEGORY_LIST_TTL_SEC = 600; // 10 minutes

function categoryListCacheKey(
  parentId: string | undefined,
  page: number,
  limit: number,
  includeInactive: boolean
): string {
  const p = parentId ?? 'root';
  return `${CATEGORY_LIST_CACHE_PREFIX}${p}:${page}:${limit}:${includeInactive}`;
}

export class CategoryController {
  private static async invalidateCategoryListCache(): Promise<void> {
    try {
      const n = await RedisService.deleteKeysMatching(`${CATEGORY_LIST_CACHE_PREFIX}*`);
      if (n > 0) {
        console.log(`🗑️ Category list cache invalidated (${n} key(s))`);
      }
    } catch (e) {
      console.warn('Category list cache invalidation failed:', e);
    }
  }

  static async getAllCategories(req: Request, res: Response): Promise<void> {
    try {
      const parentId = req.query.parentId as string | undefined;
      const page = parseInt(req.query.page as string) || 1;
      const limit = parseInt(req.query.limit as string) || 20;
      const skip = (page - 1) * limit;
      const includeInactive = req.query.includeInactive === 'true';

      const cacheKey = categoryListCacheKey(parentId, page, limit, includeInactive);
      try {
        const cached = await RedisService.getJson<{
          categories: unknown[];
          pagination: {
            page: number;
            limit: number;
            total: number;
            totalPages: number;
            hasMore: boolean;
          };
        }>(cacheKey);
        if (cached) {
          res.json(cached);
          return;
        }
      } catch {
        // Redis hiccup — fall through to DB
      }

      const categoryRepository = AppDataSource.getRepository(Category);

      // Build query
      const queryBuilder = categoryRepository
        .createQueryBuilder('category')
        .leftJoinAndSelect('category.subcategories', 'subcategories')
        .leftJoinAndSelect('category.parentCategory', 'parentCategory');

      // Only filter by isActive if includeInactive is not true
      if (!includeInactive) {
        queryBuilder.where('category.isActive = :isActive', { isActive: true });
      }

      // Filter by parent category if provided
      if (parentId) {
        queryBuilder.andWhere('category.parentCategoryId = :parentId', {
          parentId: Number(parentId),
        });
      } else {
        // Only top-level categories (no parent)
        queryBuilder.andWhere('category.parentCategoryId IS NULL');
      }

      queryBuilder
        .orderBy('category.displayOrder', 'ASC')
        .addOrderBy('category.name', 'ASC')
        .skip(skip)
        .take(limit);

      const [categories, total] = await queryBuilder.getManyAndCount();

      const payload = {
        categories: categories.map(mapCategoryPublic),
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
          hasMore: page * limit < total,
        },
      };

      try {
        await RedisService.setJson(cacheKey, payload, CATEGORY_LIST_TTL_SEC);
      } catch (e) {
        console.warn('Category list cache set failed:', e);
      }

      res.json(payload);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching categories' });
    }
  }

  static async getCategoryById(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const categoryRepository = AppDataSource.getRepository(Category);
      const category = await categoryRepository.findOne({
        where: { id: Number(id) },
        relations: ['products', 'subcategories', 'parentCategory'],
      });

      if (!category) {
        res.status(404).json({ message: 'Category not found' });
        return;
      }

      res.json(mapCategoryPublic(category));
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching category' });
    }
  }

  /**
   * Get subcategories of a parent category
   * GET /api/categories/:id/subcategories
   */
  static async getSubcategories(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const includeInactive = req.query.includeInactive === 'true';
      const categoryRepository = AppDataSource.getRepository(Category);

      const whereCondition: any = {
        parentCategory: { id: Number(id) },
      };

      // Only filter by isActive if includeInactive is not true
      if (!includeInactive) {
        whereCondition.isActive = true;
      }

      const subcategories = await categoryRepository.find({
        where: whereCondition,
        relations: ['parentCategory'],
        order: { displayOrder: 'ASC', name: 'ASC' },
      });

      res.json({ subcategories: subcategories.map(mapCategoryPublic) });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching subcategories' });
    }
  }

  static async createCategory(req: Request, res: Response): Promise<void> {
    try {
      const { name, description, imageUrl, parentCategoryId, displayOrder } = req.body;

      if (!name) {
        res.status(400).json({ message: 'Category name is required' });
        return;
      }

      const categoryRepository = AppDataSource.getRepository(Category);

      // Check if category with same name already exists under the same parent
      const whereCondition: any = { name: name.trim() };
      if (parentCategoryId) {
        whereCondition.parentCategory = { id: Number(parentCategoryId) };
      } else {
        whereCondition.parentCategory = null;
      }

      const existingCategory = await categoryRepository.findOne({
        where: whereCondition,
      });

      if (existingCategory) {
        res.status(409).json({
          message: `Category with name "${name}" already exists${parentCategoryId ? ' in this parent category' : ''}`,
          error: 'DUPLICATE_CATEGORY_NAME',
        });
        return;
      }

      // Validate parent category if provided
      let parentCategory: Category | null = null;
      if (parentCategoryId) {
        parentCategory = await categoryRepository.findOneBy({ id: Number(parentCategoryId) });
        if (!parentCategory) {
          res.status(404).json({ message: 'Parent category not found' });
          return;
        }
      }

      const category = categoryRepository.create({
        name: name.trim(),
        description,
        imageUrl: normalizeMediaForStorage(imageUrl),
        parentCategory: parentCategory,
        displayOrder: displayOrder ?? 0,
      });

      await categoryRepository.save(category);

      // Reload with relations
      const savedCategory = await categoryRepository.findOne({
        where: { id: category.id },
        relations: ['parentCategory', 'subcategories'],
      });

      await CategoryController.invalidateCategoryListCache();
      res.status(201).json(savedCategory ? mapCategoryPublic(savedCategory) : savedCategory);
    } catch (error: any) {
      console.error('Error creating category:', error);

      // Handle duplicate entry error from database
      if (error.code === 'ER_DUP_ENTRY' || error.errno === 1062) {
        res.status(409).json({
          message: `Category with name "${req.body.name}" already exists`,
          error: 'DUPLICATE_CATEGORY_NAME',
        });
        return;
      }

      res.status(500).json({ message: 'Error creating category' });
    }
  }

  static async updateCategory(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const categoryRepository = AppDataSource.getRepository(Category);
      const category = await categoryRepository.findOneBy({ id: Number(id) });

      if (!category) {
        res.status(404).json({ message: 'Category not found' });
        return;
      }

      const { name, description, imageUrl, isActive, parentCategoryId, displayOrder } = req.body;

      // Check for duplicate name if name is being updated
      if (name && name.trim() !== category.name) {
        const whereCondition: any = { name: name.trim() };
        const targetParentId =
          parentCategoryId !== undefined ? Number(parentCategoryId) : category.parentCategory?.id;

        if (targetParentId) {
          whereCondition.parentCategory = { id: targetParentId };
        } else {
          whereCondition.parentCategory = null;
        }

        const existingCategory = await categoryRepository.findOne({
          where: whereCondition,
        });

        if (existingCategory && existingCategory.id !== category.id) {
          res.status(409).json({
            message: `Category with name "${name}" already exists${targetParentId ? ' in this parent category' : ''}`,
            error: 'DUPLICATE_CATEGORY_NAME',
          });
          return;
        }
      }

      // Validate parent category if being changed
      if (parentCategoryId !== undefined) {
        if (parentCategoryId === null) {
          category.parentCategory = null;
        } else {
          const parentCategory = await categoryRepository.findOneBy({
            id: Number(parentCategoryId),
          });
          if (!parentCategory) {
            res.status(404).json({ message: 'Parent category not found' });
            return;
          }
          // Prevent circular reference (category cannot be its own parent)
          if (parentCategory.id === category.id) {
            res.status(400).json({ message: 'Category cannot be its own parent' });
            return;
          }
          category.parentCategory = parentCategory;
        }
      }

      if (name) category.name = name.trim();
      if (description !== undefined) category.description = description;
      if (imageUrl !== undefined)
        category.imageUrl = normalizeMediaForStorage(imageUrl) ?? '';
      if (isActive !== undefined) category.isActive = isActive;
      if (displayOrder !== undefined) category.displayOrder = displayOrder;

      await categoryRepository.save(category);
      await CategoryController.invalidateCategoryListCache();
      res.json(mapCategoryPublic(category));
    } catch (error: any) {
      console.error('Error updating category:', error);

      // Handle duplicate entry error from database
      if (error.code === 'ER_DUP_ENTRY' || error.errno === 1062) {
        res.status(409).json({
          message: `Category with name "${req.body.name}" already exists`,
          error: 'DUPLICATE_CATEGORY_NAME',
        });
        return;
      }

      res.status(500).json({ message: 'Error updating category' });
    }
  }

  static async deleteCategory(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const categoryRepository = AppDataSource.getRepository(Category);
      const category = await categoryRepository.findOneBy({ id: Number(id) });

      if (!category) {
        res.status(404).json({ message: 'Category not found' });
        return;
      }

      await categoryRepository.remove(category);
      await CategoryController.invalidateCategoryListCache();
      res.json({ message: 'Category deleted successfully' });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error deleting category' });
    }
  }
}
