import { S3Client, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { generateSlug, sanitizeSlug, getFileExtension } from '../utils/slug.util';

export class S3Service {
  private static s3Client: S3Client | null = null;
  private static bucketName: string;
  private static region: string;

  /**
   * Initialize S3 client
   */
  static initialize(): void {
    const accessKeyId = process.env.AWS_ACCESS_KEY_ID;
    const secretAccessKey = process.env.AWS_SECRET_ACCESS_KEY;
    const region = process.env.AWS_REGION || 'ap-south-1'; // Mumbai, India - better for Indian users
    const bucketName = process.env.AWS_S3_BUCKET_NAME;

    if (!accessKeyId || !secretAccessKey) {
      console.warn('⚠️ AWS S3 credentials not configured. Image upload will be disabled.');
      return;
    }

    if (!bucketName) {
      console.warn('⚠️ AWS S3 bucket name not configured. Image upload will be disabled.');
      return;
    }

    this.region = region;
    this.bucketName = bucketName;

    this.s3Client = new S3Client({
      region,
      credentials: {
        accessKeyId,
        secretAccessKey,
      },
    });

    console.log('✅ AWS S3 client initialized');
    console.log(`📦 Bucket: ${bucketName}`);
    console.log(`🌍 Region: ${region}`);
  }

  /**
   * Generate structured filename
   * Format: {type}-{id}-{slug}.{ext}
   */
  static generateFilename(
    type: 'product' | 'category',
    id: number,
    adminName?: string,
    entityName?: string
  ): string {
    // 1. Get slug (admin name or auto-generate from entity name)
    let slug: string;
    if (adminName && adminName.trim()) {
      slug = sanitizeSlug(adminName);
    } else if (entityName && entityName.trim()) {
      slug = generateSlug(entityName);
    } else {
      // Fallback: use timestamp
      slug = `image-${Date.now()}`;
    }

    // 2. Get file extension (will be provided when uploading)
    // For now, return without extension (will be added in upload method)
    return `${type}-${id}-${slug}`;
  }

  /**
   * Upload image to S3
   */
  static async uploadImage(
    file: Express.Multer.File,
    type: 'product' | 'category',
    id: number,
    adminName?: string,
    entityName?: string
  ): Promise<{ url: string; filename: string; path: string }> {
    if (!this.s3Client) {
      throw new Error('S3 client not initialized. Please configure AWS credentials.');
    }

    // Validate file type
    const allowedMimeTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
    if (!file.mimetype || !allowedMimeTypes.includes(file.mimetype)) {
      throw new Error('Invalid file type. Only JPG, PNG, and WebP are allowed.');
    }

    // Validate file size (max 5MB)
    const maxSize = 5 * 1024 * 1024; // 5MB
    if (file.size > maxSize) {
      throw new Error('File size exceeds 5MB limit.');
    }

    // Generate filename
    const baseFilename = this.generateFilename(type, id, adminName, entityName);
    const ext = getFileExtension(file.originalname);
    const filename = `${baseFilename}.${ext}`;
    // Proper pluralization: category -> categories, product -> products
    const folderName = type === 'category' ? 'categories' : 'products';
    const key = `${folderName}/${filename}`;

    // Upload to S3
    try {
      const command = new PutObjectCommand({
        Bucket: this.bucketName,
        Key: key,
        Body: file.buffer,
        ContentType: file.mimetype,
        // Note: ACL removed - bucket should use bucket policies for public access
        // If bucket has ACLs disabled (recommended), use bucket policy instead
      });

      await this.s3Client.send(command);

      // Construct public URL
      const url = `https://${this.bucketName}.s3.${this.region}.amazonaws.com/${key}`;

      console.log(`✅ Image uploaded to S3: ${key}`);
      console.log(`🔗 URL: ${url}`);

      return {
        url,
        filename,
        path: key,
      };
    } catch (error) {
      console.error('❌ Error uploading to S3:', error);
      throw new Error(
        `Failed to upload image to S3: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  }

  /**
   * Delete image from S3
   */
  static async deleteImage(key: string): Promise<void> {
    if (!this.s3Client) {
      throw new Error('S3 client not initialized.');
    }

    try {
      const command = new DeleteObjectCommand({
        Bucket: this.bucketName,
        Key: key,
      });

      await this.s3Client.send(command);
      console.log(`✅ Image deleted from S3: ${key}`);
    } catch (error) {
      console.error('❌ Error deleting from S3:', error);
      throw new Error(
        `Failed to delete image from S3: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  }

  /**
   * Extract S3 key from URL
   */
  static extractKeyFromUrl(url: string): string | null {
    try {
      // URL format: https://bucket-name.s3.region.amazonaws.com/products/filename.jpg
      const urlObj = new URL(url);
      const pathParts = urlObj.pathname.split('/').filter((p) => p);

      if (pathParts.length >= 2) {
        // Remove bucket name (first part), return rest
        return pathParts.slice(1).join('/');
      }

      return null;
    } catch (error) {
      console.error('Error extracting key from URL:', error);
      return null;
    }
  }

  static async uploadProfileImage(
  file: Express.Multer.File,
  userId: number
): Promise<{ url: string; filename: string; path: string }> {
  if (!this.s3Client) {
    throw new Error(
      'S3 client not initialized. Please configure AWS credentials.'
    );
  }

  const allowedMimeTypes = [
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  ];

  if (!file.mimetype || !allowedMimeTypes.includes(file.mimetype)) {
    throw new Error(
      'Invalid file type. Only JPG, PNG, and WebP are allowed.'
    );
  }

  const maxSize = 5 * 1024 * 1024;

  if (file.size > maxSize) {
    throw new Error('File size exceeds 5MB limit.');
  }

  const extension =
    file.mimetype === 'image/png'
      ? 'png'
      : file.mimetype === 'image/webp'
        ? 'webp'
        : 'jpg';

  const filename = `user-${userId}.${extension}`;

  const key = `profiles/${filename}`;

  const command = new PutObjectCommand({
    Bucket: this.bucketName,
    Key: key,
    Body: file.buffer,
    ContentType: file.mimetype,
  });

  await this.s3Client.send(command);

  const url =
    `https://${this.bucketName}.s3.${this.region}.amazonaws.com/${key}`;

  console.log(`Profile image uploaded to S3: ${key}`);

  return {
    url,
    filename,
    path: key,
  };
}
}

// Initialize on module load
S3Service.initialize();
