import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
  Index,
  VersionColumn,
} from 'typeorm';
import { Order } from './Order';

export type PaymentStatus =
  | 'initiated'
  | 'success_unverified'
  | 'paid'
  | 'failed'
  | 'refund_pending'
  | 'refunded';

@Entity({ name: 'payments' })
export class Payment {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id!: string;

  @ManyToOne(() => Order)
  @JoinColumn({ name: 'order_id' })
  order!: Order;

  @Column({ name: 'order_id', type: 'int' })
  orderId!: number;

  @Index('idx_payment_user_status')
  @Column({ name: 'user_id', type: 'int' })
  userId!: number;

  @Index('uniq_rzp_order', { unique: true })
  @Column({ name: 'razorpay_order_id', type: 'varchar', length: 64 })
  razorpayOrderId!: string;

  @Index('uniq_rzp_payment', { unique: true })
  @Column({ name: 'razorpay_payment_id', type: 'varchar', length: 64, nullable: true })
  razorpayPaymentId!: string | null;

  @Column({ name: 'amount_paise', type: 'bigint', unsigned: true })
  amountPaise!: string;

  @Column({ type: 'char', length: 3, default: 'INR' })
  currency!: string;

  @Column({
    type: 'enum',
    enum: ['initiated', 'success_unverified', 'paid', 'failed', 'refund_pending', 'refunded'],
    default: 'initiated',
  })
  status!: PaymentStatus;

  @Column({ name: 'failure_code', type: 'varchar', length: 64, nullable: true })
  failureCode!: string | null;

  @Column({ name: 'raw_webhook_json', type: 'json', nullable: true })
  rawWebhookJson!: unknown;

  @VersionColumn()
  version!: number;

  @CreateDateColumn({ name: 'created_at', precision: 3 })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', precision: 3 })
  updatedAt!: Date;
}
