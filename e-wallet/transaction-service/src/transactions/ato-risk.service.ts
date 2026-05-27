import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

import { Wallet } from '../wallets/entities/wallet.entity';
import {
	TransactionEntity,
	TransactionStatus,
} from './entities/transaction.entity';

interface GrpcInt64 {
	low: number;
	high: number;
	unsigned: boolean;
}

export interface AssessTransferRiskRequest {
	requestingUserId: string;
	fromUserId: string;
	toUserId: string;
	amount: number | string | GrpcInt64;
	currency: string;
	isExternal?: boolean;
	externalPartner?: string;
	externalAccountNo?: string;
	deviceId?: string;
}

interface NormalizedRiskRequest {
	requestingUserId: string;
	fromUserId: string;
	toUserId: string;
	amount: number;
	currency: string;
	isExternal: boolean;
	externalPartner: string;
	externalAccountNo: string;
	deviceId: string;
}

interface DestinationStats {
	txCount: number;
	avgAmount: number;
	uniqueSenders: number;
}

type AtoTransactionType = 'CASH_IN' | 'CASH_OUT' | 'DEBIT' | 'PAYMENT' | 'TRANSFER';

type AtoFeatureVector = {
	step: number;
	amount: number;
	oldbalanceOrg: number;
	hour_of_day: number;
	day_of_month: number;
	type_encoded: number;
	is_high_risk_type: number;
	amount_log: number;
	nameDest_tx_count: number;
	nameDest_avg_amount: number;
	dest_unique_senders_before: number;
	dest_amount_spike_ratio: number;
};

interface AtoModelResponse {
	verdict: string;
	probability: number;
	threshold: number;
	modelVersion: string;
}

export interface AtoRiskAssessment {
	requiresStepUp: boolean;
	reasons: string[];
	verdict: string;
	probability: number;
	threshold: number;
	modelVersion: string;
	modelType: AtoTransactionType;
	senderBalance: number;
	destinationTxCount: number;
	destinationAvgAmount: number;
	destinationUniqueSenders: number;
}

const TYPE_ENCODING: Record<AtoTransactionType, number> = {
	CASH_IN: 0,
	CASH_OUT: 1,
	DEBIT: 2,
	PAYMENT: 3,
	TRANSFER: 4,
};

@Injectable()
export class AtoRiskService {
	private readonly logger = new Logger(AtoRiskService.name);
	private readonly serviceUrl: string;
	private readonly timeoutMs: number;
	private readonly failOpen: boolean;
	private readonly localTimezoneOffsetMinutes: number;
	private readonly statsCacheTtlMs: number;
	private readonly statsCacheMaxEntries: number;
	private readonly fallbackHardAmount: number;
	private readonly statsCache = new Map<
		string,
		{ expiresAtMs: number; value: DestinationStats }
	>();

	constructor(
		private readonly cfg: ConfigService,
		@InjectRepository(Wallet)
		private readonly walletRepo: Repository<Wallet>,
		@InjectRepository(TransactionEntity)
		private readonly txRepo: Repository<TransactionEntity>,
	) {
		this.serviceUrl = (this.cfg.get<string>('ATO_SERVICE_URL') ?? '').replace(
			/\/+$/,
			'',
		);
		this.timeoutMs = this.toInt(this.cfg.get<string>('ATO_TIMEOUT_MS'), 250);
		this.failOpen =
			String(this.cfg.get<string>('ATO_FAIL_OPEN') ?? 'false').toLowerCase() ===
			'true';
		this.localTimezoneOffsetMinutes = this.toInt(
			this.cfg.get<string>('ATO_TIMEZONE_OFFSET_MINUTES'),
			420,
		);
		this.statsCacheTtlMs = this.toInt(
			this.cfg.get<string>('ATO_STATS_CACHE_TTL_MS'),
			5000,
		);
		this.statsCacheMaxEntries = this.toInt(
			this.cfg.get<string>('ATO_STATS_CACHE_MAX_ENTRIES'),
			10000,
		);
		this.fallbackHardAmount = this.toInt(
			this.cfg.get<string>('ATO_FALLBACK_HARD_AMOUNT'),
			50_000_000,
		);
	}

	async assessTransferRisk(
		request: AssessTransferRiskRequest,
	): Promise<AtoRiskAssessment> {
		const req = this.validate(request);
		const wallet = await this.walletRepo.findOne({
			where: { userId: req.fromUserId, currency: req.currency },
		});
		const senderBalance = Number(wallet?.balance ?? 0);
		const stats = await this.getDestinationStats(req);
		const modelType = this.toModelType(req);
		const features = this.buildFeatureVector(req, senderBalance, stats, modelType);

		try {
			const model = await this.callAtoModel(features);
			const fallbackReasons = this.fallbackReasons(req, senderBalance, stats);
			const modelRequiresStepUp = model.verdict === 'ATO_SUSPECTED';
			const requiresStepUp = modelRequiresStepUp || fallbackReasons.length > 0;
			return {
				requiresStepUp,
				reasons: [
					...(modelRequiresStepUp ? ['ato_model_suspected'] : []),
					...fallbackReasons,
				],
				verdict: model.verdict,
				probability: model.probability,
				threshold: model.threshold,
				modelVersion: model.modelVersion,
				modelType,
				senderBalance,
				destinationTxCount: stats.txCount,
				destinationAvgAmount: stats.avgAmount,
				destinationUniqueSenders: stats.uniqueSenders,
			};
		} catch (error) {
			const msg = error instanceof Error ? error.message : String(error);
			this.logger.warn(`ATO model unavailable: ${msg}`);
			const fallbackReasons = this.fallbackReasons(req, senderBalance, stats);
			const requiresStepUp = !this.failOpen || fallbackReasons.length > 0;
			return {
				requiresStepUp,
				reasons: requiresStepUp
					? ['ato_model_unavailable', ...fallbackReasons]
					: ['ato_model_unavailable_fail_open'],
				verdict: 'UNAVAILABLE',
				probability: 0,
				threshold: 0,
				modelVersion: '',
				modelType,
				senderBalance,
				destinationTxCount: stats.txCount,
				destinationAvgAmount: stats.avgAmount,
				destinationUniqueSenders: stats.uniqueSenders,
			};
		}
	}

	private validate(request: AssessTransferRiskRequest): NormalizedRiskRequest {
		const requestingUserId = (request.requestingUserId ?? '').trim();
		const fromUserId = (request.fromUserId ?? '').trim();
		const toUserId = (request.toUserId ?? '').trim();
		if (!requestingUserId || !fromUserId || !toUserId) {
			throw new BadRequestException(
				'requestingUserId, fromUserId, toUserId required',
			);
		}
		if (requestingUserId !== fromUserId) {
			throw new BadRequestException('requestingUserId must match fromUserId');
		}

		const amount = this.normalizeAmount(request.amount);
		if (!Number.isInteger(amount) || amount <= 0) {
			throw new BadRequestException('amount must be positive integer');
		}

		const currency = (request.currency || 'VND').trim().toUpperCase();
		if (!currency || currency.length > 16) {
			throw new BadRequestException('currency is invalid');
		}

		const isExternal = request.isExternal === true;
		const externalPartner = (request.externalPartner ?? '').trim();
		const externalAccountNo = (request.externalAccountNo ?? '').trim();
		if (isExternal && (!externalPartner || !externalAccountNo)) {
			throw new BadRequestException(
				'external transfer requires externalPartner and externalAccountNo',
			);
		}

		return {
			requestingUserId,
			fromUserId,
			toUserId,
			amount,
			currency,
			isExternal,
			externalPartner,
			externalAccountNo,
			deviceId: (request.deviceId ?? '').trim(),
		};
	}

	private buildFeatureVector(
		req: NormalizedRiskRequest,
		senderBalance: number,
		stats: DestinationStats,
		modelType: AtoTransactionType,
	): AtoFeatureVector {
		const temporal = this.temporalFeatures(new Date());
		return {
			step: temporal.step,
			amount: req.amount,
			oldbalanceOrg: senderBalance,
			hour_of_day: temporal.hourOfDay,
			day_of_month: temporal.dayOfMonth,
			type_encoded: TYPE_ENCODING[modelType],
			is_high_risk_type:
				modelType === 'TRANSFER' || modelType === 'CASH_OUT' ? 1 : 0,
			amount_log: Math.log1p(req.amount),
			nameDest_tx_count: stats.txCount,
			nameDest_avg_amount: stats.avgAmount,
			dest_unique_senders_before: stats.uniqueSenders,
			dest_amount_spike_ratio:
				stats.avgAmount === 0 ? 1 : req.amount / (stats.avgAmount + 1e-5),
		};
	}

	private temporalFeatures(now: Date) {
		const localMs =
			now.getTime() + this.localTimezoneOffsetMinutes * 60 * 1000;
		const localHours = Math.floor(localMs / (60 * 60 * 1000));
		const step = (localHours % (30 * 24)) + 1;
		return {
			step,
			hourOfDay: (step - 1) % 24,
			dayOfMonth: Math.floor((step - 1) / 24) + 1,
		};
	}

	private async getDestinationStats(
		req: NormalizedRiskRequest,
	): Promise<DestinationStats> {
		const cacheKey = this.destinationCacheKey(req);
		const cached = this.statsCache.get(cacheKey);
		if (cached && cached.expiresAtMs > Date.now()) {
			return cached.value;
		}

		const qb = this.txRepo
			.createQueryBuilder('tx')
			.select('COUNT(*)', 'tx_count')
			.addSelect('COALESCE(AVG(tx.amount), 0)', 'avg_amount')
			.addSelect('COUNT(DISTINCT tx.fromUserId)', 'unique_senders')
			.where('tx.currency = :currency', { currency: req.currency })
			.andWhere('tx.status != :failedStatus', {
				failedStatus: TransactionStatus.FAILED,
			});

		if (req.isExternal) {
			qb.andWhere('tx.isExternal = true').andWhere(
				'tx.externalAccountNo = :destination',
				{ destination: req.externalAccountNo },
			);
		} else {
			qb.andWhere('tx.toUserId = :destination', { destination: req.toUserId });
		}

		const row = await qb.getRawOne<{
			tx_count?: string | number;
			avg_amount?: string | number;
			unique_senders?: string | number;
		}>();
		const value = {
			txCount: this.toInt(row?.tx_count, 0),
			avgAmount: this.toNumber(row?.avg_amount, 0),
			uniqueSenders: this.toInt(row?.unique_senders, 0),
		};
		this.cacheDestinationStats(cacheKey, value);
		return value;
	}

	private async callAtoModel(features: AtoFeatureVector): Promise<AtoModelResponse> {
		if (!this.serviceUrl) {
			throw new Error('ATO_SERVICE_URL is not configured');
		}

		const controller = new AbortController();
		const timer = setTimeout(() => controller.abort(), this.timeoutMs);
		try {
			const response = await fetch(`${this.serviceUrl}/score`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ features }),
				signal: controller.signal,
			});
			const payload = (await response.json().catch(() => ({}))) as Record<
				string,
				unknown
			>;
			if (!response.ok) {
				throw new Error(
					`${response.status} ${payload['message'] ?? 'ATO scoring failed'}`,
				);
			}
			const probability = this.toNumber(payload['probability'], Number.NaN);
			const threshold = this.toNumber(payload['threshold'], Number.NaN);
			const verdict = `${payload['verdict'] ?? ''}`.trim().toUpperCase();
			if (!Number.isFinite(probability) || !verdict) {
				throw new Error('ATO scoring response is invalid');
			}
			return {
				verdict,
				probability,
				threshold: Number.isFinite(threshold) ? threshold : 0,
				modelVersion: `${payload['modelVersion'] ?? ''}`,
			};
		} finally {
			clearTimeout(timer);
		}
	}

	private fallbackReasons(
		req: NormalizedRiskRequest,
		senderBalance: number,
		stats: DestinationStats,
	): string[] {
		const reasons: string[] = [];
		if (req.amount >= this.fallbackHardAmount) {
			reasons.push('amount_over_fallback_threshold');
		}
		if (senderBalance > 0 && req.amount >= senderBalance * 0.9) {
			reasons.push('amount_near_sender_balance');
		}
		if (stats.avgAmount > 0 && req.amount >= stats.avgAmount * 5) {
			reasons.push('destination_amount_spike');
		}
		return reasons;
	}

	private toModelType(req: NormalizedRiskRequest): AtoTransactionType {
		if (req.isExternal) {
			return 'CASH_OUT';
		}
		return 'TRANSFER';
	}

	private destinationCacheKey(req: NormalizedRiskRequest): string {
		if (req.isExternal) {
			return `external:${req.currency}:${req.externalPartner}:${req.externalAccountNo}`;
		}
		return `wallet:${req.currency}:${req.toUserId}`;
	}

	private cacheDestinationStats(key: string, value: DestinationStats) {
		if (this.statsCacheTtlMs <= 0) {
			return;
		}
		this.statsCache.set(key, {
			value,
			expiresAtMs: Date.now() + this.statsCacheTtlMs,
		});
		if (this.statsCache.size <= this.statsCacheMaxEntries) {
			return;
		}
		const oldestKey = this.statsCache.keys().next().value;
		if (oldestKey) {
			this.statsCache.delete(oldestKey);
		}
	}

	private normalizeAmount(rawAmount: number | string | GrpcInt64): number {
		if (typeof rawAmount === 'number' && Number.isFinite(rawAmount)) {
			return Math.floor(rawAmount);
		}
		if (typeof rawAmount === 'string' && rawAmount.trim() !== '') {
			const parsed = Number(rawAmount);
			if (Number.isFinite(parsed)) {
				return Math.floor(parsed);
			}
		}
		if (rawAmount && typeof rawAmount === 'object' && 'low' in rawAmount) {
			const low = Number(rawAmount.low);
			const high = Number(rawAmount.high ?? 0);
			if (high === 0) {
				return rawAmount.unsigned ? low >>> 0 : low;
			}
		}
		return Number.NaN;
	}

	private toInt(raw: unknown, fallback: number): number {
		return Math.floor(this.toNumber(raw, fallback));
	}

	private toNumber(raw: unknown, fallback: number): number {
		if (typeof raw === 'number' && Number.isFinite(raw)) {
			return raw;
		}
		if (typeof raw === 'string' && raw.trim() !== '') {
			const parsed = Number(raw);
			if (Number.isFinite(parsed)) {
				return parsed;
			}
		}
		return fallback;
	}
}
