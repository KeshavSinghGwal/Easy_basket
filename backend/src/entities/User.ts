import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  OneToMany,
} from 'typeorm';
import { Address } from './Address';
import { Order } from './Order';
import { UserRole } from '../constants/roles';

@Entity()
export class User {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ unique: true })
  phoneNumber!: string;

  @Column({ nullable: true })
  name!: string;

  @Column({ nullable: true })
  email!: string;

  @Column({ type: 'date', nullable: true })
  birthday!: Date | null;

  @Column({ default: 'customer' }) // customer, admin, delivery
  role!: UserRole;

  /** Full FCM device tokens are ~140–180 chars; avoid VARCHAR(255) truncation in MySQL. */
  @Column({ type: 'varchar', length: 512, nullable: true, charset: 'utf8mb4' })
  fcmToken!: string | null;

  @Column({ type: 'varchar', length: 1024, nullable: true })
  profileImageUrl!: string | null;

  @Column({ default: true })
  isActive!: boolean;

  @OneToMany(() => Address, (address) => address.user)
  addresses!: Address[];

  @OneToMany(() => Order, (order) => order.user)
  orders!: Order[];

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
