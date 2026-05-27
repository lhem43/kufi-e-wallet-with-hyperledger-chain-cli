import {
	Entity,
	Column,
	PrimaryGeneratedColumn,
	CreateDateColumn,
	UpdateDateColumn,
	Index,
} from 'typeorm';
import { bigintTransformer } from '../../common/bigint.transformer';

export enum TransactionType {
	TRANSFER = 'TRANSFER',
	DEPOSIT = 'DEPOSIT',
	WITHDRAWAL = 'WITHDRAWAL',
}

export enum TransactionStatus {
	PENDING = 'PENDING',
	COMPLETED = 'COMPLETED',
	FAILED = 'FAILED',
	BLOCKED = 'BLOCKED',
}

export enum SettlementStatus {
	NONE = 'NONE',
	PENDING = 'PENDING',
	SETTLED = 'SETTLED',
	FAILED = 'FAILED',
}

export enum ChainStatus {
	PENDING = 'PENDING',
	ANCHORED = 'ANCHORED',
	FAILED = 'FAILED',
}

@Entity('transactions')
@Index(['fromUserId', 'createdAt'])
@Index(['toUserId', 'createdAt'])
@Index(['toUserId', 'currency', 'createdAt'])
@Index(['toUserId', 'fromUserId'])
@Index(['status', 'createdAt'])
@Index(['isExternal', 'settlementStatus'])
@Index(['externalAccountNo', 'currency', 'createdAt'])
@Index(['chainStatus', 'chainNextAttemptAt'])
export class TransactionEntity {
	@PrimaryGeneratedColumn('uuid')
	id: string;

	@Index({ unique: true })
	@Column({ type: 'varchar', length: 128 })
	idempotencyKey: string;

	@Column({
		type: 'enum',
		enum: TransactionType,
		default: TransactionType.TRANSFER,
	})
	type: TransactionType;

	@Column({
		type: 'enum',
		enum: TransactionStatus,
		default: TransactionStatus.PENDING,
	})
	status: TransactionStatus;

	@Column({
		type: 'enum',
		enum: SettlementStatus,
		default: SettlementStatus.NONE,
	})
	settlementStatus: SettlementStatus;

	@Column({
		type: 'enum',
		enum: ChainStatus,
		default: ChainStatus.PENDING,
	})
	chainStatus: ChainStatus;

	@Index()
	@Column({ type: 'uuid' })
	requestingUserId: string;

	@Index()
	@Column({ type: 'uuid' })
	fromUserId: string;

	@Index()
	@Column({ type: 'uuid', nullable: true })
	toUserId?: string | null;

	@Column({
		type: 'bigint',
		transformer: bigintTransformer,
	})
	amount: number;

	@Column({ type: 'varchar', length: 16 })
	currency: string;

	@Column({ type: 'varchar', length: 512, nullable: true })
	memo?: string | null;

	@Column({ type: 'boolean', default: false })
	isExternal: boolean;

	@Column({ type: 'varchar', length: 64, nullable: true })
	externalPartner?: string | null;

	@Column({ type: 'varchar', length: 128, nullable: true })
	externalAccountNo?: string | null;

	@Column({ type: 'varchar', length: 128, nullable: true })
	externalRef?: string | null;

	@Column({ type: 'varchar', length: 128, nullable: true })
	chainTxId?: string | null;

	@Column({ type: 'text', nullable: true })
	receiptJson?: string | null;

	@Column({ type: 'int', default: 0 })
	chainRetryCount: number;

	@Column({ type: 'timestamptz', nullable: true })
	chainLastAttemptAt?: Date | null;

	@Column({ type: 'timestamptz', nullable: true })
	chainNextAttemptAt?: Date | null;

	@Column({ type: 'varchar', length: 64, nullable: true })
	errorCode?: string | null;

	@Column({ type: 'varchar', length: 1024, nullable: true })
	errorMessage?: string | null;

	@CreateDateColumn({ type: 'timestamptz' })
	createdAt: Date;

	@UpdateDateColumn({ type: 'timestamptz' })
	updatedAt: Date;
}
