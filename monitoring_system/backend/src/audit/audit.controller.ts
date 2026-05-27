import { Controller, Get, Query } from '@nestjs/common';
import { Permissions } from '../common/decorators/permissions.decorator';
import { Permission } from '../common/constants/permissions';
import { AuditService } from './audit.service';

@Controller('audit')
export class AuditController {
  constructor(private readonly auditService: AuditService) {}

  @Permissions(Permission.AUDIT_VIEW)
  @Get('logs')
  listLogs(@Query('limit') limit?: string) {
    return this.auditService.listLogs(Number(limit ?? 50));
  }
}
