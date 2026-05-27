import {
	Column,
	CreateDateColumn,
	Entity,
	Index,
	PrimaryGeneratedColumn,
	UpdateDateColumn,
} from 'typeorm';

export enum KycStatus {
	UNVERIFIED = 'unverified',
	PENDING_REVIEW = 'pending_review',
	VERIFIED = 'verified',
	REJECTED = 'rejected',
}

export enum KycRiskLevel {
	LOW = 'low',
	MEDIUM = 'medium',
	HIGH = 'high',
}

@Entity('kyc_profiles')
@Index(['status', 'updatedAt'])
export class KycProfile {
	@PrimaryGeneratedColumn('uuid')
	id: string;

	@Column({ type: 'uuid', unique: true })
	userId: string;

	@Column({ type: 'varchar', length: 255 })
	fullName: string;

	@Column({ type: 'varchar', length: 32, unique: true })
	nationalId: string;

	@Column({ type: 'date' })
	dateOfBirth: Date;

	@Column({ type: 'date', nullable: true })
	idIssueDate?: Date | null;

	@Column({ type: 'varchar', length: 255, nullable: true })
	idIssuePlace?: string | null;

	@Column({ type: 'varchar', length: 512 })
	residentialAddress: string;

	@Column({
		type: 'enum',
		enum: KycStatus,
		default: KycStatus.UNVERIFIED,
	})
	status: KycStatus;

	@Column({
		type: 'enum',
		enum: KycRiskLevel,
		default: KycRiskLevel.LOW,
	})
	riskLevel: KycRiskLevel;

	@Column({ type: 'varchar', length: 512, nullable: true })
	rejectionReason?: string | null;

	@Column({ type: 'timestamptz', nullable: true })
	submittedAt?: Date | null;

	@Column({ type: 'timestamptz', nullable: true })
	reviewedAt?: Date | null;

	@CreateDateColumn()
	createdAt: Date;

	@UpdateDateColumn()
	updatedAt: Date;
}
