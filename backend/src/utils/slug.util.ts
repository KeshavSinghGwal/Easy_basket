/**
 * Utility functions for generating and sanitizing slugs
 */

/**
 * Generate a slug from a string (e.g., product name)
 * Converts to lowercase, replaces spaces with hyphens, removes special chars
 */
export function generateSlug(input: string): string {
  if (!input || typeof input !== 'string') {
    return '';
  }

  return input
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9\s-]/g, '') // Remove special characters (keep spaces and hyphens)
    .replace(/\s+/g, '-') // Replace spaces with hyphens
    .replace(/-+/g, '-') // Replace multiple hyphens with single hyphen
    .replace(/^-|-$/g, '') // Remove leading/trailing hyphens
    .substring(0, 50); // Limit to 50 characters
}

/**
 * Sanitize a slug (for admin-provided names)
 * More strict - removes all special chars except hyphens
 */
export function sanitizeSlug(input: string): string {
  if (!input || typeof input !== 'string') {
    return '';
  }

  return input
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9-]/g, '-') // Replace special chars with hyphens
    .replace(/-+/g, '-') // Replace multiple hyphens with single hyphen
    .replace(/^-|-$/g, '') // Remove leading/trailing hyphens
    .substring(0, 50); // Limit to 50 characters
}

/**
 * Get file extension from filename
 */
export function getFileExtension(filename: string): string {
  const parts = filename.split('.');
  if (parts.length < 2) {
    return 'jpg'; // Default to jpg
  }
  const ext = parts[parts.length - 1].toLowerCase();
  // Only allow image extensions
  const allowedExts = ['jpg', 'jpeg', 'png', 'webp'];
  return allowedExts.includes(ext) ? ext : 'jpg';
}
