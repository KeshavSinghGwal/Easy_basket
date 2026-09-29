import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { S3Service } from '../services/s3.service';
import { AppDataSource } from '../config/database';
import { Product } from '../entities/Product';
import { Category } from '../entities/Category';
import { detectImageType } from '../utils/image-type.util';

export class UploadController {
  /**
   * Upload image for product or category
   * POST /api/admin/upload-image
   */
  static async uploadImage(req: AuthRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;

      if (!userId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      // Check if file was uploaded
      if (!req.file) {
        res.status(400).json({ message: 'No file uploaded' });
        return;
      }

      // Identify the file by its BYTES, not by what the client said it was.
      //
      // Until here nothing had looked at the content: multer's fileFilter and
      // S3Service both checked `file.mimetype`, which is just the Content-Type
      // string on the multipart part, and the stored extension came from
      // `file.originalname`. Both are attacker-chosen. The verified values are
      // written back onto the file object below so S3Service — which reads
      // exactly these two fields to set the object's ContentType and key — ends
      // up describing the object truthfully without any change to its contract.
      //
      // Magic-byte checking cannot live in multer's fileFilter: with
      // memoryStorage that hook runs on the part headers, before the buffer is
      // complete. It has to be here.
      const detected = detectImageType(req.file.buffer);
      if (!detected) {
        res.status(400).json({
          message: 'That file is not a JPEG, PNG or WebP image.',
          code: 'INVALID_IMAGE',
        });
        return;
      }
      req.file.mimetype = detected.mime;
      req.file.originalname = `upload.${detected.ext}`;

      // Get form data
      const { type, id, name } = req.body;

      // Validate type
      if (!type || !['product', 'category'].includes(type)) {
        res.status(400).json({ message: 'Invalid type. Must be "product" or "category"' });
        return;
      }

      // Validate ID
      const entityId = parseInt(id, 10);
      if (!entityId || isNaN(entityId)) {
        res.status(400).json({ message: 'Invalid ID' });
        return;
      }

      // Verify entity exists and belongs to admin (or is accessible)
      let entityName: string | undefined;

      if (type === 'product') {
        const productRepository = AppDataSource.getRepository(Product);
        const product = await productRepository.findOneBy({ id: entityId });
        if (!product) {
          res.status(404).json({ message: 'Product not found' });
          return;
        }
        entityName = product.name;
      } else if (type === 'category') {
        const categoryRepository = AppDataSource.getRepository(Category);
        const category = await categoryRepository.findOneBy({ id: entityId });
        if (!category) {
          res.status(404).json({ message: 'Category not found' });
          return;
        }
        entityName = category.name;
      }

      // Upload to S3
      const result = await S3Service.uploadImage(
        req.file,
        type as 'product' | 'category',
        entityId,
        name, // Admin-provided name (optional)
        entityName // Entity name for auto-generation
      );

      res.status(200).json({
        success: true,
        url: result.url,
        filename: result.filename,
        path: result.path,
        size: req.file.size,
        mimetype: req.file.mimetype,
      });
    } catch (error) {
      console.error('Error uploading image:', error);
      const errorMessage = error instanceof Error ? error.message : 'Error uploading image';
      res.status(500).json({ message: errorMessage });
    }
  }

  /**
   * Delete image from S3
   * DELETE /api/admin/delete-image
   */
  static async deleteImage(req: AuthRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;

      if (!userId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      // Addressed by ENTITY, not by URL.
      //
      // This used to take an arbitrary `url`, derive a key from it and delete
      // whatever that pointed at — with no check that the key belonged to this
      // application's namespace, let alone to the row being edited. A typo or a
      // compromised admin session could remove any object in the bucket. Now the
      // only thing deletable is the image the named product or category is
      // currently using, which is the only thing this endpoint ever needed to do.
      //
      // No client calls the old shape (grepped across mobile and both websites),
      // so changing the contract breaks nothing.
      const { type, id } = req.body as { type?: string; id?: number | string };

      if (!type || !['product', 'category'].includes(type)) {
        res.status(400).json({ message: 'Invalid type. Must be "product" or "category"' });
        return;
      }

      const entityId = parseInt(String(id), 10);
      if (!Number.isFinite(entityId) || entityId <= 0) {
        res.status(400).json({ message: 'Invalid ID' });
        return;
      }

      let storedPath: string | undefined;

      if (type === 'product') {
        const product = await AppDataSource.getRepository(Product).findOneBy({ id: entityId });
        if (!product) {
          res.status(404).json({ message: 'Product not found' });
          return;
        }
        storedPath = product.imageUrl;
      } else {
        const category = await AppDataSource.getRepository(Category).findOneBy({ id: entityId });
        if (!category) {
          res.status(404).json({ message: 'Category not found' });
          return;
        }
        storedPath = category.imageUrl;
      }

      if (!storedPath) {
        res.status(404).json({ message: 'That item has no image to delete' });
        return;
      }

      // Stored values are path-only keys (see normalizeMediaForStorage), but
      // legacy rows may still hold a full URL — extractKeyFromUrl handles both.
      const key = /^https?:\/\//i.test(storedPath)
        ? S3Service.extractKeyFromUrl(storedPath)
        : storedPath.replace(/^\/+/, '');

      if (!key) {
        res.status(400).json({ message: 'Could not resolve the stored image path' });
        return;
      }

      await S3Service.deleteImage(key);

      res.status(200).json({
        success: true,
        message: 'Image deleted successfully',
      });
    } catch (error) {
      console.error('Error deleting image:', error);
      const errorMessage = error instanceof Error ? error.message : 'Error deleting image';
      res.status(500).json({ message: errorMessage });
    }
  }
}
