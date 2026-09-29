import { createHash } from 'crypto';
import { Request, Response } from 'express';

import { AppDataSource } from '../config/database';
import { Category } from '../entities/Category';
import { Product } from '../entities/Product';
import { RedisService } from '../services/redis.service';
import { mapProductPublic, normalizeMediaForStorage, publicMediaUrl } from '../utils/media-url.util';

import { Brackets, In } from 'typeorm';

// ---------------------------------------------------------------------------
// Search cache configuration
// ---------------------------------------------------------------------------
// Two parallel caches (each keyed by normalized query):
//   cache:search:suggest:v1:{lang}:{q}                                 → autocomplete rows
//   cache:search:results:v1:{lang}:{q}:{categoryId}:{page}:{limit}     → product IDs only
//
// We cache IDs (not full objects) for the results endpoint so product rows
// stay fresh — price/stock/name edits never go stale by more than one DB read.
//
// Popularity: every /api/products search does ZINCRBY search:count. We only
// write to the results cache when the query's reverse rank is < TOP_CACHE_N
// so long-tail (one-off) queries don't bloat Redis.
// ---------------------------------------------------------------------------

const SUGGEST_CACHE_PREFIX = 'cache:search:suggest:v1:';
const RESULTS_CACHE_PREFIX = 'cache:search:results:v1:';
const SEARCH_CACHE_PATTERN_ALL = 'cache:search:*';
const SEARCH_CACHE_TTL_SEC = 600; // 10 minutes

const SEARCH_POPULARITY_KEY = 'search:count';
const TOP_CACHE_N = 100; // only cache results for the top 100 queries

// Public catalogue listing is always bounded — see getAllProducts.
const DEFAULT_PRODUCT_LIMIT = 50;
const MAX_PRODUCT_LIMIT = 100;

// Legacy prefix — kept so existing invalidation helpers still wipe it.
const PRODUCT_LIST_CACHE_PATTERN = 'cache:products:list:*';

// Language hash — placeholder for future multi-language search. Our catalogue
// is mono-lingual today so we freeze a single value at module load time.
const LANG_HASH = createHash('sha256').update('en').digest('hex').slice(0, 6);

/** Canonicalize a search string so two equivalent queries collapse onto one key. */
function normalizeQuery(raw: unknown): string {
  if (raw == null) return '';
  return String(raw).trim().toLowerCase().replace(/\s+/g, ' ');
}

function suggestCacheKey(query: string): string {
  return `${SUGGEST_CACHE_PREFIX}${LANG_HASH}:${query}`;
}

function resultsCacheKey(parts: {
  query: string;
  categoryId: string;
  page: string;
  limit: string;
}): string {
  return `${RESULTS_CACHE_PREFIX}${LANG_HASH}:${parts.query}:${parts.categoryId}:${parts.page}:${parts.limit}`;
}

/**
 * Fetch products by IDs in one DB round-trip and return them in the exact order
 * of `ids` (TypeORM's `In(...)` doesn't preserve input order). Variants are also
 * sorted by displayOrder to match the shape `getAllProducts` produces on a miss.
 */
async function hydrateProductsInOrder(ids: number[]): Promise<unknown[]> {
  if (ids.length === 0) return [];
  const productRepository = AppDataSource.getRepository(Product);
  const products = await productRepository.find({
    where: { id: In(ids), isAvailable: true },
    relations: ['category', 'variants'],
  });
  const byId = new Map(products.map((p) => [p.id, p]));
  const ordered: Product[] = [];
  for (const id of ids) {
    const p = byId.get(id);
    if (p) ordered.push(p);
  }
  ordered.forEach((product) => {
    if (product.variants) {
      product.variants.sort((a, b) => {
        if (a.displayOrder !== b.displayOrder) return a.displayOrder - b.displayOrder;
        return a.quantity - b.quantity;
      });
    }
  });
  return ordered.map(mapProductPublic);
}

export class ProductController {
  /**
   * Wipe every product-flavored cache entry on any product/variant/stock change.
   * Covers:
   *   - legacy list cache (`cache:products:list:*`)
   *   - new search-results cache (`cache:search:results:*`)
   *   - autocomplete cache (`cache:search:suggest:*`)
   *
   * The `search:count` sorted set is NOT touched — it's popularity, not stale data.
   */
  static async invalidateProductListCache(): Promise<void> {
    try {
      const [legacy, search] = await Promise.all([
        RedisService.deleteKeysMatching(PRODUCT_LIST_CACHE_PATTERN),
        RedisService.deleteKeysMatching(SEARCH_CACHE_PATTERN_ALL),
      ]);
      const n = legacy + search;
      if (n > 0) {
        console.log(`🗑️ Product cache invalidated (${legacy} list + ${search} search)`);
      }
    } catch (e) {
      console.warn('Product list cache invalidation failed:', e);
    }
  }

  static async getSuggestions(req: Request, res: Response): Promise<void> {
    try {
      const query = normalizeQuery(req.query.search);

      if (query.length < 2) {
        res.json([]);
        return;
      }

      // 1) Cache lookup — cheap string+image payload, safe to cache whole since it's
      //    tiny (max 8 rows) and we only need dropdown display.
      const cacheKey = suggestCacheKey(query);
      try {
        const cached = await RedisService.getJson<Array<{ name: string; imageUrl: string | null }>>(
          cacheKey
        );
        if (cached) {
          res.json(cached.map((s, index) => ({ id: index, name: s.name, imageUrl: s.imageUrl })));
          return;
        }
      } catch {
        // Redis hiccup — fall through to DB
      }

      // 2) DB query — unchanged (MATCH AGAINST + LIKE fallback, grouped by name)
      const productRepository = AppDataSource.getRepository(Product);
      const searchTerms = query
        .split(/\s+/)
        .map((term) => (term.length <= 2 ? `${term}*` : `+${term}*`))
        .join(' ');

      const suggestions = await productRepository
        .createQueryBuilder('product')
        .select('product.name', 'name')
        .addSelect('MAX(product.imageUrl)', 'imageUrl')
        .where('product.isAvailable = :isAvailable', { isAvailable: true })
        .andWhere(
          new Brackets((qb) => {
            qb.where(
              `MATCH(product.name, product.tags, product.description) AGAINST(:search IN BOOLEAN MODE)`,
              { search: searchTerms }
            ).orWhere('product.name LIKE :likeSearch', { likeSearch: `%${query}%` });
          })
        )
        .groupBy('product.name')
        .limit(8)
        .getRawMany<{ name: string; imageUrl: string | null }>();

      // 3) Cache the raw (name, imageUrl) tuples — we resolve the public URL on the
      //    response side so cached entries stay valid across S3 bucket renames.
      try {
        await RedisService.setJson(cacheKey, suggestions, SEARCH_CACHE_TTL_SEC);
      } catch (e) {
        console.warn('Suggest cache set failed:', e);
      }

      res.json(
        suggestions.map((s, index) => ({
          id: index,
          name: s.name,
          imageUrl: publicMediaUrl(s.imageUrl),
        }))
      );
    } catch (error) {
      console.error('Error fetching suggestions:', error);
      res.status(500).json({ message: 'Error fetching suggestions' });
    }
  }

  static async getAllProducts(req: Request, res: Response): Promise<void> {
    try {
      const { categoryId, limit, page } = req.query;
      const query = normalizeQuery(req.query.search);

      const catKey = categoryId ? String(Number(categoryId)) : '_';

      // Always paginate. This used to resolve to `undefined` when neither a limit
      // nor a search term was supplied, and the `if (takeLimit)` guard below then
      // skipped take/skip entirely — so an unauthenticated GET /api/products
      // returned the ENTIRE catalogue, with category and variant joins, on a route
      // with no rate limit. The mobile client always sends a limit, which is the
      // only reason this never surfaced.
      //
      // Same clamp getUserOrders already applies to its own limit.
      const parsedLimit = limit != null ? parseInt(String(limit), 10) : NaN;
      const takeLimit = Number.isFinite(parsedLimit)
        ? Math.min(Math.max(parsedLimit, 1), MAX_PRODUCT_LIMIT)
        : DEFAULT_PRODUCT_LIMIT;
      const parsedPage = page != null ? parseInt(String(page), 10) : NaN;
      const pageNum = Number.isFinite(parsedPage) ? Math.max(1, parsedPage) : 1;
      const limKey = String(takeLimit);

      // ----------------------------------------------------------------
      // Popularity + cache flow (only when we actually have a search query)
      // ----------------------------------------------------------------
      const cacheable = query.length >= 2;
      const cacheKey = cacheable
        ? resultsCacheKey({ query, categoryId: catKey, page: String(pageNum), limit: limKey })
        : null;

      // 1) Track popularity — every request, even cache hits.
      if (cacheable) {
        try {
          await RedisService.zIncrBy(SEARCH_POPULARITY_KEY, 1, query);
        } catch (e) {
          console.warn('Popularity increment failed:', e);
        }
      }

      // 2) Cache lookup — IDs only. We re-fetch full product rows on hit so prices
      //    and stock never go stale by more than one DB read.
      if (cacheKey) {
        try {
          const cachedIds = await RedisService.getJson<number[]>(cacheKey);
          if (cachedIds && cachedIds.length > 0) {
            const hydrated = await hydrateProductsInOrder(cachedIds);
            res.json(hydrated);
            return;
          }
          if (cachedIds && cachedIds.length === 0) {
            // Cached empty result — legit "no matches".
            res.json([]);
            return;
          }
        } catch {
          // Redis hiccup — fall through to DB
        }
      }

      // ----------------------------------------------------------------
      // 3) DB query — unchanged logic
      // ----------------------------------------------------------------
      const productRepository = AppDataSource.getRepository(Product);
      const queryBuilder = productRepository
        .createQueryBuilder('product')
        .select([
          'product.id',
          'product.name',
          'product.price',
          'product.imageUrl',
          'product.stock',
          'product.unit',
          'product.isAvailable',
          'product.hasVariants',
          'product.baseUnit',
          'product.minQuantity',
          'product.maxQuantity',
          'product.categoryId',
          'product.tags',
        ])
        .leftJoinAndSelect('product.category', 'category')
        .leftJoinAndSelect('product.variants', 'variants')
        .where('product.isAvailable = :isAvailable', { isAvailable: true });

      if (categoryId) {
        queryBuilder.andWhere('product.categoryId = :categoryId', { categoryId });
      }

      if (query) {
        const searchTerms = query
          .split(/\s+/)
          .map((term) => (term.length <= 2 ? `${term}*` : `+${term}*`))
          .join(' ');
        queryBuilder.andWhere(
          new Brackets((qb) => {
            qb.where(
              `MATCH(product.name, product.tags, product.description) AGAINST(:search IN BOOLEAN MODE)`,
              { search: searchTerms }
            ).orWhere('product.name LIKE :likeSearch', { likeSearch: `%${query}%` });
          })
        );
      }

      // Unconditional now — takeLimit is always a bounded number.
      queryBuilder.take(takeLimit);
      queryBuilder.skip((pageNum - 1) * takeLimit);

      const products = await queryBuilder.getMany();

      products.forEach((product) => {
        if (product.variants) {
          product.variants.sort((a, b) => {
            if (a.displayOrder !== b.displayOrder) {
              return a.displayOrder - b.displayOrder;
            }
            return a.quantity - b.quantity;
          });
        }
      });

      const publicProducts = products.map(mapProductPublic);

      // ----------------------------------------------------------------
      // 4) Popularity-gated cache write — only top-N queries get cached
      //    so the tail (one-off unique queries) can't bloat Redis.
      // ----------------------------------------------------------------
      if (cacheKey) {
        try {
          const rank = await RedisService.zRevRank(SEARCH_POPULARITY_KEY, query);
          if (rank !== null && rank < TOP_CACHE_N) {
            const ids = products.map((p) => p.id);
            await RedisService.setJson(cacheKey, ids, SEARCH_CACHE_TTL_SEC);
          }
        } catch (e) {
          console.warn('Results cache set failed:', e);
        }
      }

      res.json(publicProducts);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching products' });
    }
  }

  static async getProductById(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const productRepository = AppDataSource.getRepository(Product);
      const product = await productRepository.findOne({
        where: { id: Number(id) },
        relations: ['category', 'variants'],
      });

      if (!product) {
        res.status(404).json({ message: 'Product not found' });
        return;
      }

      // Sort variants by displayOrder
      if (product.variants) {
        product.variants.sort((a, b) => {
          if (a.displayOrder !== b.displayOrder) {
            return a.displayOrder - b.displayOrder;
          }
          return a.quantity - b.quantity;
        });
      }

      res.json(mapProductPublic(product));
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching product' });
    }
  }

  static async createProduct(req: Request, res: Response): Promise<void> {
    try {
      const { name, description, price, imageUrl, categoryId, stock, unit, tags } = req.body;

      if (!name || !price || !categoryId) {
        res.status(400).json({ message: 'Name, price, and category are required' });
        return;
      }

      const categoryRepository = AppDataSource.getRepository(Category);
      const category = await categoryRepository.findOneBy({ id: categoryId });

      if (!category) {
        res.status(404).json({ message: 'Category not found' });
        return;
      }

      const productRepository = AppDataSource.getRepository(Product);
      const product = productRepository.create({
        name,
        description,
        price,
        imageUrl: normalizeMediaForStorage(imageUrl),
        category,
        stock: stock || 0,
        unit: unit || 'piece',
        tags,
      });

      await productRepository.save(product);
      await ProductController.invalidateProductListCache();
      res.status(201).json(mapProductPublic(product));
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error creating product' });
    }
  }

  static async updateProduct(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const productRepository = AppDataSource.getRepository(Product);
      const product = await productRepository.findOneBy({ id: Number(id) });

      if (!product) {
        res.status(404).json({ message: 'Product not found' });
        return;
      }

      const { name, description, price, imageUrl, categoryId, stock, unit, isAvailable, tags } =
        req.body;

      if (name) product.name = name;
      if (description !== undefined) product.description = description;
      if (price) product.price = price;
      if (imageUrl !== undefined)
        product.imageUrl = normalizeMediaForStorage(imageUrl) ?? '';
      if (stock !== undefined) product.stock = stock;
      if (unit) product.unit = unit;
      if (isAvailable !== undefined) product.isAvailable = isAvailable;
      if (tags !== undefined) product.tags = tags;

      if (categoryId) {
        const categoryRepository = AppDataSource.getRepository(Category);
        const category = await categoryRepository.findOneBy({ id: categoryId });
        if (category) {
          product.category = category;
        }
      }

      await productRepository.save(product);
      await ProductController.invalidateProductListCache();
      res.json(mapProductPublic(product));
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error updating product' });
    }
  }

  static async deleteProduct(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const productRepository = AppDataSource.getRepository(Product);
      const product = await productRepository.findOneBy({ id: Number(id) });

      if (!product) {
        res.status(404).json({ message: 'Product not found' });
        return;
      }

      await productRepository.remove(product);
      await ProductController.invalidateProductListCache();
      res.json({ message: 'Product deleted successfully' });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error deleting product' });
    }
  }
}
