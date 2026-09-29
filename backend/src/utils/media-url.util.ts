import { Campaign } from '../entities/Campaign';
import { Category } from '../entities/Category';
import { Order } from '../entities/Order';
import { Product } from '../entities/Product';

/**
 * Public base URL for media (S3 website URL, CloudFront, or any CDN).
 * Stored DB values should be object keys only, e.g. `products/foo.jpg`.
 *
 * @example PUBLIC_MEDIA_BASE_URL=https://my-bucket.s3.ap-south-1.amazonaws.com
 * @example PUBLIC_MEDIA_BASE_URL=https://d111111abcdef8.cloudfront.net
 */
export function getPublicMediaBaseUrl(): string {
  return (process.env.PUBLIC_MEDIA_BASE_URL || process.env.MEDIA_PUBLIC_BASE_URL || '')
    .trim()
    .replace(/\/+$/, '');
}

/**
 * Extract storage path from a full URL or return a normalized path string.
 */
export function extractMediaPath(stored: string): string | null {
  const trimmed = stored.trim();
  if (!trimmed) return null;
  if (/^https?:\/\//i.test(trimmed)) {
    try {
      const u = new URL(trimmed);
      const p = u.pathname.replace(/^\/+/, '');
      return p || null;
    } catch {
      return trimmed;
    }
  }
  return trimmed.replace(/^\/+/, '');
}

/**
 * Persist path-only keys. Strips scheme/host from legacy full S3/CDN URLs.
 */
export function normalizeMediaForStorage(value: unknown): string | undefined {
  if (value === undefined || value === null) return undefined;
  const s = String(value).trim();
  if (!s) return undefined;
  const path = extractMediaPath(s);
  return path ?? undefined;
}

/**
 * Absolute URL for clients. Uses `PUBLIC_MEDIA_BASE_URL` + path.
 * If base is unset, returns legacy full URLs unchanged; path-only values are returned as-is (set base in production).
 */
export function publicMediaUrl(stored: string | null | undefined): string | null {
  if (stored == null) return null;
  const raw = String(stored).trim();
  if (!raw) return null;

  const base = getPublicMediaBaseUrl();
  const pathOnly = extractMediaPath(raw);
  if (!pathOnly) return null;

  if (!base) {
    if (/^https?:\/\//i.test(raw)) return raw;
    return pathOnly;
  }

  return `${base}/${pathOnly}`;
}

export function mapProductPublic(p: Product): Product {
  const o = { ...p };
  o.imageUrl = publicMediaUrl(p.imageUrl) ?? '';
  if (p.category) {
    o.category = {
      ...p.category,
      imageUrl: publicMediaUrl(p.category.imageUrl) ?? '',
    } as Category;
  }
  return o;
}

export function mapCategoryPublic(c: Category): Category {
  const o = { ...c } as Category;
  o.imageUrl = publicMediaUrl(c.imageUrl) ?? '';
  if (c.subcategories?.length) {
    o.subcategories = c.subcategories.map(mapCategoryPublic);
  }
  if (c.parentCategory) {
    o.parentCategory = {
      ...c.parentCategory,
      imageUrl: publicMediaUrl(c.parentCategory.imageUrl) ?? '',
    } as Category;
  }
  if (c.products?.length) {
    o.products = c.products.map(mapProductPublic);
  }
  return o;
}

export function mapCampaignPublic(c: Campaign): Campaign {
  const o = { ...c };
  o.imageUrl = publicMediaUrl(c.imageUrl);
  return o;
}

export function mapOrderPublic(order: Order): Order {
  const o = { ...order };
  if (o.items?.length) {
    o.items = o.items.map((item) => ({
      ...item,
      product: item.product ? mapProductPublic(item.product) : item.product,
    })) as typeof o.items;
  }
  return o;
}
