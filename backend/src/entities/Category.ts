import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  OneToMany,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';
import { Product } from './Product';

@Entity()
export class Category {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column()
  name!: string;

  @Column({ nullable: true })
  description!: string;

  @Column({ nullable: true })
  imageUrl!: string;

  @Column({ default: true })
  isActive!: boolean;

  /**
   * Parent category for subcategories
   * Null for top-level categories
   */
  @ManyToOne(() => Category, (category) => category.subcategories, {
    nullable: true,
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'parentCategoryId' })
  parentCategory!: Category | null;

  /**
   * Subcategories of this category
   */
  @OneToMany(() => Category, (category) => category.parentCategory)
  subcategories!: Category[];

  /**
   * Products in this category
   * Note: Products should be assigned to leaf categories (subcategories), not parent categories
   */
  @OneToMany(() => Product, (product) => product.category)
  products!: Product[];

  /**
   * Display order for sorting categories
   */
  @Column({ default: 0 })
  displayOrder!: number;

  /**
   * Whether this is a parent category (has subcategories)
   */
  get isParentCategory(): boolean {
    return this.subcategories != null && this.subcategories.length > 0;
  }

  /**
   * Whether this is a leaf category (no subcategories, can have products)
   */
  get isLeafCategory(): boolean {
    return this.subcategories == null || this.subcategories.length === 0;
  }

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
