import { EntityManager } from 'typeorm';
import { AppDataSource } from '../config/database';
import { OrderItem } from '../entities/OrderItem';
import { Product } from '../entities/Product';
import { ProductVariant } from '../entities/ProductVariant';
import { ProductController } from '../controllers/product.controller';

/**
 * Mirrors create-order stock deduction: restore variant stock when a line has a variant,
 * otherwise restore base product stock.
 *
 * Pass `manager` to enlist the stock writes in a caller's transaction (e.g. the payment
 * state machine) so the restore commits atomically with the order/payment transition.
 */
export class OrderInventoryService {
  static async restoreReservedStockForItems(
    items: OrderItem[],
    manager?: EntityManager
  ): Promise<void> {
    const db = manager ?? AppDataSource.manager;
    const productRepository = db.getRepository(Product);
    const variantRepository = db.getRepository(ProductVariant);

    // Atomic increments (SET stock = stock + qty) instead of read-modify-write —
    // two concurrent restores can't lose each other's update. (Callers still guard
    // against double-INVOCATION via an atomic status claim before calling this.)
    for (const line of items) {
      const qty = Number(line.quantity);
      if (!Number.isFinite(qty) || qty <= 0) continue;
      if (line.variant?.id != null) {
        await variantRepository.increment({ id: line.variant.id }, 'stock', qty);
      } else if (line.product?.id != null) {
        await productRepository.increment({ id: line.product.id }, 'stock', qty);
      }
    }

    // No cache invalidation. Restoring stock is the mirror of reserving it, and
    // for the same reason as in OrderController.createOrder there is nothing to
    // invalidate: the search cache holds IDs, not stock values, and every hit
    // re-reads the rows. This path runs from the auto-cancel sweep, which can
    // process a batch of orders in one tick — a keyspace sweep per order was
    // pure waste.
  }
}
