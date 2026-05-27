import {
	Entity,
	Column,
	PrimaryGeneratedColumn,
	CreateDateColumn,
	Index,
} from 'typeorm';
import { bigintTransformer } from '../../common/bigint.transformer';

export enum LedgerDirection {
	DEBIT = 'DEBIT',
	CREDIT = 'CREDIT',
}

@Entity('ledger_entries')
@Index(['transactionId'])
@Index(['walletId'])
@Index(['walletId', 'direction'])
export class LedgerEntry {
	@PrimaryGeneratedColumn('increment')
	id: number;

	@Column({ type: 'uuid' })
	transactionId: string;

	@Column({ type: 'uuid', nullable: true })
	walletId?: string | null;

	@Column({
		type: 'enum',
		enum: LedgerDirection,
	})
	direction: LedgerDirection;

	@Column({
		type: 'bigint',
		transformer: bigintTransformer,
	})
	amount: number;

	@Column({
		type: 'bigint',
		transformer: bigintTransformer,
	})
	balanceBefore: number;

	@Column({
		type: 'bigint',
		transformer: bigintTransformer,
	})
	balanceAfter: number;

	@Column({ type: 'varchar', length: 512, nullable: true })
	note?: string | null;

	@CreateDateColumn({ type: 'timestamptz' })
	createdAt: Date;
}
