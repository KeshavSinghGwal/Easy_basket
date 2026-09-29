import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';

@Entity()
@Index(['pincode', 'country'], { unique: true }) // Ensure unique pincode per country
export class ServiceArea {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column()
  pincode!: string; // 6-digit pincode (for India) or postal code

  @Column()
  city!: string;

  @Column()
  state!: string;

  @Column({ default: 'India' })
  country!: string; // Default to India, but support other countries

  @Column({ default: true })
  isActive!: boolean; // Can temporarily disable a service area

  @Column({ nullable: true })
  notes!: string; // Optional notes about the service area

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
