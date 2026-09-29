import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, Index } from 'typeorm';

@Entity({ name: 'webhook_events' })
export class WebhookEvent {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id!: string;

  @Index('uniq_event', { unique: true })
  @Column({ name: 'event_id', type: 'varchar', length: 64 })
  eventId!: string;

  @Column({ name: 'event_type', type: 'varchar', length: 64 })
  eventType!: string;

  @Column({ type: 'json' })
  payload!: unknown;

  @Column({ name: 'processed_at', type: 'datetime', precision: 3, nullable: true })
  processedAt!: Date | null;

  @CreateDateColumn({ name: 'received_at', precision: 3 })
  receivedAt!: Date;
}
