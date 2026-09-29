import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  OneToMany,
  Index,
} from 'typeorm';
import { Category } from './Category';
import { ProductVariant } from './ProductVariant';

@Entity()
@Index('IDX_PRODUCT_FULLTEXT', ['name', 'tags', 'description'], { fulltext: true })
export class Product {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column()
  name!: string;

  @Column('text', { nullable: true })
  description!: string;

  /**
   * Search keywords/tags to help find products with different names/spellings
   * Example: for "Coke", tags could be "soda, cold drink, beverage, coca cola"
   */
  @Column('text', { nullable: true })
  tags!: string;

  /**
   * Base price - used when no variants exist or as fallback
   * If variants exist, this can be the price for the default variant
   */
  @Column('decimal', { precision: 10, scale: 2 })
  price!: number;

  @Column({ nullable: true })
  imageUrl!: string;

  @ManyToOne(() => Category, (category) => category.products)
  category!: Category;

  /**
   * Base stock - used when no variants exist
   * If variants exist, stock is tracked per variant
   */
  @Column({ default: 0 })
  stock!: number;

  @Column({ default: true })
  isAvailable!: boolean;

  /**
   * Base unit - used when no variants exist
   * Examples: 'kg', 'piece', 'pack', etc.
   */
  @Column({ nullable: true })
  unit!: string;

  /**
   * Whether this product has variants (quantity options)
   * If true, customers can select from different quantities/weights
   */
  @Column({ default: false })
  hasVariants!: boolean;

  /**
   * Base unit for quantity calculations
   * For pulses: 'kg' (so 250g = 0.25, 1kg = 1.0)
   */
  @Column({ nullable: true })
  baseUnit!: string;

  /**
   * Minimum quantity allowed (in base unit)
   * For pulses: 0.25 (250g minimum)
   */
  @Column('decimal', { precision: 10, scale: 3, nullable: true })
  minQuantity!: number | null;

  /**
   * Maximum quantity allowed (in base unit)
   * For pulses: 5 (5kg maximum)
   */
  @Column('decimal', { precision: 10, scale: 3, nullable: true })
  maxQuantity!: number | null;

  /**
   * Product variants (quantity/weight options)
   * Example: 250g, 500g, 1kg, 2kg, 5kg for pulses
   */
  @OneToMany(() => ProductVariant, (variant) => variant.product, { cascade: true })
  variants!: ProductVariant[];

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
