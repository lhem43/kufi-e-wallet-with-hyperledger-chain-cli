import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MetricSnapshotEntity } from '../database/entities/metric-snapshot.entity';
import { ChainObserverService } from './adapters/chain-observer.service';
import { SystemInsightsService } from './adapters/system-insights.service';
import { AmlObserverService } from './adapters/aml-observer.service';
import { WalletAnalyticsService } from './adapters/wallet-analytics.service';
import { MobileController } from './mobile.controller';
import { MonitoringController } from './monitoring.controller';
import { MonitoringService } from './monitoring.service';

@Module({
  imports: [TypeOrmModule.forFeature([MetricSnapshotEntity])],
  controllers: [MonitoringController, MobileController],
  providers: [
    MonitoringService,
    SystemInsightsService,
    WalletAnalyticsService,
    ChainObserverService,
    AmlObserverService,
  ],
  exports: [MonitoringService],
})
export class MonitoringModule {}
