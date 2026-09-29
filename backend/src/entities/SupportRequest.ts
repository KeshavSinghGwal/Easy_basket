import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';
import { User } from './User';
import { Order } from './Order';

@Entity()
export class SupportRequest {
  @PrimaryGeneratedColumn()
  id!: number;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  user!: User;

  @ManyToOne(() => Order, { nullable: true, onDelete: 'SET NULL' })
  order!: Order | null;

  @Column()
  category!: string;

  @Column({ type: 'text' })
  description!: string;

  @Column({ default: 'open' })
  status!: string;

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}