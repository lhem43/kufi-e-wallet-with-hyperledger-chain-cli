import {
	BadRequestException,
	Inject,
	Injectable,
	Logger,
	OnModuleDestroy,
	OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { ClientGrpc } from '@nestjs/microservices';
import { createHash, randomUUID } from 'crypto';
import { firstValueFrom, Observable, timeout } from 'rxjs';
import { DataSource, EntityManager, QueryFailedError, Repository } from 'typeorm';

import { TransactionOutboxService } from '../events/transaction-outbox.service';
import { Wallet, WalletStatus } from '../wallets/entities/wallet.entity';
import {
	ChainStatus,
	SettlementStatus,
	TransactionEntity,
	TransactionStatus,
	TransactionType,
} from './entities/transaction.entity';
import { FundingSource, FundingSourceStatus } from './entities/funding-source.entity';
import { LedgerDirection, LedgerEntry } from './entities/ledger-entry.entity';

/* ── gRPC service interfaces ────────────────────────────── */

interface InitiateTransferRequest {
	transactionId: string;
	partnerCode: string;
	accountNo: string;
	amount: number;
	currency: string;
	note?: string;
	transferType?: string;
}

interface InitiateTransferResponse {
	status: string;
	partnerRef: string;
	partnerMessage: string;
}

interface OutsidePaymentGrpcService {
	initiateTransfer(req: InitiateTransferRequest): Observable<InitiateTransferResponse>;
}

interface AnchorTransferRequest {
	transactionId: string;
	fromUserId: string;
	toUserId: string;
	amount: number;
	memo: string;
	internalRef: string;
	settlementRef: string;
	timestamp: string;
	nonce: string;
	idempotencyKey: string;
	riskFlag: string;
}

interface AnchorTransferResponse {
	chainStatus: string;
	txId: string;
	blockNumber: number;
	commitmentHash: string;
	receiptJson: string;
}

interface ChainGrpcService {
	anchorTransfer(req: AnchorTransferRequest): Observable<AnchorTransferResponse>;
	getReceipt(req: { txId: string }): Observable<AnchorTransferResponse>;
}

interface GrpcInt64 {
	low: number;
	high: number;
	unsigned: boolean;
}

/* ── Transfer request ───────────────────────────────────── */

interface CreateTransferRequest {
	idempotencyKey: string;
	requestingUserId: string;
	fromUserId: string;
	toUserId: string;
	amount: number;
	currency: string;
	memo?: string;
	otpCode: string;
	isExternal?: boolean;
	externalPartner?: string;
	externalAccountNo?: string;
}

interface CreateFundingSourceRequest {
	userId: string;
	provider: string;
	accountRef: string;
	providerToken?: string;
	displayName?: string;
}

interface CreateTopupIntentRequest {
	idempotencyKey: string;
	userId: string;
	fundingSourceId: string;
	amount: number;
	currency: string;
	memo?: string;
}

interface CreateWithdrawalRequest {
	idempotencyKey: string;
	userId: string;
	fundingSourceId: string;
	amount: number;
	currency: string;
	memo?: string;
	simulateFailure?: boolean;
}

@Injectable()
export class TransactionsService implements OnModuleInit, OnModuleDestroy {
	private readonly logger = new Logger(TransactionsService.name);
	private outsidePaymentSvc!: OutsidePaymentGrpcService;
	private chainSvc!: ChainGrpcService;
	private readonly chainRiskHighAmount: number;
	private readonly chainAsyncEnabled: boolean;
	private readonly chainAsyncPollIntervalMs: number;
	private readonly chainAsyncBatchSize: number;
	private readonly chainAsyncWorkers: number;
	private readonly chainAsyncLeaseMs: number;
	private readonly chainAsyncInitialBackoffMs: number;
	private readonly chainAsyncMaxBackoffMs: number;
	private readonly chainAsyncMaxRetries: number;
	private readonly chainExternalSourceUserId: string;
	private readonly chainExternalSinkUserId: string;
	private chainAsyncTimer: NodeJS.Timeout | null = null;
	private chainAsyncTickRunning = false;

	constructor(
		private readonly cfg: ConfigService,
		private readonly dataSource: DataSource,
		@InjectRepository(Wallet)
		private readonly walletRepo: Repository<Wallet>,
		@InjectRepository(TransactionEntity)
		private readonly txRepo: Repository<TransactionEntity>,
		@InjectRepository(LedgerEntry)
		private readonly ledgerRepo: Repository<LedgerEntry>,
		@InjectRepository(FundingSource)
		private readonly fundingSourceRepo: Repository<FundingSource>,
		private readonly outboxService: TransactionOutboxService,
		@Inject('OUTSIDE_PAYMENT_PACKAGE')
		private readonly outsidePaymentClient: ClientGrpc,
		@Inject('CHAIN_PACKAGE')
		private readonly chainClient: ClientGrpc,
	) {
		const raw = this.cfg.get<string>('CHAIN_RISK_HIGH_AMOUNT');
		if (raw == null || raw === '') {
			this.logger.warn(
				'CHAIN_RISK_HIGH_AMOUNT is not configured — defaulting to 50,000,000 VND',
			);
		}
		this.chainRiskHighAmount = Number(raw ?? 50_000_000);
		this.chainAsyncEnabled =
			String(this.cfg.get<string>('CHAIN_ASYNC_ENABLED') ?? 'true').toLowerCase() !==
			'false';
		this.chainAsyncPollIntervalMs = this.toInt(
			this.cfg.get<string>('CHAIN_ASYNC_POLL_INTERVAL_MS'),
			3000,
		);
		this.chainAsyncBatchSize = this.toInt(
			this.cfg.get<string>('CHAIN_ASYNC_BATCH_SIZE'),
			200,
		);
		this.chainAsyncWorkers = this.toInt(
			this.cfg.get<string>('CHAIN_ASYNC_WORKERS'),
			10,
		);
		this.chainAsyncLeaseMs = this.toInt(
			this.cfg.get<string>('CHAIN_ASYNC_LEASE_MS'),
			30000,
		);
		this.chainAsyncInitialBackoffMs = this.toInt(
			this.cfg.get<string>('CHAIN_ASYNC_INITIAL_BACKOFF_MS'),
			5000,
		);
		this.chainAsyncMaxBackoffMs = this.toInt(
			this.cfg.get<string>('CHAIN_ASYNC_MAX_BACKOFF_MS'),
			300000,
		);
		this.chainAsyncMaxRetries = Math.max(
			0,
			this.toInt(this.cfg.get<string>('CHAIN_ASYNC_MAX_RETRIES'), 0),
		);
		this.chainExternalSourceUserId =
			(this.cfg.get<string>('CHAIN_EXTERNAL_SOURCE_USER_ID') || '').trim() ||
			'00000000-0000-0000-0000-000000000001';
		this.chainExternalSinkUserId =
			(this.cfg.get<string>('CHAIN_EXTERNAL_SINK_USER_ID') || '').trim() ||
			'00000000-0000-0000-0000-000000000002';
	}

	onModuleInit() {
		this.outsidePaymentSvc =
			this.outsidePaymentClient.getService<OutsidePaymentGrpcService>(
				'OutsidePaymentService',
			);
		this.chainSvc = this.chainClient.getService<ChainGrpcService>('ChainService');

		if (this.chainAsyncEnabled) {
			this.chainAsyncTimer = setInterval(() => {
				void this.runChainAsyncTick();
			}, this.chainAsyncPollIntervalMs);
			void this.runChainAsyncTick();
			this.logger.log(
				`Chain async worker started (poll=${this.chainAsyncPollIntervalMs}ms, batch=${this.chainAsyncBatchSize}, workers=${this.chainAsyncWorkers})`,
			);
		} else {
			this.logger.warn('Chain async worker is disabled via CHAIN_ASYNC_ENABLED=false');
		}
	}

	onModuleDestroy() {
		if (this.chainAsyncTimer) {
			clearInterval(this.chainAsyncTimer);
			this.chainAsyncTimer = null;
		}
	}

	// ── Wallet ────────────────────────────────────────────────────

	async createWallet(userId: string, currencyRaw: string): Promise<Wallet> {
		const currency = this.normalizeCurrency(currencyRaw);

		let wallet = await this.walletRepo.findOne({
			where: { userId, currency },
		});
		if (wallet) return wallet;

		wallet = this.walletRepo.create({
			userId,
			currency,
			balance: 0,
			status: WalletStatus.ACTIVE,
		});

		try {
			return await this.walletRepo.save(wallet);
		} catch (error) {
			if (error instanceof QueryFailedError) {
				const existing = await this.walletRepo.findOne({
					where: { userId, currency },
				});
				if (existing) return existing;
			}
			throw error;
		}
	}

	async getWallet(userId: string, currencyRaw: string): Promise<Wallet | null> {
		const currency = this.normalizeCurrency(currencyRaw);
		return this.walletRepo.findOne({ where: { userId, currency } });
	}

	async createFundingSource(request: CreateFundingSourceRequest): Promise<FundingSource> {
		const normalized = this.validateCreateFundingSource(request);
		const accountRefHash = this.hashAccountRef(
			normalized.provider,
			normalized.accountRef,
		);

		const existing = await this.fundingSourceRepo.findOne({
			where: {
				userId: normalized.userId,
				provider: normalized.provider,
				accountRefHash,
			},
		});
		if (existing) {
			return existing;
		}

		const entity = this.fundingSourceRepo.create({
			userId: normalized.userId,
			provider: normalized.provider,
			accountRefMasked: this.maskAccountRef(normalized.accountRef),
			accountRefHash,
			providerToken: normalized.providerToken || null,
			displayName: normalized.displayName || null,
			status: FundingSourceStatus.ACTIVE,
		});

		try {
			return await this.fundingSourceRepo.save(entity);
		} catch (error) {
			if (error instanceof QueryFailedError) {
				const duplicate = await this.fundingSourceRepo.findOne({
					where: {
						userId: normalized.userId,
						provider: normalized.provider,
						accountRefHash,
					},
				});
				if (duplicate) return duplicate;
			}
			throw error;
		}
	}

	async listFundingSources(userId: string): Promise<FundingSource[]> {
		const normalizedUserId = (userId || '').trim();
		if (!normalizedUserId) {
			throw new BadRequestException('userId is required');
		}
		return this.fundingSourceRepo.find({
			where: { userId: normalizedUserId },
			order: { createdAt: 'DESC' },
		});
	}

	async createTopupIntent(request: CreateTopupIntentRequest) {
		const req = this.validateCreateTopupIntent(request);
		const fundingSource = await this.getActiveFundingSource(req.userId, req.fundingSourceId);

		const existing = await this.txRepo.findOne({
			where: { idempotencyKey: req.idempotencyKey },
		});
		if (existing) {
			const wallet = await this.getWallet(req.userId, req.currency);
			return this.mapTransferResponse(existing, wallet?.balance ?? 0, wallet?.balance ?? 0);
		}

		const persisted = await this.persistTopupIntent(req, fundingSource);
		let tx = persisted.transaction;
		tx = await this.submitOutsideTransfer(tx);
		if (tx.status === TransactionStatus.FAILED) {
			tx = await this.anchorToChain(tx);
			await this.enqueueTransactionEvent(tx);
			return this.mapTransferResponse(tx, persisted.walletBalance, persisted.walletBalance);
		}

		// External successful submission remains pending until settlement finalizes.
		// Chain anchoring is processed only after settlement becomes SETTLED/FAILED.
		await this.enqueueTransactionEvent(tx);
		return this.mapTransferResponse(tx, persisted.walletBalance, persisted.walletBalance);
	}

	async createWithdrawalRequest(request: CreateWithdrawalRequest) {
		const req = this.validateCreateWithdrawalRequest(request);
		const fundingSource = await this.getActiveFundingSource(req.userId, req.fundingSourceId);

		const existing = await this.txRepo.findOne({
			where: { idempotencyKey: req.idempotencyKey },
		});
		if (existing) {
			const wallet = await this.getWallet(req.userId, req.currency);
			return this.mapTransferResponse(existing, wallet?.balance ?? 0, 0);
		}

		const persisted = await this.persistWithdrawalRequest(req, fundingSource);
		let tx = persisted.transaction;

		if (req.simulateFailure) {
			await this.rollbackWithdrawalDebit(tx, 'WITHDRAWAL_SIMULATED_FAILURE');
			tx.status = TransactionStatus.FAILED;
			tx.settlementStatus = SettlementStatus.FAILED;
			tx.errorCode = 'WITHDRAWAL_SIMULATED_FAILURE';
			tx.errorMessage = 'Withdrawal failure simulated by request';
			tx = await this.txRepo.save(tx);
			tx = await this.anchorToChain(tx);
			await this.enqueueTransactionEvent(tx);
			return this.mapTransferResponse(tx, persisted.walletBalance + req.amount, 0);
		}

		tx = await this.submitOutsideTransfer(tx);
		if (tx.status === TransactionStatus.FAILED) {
			await this.rollbackWithdrawalDebit(tx, tx.errorCode ?? 'WITHDRAWAL_FAILED');
			tx = await this.anchorToChain(tx);
			await this.enqueueTransactionEvent(tx);
			return this.mapTransferResponse(tx, persisted.walletBalance + req.amount, 0);
		}

		// External successful submission remains pending until settlement finalizes.
		// Chain anchoring is processed only after settlement becomes SETTLED/FAILED.
		await this.enqueueTransactionEvent(tx);
		return this.mapTransferResponse(tx, persisted.walletBalance, 0);
	}

	// ── Transfer (main flow) ──────────────────────────────────────

	async createTransfer(req: CreateTransferRequest) {
		const normalizedReq = this.validateCreateTransfer(req);

		// Idempotency check
		const existing = await this.txRepo.findOne({
			where: { idempotencyKey: normalizedReq.idempotencyKey },
		});
		if (existing) {
			const senderWallet = await this.getWallet(
				normalizedReq.fromUserId,
				normalizedReq.currency,
			);
			const receiverWallet = normalizedReq.toUserId
				? await this.getWallet(normalizedReq.toUserId, normalizedReq.currency)
				: null;
			return this.mapTransferResponse(
				existing,
				senderWallet?.balance ?? 0,
				receiverWallet?.balance ?? 0,
			);
		}

		// Persist within a serialisable DB transaction
		const persisted = await this.persistTransfer(normalizedReq);
		let tx = persisted.transaction;

		// External partner submission
		if (tx.isExternal) {
			tx = await this.submitOutsideTransfer(tx);
		}

		// Do not block transfer API on chain anchoring. Receipt screen will poll
		// and reflect chain/business state changes while async worker processes it.
		if (!tx.isExternal && tx.status !== TransactionStatus.FAILED) {
			tx.chainNextAttemptAt = new Date();
			tx = await this.txRepo.save(tx);
		}

		await this.enqueueTransactionEvent(tx);

		return this.mapTransferResponse(tx, persisted.senderBalance, persisted.receiverBalance);
	}

	// ── Query ─────────────────────────────────────────────────────

	async getTransaction(transactionId: string): Promise<TransactionEntity | null> {
		const tx = await this.txRepo.findOne({ where: { id: transactionId } });
		if (!tx) {
			return null;
		}

		if (
			tx.chainStatus === ChainStatus.ANCHORED &&
			this.shouldRefreshReceiptTransparency(tx.receiptJson)
		) {
			return this.refreshAnchoredReceiptTransparency(tx);
		}

		return tx;
	}

	async listUserTransactions(
		userId: string,
		limit = 30,
		offset = 0,
		includeFailed = false,
	): Promise<TransactionEntity[]> {
		const take = Math.max(1, Math.min(limit, 200));
		const skip = Math.max(0, offset);

		const qb = this.txRepo
			.createQueryBuilder('tx')
			.where('tx.fromUserId = :userId OR tx.toUserId = :userId', { userId })
			.orderBy('tx.createdAt', 'DESC')
			.take(take)
			.skip(skip);

		if (!includeFailed) {
			qb.andWhere('tx.status != :failedStatus', {
				failedStatus: TransactionStatus.FAILED,
			})
				.andWhere('tx.chainStatus != :failedChain', {
					failedChain: ChainStatus.FAILED,
				})
				.andWhere('tx.settlementStatus != :failedSettlement', {
					failedSettlement: SettlementStatus.FAILED,
				});
		}
		return qb.getMany();
	}

	// ── Settlement helpers ────────────────────────────────────────

	async listSettlementCandidates(limit = 100): Promise<TransactionEntity[]> {
		const take = Math.max(1, Math.min(limit, 500));
		return this.txRepo.find({
			where: {
				isExternal: true,
				settlementStatus: SettlementStatus.PENDING,
			},
			order: { createdAt: 'ASC' },
			take,
		});
	}

	async markSettlement(
		transactionId: string,
		settlementStatus: string,
		note?: string,
	): Promise<boolean> {
		const normalizedStatus = (settlementStatus || '').trim().toUpperCase();
		if (normalizedStatus !== 'SETTLED' && normalizedStatus !== 'FAILED') {
			throw new BadRequestException('Unsupported settlement status');
		}

		const qr = this.dataSource.createQueryRunner();
		await qr.connect();
		await qr.startTransaction();

		let saved: TransactionEntity | null = null;
		try {
			const tx = await qr.manager
				.getRepository(TransactionEntity)
				.createQueryBuilder('tx')
				.setLock('pessimistic_write')
				.where('tx.id = :transactionId', { transactionId })
				.getOne();
			if (!tx) {
				await qr.rollbackTransaction();
				return false;
			}

			if (normalizedStatus === 'SETTLED') {
				if (tx.type === TransactionType.DEPOSIT) {
					await this.applyDepositCreditIfNeeded(qr.manager, tx);
				}
				tx.settlementStatus = SettlementStatus.SETTLED;
				// Business completion follows internal settlement; chain anchoring is asynchronous.
				tx.status = TransactionStatus.COMPLETED;
				if (tx.chainStatus === ChainStatus.PENDING) {
					tx.chainNextAttemptAt = new Date();
				}
				tx.errorCode = null;
				tx.errorMessage = null;
			} else {
				if (tx.type === TransactionType.WITHDRAWAL) {
					await this.rollbackWithdrawalDebitUsingManager(
						qr.manager,
						tx,
						'SETTLEMENT_FAILED',
					);
				}
				tx.settlementStatus = SettlementStatus.FAILED;
				tx.status = TransactionStatus.FAILED;
				if (tx.chainStatus === ChainStatus.PENDING) {
					tx.chainNextAttemptAt = new Date();
				}
				tx.errorCode = 'SETTLEMENT_FAILED';
				tx.errorMessage = note || 'Settlement failed';
			}

			saved = await qr.manager.save(tx);
			await this.enqueueTransactionEvent(saved, qr.manager);
			await qr.commitTransaction();
		} catch (error) {
			await qr.rollbackTransaction();
			throw error;
		} finally {
			await qr.release();
		}

		return true;
	}

	// ── Wallet reconciliation ─────────────────────────────────────

	async reconcileWallets(limit = 500, autoFix = false) {
		const take = Math.max(1, Math.min(limit, 5000));
		const wallets = await this.walletRepo.find({
			order: { createdAt: 'ASC' },
			take,
		});

		const items: Array<{
			walletId: string;
			userId: string;
			currency: string;
			currentBalance: number;
			expectedBalance: number;
			openingBalance: number;
			ledgerDelta: number;
		}> = [];
		let fixed = 0;

		for (const wallet of wallets) {
			const firstEntry = await this.ledgerRepo.findOne({
				where: { walletId: wallet.id },
				order: { id: 'ASC' },
			});
			if (!firstEntry) continue;

			const rawDelta: { delta: string } | undefined = await this.ledgerRepo
				.createQueryBuilder('entry')
				.select(
					"COALESCE(SUM(CASE WHEN entry.direction = 'CREDIT' THEN entry.amount ELSE -entry.amount END), 0)",
					'delta',
				)
				.where('entry.walletId = :walletId', { walletId: wallet.id })
				.getRawOne();

			const ledgerDelta = Number(rawDelta?.delta ?? 0);
			const openingBalance = Number(firstEntry.balanceBefore ?? 0);
			const expectedBalance = openingBalance + ledgerDelta;
			const currentBalance = Number(wallet.balance ?? 0);

			if (expectedBalance === currentBalance) continue;

			items.push({
				walletId: wallet.id,
				userId: wallet.userId,
				currency: wallet.currency,
				currentBalance,
				expectedBalance,
				openingBalance,
				ledgerDelta,
			});

			if (autoFix) {
				wallet.balance = expectedBalance;
				await this.walletRepo.save(wallet);
				fixed += 1;
			}
		}

		return { scanned: wallets.length, mismatches: items.length, fixed, items };
	}

	// ─────────────────────── Private ──────────────────────────────

	private async persistTransfer(req: CreateTransferRequest) {
		const qr = this.dataSource.createQueryRunner();
		await qr.connect();
		await qr.startTransaction();

		try {
			// Double-check idempotency inside the transaction
			const dup = await qr.manager.findOne(TransactionEntity, {
				where: { idempotencyKey: req.idempotencyKey },
			});
			if (dup) {
				const sender = await qr.manager.findOne(Wallet, {
					where: { userId: req.fromUserId, currency: req.currency },
				});
				const receiver = req.toUserId
					? await qr.manager.findOne(Wallet, {
							where: { userId: req.toUserId, currency: req.currency },
						})
					: null;
				await qr.commitTransaction();
				return {
					transaction: dup,
					senderBalance: sender?.balance ?? 0,
					receiverBalance: receiver?.balance ?? 0,
				};
			}

			// Lock wallets in deterministic order to avoid deadlocks
			const usersToLock = [req.fromUserId];
			if (!req.isExternal && req.toUserId && req.toUserId !== req.fromUserId) {
				usersToLock.push(req.toUserId);
			}
			usersToLock.sort((a, b) => a.localeCompare(b));

			const lockedWallets = new Map<string, Wallet>();
			for (const userId of usersToLock) {
				let wallet = await qr.manager
					.getRepository(Wallet)
					.createQueryBuilder('wallet')
					.setLock('pessimistic_write')
					.where('wallet.userId = :userId AND wallet.currency = :currency', {
						userId,
						currency: req.currency,
					})
					.getOne();

				if (!wallet) {
					if (userId === req.fromUserId) {
						throw new BadRequestException('Sender wallet not found');
					}
					// Auto-create receiver wallet
					wallet = qr.manager.create(Wallet, {
						userId,
						currency: req.currency,
						balance: 0,
						status: WalletStatus.ACTIVE,
					});
					wallet = await qr.manager.save(wallet);
				}
				lockedWallets.set(userId, wallet);
			}

			const fromWallet = lockedWallets.get(req.fromUserId)!;
			if (fromWallet.status !== WalletStatus.ACTIVE) {
				throw new BadRequestException('Sender wallet is not active');
			}
			if (fromWallet.balance < req.amount) {
				throw new BadRequestException('Insufficient balance');
			}

			// Debit sender
			const senderBefore = fromWallet.balance;
			fromWallet.balance = senderBefore - req.amount;
			await qr.manager.save(fromWallet);

			// Credit receiver (internal only)
			let receiverBefore = 0;
			let receiverAfter = 0;
			let receiverWallet: Wallet | undefined;

			if (!req.isExternal && req.toUserId) {
				receiverWallet = lockedWallets.get(req.toUserId);
				if (!receiverWallet) {
					receiverWallet = qr.manager.create(Wallet, {
						userId: req.toUserId,
						currency: req.currency,
						balance: 0,
						status: WalletStatus.ACTIVE,
					});
					receiverWallet = await qr.manager.save(receiverWallet);
				}
				if (receiverWallet.status !== WalletStatus.ACTIVE) {
					throw new BadRequestException('Receiver wallet is not active');
				}
				receiverBefore = receiverWallet.balance;
				receiverWallet.balance = receiverBefore + req.amount;
				receiverAfter = receiverWallet.balance;
				await qr.manager.save(receiverWallet);
			}

			// Persist transaction
			const tx = qr.manager.create(TransactionEntity, {
				idempotencyKey: req.idempotencyKey,
				type: TransactionType.TRANSFER,
				status: TransactionStatus.PENDING,
				settlementStatus: req.isExternal ? SettlementStatus.PENDING : SettlementStatus.NONE,
				chainStatus: ChainStatus.PENDING,
				chainRetryCount: 0,
				chainLastAttemptAt: null,
				// Transfer confirmation should move to receipt quickly; async chain
				// worker can pick this up immediately after request completes.
				chainNextAttemptAt: new Date(),
				requestingUserId: req.requestingUserId,
				fromUserId: req.fromUserId,
				toUserId: req.toUserId ?? null,
				amount: req.amount,
				currency: req.currency,
				memo: req.memo ?? null,
				isExternal: !!req.isExternal,
				externalPartner: req.externalPartner ?? null,
				externalAccountNo: req.externalAccountNo ?? null,
			});
			const savedTx = await qr.manager.save(tx);

			// Double-entry ledger
			const ledgerEntries: LedgerEntry[] = [
				qr.manager.create(LedgerEntry, {
					transactionId: savedTx.id,
					walletId: fromWallet.id,
					direction: LedgerDirection.DEBIT,
					amount: req.amount,
					balanceBefore: senderBefore,
					balanceAfter: fromWallet.balance,
					note: `Transfer debit (${req.currency})`,
				}),
			];
			if (receiverWallet) {
				ledgerEntries.push(
					qr.manager.create(LedgerEntry, {
						transactionId: savedTx.id,
						walletId: receiverWallet.id,
						direction: LedgerDirection.CREDIT,
						amount: req.amount,
						balanceBefore: receiverBefore,
						balanceAfter: receiverAfter,
						note: `Transfer credit (${req.currency})`,
					}),
				);
			}
			await qr.manager.save(ledgerEntries);

			await qr.commitTransaction();
			return {
				transaction: savedTx,
				senderBalance: fromWallet.balance,
				receiverBalance: receiverAfter,
			};
		} catch (error) {
			await qr.rollbackTransaction();
			throw error;
		} finally {
			await qr.release();
		}
	}

	private async persistTopupIntent(
		req: CreateTopupIntentRequest,
		fundingSource: FundingSource,
	) {
		const qr = this.dataSource.createQueryRunner();
		await qr.connect();
		await qr.startTransaction();

		try {
			const dup = await qr.manager.findOne(TransactionEntity, {
				where: { idempotencyKey: req.idempotencyKey },
			});
			if (dup) {
				const wallet = await qr.manager.findOne(Wallet, {
					where: { userId: req.userId, currency: req.currency },
				});
				await qr.commitTransaction();
				return {
					transaction: dup,
					walletBalance: wallet?.balance ?? 0,
				};
			}

			let wallet = await qr.manager
				.getRepository(Wallet)
				.createQueryBuilder('wallet')
				.setLock('pessimistic_write')
				.where('wallet.userId = :userId AND wallet.currency = :currency', {
					userId: req.userId,
					currency: req.currency,
				})
				.getOne();
			if (!wallet) {
				wallet = qr.manager.create(Wallet, {
					userId: req.userId,
					currency: req.currency,
					balance: 0,
					status: WalletStatus.ACTIVE,
				});
				wallet = await qr.manager.save(wallet);
			}
			if (wallet.status !== WalletStatus.ACTIVE) {
				throw new BadRequestException('Wallet is not active');
			}

			const tx = qr.manager.create(TransactionEntity, {
				idempotencyKey: req.idempotencyKey,
				type: TransactionType.DEPOSIT,
				status: TransactionStatus.PENDING,
				settlementStatus: SettlementStatus.PENDING,
				chainStatus: ChainStatus.PENDING,
				chainRetryCount: 0,
				chainLastAttemptAt: null,
				chainNextAttemptAt: new Date(Date.now() + this.chainAsyncLeaseMs),
				requestingUserId: req.userId,
				fromUserId: this.chainExternalSourceUserId,
				toUserId: req.userId,
				amount: req.amount,
				currency: req.currency,
				memo: req.memo || `Topup via ${fundingSource.provider}`,
				isExternal: true,
				externalPartner: fundingSource.provider,
				externalAccountNo: fundingSource.accountRefMasked,
			});
			const savedTx = await qr.manager.save(tx);

			await qr.commitTransaction();
			return {
				transaction: savedTx,
				walletBalance: wallet.balance,
			};
		} catch (error) {
			await qr.rollbackTransaction();
			throw error;
		} finally {
			await qr.release();
		}
	}

	private async persistWithdrawalRequest(
		req: CreateWithdrawalRequest,
		fundingSource: FundingSource,
	) {
		const qr = this.dataSource.createQueryRunner();
		await qr.connect();
		await qr.startTransaction();

		try {
			const dup = await qr.manager.findOne(TransactionEntity, {
				where: { idempotencyKey: req.idempotencyKey },
			});
			if (dup) {
				const wallet = await qr.manager.findOne(Wallet, {
					where: { userId: req.userId, currency: req.currency },
				});
				await qr.commitTransaction();
				return {
					transaction: dup,
					walletBalance: wallet?.balance ?? 0,
				};
			}

			const wallet = await qr.manager
				.getRepository(Wallet)
				.createQueryBuilder('wallet')
				.setLock('pessimistic_write')
				.where('wallet.userId = :userId AND wallet.currency = :currency', {
					userId: req.userId,
					currency: req.currency,
				})
				.getOne();
			if (!wallet) {
				throw new BadRequestException('Wallet not found');
			}
			if (wallet.status !== WalletStatus.ACTIVE) {
				throw new BadRequestException('Wallet is not active');
			}
			if (wallet.balance < req.amount) {
				throw new BadRequestException('Insufficient balance');
			}

			const balanceBefore = wallet.balance;
			wallet.balance = balanceBefore - req.amount;
			await qr.manager.save(wallet);

			const tx = qr.manager.create(TransactionEntity, {
				idempotencyKey: req.idempotencyKey,
				type: TransactionType.WITHDRAWAL,
				status: TransactionStatus.PENDING,
				settlementStatus: SettlementStatus.PENDING,
				chainStatus: ChainStatus.PENDING,
				chainRetryCount: 0,
				chainLastAttemptAt: null,
				chainNextAttemptAt: new Date(Date.now() + this.chainAsyncLeaseMs),
				requestingUserId: req.userId,
				fromUserId: req.userId,
				toUserId: this.chainExternalSinkUserId,
				amount: req.amount,
				currency: req.currency,
				memo: req.memo || `Withdrawal via ${fundingSource.provider}`,
				isExternal: true,
				externalPartner: fundingSource.provider,
				externalAccountNo: fundingSource.accountRefMasked,
			});
			const savedTx = await qr.manager.save(tx);

			const ledger = qr.manager.create(LedgerEntry, {
				transactionId: savedTx.id,
				walletId: wallet.id,
				direction: LedgerDirection.DEBIT,
				amount: req.amount,
				balanceBefore,
				balanceAfter: wallet.balance,
				note: `Withdrawal debit (${req.currency})`,
			});
			await qr.manager.save(ledger);

			await qr.commitTransaction();
			return {
				transaction: savedTx,
				walletBalance: wallet.balance,
			};
		} catch (error) {
			await qr.rollbackTransaction();
			throw error;
		} finally {
			await qr.release();
		}
	}

	private async submitOutsideTransfer(tx: TransactionEntity): Promise<TransactionEntity> {
		if (!this.outsidePaymentSvc) {
			throw new BadRequestException('Outside payment service is not available');
		}
		if (!tx.externalPartner || !tx.externalAccountNo) {
			throw new BadRequestException('Missing external partner information');
		}
		try {
			const transferType =
				tx.type === TransactionType.DEPOSIT ? 'TOPUP' : 'WITHDRAWAL';
			const response = await firstValueFrom(
				this.outsidePaymentSvc
					.initiateTransfer({
						transactionId: tx.id,
						partnerCode: tx.externalPartner ?? '',
						accountNo: tx.externalAccountNo ?? '',
						amount: tx.amount,
						currency: tx.currency,
						note: tx.memo ?? undefined,
						transferType,
					})
					.pipe(
						timeout(Number(this.cfg.get<string>('OUTSIDE_PAYMENT_TIMEOUT_MS') ?? 5000)),
					),
			);
			tx.externalRef = response.partnerRef || null;
			if (response.status !== 'SUBMITTED') {
				tx.status = TransactionStatus.FAILED;
				tx.settlementStatus = SettlementStatus.FAILED;
				tx.errorCode = 'OUTSIDE_PAYMENT_REJECTED';
				tx.errorMessage = response.partnerMessage || 'Outside payment rejected';
			}
			return this.txRepo.save(tx);
		} catch (error: unknown) {
			const msg = error instanceof Error ? error.message : String(error);
			this.logger.error(`Outside payment submit failed for tx=${tx.id}: ${msg}`);
			tx.status = TransactionStatus.FAILED;
			tx.settlementStatus = SettlementStatus.FAILED;
			tx.errorCode = 'OUTSIDE_PAYMENT_ERROR';
			tx.errorMessage = msg || 'Outside payment service unavailable';
			return this.txRepo.save(tx);
		}
	}

	private async anchorToChain(tx: TransactionEntity): Promise<TransactionEntity> {
		if (!this.chainSvc) {
			throw new BadRequestException('Chain service is not available');
		}

		try {
			const anchored = await this.callAnchorTransfer(tx);
			this.applyChainResult(tx, anchored);
			return this.txRepo.save(tx);
		} catch (error: unknown) {
			const msg = error instanceof Error ? error.message : String(error);
			this.logger.error(`Chain anchor failed for tx=${tx.id}: ${msg}`);
			this.markChainPending(tx, msg);
			return this.txRepo.save(tx);
		}
	}

	private async runChainAsyncTick() {
		if (this.chainAsyncTickRunning || !this.chainAsyncEnabled) {
			return;
		}
		if (!this.chainSvc) {
			return;
		}

		this.chainAsyncTickRunning = true;
		try {
			const claimedIds = await this.claimDueChainTransactions(this.chainAsyncBatchSize);
			if (claimedIds.length === 0) {
				return;
			}

			const workerSize = Math.max(1, this.chainAsyncWorkers);
			for (let i = 0; i < claimedIds.length; i += workerSize) {
				const chunk = claimedIds.slice(i, i + workerSize);
				await Promise.all(
					chunk.map((txId) =>
						this.processPendingChainTransaction(txId).catch((error: unknown) => {
							const msg =
								error instanceof Error ? error.message : String(error);
							this.logger.error(
								`Chain async processing failed tx=${txId}: ${msg}`,
							);
						}),
					),
				);
			}
		} catch (error: unknown) {
			const msg = error instanceof Error ? error.message : String(error);
			this.logger.error(`Chain async tick failed: ${msg}`);
		} finally {
			this.chainAsyncTickRunning = false;
		}
	}

	private async claimDueChainTransactions(limit: number): Promise<string[]> {
		const take = Math.max(1, limit);
		const now = new Date();
		const leaseUntil = new Date(now.getTime() + this.chainAsyncLeaseMs);
		const qr = this.dataSource.createQueryRunner();
		await qr.connect();
		await qr.startTransaction();
		try {
			const dueRows = await qr.manager
				.getRepository(TransactionEntity)
				.createQueryBuilder('tx')
				.setLock('pessimistic_write')
				.setOnLocked('skip_locked')
				.where('tx.chainStatus = :pending', { pending: ChainStatus.PENDING })
				.andWhere('tx.status != :failed', { failed: TransactionStatus.FAILED })
				.andWhere(
					'(tx.isExternal = false OR tx.settlementStatus IN (:...readySettlement))',
					{
						readySettlement: [SettlementStatus.SETTLED, SettlementStatus.FAILED],
					},
				)
				.andWhere('(tx.chainNextAttemptAt IS NULL OR tx.chainNextAttemptAt <= :now)', {
					now,
				})
				.orderBy('COALESCE(tx.chainNextAttemptAt, tx.createdAt)', 'ASC')
				.take(take)
				.getMany();

			if (dueRows.length > 0) {
				for (const tx of dueRows) {
					tx.chainLastAttemptAt = now;
					tx.chainNextAttemptAt = leaseUntil;
				}
				await qr.manager.save(TransactionEntity, dueRows);
			}

			await qr.commitTransaction();
			return dueRows.map((item) => item.id);
		} catch (error) {
			await qr.rollbackTransaction();
			throw error;
		} finally {
			await qr.release();
		}
	}

	private async processPendingChainTransaction(transactionId: string) {
		const tx = await this.txRepo.findOne({ where: { id: transactionId } });
		if (!tx || tx.chainStatus !== ChainStatus.PENDING || tx.status === TransactionStatus.FAILED) {
			return;
		}

		const previousStatus = tx.status;
		try {
			const chainResponse =
				tx.chainTxId && tx.chainTxId.trim() !== ''
					? await this.callGetReceipt(tx.chainTxId)
					: await this.callAnchorTransfer(tx);
			this.applyChainResult(tx, chainResponse);
		} catch (error: unknown) {
			const msg = error instanceof Error ? error.message : String(error);
			this.markChainPending(tx, msg);
		}

		if (
			this.chainAsyncMaxRetries > 0 &&
			tx.chainStatus === ChainStatus.PENDING &&
			tx.chainRetryCount >= this.chainAsyncMaxRetries
		) {
			tx.chainStatus = ChainStatus.FAILED;
			tx.chainNextAttemptAt = null;
			tx.errorCode = 'CHAIN_FAILED';
			tx.errorMessage = 'On-chain processing exceeded maximum retry attempts';
		}

		this.reconcileBusinessStatusAfterChainUpdate(tx);
		const saved = await this.txRepo.save(tx);

		if (saved.chainStatus === ChainStatus.ANCHORED) {
			await this.enqueueChainCompletedEvent(saved);
		}
		if (
			previousStatus !== TransactionStatus.COMPLETED &&
			saved.status === TransactionStatus.COMPLETED
		) {
			await this.enqueueTransactionEvent(saved);
		}
	}

	private async callAnchorTransfer(tx: TransactionEntity): Promise<AnchorTransferResponse> {
		const timeoutMs = this.toInt(this.cfg.get<string>('CHAIN_ANCHOR_TIMEOUT_MS'), 10000);
		return firstValueFrom(
			this.chainSvc
				.anchorTransfer({
					transactionId: tx.id,
					fromUserId: tx.fromUserId,
					toUserId: tx.toUserId ?? '',
					amount: tx.amount,
					memo: tx.memo ?? '',
					internalRef: tx.id,
					settlementRef: tx.externalRef ?? tx.id,
					timestamp: new Date().toISOString(),
					nonce: randomUUID(),
					idempotencyKey: tx.idempotencyKey,
					riskFlag: tx.amount >= this.chainRiskHighAmount ? 'HIGH' : 'LOW',
				})
				.pipe(timeout(timeoutMs)),
		);
	}

	private async callGetReceipt(chainTxId: string): Promise<AnchorTransferResponse> {
		const timeoutMs = this.toInt(this.cfg.get<string>('CHAIN_RECEIPT_TIMEOUT_MS'), 5000);
		return firstValueFrom(
			this.chainSvc.getReceipt({ txId: chainTxId }).pipe(timeout(timeoutMs)),
		);
	}

	private shouldRefreshReceiptTransparency(receiptJson?: string | null): boolean {
		const raw = (receiptJson || '').trim();
		if (!raw) {
			return true;
		}
		try {
			const decoded = JSON.parse(raw);
			if (!decoded || typeof decoded !== 'object') {
				return true;
			}
			const receipt = this.normalizeReceiptPayload(decoded as Record<string, unknown>);
			const observers = Array.isArray(receipt.observer_confirmations)
				? receipt.observer_confirmations
				: [];
			const transparency =
				receipt.transparency && typeof receipt.transparency === 'object'
					? (receipt.transparency as Record<string, unknown>)
					: null;
			const quorumMet = transparency?.quorum_met === true;
			return observers.length === 0 || !quorumMet;
		} catch {
			return true;
		}
	}

	private normalizeReceiptPayload(
		payload: Record<string, unknown>,
	): Record<string, unknown> {
		const nested = payload.receipt;
		if (nested && typeof nested === 'object') {
			return nested as Record<string, unknown>;
		}
		return payload;
	}

	private async refreshAnchoredReceiptTransparency(
		tx: TransactionEntity,
	): Promise<TransactionEntity> {
		const chainTxId = (tx.chainTxId || '').trim();
		if (!chainTxId || !this.chainSvc) {
			return tx;
		}
		try {
			const refreshed = await this.callGetReceipt(chainTxId);
			const receiptJson = (refreshed.receiptJson || '').trim();
			if (!receiptJson || receiptJson === tx.receiptJson) {
				return tx;
			}
			tx.receiptJson = receiptJson;
			tx.chainLastAttemptAt = new Date();
			return await this.txRepo.save(tx);
		} catch (error: unknown) {
			const msg = error instanceof Error ? error.message : String(error);
			this.logger.warn(
				`Could not refresh anchored receipt transparency for tx=${tx.id}: ${msg}`,
			);
			return tx;
		}
	}

	private applyChainResult(tx: TransactionEntity, response: AnchorTransferResponse) {
		const normalized = (response.chainStatus || '').trim().toUpperCase();
		tx.chainTxId = response.txId || tx.chainTxId;
		tx.receiptJson = response.receiptJson || tx.receiptJson;
		tx.chainLastAttemptAt = new Date();

		if (normalized === 'ANCHORED') {
			tx.chainStatus = ChainStatus.ANCHORED;
			tx.chainRetryCount = 0;
			tx.chainNextAttemptAt = null;
			tx.errorCode = null;
			tx.errorMessage = null;
			this.reconcileBusinessStatusAfterChainUpdate(tx);
			return;
		}

		if (normalized === 'FAILED') {
			tx.chainStatus = ChainStatus.FAILED;
			tx.chainNextAttemptAt = null;
			tx.errorCode = 'CHAIN_FAILED';
			tx.errorMessage = 'On-chain transaction validation failed';
			return;
		}

		this.markChainPending(tx);
	}

	private markChainPending(tx: TransactionEntity, message?: string) {
		tx.chainStatus = ChainStatus.PENDING;
		tx.chainRetryCount = Math.max(0, tx.chainRetryCount ?? 0) + 1;
		tx.chainLastAttemptAt = new Date();
		tx.chainNextAttemptAt = this.computeNextAttemptAt(tx.chainRetryCount);
		tx.errorCode = 'CHAIN_PENDING';
		tx.errorMessage =
			(message || '').trim() ||
			'On-chain receipt is still processing. System will retry automatically.';
	}

	private reconcileBusinessStatusAfterChainUpdate(tx: TransactionEntity) {
		if (tx.status === TransactionStatus.FAILED) {
			return;
		}
		if (!tx.isExternal) {
			tx.status = TransactionStatus.COMPLETED;
			return;
		}
		if (tx.settlementStatus === SettlementStatus.SETTLED && tx.chainStatus === ChainStatus.ANCHORED) {
			tx.status = TransactionStatus.COMPLETED;
		}
	}

	private computeNextAttemptAt(retryCount: number): Date {
		const exponent = Math.max(0, retryCount - 1);
		const rawDelay = this.chainAsyncInitialBackoffMs * Math.pow(2, exponent);
		const cappedDelay = Math.min(rawDelay, this.chainAsyncMaxBackoffMs);
		const jitter = Math.floor(cappedDelay * Math.random() * 0.25);
		return new Date(Date.now() + cappedDelay + jitter);
	}

	private async enqueueTransactionEvent(
		tx: TransactionEntity,
		manager?: EntityManager,
	) {
		const { senderBalance, receiverBalance } = await this.resolveEventBalances(
			tx,
			manager,
		);
		const eventType =
			tx.status === TransactionStatus.FAILED
				? 'transaction.failed'
				: tx.status === TransactionStatus.COMPLETED
					? 'transaction.completed'
					: 'transaction.pending';
		await this.outboxService.enqueue(
			{
				aggregateType: 'TRANSACTION',
				aggregateId: tx.id,
				eventType,
				payload: {
					eventType,
					transactionId: tx.id,
					status: tx.status,
					type: tx.type,
					isExternal: tx.isExternal,
					settlementStatus: tx.settlementStatus,
					chainStatus: tx.chainStatus,
					requestingUserId: tx.requestingUserId,
					fromUserId: tx.fromUserId,
					toUserId: tx.toUserId,
					amount: tx.amount,
					currency: tx.currency,
					memo: tx.memo,
					senderBalance,
					receiverBalance,
					createdAt: tx.createdAt.toISOString(),
					receiptJson: tx.receiptJson,
				},
			},
			manager,
		);
	}

	private async resolveEventBalances(
		tx: TransactionEntity,
		manager?: EntityManager,
	): Promise<{ senderBalance: number | null; receiverBalance: number | null }> {
		const walletRepo = manager?.getRepository(Wallet) ?? this.walletRepo;
		let senderBalance: number | null = null;
		let receiverBalance: number | null = null;

		if (tx.fromUserId) {
			const senderWallet = await walletRepo.findOne({
				where: {
					userId: tx.fromUserId,
					currency: tx.currency,
				},
			});
			senderBalance = senderWallet ? Number(senderWallet.balance ?? 0) : null;
		}

		if (tx.toUserId) {
			const receiverWallet = await walletRepo.findOne({
				where: {
					userId: tx.toUserId,
					currency: tx.currency,
				},
			});
			receiverBalance = receiverWallet ? Number(receiverWallet.balance ?? 0) : null;
		}

		return {
			senderBalance,
			receiverBalance,
		};
	}

	private async enqueueChainCompletedEvent(tx: TransactionEntity) {
		await this.outboxService.enqueue({
			aggregateType: 'TRANSACTION',
			aggregateId: tx.id,
			eventType: 'transaction.chain.completed',
			payload: {
				eventType: 'transaction.chain.completed',
				transactionId: tx.id,
				status: tx.status,
				requestingUserId: tx.requestingUserId,
				fromUserId: tx.fromUserId,
				toUserId: tx.toUserId,
				amount: tx.amount,
				currency: tx.currency,
				memo: tx.memo,
				createdAt: tx.createdAt.toISOString(),
				receiptJson: tx.receiptJson,
			},
		});
	}

	private mapTransferResponse(
		tx: TransactionEntity,
		senderBalance: number,
		receiverBalance: number,
	) {
		return {
			transactionId: tx.id,
			type: tx.type,
			status: tx.status,
			settlementStatus: tx.settlementStatus,
			senderBalance,
			receiverBalance,
			chainStatus: tx.chainStatus,
			receiptJson: tx.receiptJson ?? '',
			fromUserId: tx.fromUserId,
			toUserId: tx.toUserId ?? '',
			errorCode: tx.errorCode ?? '',
			errorMessage: tx.errorMessage ?? '',
			createdAt: tx.createdAt.toISOString(),
		};
	}

	private validateCreateFundingSource(request: CreateFundingSourceRequest) {
		const userId = (request.userId || '').trim();
		if (!userId) throw new BadRequestException('userId is required');

		const provider = (request.provider || '').trim().toUpperCase();
		if (!provider) throw new BadRequestException('provider is required');
		if (provider.length > 32) throw new BadRequestException('provider is invalid');

		const accountRef = (request.accountRef || '').trim();
		if (!accountRef) throw new BadRequestException('accountRef is required');
		if (accountRef.length > 128) throw new BadRequestException('accountRef is invalid');

		const providerToken = (request.providerToken || '').trim();
		const displayName = (request.displayName || '').trim();

		return {
			userId,
			provider,
			accountRef,
			providerToken,
			displayName,
		};
	}

	private validateCreateTopupIntent(request: CreateTopupIntentRequest) {
		const idempotencyKey = (request.idempotencyKey || '').trim();
		if (!idempotencyKey) throw new BadRequestException('idempotencyKey is required');
		if (idempotencyKey.length > 128) throw new BadRequestException('idempotencyKey too long');

		const userId = (request.userId || '').trim();
		if (!userId) throw new BadRequestException('userId is required');

		const fundingSourceId = (request.fundingSourceId || '').trim();
		if (!fundingSourceId) throw new BadRequestException('fundingSourceId is required');

		const amount = this.normalizeAmount(request.amount);
		if (!Number.isInteger(amount) || amount <= 0)
			throw new BadRequestException('amount must be positive integer');

		const currency = this.normalizeCurrency(request.currency);
		const memo = (request.memo || '').trim();

		return {
			idempotencyKey,
			userId,
			fundingSourceId,
			amount,
			currency,
			memo,
		};
	}

	private validateCreateWithdrawalRequest(request: CreateWithdrawalRequest) {
		const normalized = this.validateCreateTopupIntent({
			idempotencyKey: request.idempotencyKey,
			userId: request.userId,
			fundingSourceId: request.fundingSourceId,
			amount: request.amount,
			currency: request.currency,
			memo: request.memo,
		});
		return {
			...normalized,
			simulateFailure: request.simulateFailure === true,
		};
	}

	private async getActiveFundingSource(
		userId: string,
		fundingSourceId: string,
	): Promise<FundingSource> {
		const fundingSource = await this.fundingSourceRepo.findOne({
			where: {
				id: fundingSourceId,
				userId,
				status: FundingSourceStatus.ACTIVE,
			},
		});
		if (!fundingSource) {
			throw new BadRequestException('Funding source not found or inactive');
		}
		return fundingSource;
	}

	private hashAccountRef(provider: string, accountRef: string): string {
		return createHash('sha256')
			.update(`${provider}:${accountRef}`)
			.digest('hex');
	}

	private maskAccountRef(accountRef: string): string {
		const compact = accountRef.replace(/\s+/g, '');
		if (compact.length <= 4) {
			return `***${compact}`.slice(0, 32);
		}
		const tail = compact.slice(-4);
		return `****${tail}`;
	}

	private async applyDepositCreditIfNeeded(
		manager: EntityManager,
		tx: TransactionEntity,
	): Promise<void> {
		if (tx.type !== TransactionType.DEPOSIT) {
			return;
		}

		const existingCredit = await manager.findOne(LedgerEntry, {
			where: {
				transactionId: tx.id,
				direction: LedgerDirection.CREDIT,
			},
		});
		if (existingCredit) {
			return;
		}

		let wallet = await manager
			.getRepository(Wallet)
			.createQueryBuilder('wallet')
			.setLock('pessimistic_write')
			.where('wallet.userId = :userId AND wallet.currency = :currency', {
				userId: tx.toUserId ?? tx.requestingUserId,
				currency: tx.currency,
			})
			.getOne();
		if (!wallet) {
			wallet = manager.create(Wallet, {
				userId: tx.toUserId ?? tx.requestingUserId,
				currency: tx.currency,
				balance: 0,
				status: WalletStatus.ACTIVE,
			});
			wallet = await manager.save(wallet);
		}
		if (wallet.status !== WalletStatus.ACTIVE) {
			throw new BadRequestException('Wallet is not active');
		}

		const balanceBefore = wallet.balance;
		wallet.balance = balanceBefore + tx.amount;
		await manager.save(wallet);

		const ledger = manager.create(LedgerEntry, {
			transactionId: tx.id,
			walletId: wallet.id,
			direction: LedgerDirection.CREDIT,
			amount: tx.amount,
			balanceBefore,
			balanceAfter: wallet.balance,
			note: `Topup settlement credit (${tx.currency})`,
		});
		await manager.save(ledger);
	}

	private async rollbackWithdrawalDebit(
		tx: TransactionEntity,
		reasonCode: string,
	): Promise<void> {
		if (tx.type !== TransactionType.WITHDRAWAL) {
			return;
		}

		const qr = this.dataSource.createQueryRunner();
		await qr.connect();
		await qr.startTransaction();
		try {
			await this.rollbackWithdrawalDebitUsingManager(qr.manager, tx, reasonCode);
			await qr.commitTransaction();
		} catch (error) {
			await qr.rollbackTransaction();
			throw error;
		} finally {
			await qr.release();
		}
	}

	private async rollbackWithdrawalDebitUsingManager(
		manager: EntityManager,
		tx: TransactionEntity,
		reasonCode: string,
	): Promise<void> {
		const reversalExists = await manager.findOne(LedgerEntry, {
			where: {
				transactionId: tx.id,
				direction: LedgerDirection.CREDIT,
			},
		});
		if (reversalExists) {
			return;
		}

		const wallet = await manager
			.getRepository(Wallet)
			.createQueryBuilder('wallet')
			.setLock('pessimistic_write')
			.where('wallet.userId = :userId AND wallet.currency = :currency', {
				userId: tx.fromUserId,
				currency: tx.currency,
			})
			.getOne();
		if (!wallet) {
			throw new BadRequestException('Wallet not found for rollback');
		}

		const balanceBefore = wallet.balance;
		wallet.balance = balanceBefore + tx.amount;
		await manager.save(wallet);

		const ledger = manager.create(LedgerEntry, {
			transactionId: tx.id,
			walletId: wallet.id,
			direction: LedgerDirection.CREDIT,
			amount: tx.amount,
			balanceBefore,
			balanceAfter: wallet.balance,
			note: `Withdrawal rollback (${reasonCode})`,
		});
		await manager.save(ledger);
	}

	private validateCreateTransfer(request: CreateTransferRequest) {
		const idempotencyKey = request.idempotencyKey?.trim();
		if (!idempotencyKey) throw new BadRequestException('idempotencyKey is required');
		if (idempotencyKey.length > 128) throw new BadRequestException('idempotencyKey too long');

		const requestingUserId = request.requestingUserId?.trim();
		const fromUserId = request.fromUserId?.trim();
		const toUserId = request.toUserId?.trim();
		if (!requestingUserId || !fromUserId || !toUserId)
			throw new BadRequestException('requestingUserId, fromUserId, toUserId required');
		if (requestingUserId !== fromUserId)
			throw new BadRequestException('requestingUserId must match fromUserId');
		if (fromUserId === toUserId && !request.isExternal)
			throw new BadRequestException('fromUserId and toUserId must be different');

		const amount = this.normalizeAmount(request.amount);
		if (!Number.isInteger(amount) || amount <= 0)
			throw new BadRequestException('amount must be positive integer');

		const currency = this.normalizeCurrency(request.currency);
		if (!request.otpCode?.trim()) throw new BadRequestException('otpCode required');

		const isExternal = !!request.isExternal;
		const externalPartner = request.externalPartner?.trim() || '';
		const externalAccountNo = request.externalAccountNo?.trim() || '';
		if (isExternal && (!externalPartner || !externalAccountNo))
			throw new BadRequestException(
				'external transfer requires externalPartner and externalAccountNo',
			);

		return {
			...request,
			idempotencyKey,
			requestingUserId,
			fromUserId,
			toUserId,
			amount,
			currency,
			memo: request.memo?.trim() || '',
			isExternal,
			externalPartner: externalPartner || undefined,
			externalAccountNo: externalAccountNo || undefined,
		};
	}

	private normalizeAmount(rawAmount: number | string | GrpcInt64): number {
		if (typeof rawAmount === 'number' && Number.isFinite(rawAmount)) return rawAmount;
		if (typeof rawAmount === 'string' && rawAmount.trim() !== '') {
			const parsed = Number(rawAmount);
			if (Number.isFinite(parsed)) return parsed;
		}
		if (rawAmount && typeof rawAmount === 'object' && 'low' in rawAmount) {
			const low = Number(rawAmount.low);
			const high = Number(rawAmount.high ?? 0);
			if (high === 0) return rawAmount.unsigned ? low >>> 0 : low;
		}
		return Number.NaN;
	}

	private normalizeCurrency(currencyRaw: string): string {
		const currency = (currencyRaw || 'VND').trim().toUpperCase();
		if (!currency) throw new BadRequestException('currency is required');
		if (currency.length > 16) throw new BadRequestException('currency is invalid');
		return currency;
	}

	private toInt(raw: unknown, fallback: number): number {
		if (typeof raw === 'number' && Number.isFinite(raw)) {
			return Math.floor(raw);
		}
		if (typeof raw === 'string' && raw.trim() !== '') {
			const parsed = Number(raw);
			if (Number.isFinite(parsed)) {
				return Math.floor(parsed);
			}
		}
		return fallback;
	}
}
