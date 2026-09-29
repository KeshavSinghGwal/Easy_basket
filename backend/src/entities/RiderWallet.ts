import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  OneToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
  VersionColumn,
} from 'typeorm';
import { User } from './User';

/**
 * One row per rider. Invariant (enforced by application logic):
 *   cash_in_hand_paise = lifetime_collected_paise - lifetime_deposited_paise
 *
 * cash_in_hand is signed (BIGINT) so corrections can briefly push negative.
 * The other lifetime counters are monotonically increasing.
 */
@Entity({ name: 'rider_wallets' })
export class RiderWallet {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id!: string;

  @OneToOne(() => User)
  @JoinColumn({ name: 'rider_id' })
  rider!: User;

  @Index('uniq_rider_id', { unique: true })
  @Column({ name: 'rider_id', type: 'int' })
  riderId!: number;

  @Column({ name: 'cash_in_hand_paise', type: 'bigint', default: 0 })
  cashInHandPaise!: string;

  @Column({ name: 'lifetime_collected_paise', type: 'bigint', unsigned: true, default: 0 })
  lifetimeCollectedPaise!: string;

  @Column({ name: 'lifetime_deposited_paise', type: 'bigint', unsigned: true, default: 0 })
  lifetimeDepositedPaise!: string;

  @Column({ name: 'pending_earnings_paise', type: 'bigint', unsigned: true, default: 0 })
  pendingEarningsPaise!: string;

  @VersionColumn()
  version!: number;

  @CreateDateColumn({ name: 'created_at', precision: 3 })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', precision: 3 })
  updatedAt!: Date;
}
