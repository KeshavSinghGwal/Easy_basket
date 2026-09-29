import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  CreateDateColumn,
  UpdateDateColumn,
  JoinColumn,
} from 'typeorm';
import { Product } from './Product';

/**
 * ProductVariant Entity
 *
 * Represents different quantity/weight options for a product.
 * Example: Pulses can have variants like:
 * - 250g (₹50)
 * - 500g (₹95)
 * - 1kg (₹180)
 * - 2kg (₹350)
 * - 5kg (₹850)
 *
 * Each variant has its own:
 * - Quantity value (e.g., 0.25 for 250g, 1 for 1kg)
 * - Unit (g, kg, piece, etc.)
 * - Price (can have bulk discounts)
 * - Stock (tracked separately)
 * - Min/Max limits
 */
@Entity()
export class ProductVariant {
  @PrimaryGeneratedColumn()
  id!: number;

  @ManyToOne(() => Product, (product) => product.variants, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'productId' })
  product!: Product;

  /**
   * Quantity value in base unit
   * Examples:
   * - 0.25 for 250g (when baseUnit is 'kg')
   * - 1 for 1kg
   * - 2 for 2kg
   * - 5 for 5kg
   */
  @Column('decimal', { precision: 10, scale: 3 })
  quantity!: number;

  /**
   * Unit of measurement
   * Examples: 'g', 'kg', 'piece', 'pack', 'dozen'
   * For pulses: 'g' or 'kg'
   */
  @Column()
  unit!: string;

  /**
   * Display label for the variant
   * Examples: "250g", "1/2 kg", "1 kg", "2 kg", "5 kg"
   * This is what customers see in the UI
   */
  @Column()
  label!: string;

  /**
   * Price for this specific variant
   * Can be different from base product price (bulk discounts, etc.)
   */
  @Column('decimal', { precision: 10, scale: 2 })
  price!: number;

  /**
   * Stock available for this variant
   * Tracked separately from product stock
   */
  @Column({ default: 0 })
  stock!: number;

  /**
   * Whether this variant is available for purchase
   */
  @Column({ default: true })
  isAvailable!: boolean;

  /**
   * Minimum quantity that can be ordered (in base units)
   * For pulses: 0.25 (250g minimum)
   */
  @Column('decimal', { precision: 10, scale: 3, nullable: true })
  minQuantity!: number | null;

  /**
   * Maximum quantity that can be ordered (in base units)
   * For pulses: 5 (5kg maximum)
   */
  @Column('decimal', { precision: 10, scale: 3, nullable: true })
  maxQuantity!: number | null;

  /**
   * Display order for sorting variants
   * Lower numbers appear first
   */
  @Column({ default: 0 })
  displayOrder!: number;

  /**
   * Whether this is the default variant (shown first)
   */
  @Column({ default: false })
  isDefault!: boolean;

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
