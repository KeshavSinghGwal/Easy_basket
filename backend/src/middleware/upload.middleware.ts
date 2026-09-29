import multer from 'multer';
import { Request } from 'express';

/**
 * Multer configuration for file uploads
 * Stores files in memory (as buffers) for S3 upload
 */
const storage = multer.memoryStorage();

/**
 * File filter - only allow image files
 */
const fileFilter = (req: Request, file: Express.Multer.File, cb: multer.FileFilterCallback) => {
  const allowedMimeTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];

  if (allowedMimeTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('Invalid file type. Only JPG, PNG, and WebP images are allowed.'));
  }
};

/**
 * Multer upload middleware
 * - Max file size: 5MB
 * - Single file upload
 * - Memory storage (for S3 upload)
 */
export const upload = multer({
  storage,
  fileFilter,
  limits: {
    fileSize: 5 * 1024 * 1024, // 5MB
  },
});

/**
 * Single file upload middleware
 */
export const uploadSingle = upload.single('file');
export const uploadProfileImage = upload.single('image');
