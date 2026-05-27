import { BadRequestException, Controller, Logger } from '@nestjs/common';
import { GrpcMethod } from '@nestjs/microservices';
import { status as GrpcStatus } from '@grpc/grpc-js';
import { RpcException } from '@nestjs/microservices';
import { TransactionsService } from './transactions.service';
import { AtoRiskService } from './ato-risk.service';

@Controller()
export class TransactionsGrpcController {
  private readonly logger = new Logger(TransactionsGrpcController.name);

  constructor(
    private readonly txService: TransactionsService,
    private readonly atoRisk: AtoRiskService,
  ) {}

  @GrpcMethod('TransactionService', 'AssessTransferRisk')
  async assessTransferRisk(data: any) {
    const risk = await this.wrapGrpc(() => this.atoRisk.assessTransferRisk(data));
    return {
      requiresStepUp: risk.requiresStepUp,
      reasons: risk.reasons,
      verdict: risk.verdict,
      probability: risk.probability,
      threshold: risk.threshold,
      modelVersion: risk.modelVersion,
      modelType: risk.modelType,
      senderBalance: risk.senderBalance,
      destinationTxCount: risk.destinationTxCount,
      destinationAvgAmount: risk.destinationAvgAmount,
      destinationUniqueSenders: risk.destinationUniqueSenders,
    };
  }

  @GrpcMethod('TransactionService', 'CreateTransfer')
  async createTransfer(data: any) {
    this.logger.log(
      `CreateTransfer request idempotencyKey=${data?.idempotencyKey ?? ''} from=${data?.fromUserId ?? ''} to=${data?.toUserId ?? ''} amount=${data?.amount ?? ''}`,
    );
    return this.wrapGrpc(() => this.txService.createTransfer(data));
  }

  @GrpcMethod('TransactionService', 'CreateFundingSource')
  async createFundingSource(data: any) {
    const item = await this.wrapGrpc(() => this.txService.createFundingSource(data));
    return {
      fundingSourceId: item.id,
      userId: item.userId,
      provider: item.provider,
      accountRefMasked: item.accountRefMasked,
      status: item.status,
      displayName: item.displayName ?? '',
      createdAt: item.createdAt?.toISOString() ?? '',
      updatedAt: item.updatedAt?.toISOString() ?? '',
    };
  }

  @GrpcMethod('TransactionService', 'ListFundingSources')
  async listFundingSources(data: any) {
    const items = await this.wrapGrpc(() => this.txService.listFundingSources(data.userId));
    return {
      items: items.map((item) => ({
        fundingSourceId: item.id,
        userId: item.userId,
        provider: item.provider,
        accountRefMasked: item.accountRefMasked,
        status: item.status,
        displayName: item.displayName ?? '',
        createdAt: item.createdAt?.toISOString() ?? '',
        updatedAt: item.updatedAt?.toISOString() ?? '',
      })),
    };
  }

  @GrpcMethod('TransactionService', 'CreateTopupIntent')
  async createTopupIntent(data: any) {
    return this.wrapGrpc(() => this.txService.createTopupIntent(data));
  }

  @GrpcMethod('TransactionService', 'CreateWithdrawalRequest')
  async createWithdrawalRequest(data: any) {
    return this.wrapGrpc(() => this.txService.createWithdrawalRequest(data));
  }

  @GrpcMethod('TransactionService', 'CreateWallet')
  async createWallet(data: any) {
    const wallet = await this.wrapGrpc(() => this.txService.createWallet(
      data.userId,
      data.currency || 'VND',
    ));
    return {
      walletId: wallet.id,
      userId: wallet.userId,
      currency: wallet.currency,
      balance: wallet.balance,
      status: wallet.status,
    };
  }

  @GrpcMethod('TransactionService', 'GetWallet')
  async getWallet(data: any) {
    const wallet = await this.wrapGrpc(() => this.txService.getWallet(
      data.userId,
      data.currency || 'VND',
    ));
    if (!wallet) {
      return {
        walletId: '',
        userId: data.userId,
        currency: data.currency || 'VND',
        balance: 0,
        status: 'NOT_FOUND',
      };
    }
    return {
      walletId: wallet.id,
      userId: wallet.userId,
      currency: wallet.currency,
      balance: wallet.balance,
      status: wallet.status,
    };
  }

  @GrpcMethod('TransactionService', 'GetTransaction')
  async getTransaction(data: any) {
    const tx = await this.wrapGrpc(() => this.txService.getTransaction(data.transactionId));
    if (!tx) {
      return {
        transactionId: '',
        status: 'NOT_FOUND',
        errorMessage: 'Transaction not found',
      };
    }
    return {
      transactionId: tx.id,
      idempotencyKey: tx.idempotencyKey,
      type: tx.type,
      status: tx.status,
      settlementStatus: tx.settlementStatus,
      chainStatus: tx.chainStatus,
      fromUserId: tx.fromUserId,
      toUserId: tx.toUserId ?? '',
      amount: tx.amount,
      currency: tx.currency,
      memo: tx.memo ?? '',
      isExternal: tx.isExternal,
      externalPartner: tx.externalPartner ?? '',
      externalAccountNo: tx.externalAccountNo ?? '',
      externalRef: tx.externalRef ?? '',
      chainTxId: tx.chainTxId ?? '',
      receiptJson: tx.receiptJson ?? '',
      errorCode: tx.errorCode ?? '',
      errorMessage: tx.errorMessage ?? '',
      createdAt: tx.createdAt?.toISOString() ?? '',
      updatedAt: tx.updatedAt?.toISOString() ?? '',
    };
  }

  @GrpcMethod('TransactionService', 'ListUserTransactions')
  async listUserTransactions(data: any) {
    const txs = await this.wrapGrpc(() => this.txService.listUserTransactions(
      data.userId,
      data.limit || 30,
      data.offset || 0,
      data.includeFailed ?? false,
    ));
    return {
      items: txs.map((tx) => ({
        transactionId: tx.id,
        idempotencyKey: tx.idempotencyKey,
        type: tx.type,
        status: tx.status,
        settlementStatus: tx.settlementStatus,
        chainStatus: tx.chainStatus,
        fromUserId: tx.fromUserId,
        toUserId: tx.toUserId ?? '',
        amount: tx.amount,
        currency: tx.currency,
        memo: tx.memo ?? '',
        isExternal: tx.isExternal,
        externalPartner: tx.externalPartner ?? '',
        externalAccountNo: tx.externalAccountNo ?? '',
        externalRef: tx.externalRef ?? '',
        chainTxId: tx.chainTxId ?? '',
        receiptJson: tx.receiptJson ?? '',
        errorCode: tx.errorCode ?? '',
        errorMessage: tx.errorMessage ?? '',
        createdAt: tx.createdAt?.toISOString() ?? '',
        updatedAt: tx.updatedAt?.toISOString() ?? '',
      })),
    };
  }

  // ── Settlement RPCs ───────────────────────────────────

  @GrpcMethod('TransactionService', 'ListSettlementCandidates')
  async listSettlementCandidates(data: any) {
    const txs = await this.wrapGrpc(() => this.txService.listSettlementCandidates(
      data.limit || 100,
    ));
    return {
      items: txs.map((tx) => ({
        transactionId: tx.id,
          type: tx.type,
        status: tx.status,
        settlementStatus: tx.settlementStatus,
        fromUserId: tx.fromUserId,
        toUserId: tx.toUserId ?? '',
        amount: tx.amount,
        currency: tx.currency,
        isExternal: tx.isExternal,
        externalPartner: tx.externalPartner ?? '',
        externalAccountNo: tx.externalAccountNo ?? '',
        externalRef: tx.externalRef ?? '',
        createdAt: tx.createdAt?.toISOString() ?? '',
      })),
    };
  }

  @GrpcMethod('TransactionService', 'MarkSettlement')
  async markSettlement(data: any) {
    const success = await this.wrapGrpc(() => this.txService.markSettlement(
      data.transactionId,
      data.settlementStatus,
      data.note,
    ));
    return { success };
  }

  @GrpcMethod('TransactionService', 'ReconcileWallets')
  async reconcileWallets(data: any) {
    const result = await this.wrapGrpc(() => this.txService.reconcileWallets(
      data.limit || 500,
      data.autoFix ?? false,
    ));
    return {
      scanned: result.scanned,
      mismatches: result.mismatches,
      fixed: result.fixed,
      items: result.items.map((item) => ({
        walletId: item.walletId,
        userId: item.userId,
        currency: item.currency,
        currentBalance: item.currentBalance,
        expectedBalance: item.expectedBalance,
      })),
    };
  }

  private async wrapGrpc<T>(fn: () => Promise<T>): Promise<T> {
    try {
      return await fn();
    } catch (error: any) {
      if (error instanceof RpcException) {
        throw error;
      }
      if (error instanceof BadRequestException) {
        throw new RpcException({
          code: GrpcStatus.INVALID_ARGUMENT,
          message: error.message || 'Bad request',
        });
      }
      throw new RpcException({
        code: GrpcStatus.UNKNOWN,
        message: error?.message || 'Internal server error',
      });
    }
  }
}
