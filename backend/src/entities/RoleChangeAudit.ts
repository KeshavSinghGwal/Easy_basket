import { Column, CreateDateColumn, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';
import { UserRole } from '../constants/roles';

@Entity('role_change_audit')
export class RoleChangeAudit {
  @PrimaryGeneratedColumn()
  id!: number;

  @Index()
  @Column()
  actorUserId!: number;

  @Index()
  @Column()
  targetUserId!: number;

  @Column({ length: 32 })
  fromRole!: UserRole;

  @Column({ length: 32 })
  toRole!: UserRole;

  @Column({ type: 'varchar', length: 64, nullable: true })
  ip!: string | null;

  @Column({ type: 'varchar', length: 512, nullable: true })
  userAgent!: string | null;

  @CreateDateColumn()
  createdAt!: Date;
}
