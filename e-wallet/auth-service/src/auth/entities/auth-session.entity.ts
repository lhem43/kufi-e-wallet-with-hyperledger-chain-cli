import {
    Column,
    CreateDateColumn,
    Entity,
    Index,
    PrimaryGeneratedColumn,
    UpdateDateColumn
} from 'typeorm';

@Entity('auth_sessions')
export class AuthSession {
    @PrimaryGeneratedColumn('uuid')
    id: string;

    @Index()
    @Column({ type: 'varchar' })
    userId: string;

    @Column({ type: 'varchar', unique: true })
    refreshTokenHash: string;

    @Column({ type: 'timestamptz' })
    refreshTokenExpiresAt: Date;

    @Column({ type: 'timestamptz', nullable: true })
    revokedAt?: Date | null;

    @Column({ type: 'timestamptz', nullable: true })
    lastUsedAt?: Date | null;

    @Column({ type: 'varchar', nullable: true })
    userAgent?: string | null;

    @Column({ type: 'varchar', nullable: true })
    ipAddress?: string | null;

    @CreateDateColumn()
    createdAt: Date;

    @UpdateDateColumn()
    updatedAt: Date;
}
