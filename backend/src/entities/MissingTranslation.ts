import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from "typeorm";

@Entity("missing_translations")
@Index(["key"], { unique: true })
export class MissingTranslation {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column()
  key!: string;

  @Column("text")
  en!: string;

  @Column({
    default: "product",
  })
  type!: string;

  @Column({
    default: "pending",
  })
  status!: string;

  @CreateDateColumn({
    name: "created_at",
  })
  createdAt!: Date;

  @UpdateDateColumn({
    name: "updated_at",
  })
  updatedAt!: Date;
}