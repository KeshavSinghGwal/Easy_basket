import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { User } from './User';

/**
 * Immutable log of cash deposits made by a rider to the hub.
 * Appending a row is the ONLY way `rider_wallets.lifetime_deposited_paise` advances.
 * Idempotency: UNIQUE(rider_id, idempotency_key) so retried POSTs don't double-deposit.
 */
@Entity({ name: 'rider_cash_deposits' })
@Index('uniq_rider_idem', ['riderId', 'idempotencyKey'], { unique: true })
export class RiderCashDeposit {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id!: string;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'rider_id' })
  rider!: User;

  @Column({ name: 'rider_id', type: 'int' })
  riderId!: number;

  @ManyToOne(() => User)
  @JoinColumn({ name: 'admin_user_id' })
  admin!: User;

  @Column({ name: 'admin_user_id', type: 'int' })
  adminUserId!: number;

  @Column({ name: 'amount_paise', type: 'bigint', unsigned: true })
  amountPaise!: string;

  @Column({ type: 'varchar', length: 255, nullable: true })
  note!: string | null;

  @Column({ name: 'idempotency_key', type: 'char', length: 64 })
  idempotencyKey!: string;

  @CreateDateColumn({ name: 'created_at', precision: 3 })
  createdAt!: Date;
}
