import {
	Column,
	CreateDateColumn,
	Entity,
	Index,
	PrimaryGeneratedColumn,
	UpdateDateColumn,
} from 'typeorm';

export enum OtpPurpose {
	TRANSFER = 'TRANSFER',
	STEP_UP_EMAIL = 'STEP_UP_EMAIL',
}

@Entity('auth_otps')
@Index(['userId', 'purpose', 'expiresAt'])
@Index(['userId', 'purpose', 'usedAt', 'createdAt'])
export class AuthOtp {
	@PrimaryGeneratedColumn('uuid')
	id: string;

	@Index()
	@Column('uuid')
	userId: string;

	@Column({
		type: 'enum',
		enum: OtpPurpose,
		default: OtpPurpose.TRANSFER,
	})
	purpose: OtpPurpose;

	@Column({ type: 'varchar', length: 128 })
	otpHash: string;

	@Column({ type: 'smallint', default: 0 })
	attemptCount: number;

	@Column({ type: 'timestamptz' })
	expiresAt: Date;

	@Column({ type: 'timestamptz', nullable: true })
	usedAt?: Date | null;

	@Column({ type: 'varchar', length: 512, nullable: true })
	userAgent?: string | null;

	@Column({ type: 'varchar', length: 64, nullable: true })
	ipAddress?: string | null;

	@Column({ type: 'varchar', length: 128, nullable: true })
	deviceId?: string | null;

	@CreateDateColumn()
	createdAt: Date;

	@UpdateDateColumn()
	updatedAt: Date;
}
