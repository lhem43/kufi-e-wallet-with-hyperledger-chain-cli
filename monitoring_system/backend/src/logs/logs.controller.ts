import { Controller, Get, Query } from '@nestjs/common';
import { Permissions } from '../common/decorators/permissions.decorator';
import { Permission } from '../common/constants/permissions';
import { LogsService } from './logs.service';

@Controller('logs')
export class LogsController {
  constructor(private readonly logsService: LogsService) {}

  @Permissions(Permission.LOGS_VIEW)
  @Get('sources')
  sources() {
    return this.logsService.listSources();
  }

  @Permissions(Permission.LOGS_VIEW)
  @Get('tail')
  tail(@Query('source') source: string, @Query('limit') limit?: string) {
    return this.logsService.tail(source, Number(limit ?? 120));
  }
}
