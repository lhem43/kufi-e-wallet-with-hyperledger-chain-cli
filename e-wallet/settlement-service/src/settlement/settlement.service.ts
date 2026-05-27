import {
  Inject,
  Injectable,
  Logger,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron } from '@nestjs/schedule';
import { ClientGrpc } from '@nestjs/microservices';
import { firstValueFrom, timeout } from 'rxjs';

const DEFAULT_SETTLEMENT_POLL_CRON = '*/3 * * * * *';
const SETTLEMENT_POLL_CRON =
  `${process.env.SETTLEMENT_POLL_CRON ?? ''}`.trim() ||
  DEFAULT_SETTLEMENT_POLL_CRON;

@Injectable()
export class SettlementService implements OnModuleInit {
  private readonly logger = new Logger(SettlementService.name);
  private txService: any;
  private outsideService: any;
  private running = false;

  constructor(
    private readonly cfg: ConfigService,
    @Inject('TRANSACTION_PACKAGE')
    private readonly transactionClient: ClientGrpc,
    @Inject('OUTSIDE_PAYMENT_PACKAGE')
    private readonly outsidePaymentClient: ClientGrpc,
  ) {}

  onModuleInit() {
    this.txService =
      this.transactionClient.getService('TransactionService');
    this.outsideService =
      this.outsidePaymentClient.getService('OutsidePaymentService');
  }

  @Cron(SETTLEMENT_POLL_CRON)
  async runSettlementJob() {
    if (this.running) return;
    this.running = true;
    try {
      const result = await this.runSettlementCycle();
      if (
        result.settlement.scanned > 0 ||
        result.reconcile.mismatches > 0 ||
        result.reconcile.fixed > 0
      ) {
        this.logger.log(
          `Settlement cycle scanned=${result.settlement.scanned} settled=${result.settlement.settled} failed=${result.settlement.failed} mismatches=${result.reconcile.mismatches} fixed=${result.reconcile.fixed}`,
        );
      }
    } catch (error: any) {
      this.logger.error(
        `Settlement job failed: ${error?.message ?? error}`,
      );
    } finally {
      this.running = false;
    }
  }

  async runSettlementCycle(options?: {
    settlementLimit?: number;
    reconcileLimit?: number;
    autoFixBalances?: boolean;
  }) {
    const settlement = await this.reconcilePendingTransfers(
      options?.settlementLimit,
    );
    const reconcile = await this.reconcileWalletBalances(
      options?.reconcileLimit,
      options?.autoFixBalances,
    );
    return {
      settlement,
      reconcile,
      executedAt: new Date().toISOString(),
    };
  }

  private async reconcilePendingTransfers(limitOverride?: number) {
    if (!this.txService || !this.outsideService) {
      return { scanned: 0, settled: 0, failed: 0, skipped: 0, errors: 0 };
    }

    const rpcTimeoutMs = Number(
      this.cfg.get('SETTLEMENT_RPC_TIMEOUT_MS') ?? 5000,
    );
    const limit = Math.max(
      1,
      Math.min(
        Number(
          limitOverride ?? this.cfg.get('SETTLEMENT_BATCH_SIZE') ?? 100,
        ),
        1000,
      ),
    );

    const candidates: any = await firstValueFrom(
      this.txService
        .listSettlementCandidates({ limit })
        .pipe(timeout(rpcTimeoutMs)),
    );

    const items = candidates.items || [];
    if (!items.length) {
      return { scanned: 0, settled: 0, failed: 0, skipped: 0, errors: 0 };
    }

    const concurrency = Math.max(
      1,
      Math.min(
        Number(this.cfg.get('SETTLEMENT_CONCURRENCY') ?? 10),
        100,
      ),
    );

    const stats = {
      scanned: items.length,
      settled: 0,
      failed: 0,
      skipped: 0,
      errors: 0,
    };

    for (let index = 0; index < items.length; index += concurrency) {
      const chunk = items.slice(index, index + concurrency);
      const results = await Promise.allSettled(
        chunk.map((item: any) =>
          this.processCandidate(item, rpcTimeoutMs),
        ),
      );
      for (const result of results) {
        if (result.status === 'fulfilled') {
          if (result.value === 'SETTLED') stats.settled += 1;
          else if (result.value === 'FAILED') stats.failed += 1;
          else if (result.value === 'SKIPPED') stats.skipped += 1;
        } else {
          stats.errors += 1;
        }
      }
    }

    return stats;
  }

  private async processCandidate(
    item: any,
    rpcTimeoutMs: number,
  ): Promise<'SETTLED' | 'FAILED' | 'SKIPPED'> {
    if (!this.txService || !this.outsideService) return 'SKIPPED';

    if (!item.externalPartner || !item.externalRef) {
      await firstValueFrom(
        this.txService
          .markSettlement({
            transactionId: item.transactionId,
            settlementStatus: 'FAILED',
            note: 'Missing external references',
          })
          .pipe(timeout(rpcTimeoutMs)),
      );
      return 'FAILED';
    }

    try {
      const statusResult: any = await firstValueFrom(
        this.outsideService
          .checkTransfer({
            partnerCode: item.externalPartner,
            partnerRef: item.externalRef,
          })
          .pipe(timeout(rpcTimeoutMs)),
      );

      if (statusResult.status === 'SETTLED') {
        await firstValueFrom(
          this.txService
            .markSettlement({
              transactionId: item.transactionId,
              settlementStatus: 'SETTLED',
              note: statusResult.partnerMessage,
            })
            .pipe(timeout(rpcTimeoutMs)),
        );
        return 'SETTLED';
      }

      if (statusResult.status === 'FAILED') {
        await firstValueFrom(
          this.txService
            .markSettlement({
              transactionId: item.transactionId,
              settlementStatus: 'FAILED',
              note: statusResult.partnerMessage,
            })
            .pipe(timeout(rpcTimeoutMs)),
        );
        return 'FAILED';
      }

      return 'SKIPPED';
    } catch (error: any) {
      this.logger.error(
        `Settlement candidate failed tx=${item.transactionId}: ${error?.message ?? error}`,
      );
      return 'SKIPPED';
    }
  }

  private async reconcileWalletBalances(
    limitOverride?: number,
    autoFixOverride?: boolean,
  ) {
    if (!this.txService) {
      return { scanned: 0, mismatches: 0, fixed: 0, items: [] };
    }

    const rpcTimeoutMs = Number(
      this.cfg.get('SETTLEMENT_RPC_TIMEOUT_MS') ?? 5000,
    );
    const reconcileLimit = Math.max(
      1,
      Math.min(
        Number(
          limitOverride ??
            this.cfg.get('SETTLEMENT_RECONCILE_LIMIT') ??
            500,
        ),
        5000,
      ),
    );

    const autoFix =
      typeof autoFixOverride === 'boolean'
        ? autoFixOverride
        : String(
            this.cfg.get('SETTLEMENT_RECONCILE_AUTOFIX') ?? 'false',
          ).toLowerCase() === 'true';

    return firstValueFrom(
      this.txService
        .reconcileWallets({ limit: reconcileLimit, autoFix })
        .pipe(timeout(rpcTimeoutMs)),
    ) as Promise<{ scanned: number; mismatches: number; fixed: number; items: any[] }>;
  }
}
