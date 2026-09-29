import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from "typeorm";

@Entity("translations")
export class Translation {
  @PrimaryGeneratedColumn()
  id!: number;

  @Index({ unique: true })
  @Column({ length: 255 })
  key!: string;

  /*
   * Source text. TEXT rather than VARCHAR(255) because product
   * descriptions routinely exceed 255 characters.
   */
  @Column("text")
  en!: string;

  @Column("text", { nullable: true })
  hi!: string | null;

  @Column("text", { nullable: true })
  pa!: string | null;

  @Column({
    default: "content",
  })
  type!: string;

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
