import {
  Entity,
  Column,
  PrimaryGeneratedColumn,
  CreateDateColumn,
  Index,
} from 'typeorm';

export enum NotificationChannel {
  APP = 'APP',
  EMAIL = 'EMAIL',
  SMS = 'SMS',
}

@Entity('notifications')
@Index(['userId', 'createdAt'])
export class NotificationEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid' })
  userId: string;

  @Column({
    type: 'enum',
    enum: NotificationChannel,
    default: NotificationChannel.APP,
  })
  channel: NotificationChannel;

  @Column({ length: 255 })
  title: string;

  @Column({ length: 1024 })
  content: string;

  @Column({ type: 'text', nullable: true })
  payloadJson: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  readAt: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
