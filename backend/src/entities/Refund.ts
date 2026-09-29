import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import { Payment } from './Payment';

export type RefundStatus = 'pending' | 'processed' | 'failed';

@Entity({ name: 'refunds' })
@Index('uniq_payment_idem', ['paymentId', 'idempotencyKey'], { unique: true })
@Index('idx_refund_retry', ['status', 'nextRetryAt'])
export class Refund {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id!: string;

  @ManyToOne(() => Payment)
  @JoinColumn({ name: 'payment_id' })
  payment!: Payment;

  @Column({ name: 'payment_id', type: 'bigint', unsigned: true })
  paymentId!: string;

  @Column({ name: 'user_id', type: 'int' })
  userId!: number;

  @Index('uniq_rzp_refund', { unique: true })
  @Column({ name: 'razorpay_refund_id', type: 'varchar', length: 64, nullable: true })
  razorpayRefundId!: string | null;

  @Column({ name: 'amount_paise', type: 'bigint', unsigned: true })
  amountPaise!: string;

  @Column({ type: 'enum', enum: ['pending', 'processed', 'failed'], default: 'pending' })
  status!: RefundStatus;

  @Column({ type: 'varchar', length: 255, nullable: true })
  reason!: string | null;

  @Column({ name: 'idempotency_key', type: 'char', length: 64 })
  idempotencyKey!: string;

  /**
   * Number of times we have actually POSTed this refund to Razorpay.
   * Only a real API call increments it — a retry job that could not acquire the
   * payment lock reschedules itself without burning an attempt.
   */
  @Column({ name: 'attempt_count', type: 'int', unsigned: true, default: 0 })
  attemptCount!: number;

  /** Short reason for the most recent failure. Surfaced to admin in the UI. */
  @Column({ name: 'last_error', type: 'varchar', length: 255, nullable: true })
  lastError!: string | null;

  /** When the automatic retry is due. NULL once retries are exhausted or done. */
  @Column({ name: 'next_retry_at', type: 'datetime', precision: 3, nullable: true })
  nextRetryAt!: Date | null;

  @Column({ name: 'last_attempt_at', type: 'datetime', precision: 3, nullable: true })
  lastAttemptAt!: Date | null;

  @CreateDateColumn({ name: 'created_at', precision: 3 })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', precision: 3 })
  updatedAt!: Date;
}
