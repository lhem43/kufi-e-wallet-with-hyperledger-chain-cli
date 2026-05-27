import {
  Entity,
  Column,
  PrimaryGeneratedColumn,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';
import { bigintTransformer } from '../../common/bigint.transformer';

export enum ExternalTransferStatus {
  SUBMITTED = 'SUBMITTED',
  SETTLED = 'SETTLED',
  FAILED = 'FAILED',
}

export enum ExternalTransferType {
  WITHDRAWAL = 'WITHDRAWAL',
  TOPUP = 'TOPUP',
}

@Entity('external_transfers')
export class ExternalTransfer {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index({ unique: true })
  @Column({ type: 'uuid' })
  transactionId: string;

  @Column({ length: 64 })
  partnerCode: string;

  @Column({ length: 128 })
  accountNo: string;

  @Column({
    type: 'enum',
    enum: ExternalTransferType,
    default: ExternalTransferType.WITHDRAWAL,
  })
  transferType: ExternalTransferType;

  @Column({ type: 'bigint', transformer: bigintTransformer })
  amount: number;

  @Column({ length: 16 })
  currency: string;

  @Index({ unique: true })
  @Column({ length: 128 })
  partnerRef: string;

  @Column({
    type: 'enum',
    enum: ExternalTransferStatus,
    default: ExternalTransferStatus.SUBMITTED,
  })
  status: ExternalTransferStatus;

  @Column({ type: 'varchar', length: 1024, nullable: true })
  partnerMessage: string | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
