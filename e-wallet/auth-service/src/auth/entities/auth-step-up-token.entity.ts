import {
	Column,
	CreateDateColumn,
	Entity,
	Index,
	PrimaryGeneratedColumn,
	UpdateDateColumn,
} from 'typeorm';

@Entity('auth_step_up_tokens')
@Index(['userId', 'expiresAt'])
export class AuthStepUpToken {
	@PrimaryGeneratedColumn('uuid')
	id: string;

	@Index({ unique: true })
	@Column({ type: 'varchar', length: 128 })
	token: string;

	@Index()
	@Column({ type: 'uuid' })
	userId: string;

	@Column({ type: 'varchar', length: 128, nullable: true })
	deviceId?: string | null;

	@Column({ type: 'varchar', length: 32, nullable: true })
	method?: string | null;

	@Column({ type: 'timestamptz' })
	expiresAt: Date;

	@CreateDateColumn({ type: 'timestamptz' })
	createdAt: Date;

	@UpdateDateColumn({ type: 'timestamptz' })
	updatedAt: Date;
}
