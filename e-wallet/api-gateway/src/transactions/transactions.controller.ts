import {
	Body,
	Controller,
	ConflictException,
	ForbiddenException,
	BadRequestException,
	Get,
	GatewayTimeoutException,
	Headers,
	InternalServerErrorException,
	NotFoundException,
	Param,
	Post,
	Query,
	Req,
	ServiceUnavailableException,
	UnauthorizedException,
	UseGuards,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { status as grpcStatus } from '@grpc/grpc-js';
import {
	IsBoolean,
	IsNotEmpty,
	IsNumber,
	IsOptional,
	IsString,
	Min,
} from 'class-validator';
import { firstValueFrom, timeout } from 'rxjs';
import { randomUUID } from 'crypto';
import { AuthGuard } from '../common/auth.guard';
import { GrpcClientsService } from '../common/grpc-clients.service';

class CreateTransferDto {
	@IsString()
	@IsOptional()
	toUserId?: string;

	@IsString()
	@IsOptional()
	recipient?: string;

	@IsNumber()
	amount!: number;

	@IsString()
	@IsNotEmpty()
	currency!: string;

	@IsString()
	@IsOptional()
	memo?: string;

	@IsString()
	@IsNotEmpty()
	otpCode!: string;

	@IsString()
	@IsOptional()
	idempotencyKey?: string;

	@IsBoolean()
	@IsOptional()
	isExternal?: boolean;

	@IsString()
	@IsOptional()
	externalPartner?: string;

	@IsString()
	@IsOptional()
	externalAccountNo?: string;
}

class AssessTransferRiskDto {
	@IsString()
	@IsOptional()
	toUserId?: string;

	@IsString()
	@IsOptional()
	recipient?: string;

	@IsNumber()
	amount!: number;

	@IsString()
	@IsNotEmpty()
	currency!: string;

	@IsBoolean()
	@IsOptional()
	isExternal?: boolean;

	@IsString()
	@IsOptional()
	externalPartner?: string;

	@IsString()
	@IsOptional()
	externalAccountNo?: string;
}

class CreateFundingSourceDto {
	@IsString()
	@IsNotEmpty()
	provider!: string;

	@IsString()
	@IsNotEmpty()
	accountRef!: string;

	@IsString()
	@IsOptional()
	providerToken?: string;

	@IsString()
	@IsOptional()
	displayName?: string;
}

class CreateTopupDto {
	@IsString()
	@IsNotEmpty()
	fundingSourceId!: string;

	@IsNumber()
	@Min(1)
	amount!: number;

	@IsString()
	@IsNotEmpty()
	currency!: string;

	@IsString()
	@IsOptional()
	memo?: string;

	@IsString()
	@IsOptional()
	idempotencyKey?: string;
}

class CreateWithdrawalDto extends CreateTopupDto {
	@IsBoolean()
	@IsOptional()
	simulateFailure?: boolean;
}

@Controller('v1/transactions')
@UseGuards(AuthGuard)
export class TransactionsController {
	private readonly transferTimeoutMs: number;
	private readonly grpcTimeoutMs: number;

	constructor(
		private readonly grpcClients: GrpcClientsService,
		private readonly config: ConfigService,
	) {
		this.transferTimeoutMs = Number(this.config.get('TRANSFER_TIMEOUT_MS') ?? 15000);
		this.grpcTimeoutMs = Number(this.config.get('GRPC_TIMEOUT_MS') ?? 5000);
	}

	@Post('transfers/risk-assessment')
	async assessTransferRiskPreview(
		@Req() req: any,
		@Body() dto: AssessTransferRiskDto,
		@Headers('x-device-id') deviceIdHeader?: string,
	) {
		const deviceId = (deviceIdHeader || '').trim();
		const toUserId = (dto?.toUserId || '').trim() || (dto?.recipient || '').trim();
		if (!toUserId || !dto?.amount || !dto?.currency) {
			throw new BadRequestException('Missing required transfer fields');
		}

		const risk = await this.assessTransferRisk(
			req.authUser.userId,
			toUserId,
			Number(dto.amount),
			dto.currency,
			deviceId,
			!!dto.isExternal,
			dto.externalPartner || '',
			dto.externalAccountNo || '',
		);

		return {
			requiresStepUp: risk.requiresStepUp,
			reasons: risk.reasons,
			verdict: risk.verdict,
			probability: risk.probability,
			threshold: risk.threshold,
			modelVersion: risk.modelVersion,
		};
	}

	@Post('transfers')
	async createTransfer(
		@Req() req: any,
		@Body() dto: CreateTransferDto,
		@Headers('x-device-id') deviceIdHeader?: string,
		@Headers('x-face-verified') faceVerifiedHeader?: string,
		@Headers('x-step-up-token') stepUpTokenHeader?: string,
	) {
		const deviceId = (deviceIdHeader || '').trim();
		const toUserId = (dto?.toUserId || '').trim() || (dto?.recipient || '').trim();
		if (!toUserId || !dto?.amount || !dto?.currency || !dto?.otpCode) {
			throw new BadRequestException('Missing required transfer fields');
		}
		const risk = await this.assessTransferRisk(
			req.authUser.userId,
			toUserId,
			Number(dto.amount),
			dto.currency,
			deviceId,
			!!dto.isExternal,
			dto.externalPartner || '',
			dto.externalAccountNo || '',
		);
		const faceVerified = faceVerifiedHeader === 'true';
		if (risk.requiresStepUp && !faceVerified) {
			const stepUpToken = (stepUpTokenHeader ?? '').trim();
			if (!stepUpToken) {
				throw new ForbiddenException({
					message: 'Step-up verification required',
					reasons: risk.reasons,
					verdict: risk.verdict,
					probability: risk.probability,
					threshold: risk.threshold,
				});
			}
			const validStepUp = await this.verifyStepUpToken(
				req.authUser.userId,
				deviceId,
				stepUpToken,
			);
			if (!validStepUp) {
				throw new ForbiddenException({
					message: 'Invalid or expired step-up token',
					reasons: risk.reasons,
					verdict: risk.verdict,
				});
			}
		}
		const transfer = await this.callTransaction(
			this.grpcClients.transaction.createTransfer({
					idempotencyKey:
						dto.idempotencyKey?.trim() || randomUUID(),
					requestingUserId: req.authUser.userId,
					fromUserId: req.authUser.userId,
					toUserId,
					amount: Number(dto.amount),
					currency: dto.currency,
					memo: dto.memo || '',
					otpCode: dto.otpCode,
					isExternal: !!dto.isExternal,
					externalPartner: dto.externalPartner || '',
					externalAccountNo: dto.externalAccountNo || '',
				})
				.pipe(timeout(this.transferTimeoutMs)),
		) as Record<string, any>;
		const normalizedTransfer = {
			...transfer,
			senderBalance: this.int64ToNumber(transfer.senderBalance),
			receiverBalance: this.int64ToNumber(transfer.receiverBalance),
		};
		return {
			...normalizedTransfer,
			toUserId,
			risk: {
				stepUpApplied: risk.requiresStepUp,
				reasons: risk.reasons,
				verdict: risk.verdict,
				probability: risk.probability,
				threshold: risk.threshold,
				modelVersion: risk.modelVersion,
			},
		};
	}

	@Post('funding-sources')
	async createFundingSource(@Req() req: any, @Body() dto: CreateFundingSourceDto) {
		if (!dto.provider?.trim() || !dto.accountRef?.trim()) {
			throw new BadRequestException('provider and accountRef are required');
		}
		return this.callTransaction(
			this.grpcClients.transaction.createFundingSource({
					userId: req.authUser.userId,
					provider: dto.provider.trim(),
					accountRef: dto.accountRef.trim(),
					providerToken: dto.providerToken?.trim() || '',
					displayName: dto.displayName?.trim() || '',
				})
				.pipe(timeout(this.grpcTimeoutMs)),
		) as Record<string, any>;
	}

	@Get('funding-sources')
	async listFundingSources(@Req() req: any) {
		const result = (await this.callTransaction(
			this.grpcClients.transaction
				.listFundingSources({ userId: req.authUser.userId })
				.pipe(timeout(this.grpcTimeoutMs)),
		)) as Record<string, any>;
		return {
			items: Array.isArray(result.items) ? result.items : [],
		};
	}

	@Post('topups')
	async createTopupIntent(
		@Req() req: any,
		@Body() dto: CreateTopupDto,
		@Headers('x-device-id') deviceIdHeader?: string,
		@Headers('x-face-verified') faceVerifiedHeader?: string,
		@Headers('x-step-up-token') stepUpTokenHeader?: string,
	) {
		if (!dto.fundingSourceId?.trim() || !dto.currency?.trim()) {
			throw new BadRequestException('fundingSourceId and currency are required');
		}
		if (!Number.isFinite(dto.amount) || dto.amount <= 0) {
			throw new BadRequestException('amount must be a positive number');
		}
		const fundingSourceId = dto.fundingSourceId.trim();
		const deviceId = (deviceIdHeader || '').trim();
		const riskTarget = await this.resolveFundingSourceRiskTarget(
			req.authUser.userId,
			fundingSourceId,
		);
		const risk = await this.assessTransferRisk(
			req.authUser.userId,
			riskTarget.toUserId,
			Number(dto.amount),
			dto.currency.trim(),
			deviceId,
			true,
			riskTarget.externalPartner,
			riskTarget.externalAccountNo,
		);
		await this.requireStepUpIfNeeded({
			userId: req.authUser.userId,
			deviceId,
			faceVerifiedHeader,
			stepUpTokenHeader,
			risk,
		});

		const transfer = await this.callTransaction(
			this.grpcClients.transaction.createTopupIntent({
					idempotencyKey: dto.idempotencyKey?.trim() || randomUUID(),
					userId: req.authUser.userId,
					fundingSourceId,
					amount: Number(dto.amount),
					currency: dto.currency.trim(),
					memo: dto.memo?.trim() || '',
				})
				.pipe(timeout(this.transferTimeoutMs)),
		) as Record<string, any>;

		return {
			...transfer,
			senderBalance: this.int64ToNumber(transfer.senderBalance),
			receiverBalance: this.int64ToNumber(transfer.receiverBalance),
			risk: {
				stepUpApplied: risk.requiresStepUp,
				reasons: risk.reasons,
				verdict: risk.verdict,
				probability: risk.probability,
				threshold: risk.threshold,
				modelVersion: risk.modelVersion,
			},
		};
	}

	@Post('withdrawals')
	async createWithdrawalRequest(
		@Req() req: any,
		@Body() dto: CreateWithdrawalDto,
		@Headers('x-device-id') deviceIdHeader?: string,
		@Headers('x-face-verified') faceVerifiedHeader?: string,
		@Headers('x-step-up-token') stepUpTokenHeader?: string,
	) {
		if (!dto.fundingSourceId?.trim() || !dto.currency?.trim()) {
			throw new BadRequestException('fundingSourceId and currency are required');
		}
		if (!Number.isFinite(dto.amount) || dto.amount <= 0) {
			throw new BadRequestException('amount must be a positive number');
		}
		const fundingSourceId = dto.fundingSourceId.trim();
		const deviceId = (deviceIdHeader || '').trim();
		const riskTarget = await this.resolveFundingSourceRiskTarget(
			req.authUser.userId,
			fundingSourceId,
		);
		const risk = await this.assessTransferRisk(
			req.authUser.userId,
			riskTarget.toUserId,
			Number(dto.amount),
			dto.currency.trim(),
			deviceId,
			true,
			riskTarget.externalPartner,
			riskTarget.externalAccountNo,
		);
		await this.requireStepUpIfNeeded({
			userId: req.authUser.userId,
			deviceId,
			faceVerifiedHeader,
			stepUpTokenHeader,
			risk,
		});

		const transfer = await this.callTransaction(
			this.grpcClients.transaction.createWithdrawalRequest({
					idempotencyKey: dto.idempotencyKey?.trim() || randomUUID(),
					userId: req.authUser.userId,
					fundingSourceId,
					amount: Number(dto.amount),
					currency: dto.currency.trim(),
					memo: dto.memo?.trim() || '',
					simulateFailure: dto.simulateFailure === true,
				})
				.pipe(timeout(this.transferTimeoutMs)),
		) as Record<string, any>;

		return {
			...transfer,
			senderBalance: this.int64ToNumber(transfer.senderBalance),
			receiverBalance: this.int64ToNumber(transfer.receiverBalance),
			risk: {
				stepUpApplied: risk.requiresStepUp,
				reasons: risk.reasons,
				verdict: risk.verdict,
				probability: risk.probability,
				threshold: risk.threshold,
				modelVersion: risk.modelVersion,
			},
		};
	}

	@Get()
	async listTransactions(
		@Req() req: any,
		@Query('limit') limit = '30',
		@Query('offset') offset = '0',
		@Query('includeFailed') includeFailed = 'false',
	) {
		const resolvedLimit = Math.max(1, Math.min(Number(limit) || 30, 200));
		const resolvedOffset = Math.max(0, Number(offset) || 0);
		const includeFailedBool =
			`${includeFailed}`.trim().toLowerCase() === 'true';

		const result = (await this.callTransaction(
			this.grpcClients.transaction.listUserTransactions({
					userId: req.authUser.userId,
					limit: resolvedLimit,
					offset: resolvedOffset,
					includeFailed: includeFailedBool,
				})
				.pipe(timeout(this.grpcTimeoutMs)),
		)) as Record<string, any>;

		const items = Array.isArray(result.items) ? result.items : [];
		const userIds = new Set<string>();
		for (const item of items) {
			const fromUserId = `${item?.fromUserId ?? ''}`.trim();
			const toUserId = `${item?.toUserId ?? ''}`.trim();
			if (fromUserId) {
				userIds.add(fromUserId);
			}
			if (toUserId) {
				userIds.add(toUserId);
			}
		}
		const profileNameMap = new Map<string, string>();
		await Promise.all(
			Array.from(userIds).map(async (userId) => {
				const name = await this.fetchDisplayName(userId);
				if (name) {
					profileNameMap.set(userId, name);
				}
			}),
		);

		return {
			items: items.map((item: any) => ({
				...item,
				amount: this.int64ToNumber(item.amount),
				senderDisplayName:
					profileNameMap.get(`${item?.fromUserId ?? ''}`.trim()) ?? '',
				recipientDisplayName:
					profileNameMap.get(`${item?.toUserId ?? ''}`.trim()) ?? '',
			})),
			limit: resolvedLimit,
			offset: resolvedOffset,
		};
	}

	@Get(':transactionId')
	async getTransaction(
		@Req() req: any,
		@Param('transactionId') transactionId: string,
	) {
		if (!transactionId || transactionId === 'null' || transactionId === 'undefined') {
			throw new BadRequestException('transactionId is required');
		}
		const tx = await this.callTransaction(
			this.grpcClients.transaction
				.getTransaction({ transactionId })
				.pipe(timeout(this.grpcTimeoutMs)),
		) as Record<string, any>;
		if (
			tx.fromUserId !== req.authUser.userId &&
			tx.toUserId !== req.authUser.userId
		) {
			throw new ForbiddenException(
				'Not authorized to view this transaction',
			);
		}
		return {
			...tx,
			amount: this.int64ToNumber(tx.amount),
		};
	}

	private int64ToNumber(value: any): number {
		if (typeof value === 'number' && Number.isFinite(value)) {
			return Math.floor(value);
		}
		if (typeof value === 'string' && value.trim() !== '') {
			const parsed = Number(value);
			if (Number.isFinite(parsed)) {
				return Math.floor(parsed);
			}
		}
		if (value && typeof value === 'object' && typeof value.low === 'number') {
			const high = Number(value.high ?? 0);
			if (high === 0) {
				return value.unsigned ? value.low >>> 0 : value.low;
			}
		}
		return 0;
	}

	private async fetchDisplayName(userId: string): Promise<string> {
		if (!userId) {
			return '';
		}
		const baseUrl = `${this.config.get<string>('AUTH_HTTP_URL') ?? ''}`
			.trim()
			.replace(/\/+$/, '');
		const url = `${baseUrl || this.authInternalBaseUrl()}/internal/auth/profile/${encodeURIComponent(userId)}`;
		try {
			const response = await fetch(url, {
				method: 'GET',
				headers: { 'Content-Type': 'application/json' },
			});
			if (!response.ok) {
				return '';
			}
			const parsed = (await response.json()) as Record<string, unknown>;
			const displayName = `${parsed?.displayName ?? ''}`.trim();
			if (displayName.length > 0) {
				return displayName;
			}
			return `${parsed?.email ?? ''}`.trim();
		} catch {
			return '';
		}
	}

	private async assessTransferRisk(
		userId: string,
		toUserId: string,
		amount: number,
		currency: string,
		deviceId: string,
		isExternal: boolean,
		externalPartner: string,
		externalAccountNo: string,
	) {
		const result = (await this.callTransaction(
			this.grpcClients.transaction
				.assessTransferRisk({
					requestingUserId: userId,
					fromUserId: userId,
					toUserId,
					amount,
					currency,
					deviceId,
					isExternal,
					externalPartner,
					externalAccountNo,
				})
				.pipe(timeout(this.grpcTimeoutMs)),
		)) as Record<string, any>;

		return {
			requiresStepUp: result.requiresStepUp === true,
			reasons: Array.isArray(result.reasons)
				? result.reasons.map((item) => `${item}`).filter(Boolean)
				: [],
			verdict: `${result.verdict ?? ''}`.trim(),
			probability: this.toFiniteNumber(result.probability),
			threshold: this.toFiniteNumber(result.threshold),
			modelVersion: `${result.modelVersion ?? ''}`.trim(),
		};
	}

	private async resolveFundingSourceRiskTarget(
		userId: string,
		fundingSourceId: string,
	): Promise<{
		toUserId: string;
		externalPartner: string;
		externalAccountNo: string;
	}> {
		const result = (await this.callTransaction(
			this.grpcClients.transaction
				.listFundingSources({ userId })
				.pipe(timeout(this.grpcTimeoutMs)),
		)) as Record<string, any>;
		const items = Array.isArray(result.items) ? result.items : [];
		const source = items.find(
			(item) => `${item?.fundingSourceId ?? ''}`.trim() === fundingSourceId,
		);
		if (!source) {
			throw new BadRequestException('Funding source not found');
		}
		const externalPartner = `${source?.provider ?? ''}`.trim();
		return {
			// AtoRiskService currently requires toUserId; use funding source id as stable destination key.
			toUserId: fundingSourceId,
			externalPartner,
			externalAccountNo: fundingSourceId,
		};
	}

	private async requireStepUpIfNeeded(params: {
		userId: string;
		deviceId: string;
		faceVerifiedHeader?: string;
		stepUpTokenHeader?: string;
		risk: {
			requiresStepUp: boolean;
			reasons: string[];
			verdict: string;
			probability: number;
			threshold: number;
		};
	}) {
		const { userId, deviceId, faceVerifiedHeader, stepUpTokenHeader, risk } = params;
		const faceVerified = faceVerifiedHeader === 'true';
		if (!risk.requiresStepUp || faceVerified) {
			return;
		}

		const stepUpToken = (stepUpTokenHeader ?? '').trim();
		if (!stepUpToken) {
			throw new ForbiddenException({
				message: 'Step-up verification required',
				reasons: risk.reasons,
				verdict: risk.verdict,
				probability: risk.probability,
				threshold: risk.threshold,
			});
		}
		const validStepUp = await this.verifyStepUpToken(userId, deviceId, stepUpToken);
		if (!validStepUp) {
			throw new ForbiddenException({
				message: 'Invalid or expired step-up token',
				reasons: risk.reasons,
				verdict: risk.verdict,
			});
		}
	}

	private async verifyStepUpToken(
		userId: string,
		deviceId: string,
		stepUpToken: string,
	): Promise<boolean> {
		const baseUrl = `${this.config.get<string>('AUTH_HTTP_URL') ?? ''}`
			.trim()
			.replace(/\/+$/, '');
		const url = `${baseUrl || this.authInternalBaseUrl()}/internal/auth/step-up/verify`;
		try {
			const response = await fetch(url, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					userId,
					deviceId,
					stepUpToken,
				}),
			});
			if (!response.ok) {
				return false;
			}
			const payload = (await response.json()) as Record<string, unknown>;
			return payload['valid'] === true;
		} catch {
			return false;
		}
	}

	private authInternalBaseUrl(): string {
		return 'http://auth-service:3001';
	}

	private toFiniteNumber(value: any): number {
		if (typeof value === 'number' && Number.isFinite(value)) {
			return value;
		}
		if (typeof value === 'string' && value.trim() !== '') {
			const parsed = Number(value);
			if (Number.isFinite(parsed)) {
				return parsed;
			}
		}
		return 0;
	}

	private async callTransaction<T>(observable: any): Promise<T> {
		try {
			return (await firstValueFrom(observable)) as T;
		} catch (error) {
			this.rethrowGrpcError(error);
		}
	}

	private rethrowGrpcError(error: any): never {
		const code = Number(error?.code);
		const message =
			typeof error?.details === 'string' && error.details.trim()
				? error.details.trim()
				: typeof error?.message === 'string' && error.message.trim()
					? error.message.trim()
					: 'Transaction service error';

		switch (code) {
			case grpcStatus.UNAUTHENTICATED:
				throw new UnauthorizedException(message);
			case grpcStatus.PERMISSION_DENIED:
				throw new ForbiddenException(message);
			case grpcStatus.INVALID_ARGUMENT:
				throw new BadRequestException(message);
			case grpcStatus.NOT_FOUND:
				throw new NotFoundException(message);
			case grpcStatus.ALREADY_EXISTS:
				throw new ConflictException(message);
			case grpcStatus.DEADLINE_EXCEEDED:
				throw new GatewayTimeoutException('Transaction service timeout');
			case grpcStatus.UNAVAILABLE:
				throw new ServiceUnavailableException('Transaction service unavailable');
			default:
				throw new InternalServerErrorException(message);
		}
	}
}
