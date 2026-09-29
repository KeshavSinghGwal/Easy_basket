import { EntityManager } from 'typeorm';
import { AppDataSource } from '../config/database';
import { OrderEvent, OrderEventActorRole } from '../entities/OrderEvent';

/**
 * Audit-log writer. One row per state transition or notable action.
 *
 * All state-changing services MUST call `log(...)` in the same transaction as the
 * actual state write, so we never have a state change without a corresponding event
 * (or vice versa).
 *
 * Passing an `EntityManager` from a transaction scope keeps the write atomic with
 * the caller's work. Passing nothing writes via the default data source (fine for
 * fire-and-forget events like availability ping).
 */
export class OrderEventsService {
  static async log(
    params: {
      orderId: number;
      actorUserId: number | null;
      actorRole: OrderEventActorRole;
      eventType: string;
      fromState?: string | null;
      toState?: string | null;
      payload?: unknown;
    },
    em?: EntityManager
  ): Promise<OrderEvent> {
    const repo = (em ?? AppDataSource.manager).getRepository(OrderEvent);
    const row = repo.create({
      orderId: params.orderId,
      actorUserId: params.actorUserId,
      actorRole: params.actorRole,
      eventType: params.eventType,
      fromState: params.fromState ?? null,
      toState: params.toState ?? null,
      payload: params.payload ?? null,
    });
    return repo.save(row);
  }

  /** Chronological event list for an order (used by the admin audit-trail endpoint). */
  static async listForOrder(orderId: number): Promise<OrderEvent[]> {
    return AppDataSource.getRepository(OrderEvent).find({
      where: { orderId },
      order: { id: 'ASC' },
    });
  }
}
