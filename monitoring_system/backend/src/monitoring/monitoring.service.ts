import { Injectable, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Interval } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { LessThan, Repository } from 'typeorm';
import { parseNamedList } from '../common/utils/list.parser';
import { MetricSnapshotEntity } from '../database/entities/metric-snapshot.entity';
import { ChainObserverService } from './adapters/chain-observer.service';
import { SystemInsightsService } from './adapters/system-insights.service';
import { WalletAnalyticsService } from './adapters/wallet-analytics.service';
import {
  AlertItem,
  MonitoringOverview,
  ServiceHealthItem,
} from './monitoring.types';

@Injectable()
export class MonitoringService implements OnModuleInit {
  private cachedOverview: MonitoringOverview | null = null;
  private cachedOverviewAt = 0;
  private lastCollectedAt = 0;
  private lastSnapshotPersistAt = 0;
  private collectionPromise: Promise<MonitoringOverview> | null = null;

  constructor(
    @InjectRepository(MetricSnapshotEntity)
    private readonly metricSnapshotRepository: Repository<MetricSnapshotEntity>,
    private readonly configService: ConfigService,
    private readonly systemInsightsService: SystemInsightsService,
    private readonly walletAnalyticsService: WalletAnalyticsService,
    private readonly chainObserverService: ChainObserverService,
  ) {}

  async onModuleInit() {
    const latest = await this.loadLatestOverview();
    if (latest) {
      this.rememberOverview(latest);
      this.lastSnapshotPersistAt = new Date(latest.generatedAt).getTime() || 0;
      this.lastCollectedAt = this.lastSnapshotPersistAt;
    }

    if (
      !latest ||
      this.isOlderThan(
        latest.generatedAt,
        this.readNumberConfig('MONITORING_BOOTSTRAP_MAX_AGE_MS', 60_000),
      )
    ) {
      await this.collectAndStoreOverview();
    }
  }

  @Interval(30000)
  async scheduledCollection() {
    await this.collectAndStoreOverview();
  }

  @Interval(10 * 60 * 1000)
  async pruneOldSnapshots() {
    const retentionHours = this.readNumberConfig(
      'MONITORING_SNAPSHOT_RETENTION_HOURS',
      24 * 7,
      1,
      24 * 90,
    );
    const cutoff = new Date(Date.now() - retentionHours * 60 * 60 * 1000);
    await this.metricSnapshotRepository.delete({
      category: 'overview',
      createdAt: LessThan(cutoff),
    });
  }

  async getOverview(forceRefresh = false) {
    const minCollectionIntervalMs = this.readNumberConfig(
      'MONITORING_COLLECTION_MIN_INTERVAL_MS',
      30_000,
      5_000,
      10 * 60 * 1000,
    );

    if (
      !forceRefresh &&
      this.cachedOverview &&
      Date.now() - this.lastCollectedAt < minCollectionIntervalMs
    ) {
      return this.cachedOverview;
    }

    if (
      this.cachedOverview &&
      Date.now() - this.cachedOverviewAt <
        this.readNumberConfig(
          forceRefresh
            ? 'MONITORING_FORCE_REFRESH_COOLDOWN_MS'
            : 'MONITORING_OVERVIEW_CACHE_MS',
          forceRefresh ? 5_000 : 10_000,
          1_000,
          60_000,
        )
    ) {
      return this.cachedOverview;
    }

    if (this.collectionPromise) {
      return this.collectionPromise;
    }

    const latest = await this.loadLatestOverview();
    if (latest) {
      this.rememberOverview(latest);
      if (!forceRefresh) {
        return latest;
      }
    }

    return this.collectAndStoreOverview(forceRefresh);
  }

  async getAlerts() {
    const overview = await this.getOverview();
    return overview.alerts;
  }

  async getServices() {
    const overview = await this.getOverview();
    return overview.services;
  }

  async getChainOverview() {
    const overview = await this.getOverview();
    return overview.chain;
  }

  async getTimeseries(metric: string, minutes = 180) {
    const trends = await this.getTrends([metric], minutes);
    return (
      trends.series[metric] ?? {
        metric,
        minutes: Math.min(Math.max(minutes, 15), 24 * 60),
        points: [],
      }
    );
  }

  async getTrends(metrics: string[], minutes = 180) {
    const safeMinutes = Math.min(Math.max(minutes, 15), 24 * 60);
    const safeMetrics = Array.from(
      new Set(
        metrics
          .map((metric) => metric.trim())
          .filter((metric) => metric.length > 0),
      ),
    ).slice(0, 8);

    if (safeMetrics.length === 0) {
      return {
        minutes: safeMinutes,
        series: {},
      };
    }

    const since = new Date(Date.now() - safeMinutes * 60 * 1000);
    const snapshots = await this.metricSnapshotRepository
      .createQueryBuilder('snapshot')
      .where('snapshot.category = :category', { category: 'overview' })
      .andWhere('snapshot.createdAt > :since', { since })
      .orderBy('snapshot.createdAt', 'ASC')
      .getMany();

    if (snapshots.length === 0) {
      const fallback = await this.getOverview();
      return {
        minutes: safeMinutes,
        series: Object.fromEntries(
          safeMetrics.map((metric) => [
            metric,
            {
              metric,
              minutes: safeMinutes,
              points: [
                {
                  at: fallback.generatedAt,
                  value: normalizeMetricValue(
                    extractMetricValue(
                      fallback as unknown as Record<string, unknown>,
                      metric,
                    ),
                  ),
                },
              ],
            },
          ]),
        ),
      };
    }

    return {
      minutes: safeMinutes,
      series: Object.fromEntries(
        safeMetrics.map((metric) => [
          metric,
          {
            metric,
            minutes: safeMinutes,
            points: snapshots.map((snapshot) => ({
              at: snapshot.createdAt.toISOString(),
              value: normalizeMetricValue(
                extractMetricValue(snapshot.payload, metric),
              ),
            })),
          },
        ]),
      ),
    };
  }

  private async collectAndStoreOverview(force = false) {
    const minCollectionIntervalMs = this.readNumberConfig(
      'MONITORING_COLLECTION_MIN_INTERVAL_MS',
      30_000,
      5_000,
      10 * 60 * 1000,
    );

    if (
      !force &&
      this.cachedOverview &&
      Date.now() - this.lastCollectedAt < minCollectionIntervalMs
    ) {
      return this.cachedOverview;
    }

    if (this.collectionPromise) {
      return this.collectionPromise;
    }

    this.collectionPromise = (async () => {
      const [system, wallet, services, chain] = await Promise.all([
        this.systemInsightsService.collect(),
        this.walletAnalyticsService.collect(),
        this.collectServiceHealth(),
        this.chainObserverService.collect(),
      ]);

      const alerts = this.buildAlerts(system, wallet, services, chain);
      const status = deriveStatus(alerts);

      const overview: MonitoringOverview = {
        generatedAt: new Date().toISOString(),
        status,
        system,
        wallet,
        services: {
          healthyCount: services.filter((item) => item.status === 'healthy')
            .length,
          totalCount: services.length,
          items: services,
        },
        chain,
        dataWarehouse: {
          ready: Boolean(this.configService.get<string>('DW_STATUS_URL')),
          note: this.configService.get<string>(
            'DW_STATUS_NOTE',
            'Reserved for future data warehouse feeds that support rate and liquidity decisions.',
          ),
        },
        alerts,
      };

      this.lastCollectedAt = Date.now();

      if (this.shouldPersistSnapshot(overview)) {
        await this.metricSnapshotRepository.save(
          this.metricSnapshotRepository.create({
            category: 'overview',
            payload: overview as unknown as Record<string, unknown>,
          }),
        );
        this.lastSnapshotPersistAt = Date.now();
      }

      this.rememberOverview(overview);

      return overview;
    })();

    try {
      return await this.collectionPromise;
    } finally {
      this.collectionPromise = null;
    }
  }

  private async collectServiceHealth(): Promise<ServiceHealthItem[]> {
    const configuredEndpoints = this.configService
      .get<string>('MONITORED_SERVICE_ENDPOINTS')
      ?.trim();
    if (!configuredEndpoints) {
      return [];
    }

    const endpoints = parseNamedList(
      configuredEndpoints,
    );

    return Promise.all(
      endpoints.map(async (endpoint) => {
        const startedAt = Date.now();
        try {
          const response = await fetch(endpoint.value, {
            signal: AbortSignal.timeout(2500),
          });
          const payload = await safeJson(response);
          return {
            name: endpoint.name,
            url: endpoint.value,
            status: response.ok ? 'healthy' : 'critical',
            latencyMs: Date.now() - startedAt,
            httpStatus: response.status,
            lastCheckedAt: new Date().toISOString(),
            detail: payload?.status ? String(payload.status) : null,
          } satisfies ServiceHealthItem;
        } catch (error) {
          return {
            name: endpoint.name,
            url: endpoint.value,
            status: 'critical',
            latencyMs: null,
            httpStatus: null,
            lastCheckedAt: new Date().toISOString(),
            detail:
              error instanceof Error
                ? error.message
                : 'Service is unreachable.',
          } satisfies ServiceHealthItem;
        }
      }),
    );
  }

  private buildAlerts(
    system: MonitoringOverview['system'],
    wallet: MonitoringOverview['wallet'],
    services: ServiceHealthItem[],
    chain: MonitoringOverview['chain'],
  ): AlertItem[] {
    const alerts: AlertItem[] = [];
    const cpuCriticalThreshold = this.readNumberConfig(
      'MONITORING_ALERT_CPU_CRITICAL',
      85,
      1,
      100,
    );
    const memoryWarningThreshold = this.readNumberConfig(
      'MONITORING_ALERT_MEMORY_WARNING',
      80,
      1,
      100,
    );
    const diskCriticalThreshold = this.readNumberConfig(
      'MONITORING_ALERT_DISK_CRITICAL',
      90,
      1,
      100,
    );
    const loadAverageWarningThreshold = this.readNumberConfig(
      'MONITORING_ALERT_LOAD_WARNING',
      4,
      0.1,
      128,
    );
    const serviceLatencyWarningMs = this.readNumberConfig(
      'MONITORING_ALERT_SERVICE_LATENCY_WARNING_MS',
      1500,
      100,
      60_000,
    );
    const concurrentWarnThreshold = Number(
      this.configService.get<string>('WALLET_CONCURRENT_WARN_THRESHOLD', '500'),
    );

    if (system.cpuPercent >= cpuCriticalThreshold) {
      alerts.push({
        code: 'cpu_hot',
        severity: 'critical',
        metric: 'system.cpuPercent',
        currentValue: system.cpuPercent,
        threshold: cpuCriticalThreshold,
        title: 'CPU usage is in the critical zone.',
        recommendedAction:
          'Inspect high-load services and autoscaling capacity.',
      });
    }

    if (system.memoryPercent >= memoryWarningThreshold) {
      alerts.push({
        code: 'memory_pressure',
        severity: 'warning',
        metric: 'system.memoryPercent',
        currentValue: system.memoryPercent,
        threshold: memoryWarningThreshold,
        title: 'Memory pressure is rising.',
        recommendedAction:
          'Review container limits, leaks, and garbage-collection hotspots.',
      });
    }

    if (system.diskPercent >= diskCriticalThreshold) {
      alerts.push({
        code: 'disk_almost_full',
        severity: 'critical',
        metric: 'system.diskPercent',
        currentValue: system.diskPercent,
        threshold: diskCriticalThreshold,
        title: 'Disk capacity is almost exhausted.',
        recommendedAction:
          'Rotate logs and expand storage before ingest stalls.',
      });
    }

    if (system.loadAverage1m >= loadAverageWarningThreshold) {
      alerts.push({
        code: 'load_average_high',
        severity: 'warning',
        metric: 'system.loadAverage1m',
        currentValue: system.loadAverage1m,
        threshold: loadAverageWarningThreshold,
        title: 'System load average is elevated.',
        recommendedAction:
          'Inspect queue depth and CPU saturation across critical services.',
      });
    }

    if (
      typeof wallet.concurrentUsersEstimate === 'number' &&
      wallet.concurrentUsersEstimate >= concurrentWarnThreshold
    ) {
      alerts.push({
        code: 'concurrent_users_spike',
        severity: 'warning',
        metric: 'wallet.concurrentUsersEstimate',
        currentValue: wallet.concurrentUsersEstimate,
        threshold: concurrentWarnThreshold,
        title: 'Concurrent wallet usage is above the configured threshold.',
        recommendedAction:
          'Verify API latency, queue depth, and transfer throughput.',
      });
    }

    if (wallet.configured && wallet.source === 'error') {
      alerts.push({
        code: 'wallet_telemetry_unavailable',
        severity: 'warning',
        metric: 'wallet',
        currentValue: wallet.note ?? 'unavailable',
        threshold: 'readonly_db',
        title: 'Wallet telemetry is configured but currently unavailable.',
        recommendedAction:
          'Inspect the read-only database connection and session analytics query.',
      });
    }

    for (const service of services.filter(
      (item) => item.status === 'critical',
    )) {
      alerts.push({
        code: `service_down_${service.name}`,
        severity: 'critical',
        metric: `services.${service.name}`,
        currentValue: service.detail ?? 'down',
        threshold: 'healthy',
        title: `${service.name} is unreachable or unhealthy.`,
        recommendedAction:
          'Check service container logs and upstream dependencies.',
      });
    }

    for (const service of services.filter(
      (item) =>
        item.status === 'healthy' &&
        typeof item.latencyMs === 'number' &&
        item.latencyMs >= serviceLatencyWarningMs,
    )) {
      alerts.push({
        code: `service_latency_${service.name}`,
        severity: 'warning',
        metric: `services.${service.name}.latencyMs`,
        currentValue: service.latencyMs ?? 'n/a',
        threshold: serviceLatencyWarningMs,
        title: `${service.name} latency is above the warning threshold.`,
        recommendedAction:
          'Investigate upstream dependencies, database response time, and request queue pressure.',
      });
    }

    for (const anomaly of chain.anomalies) {
      alerts.push({
        code: anomaly.code,
        severity: anomaly.severity,
        metric: 'chain',
        currentValue: anomaly.message,
        threshold: 'stable topology',
        title: anomaly.message,
        recommendedAction:
          anomaly.severity === 'critical'
            ? 'Inspect Kufi chain nodes, peer connectivity, and gateway health immediately.'
            : 'Compare peer status across nodes and validate recent join or upgrade actions.',
      });
    }

    return alerts;
  }

  private async loadLatestOverview() {
    const latest = await this.metricSnapshotRepository.findOne({
      where: { category: 'overview' },
      order: { createdAt: 'DESC' },
    });
    return latest?.payload as MonitoringOverview | null;
  }

  private rememberOverview(overview: MonitoringOverview) {
    this.cachedOverview = overview;
    this.cachedOverviewAt = Date.now();
  }

  private shouldPersistSnapshot(nextOverview: MonitoringOverview) {
    const persistIntervalMs = this.readNumberConfig(
      'MONITORING_SNAPSHOT_PERSIST_MS',
      60_000,
      10_000,
      60 * 60 * 1000,
    );

    if (!this.cachedOverview || this.lastSnapshotPersistAt === 0) {
      return true;
    }

    if (Date.now() - this.lastSnapshotPersistAt >= persistIntervalMs) {
      return true;
    }

    return hasOperationalStateChanged(this.cachedOverview, nextOverview);
  }

  private isOlderThan(input: string, maxAgeMs: number) {
    const at = new Date(input).getTime();
    if (Number.isNaN(at)) {
      return true;
    }
    return Date.now() - at > maxAgeMs;
  }

  private readNumberConfig(
    key: string,
    fallback: number,
    min = Number.NEGATIVE_INFINITY,
    max = Number.POSITIVE_INFINITY,
  ) {
    const raw = Number(this.configService.get<string>(key, String(fallback)));
    if (!Number.isFinite(raw)) {
      return fallback;
    }
    return Math.min(Math.max(raw, min), max);
  }
}

function deriveStatus(alerts: AlertItem[]): 'healthy' | 'warning' | 'critical' {
  if (alerts.some((alert) => alert.severity === 'critical')) {
    return 'critical';
  }
  if (alerts.length > 0) {
    return 'warning';
  }
  return 'healthy';
}

function extractMetricValue(payload: Record<string, unknown>, metric: string) {
  return metric.split('.').reduce<unknown>((current, segment) => {
    if (!current || typeof current !== 'object' || !(segment in current)) {
      return null;
    }
    return (current as Record<string, unknown>)[segment];
  }, payload);
}

async function safeJson(response: Response) {
  try {
    return (await response.json()) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function normalizeMetricValue(value: unknown) {
  return typeof value === 'number' ? value : null;
}

function hasOperationalStateChanged(
  previous: MonitoringOverview,
  next: MonitoringOverview,
) {
  if (previous.status !== next.status) {
    return true;
  }

  if (
    serializeAlerts(previous.alerts) !== serializeAlerts(next.alerts) ||
    serializeServices(previous.services.items) !== serializeServices(next.services.items) ||
    serializeChain(previous.chain) !== serializeChain(next.chain) ||
    previous.wallet.source !== next.wallet.source
  ) {
    return true;
  }

  return false;
}

function serializeAlerts(alerts: AlertItem[]) {
  return alerts
    .map((alert) => `${alert.code}:${alert.severity}`)
    .sort()
    .join('|');
}

function serializeServices(services: ServiceHealthItem[]) {
  return services
    .map(
      (service) =>
        `${service.name}:${service.status}:${service.httpStatus ?? 'n/a'}`,
    )
    .sort()
    .join('|');
}

function serializeChain(chain: MonitoringOverview['chain']) {
  return [
    chain.gatewayStatus,
    chain.fabricStatus,
    ...chain.nodes.map(
      (node) =>
        `${node.name}:${node.status}:${node.knownPeers}:${node.pendingRequests}`,
    ),
  ].join('|');
}
