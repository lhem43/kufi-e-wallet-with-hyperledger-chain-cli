import {
	Column,
	CreateDateColumn,
	Entity,
	Index,
	PrimaryGeneratedColumn,
	UpdateDateColumn,
} from 'typeorm';

export enum FundingSourceStatus {
	ACTIVE = 'ACTIVE',
	INACTIVE = 'INACTIVE',
}

@Entity('funding_sources')
@Index(['userId', 'provider'])
@Index(['userId', 'provider', 'accountRefHash'], { unique: true })
export class FundingSource {
	@PrimaryGeneratedColumn('uuid')
	id: string;

	@Column({ type: 'uuid' })
	userId: string;

	@Column({ type: 'varchar', length: 32 })
	provider: string;

	@Column({ type: 'varchar', length: 32 })
	accountRefMasked: string;

	@Column({ type: 'varchar', length: 128 })
	accountRefHash: string;

	@Column({ type: 'varchar', length: 256, nullable: true })
	providerToken?: string | null;

	@Column({ type: 'varchar', length: 128, nullable: true })
	displayName?: string | null;

	@Column({
		type: 'enum',
		enum: FundingSourceStatus,
		default: FundingSourceStatus.ACTIVE,
	})
	status: FundingSourceStatus;

	@CreateDateColumn({ type: 'timestamptz' })
	createdAt: Date;

	@UpdateDateColumn({ type: 'timestamptz' })
	updatedAt: Date;
}
