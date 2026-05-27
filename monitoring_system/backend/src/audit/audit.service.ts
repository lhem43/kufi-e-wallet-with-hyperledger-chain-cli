import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AuditLogEntity } from '../database/entities/audit-log.entity';

export type CreateAuditLogInput = {
  actorUserId?: string | null;
  actorEmail?: string | null;
  method: string;
  path: string;
  action: string;
  resource: string;
  statusCode: number;
  ipAddress?: string | null;
  payload?: Record<string, unknown> | null;
  outcome?: string | null;
};

@Injectable()
export class AuditService {
  constructor(
    @InjectRepository(AuditLogEntity)
    private readonly auditLogRepository: Repository<AuditLogEntity>,
  ) {}

  async createLog(input: CreateAuditLogInput) {
    await this.auditLogRepository.save(this.auditLogRepository.create(input));
  }

  async listLogs(limit = 50) {
    return this.auditLogRepository.find({
      order: { createdAt: 'DESC' },
      take: Math.min(Math.max(limit, 1), 500),
    });
  }
}
