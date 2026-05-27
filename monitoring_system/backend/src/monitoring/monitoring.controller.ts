import { Controller, Get, Param, Post, Query } from '@nestjs/common';
import { Permissions } from '../common/decorators/permissions.decorator';
import { Permission } from '../common/constants/permissions';
import { MonitoringService } from './monitoring.service';
import { AmlObserverService } from './adapters/aml-observer.service';

@Controller('monitoring')
export class MonitoringController {
  constructor(
    private readonly monitoringService: MonitoringService,
    private readonly amlObserverService: AmlObserverService,
  ) {}

  @Permissions(Permission.DASHBOARD_VIEW)
  @Get('overview')
  overview(@Query('refresh') refresh?: string) {
    return this.monitoringService.getOverview(refresh === 'true');
  }

  @Permissions(Permission.METRICS_VIEW)
  @Get('timeseries')
  timeseries(
    @Query('metric') metric = 'system.cpuPercent',
    @Query('minutes') minutes?: string,
  ) {
    return this.monitoringService.getTimeseries(metric, Number(minutes ?? 180));
  }

  @Permissions(Permission.METRICS_VIEW)
  @Get('trends')
  trends(
    @Query('metrics') metrics = 'system.cpuPercent',
    @Query('minutes') minutes?: string,
  ) {
    return this.monitoringService.getTrends(
      metrics.split(','),
      Number(minutes ?? 180),
    );
  }

  @Permissions(Permission.METRICS_VIEW)
  @Get('services')
  services() {
    return this.monitoringService.getServices();
  }

  @Permissions(Permission.CHAIN_VIEW)
  @Get('chain')
  chain() {
    return this.monitoringService.getChainOverview();
  }

  @Permissions(Permission.DASHBOARD_VIEW)
  @Get('alerts')
  alerts() {
    return this.monitoringService.getAlerts();
  }

  @Permissions(Permission.METRICS_VIEW)
  @Get('aml')
  aml(@Query('limit') limit?: string) {
    return this.amlObserverService.getOverview(Number(limit ?? 100));
  }

  @Permissions(Permission.METRICS_VIEW)
  @Get('aml/accounts/:accountId/transactions')
  amlAccountTransactions(
    @Param('accountId') accountId: string,
    @Query('limit') limit?: string,
  ) {
    return this.amlObserverService.getAccountTransactions(
      accountId,
      Number(limit ?? 200),
    );
  }

  @Permissions(Permission.METRICS_VIEW)
  @Post('aml/scan')
  amlScan(@Query('lookbackHours') lookbackHours?: string) {
    return this.amlObserverService.triggerScan(Number(lookbackHours ?? 0));
  }
}
