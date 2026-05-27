import {
	Column,
	CreateDateColumn,
	Entity,
	Index,
	PrimaryGeneratedColumn,
	UpdateDateColumn,
} from 'typeorm';

export enum TransactionOutboxStatus {
	PENDING = 'PENDING',
	PUBLISHED = 'PUBLISHED',
	FAILED = 'FAILED',
}

@Entity('transaction_outbox_events')
@Index(['status', 'nextAttemptAt'])
@Index(['status', 'leasedUntil'])
@Index(['aggregateType', 'aggregateId'])
export class TransactionOutboxEvent {
	@PrimaryGeneratedColumn('uuid')
	id: string;

	@Column({ type: 'varchar', length: 64 })
	aggregateType: string;

	@Column({ type: 'varchar', length: 128 })
	aggregateId: string;

	@Column({ type: 'varchar', length: 128 })
	eventType: string;

	@Column({ type: 'jsonb' })
	payload: Record<string, any>;

	@Column({
		type: 'enum',
		enum: TransactionOutboxStatus,
		default: TransactionOutboxStatus.PENDING,
	})
	status: TransactionOutboxStatus;

	@Column({ type: 'int', default: 0 })
	attempts: number;

	@Column({ type: 'timestamptz' })
	nextAttemptAt: Date;

	@Column({ type: 'timestamptz', nullable: true })
	leasedUntil?: Date | null;

	@Column({ type: 'varchar', length: 1024, nullable: true })
	lastError?: string | null;

	@Column({ type: 'timestamptz', nullable: true })
	publishedAt?: Date | null;

	@CreateDateColumn({ type: 'timestamptz' })
	createdAt: Date;

	@UpdateDateColumn({ type: 'timestamptz' })
	updatedAt: Date;
}
