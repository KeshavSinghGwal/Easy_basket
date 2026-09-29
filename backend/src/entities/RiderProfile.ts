import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  OneToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { User } from './User';

export type RiderAvailability = 'offline' | 'idle' | 'busy';
export type RiderVehicleType = 'bicycle' | 'bike' | 'scooter' | 'car';

@Entity({ name: 'rider_profiles' })
export class RiderProfile {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id!: string;

  @OneToOne(() => User)
  @JoinColumn({ name: 'user_id' })
  user!: User;

  @Index('uniq_user_id', { unique: true })
  @Column({ name: 'user_id', type: 'int' })
  userId!: number;

  @Column({ type: 'enum', enum: ['offline', 'idle', 'busy'], default: 'offline' })
  availability!: RiderAvailability;

  @Column({
    name: 'vehicle_type',
    type: 'enum',
    enum: ['bicycle', 'bike', 'scooter', 'car'],
    default: 'bike',
  })
  vehicleType!: RiderVehicleType;

  @Column({ name: 'vehicle_number', type: 'varchar', length: 32, nullable: true })
  vehicleNumber!: string | null;

  @Column({ name: 'current_lat', type: 'decimal', precision: 10, scale: 7, nullable: true })
  currentLat!: string | null;

  @Column({ name: 'current_lng', type: 'decimal', precision: 10, scale: 7, nullable: true })
  currentLng!: string | null;

  @Column({ name: 'last_seen_at', type: 'datetime', precision: 3, nullable: true })
  lastSeenAt!: Date | null;

  @Column({ type: 'decimal', precision: 3, scale: 2, default: 5.0 })
  rating!: string;

  @Column({ name: 'total_deliveries', type: 'int', unsigned: true, default: 0 })
  totalDeliveries!: number;

  @Column({ name: 'total_cod_deliveries', type: 'int', unsigned: true, default: 0 })
  totalCodDeliveries!: number;

  @CreateDateColumn({ name: 'created_at', precision: 3 })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', precision: 3 })
  updatedAt!: Date;
}
