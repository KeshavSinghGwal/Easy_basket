import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { Order } from './Order';

export type OrderEventActorRole = 'customer' | 'admin' | 'delivery' | 'system';

/**
 * Append-only audit trail. One row per state transition or notable action.
 * Reads rarely, writes on every state change — partition by created_at if volume grows.
 */
@Entity({ name: 'order_events' })
@Index('idx_order_time', ['orderId', 'createdAt'])
@Index('idx_event_type', ['eventType', 'createdAt'])
export class OrderEvent {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id!: string;

  @ManyToOne(() => Order)
  @JoinColumn({ name: 'order_id' })
  order!: Order;

  @Column({ name: 'order_id', type: 'int' })
  orderId!: number;

  @Column({ name: 'actor_user_id', type: 'int', nullable: true })
  actorUserId!: number | null;

  @Column({
    name: 'actor_role',
    type: 'enum',
    enum: ['customer', 'admin', 'delivery', 'system'],
  })
  actorRole!: OrderEventActorRole;

  @Column({ name: 'event_type', type: 'varchar', length: 64 })
  eventType!: string;

  @Column({ name: 'from_state', type: 'varchar', length: 32, nullable: true })
  fromState!: string | null;

  @Column({ name: 'to_state', type: 'varchar', length: 32, nullable: true })
  toState!: string | null;

  @Column({ type: 'json', nullable: true })
  payload!: unknown;

  @CreateDateColumn({ name: 'created_at', precision: 3 })
  createdAt!: Date;
}
