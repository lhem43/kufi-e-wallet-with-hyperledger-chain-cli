import {
	Entity,
	Column,
	PrimaryGeneratedColumn,
	CreateDateColumn,
	UpdateDateColumn,
	Unique,
	Index,
} from 'typeorm';
import { bigintTransformer } from '../../common/bigint.transformer';

export enum WalletStatus {
	ACTIVE = 'ACTIVE',
	FROZEN = 'FROZEN',
}

@Entity('wallets')
@Unique(['userId', 'currency'])
@Index(['userId', 'currency'])
export class Wallet {
	@PrimaryGeneratedColumn('uuid')
	id: string;

	@Column({ type: 'uuid' })
	userId: string;

	@Column({ type: 'varchar', length: 16 })
	currency: string;

	@Column({
		type: 'bigint',
		default: '0',
		transformer: bigintTransformer,
	})
	balance: number;

	@Column({
		type: 'enum',
		enum: WalletStatus,
		default: WalletStatus.ACTIVE,
	})
	status: WalletStatus;

	@CreateDateColumn({ type: 'timestamptz' })
	createdAt: Date;

	@UpdateDateColumn({ type: 'timestamptz' })
	updatedAt: Date;
}
