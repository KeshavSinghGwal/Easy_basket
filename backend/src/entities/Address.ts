import {
  Column,
  CreateDateColumn,
  Entity,
  ManyToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

import { User } from './User';

@Entity()
export class Address {
  @PrimaryGeneratedColumn()
  id!: number;

  @ManyToOne(() => User, (user) => user.addresses)
  user!: User;

  @Column()
  addressLine1!: string;

  @Column({ nullable: true })
  addressLine2!: string;

  @Column()
  city!: string;

  @Column()
  state!: string;

  @Column()
  pincode!: string;

  @Column({ nullable: true })
  landmark!: string;

  @Column({ default: false })
  isDefault!: boolean;

  @Column({ nullable: true })
  latitude!: string;

  @Column({ nullable: true })
  longitude!: string;

  @Column({ nullable: true })
  tag!: string; // home, office, other, etc.

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
