import { Request, Response } from 'express';
import { AppDataSource } from '../config/database';
import { ProductVariant } from '../entities/ProductVariant';
import { Product } from '../entities/Product';
import { ProductController } from './product.controller';

export class VariantController {
  /**
   * Get all variants for a product
   * GET /api/products/:productId/variants
   */
  static async getProductVariants(req: Request, res: Response): Promise<void> {
    try {
      const { productId } = req.params;
      const variantRepository = AppDataSource.getRepository(ProductVariant);

      const variants = await variantRepository.find({
        where: { product: { id: Number(productId) } },
        order: { displayOrder: 'ASC', quantity: 'ASC' },
      });

      res.json({ variants });
    } catch (error) {
      console.error('Error fetching variants:', error);
      res.status(500).json({ message: 'Error fetching variants' });
    }
  }

  /**
   * Create a new variant for a product
   * POST /api/admin/products/:productId/variants
   */
  static async createVariant(req: Request, res: Response): Promise<void> {
    try {
      const { productId } = req.params;
      const {
        quantity,
        unit,
        label,
        price,
        stock,
        isAvailable,
        minQuantity,
        maxQuantity,
        displayOrder,
        isDefault,
      } = req.body;

      // Validate required fields
      if (!quantity || !unit || !label || price === undefined) {
        res.status(400).json({ message: 'Quantity, unit, label, and price are required' });
        return;
      }

      const productRepository = AppDataSource.getRepository(Product);
      const product = await productRepository.findOneBy({ id: Number(productId) });

      if (!product) {
        res.status(404).json({ message: 'Product not found' });
        return;
      }

      const variantRepository = AppDataSource.getRepository(ProductVariant);

      // If this is set as default, unset other defaults
      if (isDefault) {
        await variantRepository.update({ product: { id: product.id } }, { isDefault: false });
      }

      const variant = variantRepository.create({
        product,
        quantity: Number(quantity),
        unit,
        label,
        price: Number(price),
        stock: stock ?? 0,
        isAvailable: isAvailable ?? true,
        minQuantity: minQuantity ? Number(minQuantity) : null,
        maxQuantity: maxQuantity ? Number(maxQuantity) : null,
        displayOrder: displayOrder ?? 0,
        isDefault: isDefault ?? false,
      });

      await variantRepository.save(variant);

      // Update product to indicate it has variants
      if (!product.hasVariants) {
        product.hasVariants = true;
        product.baseUnit = unit;
        await productRepository.save(product);
      }

      await ProductController.invalidateProductListCache();
      res.status(201).json(variant);
    } catch (error: any) {
      console.error('Error creating variant:', error);

      // Return more detailed error message
      if (error.code === 'ER_DUP_ENTRY' || error.errno === 1062) {
        res.status(409).json({
          message: 'A variant with this configuration already exists',
          error: 'DUPLICATE_VARIANT',
        });
        return;
      }

      if (error.code === 'ER_NO_REFERENCED_ROW_2' || error.errno === 1452) {
        res.status(404).json({
          message: 'Product not found',
          error: 'PRODUCT_NOT_FOUND',
        });
        return;
      }

      res.status(500).json({
        message: 'Error creating variant',
        error: error.message || 'Unknown error',
        details: process.env.NODE_ENV === 'development' ? error.stack : undefined,
      });
    }
  }

  /**
   * Update a variant
   * PUT /api/admin/variants/:id
   */
  static async updateVariant(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const {
        quantity,
        unit,
        label,
        price,
        stock,
        isAvailable,
        minQuantity,
        maxQuantity,
        displayOrder,
        isDefault,
      } = req.body;

      const variantRepository = AppDataSource.getRepository(ProductVariant);
      const variant = await variantRepository.findOne({
        where: { id: Number(id) },
        relations: ['product'],
      });

      if (!variant) {
        res.status(404).json({ message: 'Variant not found' });
        return;
      }

      // If setting as default, unset other defaults for this product
      if (isDefault && !variant.isDefault) {
        await variantRepository.update(
          { product: { id: variant.product.id } },
          { isDefault: false }
        );
      }

      if (quantity !== undefined) variant.quantity = Number(quantity);
      if (unit) variant.unit = unit;
      if (label) variant.label = label;
      if (price !== undefined) variant.price = Number(price);
      if (stock !== undefined) variant.stock = stock;
      if (isAvailable !== undefined) variant.isAvailable = isAvailable;
      if (minQuantity !== undefined) variant.minQuantity = minQuantity ? Number(minQuantity) : null;
      if (maxQuantity !== undefined) variant.maxQuantity = maxQuantity ? Number(maxQuantity) : null;
      if (displayOrder !== undefined) variant.displayOrder = displayOrder;
      if (isDefault !== undefined) variant.isDefault = isDefault;

      await variantRepository.save(variant);
      await ProductController.invalidateProductListCache();
      res.json(variant);
    } catch (error) {
      console.error('Error updating variant:', error);
      res.status(500).json({ message: 'Error updating variant' });
    }
  }

  /**
   * Delete a variant
   * DELETE /api/admin/variants/:id
   */
  static async deleteVariant(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const variantRepository = AppDataSource.getRepository(ProductVariant);
      const variant = await variantRepository.findOne({
        where: { id: Number(id) },
        relations: ['product'],
      });

      if (!variant) {
        res.status(404).json({ message: 'Variant not found' });
        return;
      }

      await variantRepository.remove(variant);

      // Check if product has any remaining variants
      const remainingVariants = await variantRepository.count({
        where: { product: { id: variant.product.id } },
      });

      if (remainingVariants === 0) {
        const productRepository = AppDataSource.getRepository(Product);
        variant.product.hasVariants = false;
        await productRepository.save(variant.product);
      }

      await ProductController.invalidateProductListCache();
      res.json({ message: 'Variant deleted successfully' });
    } catch (error) {
      console.error('Error deleting variant:', error);
      res.status(500).json({ message: 'Error deleting variant' });
    }
  }
}
