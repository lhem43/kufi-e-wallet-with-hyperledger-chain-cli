import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  AmlAccountTransaction,
  AmlFlaggedAccount,
  AmlOverview,
} from '../monitoring.types';

@Injectable()
export class AmlObserverService {
  private readonly baseUrl: string;
  private readonly timeoutMs: number;

  constructor(private readonly configService: ConfigService) {
    this.baseUrl = (this.configService.get<string>('AML_SERVICE_BASE_URL') ?? '')
      .trim()
      .replace(/\/+$/, '');
    this.timeoutMs = this.readNumber('AML_SERVICE_TIMEOUT_MS', 5000, 1000, 20000);
  }

  async getOverview(limit = 100): Promise<AmlOverview> {
    if (!this.baseUrl) {
      return this.unconfiguredOverview();
    }

    try {
      const [status, accounts] = await Promise.all([
        this.requestJson<Record<string, unknown>>('/aml/status'),
        this.requestJson<Record<string, unknown>>(
          `/aml/accounts?limit=${Math.max(1, Math.min(limit, 500))}&offset=0`,
        ),
      ]);

      const items = Array.isArray(accounts.items)
        ? accounts.items.map((item) => this.normalizeAccount(item))
        : [];

      return {
        configured: true,
        status: this.normalizeStatus(status.status),
        generatedAt: toNullableString(status.generatedAt),
        lookbackHours: toNumber(status.lookbackHours, 24),
        totalTransactions: toNumber(status.totalTransactions, 0),
        flaggedTransactions: toNumber(status.flaggedTransactions, 0),
        flaggedAccounts: toNumber(status.flaggedAccounts, items.length),
        scanDurationMs:
          status.scanDurationMs == null ? null : toNumber(status.scanDurationMs, 0),
        error: toNullableString(status.error),
        accounts: items,
      };
    } catch (error) {
      return {
        configured: true,
        status: 'error',
        generatedAt: null,
        lookbackHours: 24,
        totalTransactions: 0,
        flaggedTransactions: 0,
        flaggedAccounts: 0,
        scanDurationMs: null,
        error: error instanceof Error ? error.message : 'AML service unavailable.',
        accounts: [],
      };
    }
  }

  async getAccountTransactions(
    accountId: string,
    limit = 200,
  ): Promise<{
    generatedAt: string | null;
    accountId: string;
    total: number;
    items: AmlAccountTransaction[];
  }> {
    if (!this.baseUrl) {
      return {
        generatedAt: null,
        accountId,
        total: 0,
        items: [],
      };
    }

    const safeLimit = Math.max(1, Math.min(limit, 1000));
    const payload = await this.requestJson<Record<string, unknown>>(
      `/aml/accounts/${encodeURIComponent(accountId)}/transactions?limit=${safeLimit}`,
    );

    const items = Array.isArray(payload.items)
      ? payload.items.map((item) => this.normalizeTransaction(item))
      : [];

    return {
      generatedAt: toNullableString(payload.generatedAt),
      accountId,
      total: toNumber(payload.total, items.length),
      items,
    };
  }

  async triggerScan(lookbackHours?: number) {
    if (!this.baseUrl) {
      return this.unconfiguredOverview();
    }

    const payload = await this.requestJson<Record<string, unknown>>('/aml/scan', {
      method: 'POST',
      body: JSON.stringify(
        lookbackHours && Number.isFinite(lookbackHours)
          ? { lookbackHours: Math.max(1, Math.min(lookbackHours, 24 * 30)) }
          : {},
      ),
      headers: {
        'Content-Type': 'application/json',
      },
    });

    return {
      configured: true,
      status: this.normalizeStatus(payload.status),
      generatedAt: toNullableString(payload.generatedAt),
      lookbackHours: toNumber(payload.lookbackHours, 24),
      totalTransactions: toNumber(payload.totalTransactions, 0),
      flaggedTransactions: toNumber(payload.flaggedTransactions, 0),
      flaggedAccounts: toNumber(payload.flaggedAccounts, 0),
      scanDurationMs:
        payload.scanDurationMs == null ? null : toNumber(payload.scanDurationMs, 0),
      error: toNullableString(payload.error),
      accounts: Array.isArray(payload.accounts)
        ? payload.accounts.map((item) => this.normalizeAccount(item))
        : [],
    } satisfies AmlOverview;
  }

  private async requestJson<T>(
    path: string,
    init?: RequestInit,
  ): Promise<T> {
    const response = await fetch(`${this.baseUrl}${path}`, {
      ...init,
      signal: AbortSignal.timeout(this.timeoutMs),
    });

    if (!response.ok) {
      throw new Error(`AML service HTTP ${response.status}`);
    }

    return (await response.json()) as T;
  }

  private normalizeStatus(value: unknown): AmlOverview['status'] {
    const normalized = `${value ?? ''}`.trim().toLowerCase();
    if (
      normalized === 'ok' ||
      normalized === 'error' ||
      normalized === 'busy' ||
      normalized === 'not_started'
    ) {
      return normalized;
    }

    return 'error';
  }

  private normalizeAccount(value: unknown): AmlFlaggedAccount {
    const item = (value ?? {}) as Record<string, unknown>;
    const riskLevelRaw = `${item.riskLevel ?? ''}`.trim().toUpperCase();
    const riskLevel = (
      ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'].includes(riskLevelRaw)
        ? riskLevelRaw
        : 'LOW'
    ) as AmlFlaggedAccount['riskLevel'];

    return {
      accountId: `${item.accountId ?? ''}`.trim(),
      riskLevel,
      isMoneyLaundering: item.isMoneyLaundering === true,
      maxFraudProbability: toNumber(item.maxFraudProbability, 0),
      avgFraudProbability: toNumber(item.avgFraudProbability, 0),
      totalTransactions: toNumber(item.totalTransactions, 0),
      flaggedTransactions: toNumber(item.flaggedTransactions, 0),
      flagRatePct: toNumber(item.flagRatePct, 0),
      totalSent: toNumber(item.totalSent, 0),
      totalReceived: toNumber(item.totalReceived, 0),
      isMuleAccount: item.isMuleAccount === true,
    };
  }

  private normalizeTransaction(value: unknown): AmlAccountTransaction {
    const item = (value ?? {}) as Record<string, unknown>;
    const directionRaw = `${item.direction ?? ''}`.trim().toLowerCase();
    return {
      transactionId: `${item.transactionId ?? ''}`.trim(),
      timestamp: `${item.timestamp ?? ''}`.trim(),
      direction: directionRaw === 'inbound' ? 'inbound' : 'outbound',
      counterpartyAccount: `${item.counterpartyAccount ?? ''}`.trim(),
      amountPaid: toNumber(item.amountPaid, 0),
      amountReceived: toNumber(item.amountReceived, 0),
      paymentFormat: `${item.paymentFormat ?? ''}`.trim(),
      // Monitoring dashboard standardizes monetary display to VND.
      paymentCurrency: 'VND',
      fraudProbability: toNumber(item.fraudProbability, 0),
      riskLevel: `${item.riskLevel ?? ''}`.trim(),
      isFlagged: item.isFlagged === true,
    };
  }

  private unconfiguredOverview(): AmlOverview {
    return {
      configured: false,
      status: 'not_started',
      generatedAt: null,
      lookbackHours: 24,
      totalTransactions: 0,
      flaggedTransactions: 0,
      flaggedAccounts: 0,
      scanDurationMs: null,
      error: 'AML service is not configured.',
      accounts: [],
    };
  }

  private readNumber(
    key: string,
    fallback: number,
    min: number,
    max: number,
  ) {
    const parsed = Number(this.configService.get<string>(key, `${fallback}`));
    if (!Number.isFinite(parsed)) {
      return fallback;
    }

    return Math.min(max, Math.max(min, Math.floor(parsed)));
  }
}

function toNumber(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toNullableString(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
