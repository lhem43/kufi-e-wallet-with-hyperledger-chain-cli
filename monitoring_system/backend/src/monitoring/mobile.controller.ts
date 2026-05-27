import { Controller, Get } from '@nestjs/common';
import { Permissions } from '../common/decorators/permissions.decorator';
import { Permission } from '../common/constants/permissions';
import { MonitoringService } from './monitoring.service';

@Controller('mobile')
export class MobileController {
  constructor(private readonly monitoringService: MonitoringService) {}

  @Permissions(Permission.MOBILE_VIEW)
  @Get('overview')
  overview() {
    return this.monitoringService.getOverview();
  }

  @Permissions(Permission.MOBILE_VIEW)
  @Get('alerts')
  alerts() {
    return this.monitoringService.getAlerts();
  }

  @Permissions(Permission.MOBILE_VIEW)
  @Get('chain')
  chain() {
    return this.monitoringService.getChainOverview();
  }
}
