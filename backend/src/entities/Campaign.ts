import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
} from 'typeorm';
import { User } from './User';

/**
 * Campaign — Promo banners, offers, announcements
 *
 * Single table handles: hero banners, category strips, product spotlights, bottom banners
 * Targeting: by pincode array (empty = global/all users)
 * Scheduling: starts_at → expires_at (auto-expire)
 * Push: optional FCM topic-based push notification
 */
@Entity({ name: 'campaigns' })
export class Campaign {
  @PrimaryGeneratedColumn()
  id!: number;

  // ── Content ──
  @Column({ type: 'varchar', length: 255 })
  title!: string;

  @Column({ type: 'varchar', length: 500, nullable: true })
  subtitle!: string | null;

  @Column({ type: 'varchar', length: 500, nullable: true })
  imageUrl!: string | null;

  @Column({ type: 'varchar', length: 100, nullable: true, default: 'Shop Now' })
  ctaText!: string | null;

  @Column({ type: 'varchar', length: 255, nullable: true })
  ctaLink!: string | null; // deep link: "/category/5", "/product/42"

  // ── Targeting ──
  // JSON array of pincodes: ["243003", "243005"]
  // Empty array or null = show to ALL users (global campaign)
  @Column({ type: 'simple-json', nullable: true })
  targetPincodes!: string[] | null;

  // JSON array of cities: ["Bareilly", "Mohali"]
  // Empty array or null = all cities
  @Column({ type: 'simple-json', nullable: true })
  targetCities!: string[] | null;

  // ── Placement ──
  // Where this campaign shows on homepage
  @Column({
    type: 'enum',
    enum: ['hero_banner', 'category_strip', 'product_spotlight', 'bottom_banner'],
    default: 'hero_banner',
  })
  placement!: 'hero_banner' | 'category_strip' | 'product_spotlight' | 'bottom_banner';

  // Lower number = higher priority (1 shows first)
  @Column({ type: 'int', default: 0 })
  priority!: number;

  // ── Scheduling ──
  @Column({ type: 'timestamp' })
  startsAt!: Date;

  @Column({ type: 'timestamp' })
  expiresAt!: Date;

  @Column({ type: 'boolean', default: true })
  isActive!: boolean;

  // ── Push Notification ──
  @Column({ type: 'boolean', default: false })
  pushEnabled!: boolean;

  @Column({ type: 'boolean', default: false })
  pushSent!: boolean;

  @Column({ type: 'timestamp', nullable: true })
  pushSentAt!: Date | null;

  // ── Metadata ──
  @ManyToOne(() => User, { nullable: true })
  createdBy!: User | null;

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
