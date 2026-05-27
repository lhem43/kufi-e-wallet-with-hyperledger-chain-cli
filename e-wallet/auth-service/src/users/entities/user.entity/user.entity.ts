import {
	Entity,
	Column,
	PrimaryGeneratedColumn,
	CreateDateColumn,
	UpdateDateColumn,
} from 'typeorm';

export enum AccountStatus {
	ACTIVE = 'active',
	BLOCKED = 'blocked',
	LOCKED = 'locked',
}

@Entity('users')
export class User {
	@PrimaryGeneratedColumn('uuid')
	id: string;

	@Column({ type: 'varchar', unique: true })
	firebaseUid: string;

	@Column({
		type: 'enum',
		enum: AccountStatus,
		default: AccountStatus.ACTIVE,
	})
	accountStatus: AccountStatus;

	@Column({ type: 'varchar', nullable: true, unique: true })
	email?: string | null;

	@Column({ type: 'varchar', nullable: true, unique: true })
	phone?: string | null;

	@Column({ type: 'varchar', nullable: true })
	displayName?: string | null;

	@Column({ type: 'varchar', default: 'pending' })
	kycStatus: string;

	@Column({ type: 'varchar', nullable: true })
	hashedPin?: string | null;

	@CreateDateColumn()
	createdAt: Date;

	@UpdateDateColumn()
	updatedAt: Date;
}
