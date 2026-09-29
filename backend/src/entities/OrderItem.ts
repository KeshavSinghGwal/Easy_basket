import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  CreateDateColumn,
  UpdateDateColumn,
  JoinColumn,
} from 'typeorm';
import { Order } from './Order';
import { Product } from './Product';
import { ProductVariant } from './ProductVariant';

@Entity()
export class OrderItem {
  @PrimaryGeneratedColumn()
  id!: number;

  @ManyToOne(() => Order, (order) => order.items)
  order!: Order;

  @ManyToOne(() => Product)
  product!: Product;

  /**
   * Product variant selected (if product has variants)
   * Null if product doesn't have variants
   */
  @ManyToOne(() => ProductVariant, {
    nullable: true,
    onDelete: 'SET NULL',
    createForeignKeyConstraints: true,
  })
  @JoinColumn({ name: 'variantId', referencedColumnName: 'id' })
  variant!: ProductVariant | null;

  /**
   * Quantity ordered
   * For variants: number of units of the variant (e.g., 2 units of 1kg = 2kg)
   * For non-variants: quantity in base unit
   */
  @Column('decimal', { precision: 10, scale: 3 })
  quantity!: number;

  /**
   * Unit of the quantity
   * Examples: 'kg', 'g', 'piece'
   */
  @Column({ nullable: true })
  unit!: string;

  /**
   * Price per unit at time of order
   * If variant exists, this is variant.price
   * Otherwise, this is product.price
   */
  @Column('decimal', { precision: 10, scale: 2 })
  price!: number;

  /**
   * Total price for this item (quantity * price)
   */
  @Column('decimal', { precision: 10, scale: 2 })
  total!: number;

  /**
   * Display label for what was ordered
   * Examples: "1 kg", "2 × 1 kg", "250g"
   */
  @Column({ nullable: true })
  displayLabel!: string;

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
