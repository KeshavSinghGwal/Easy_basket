import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  OneToMany,
} from 'typeorm';
import { User } from './User';
import { Address } from './Address';
import { OrderItem } from './OrderItem';
import { PaymentMethod } from '../constants/payment-method';

@Entity({ name: 'orders' })
export class Order {
  @PrimaryGeneratedColumn()
  id!: number;

  @ManyToOne(() => User, (user) => user.orders)
  user!: User;

  @ManyToOne(() => Address)
  deliveryAddress!: Address;

  @ManyToOne(() => User, { nullable: true })
  deliveryBoy!: User; // Assigned delivery person

  @OneToMany(() => OrderItem, (orderItem) => orderItem.order, { cascade: true })
  items!: OrderItem[];

  @Column('decimal', { precision: 10, scale: 2 })
  totalAmount!: number;

  @Column({ default: 'pending' }) // pending, accepted, preparing, out_for_delivery, delivered, cancelled
  status!: string;

  @Column({
    name: 'payment_status',
    type: 'enum',
    enum: ['initiated', 'success_unverified', 'paid', 'failed', 'refund_pending', 'refunded'],
    nullable: true,
  })
  paymentStatus!:
    | 'initiated'
    | 'success_unverified'
    | 'paid'
    | 'failed'
    | 'refund_pending'
    | 'refunded'
    | null;

  @Column({ name: 'idempotency_key', type: 'char', length: 64, nullable: true })
  idempotencyKey!: string | null;

  @Column({
    name: 'delivery_status',
    type: 'enum',
    enum: [
      'unassigned',
      'assigned',
      'at_store',
      'picked',
      'out_for_delivery',
      'arrived',
      'payment_pending',
      'delivered',
      'rto_pending',
      'rto_completed',
    ],
    nullable: true,
  })
  deliveryStatus!:
    | 'unassigned'
    | 'assigned'
    | 'at_store'
    | 'picked'
    | 'out_for_delivery'
    | 'arrived'
    | 'payment_pending'
    | 'delivered'
    | 'rto_pending'
    | 'rto_completed'
    | null;

  @Column({ name: 'delivery_assigned_at', type: 'datetime', precision: 3, nullable: true })
  deliveryAssignedAt!: Date | null;

  @Column({ name: 'delivery_picked_at', type: 'datetime', precision: 3, nullable: true })
  deliveryPickedAt!: Date | null;

  @Column({ name: 'delivery_arrived_at', type: 'datetime', precision: 3, nullable: true })
  deliveryArrivedAt!: Date | null;

  @Column({ name: 'delivery_completed_at', type: 'datetime', precision: 3, nullable: true })
  deliveryCompletedAt!: Date | null;

  @Column({ name: 'cash_collected_paise', type: 'bigint', unsigned: true, nullable: true })
  cashCollectedPaise!: string | null;

  @Column({ name: 'delivery_attempts', type: 'tinyint', unsigned: true, default: 0 })
  deliveryAttempts!: number;

  @Column({ name: 'delivery_otp_hash', type: 'char', length: 64, nullable: true })
  deliveryOtpHash!: string | null;

  @Column({ type: 'varchar', length: 16, nullable: true })
  paymentMethod!: PaymentMethod | null;

  @Column({ nullable: true })
  paymentId!: string; // Razorpay/Cashfree payment ID

  @Column({ default: false })
  isPaid!: boolean;

  // Customer cancellation/refund request (pre-'preparing' only). 'requested' =
  // awaiting admin decision; admin approve → order cancelled + refund; reject →
  // 'rejected', order stays active. After 'preparing', customers cancel directly
  // with no refund (no request needed).
  @Column({
    name: 'cancel_request_status',
    type: 'enum',
    enum: ['none', 'requested', 'rejected'],
    default: 'none',
  })
  cancelRequestStatus!: 'none' | 'requested' | 'rejected';

  @Column({ name: 'cancellation_reason', type: 'varchar', length: 255, nullable: true })
  cancellationReason!: string | null;

  @Column({ name: 'cancellation_requested_at', type: 'datetime', precision: 3, nullable: true })
  cancellationRequestedAt!: Date | null;

  @Column({ nullable: true })
  notes!: string;

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
