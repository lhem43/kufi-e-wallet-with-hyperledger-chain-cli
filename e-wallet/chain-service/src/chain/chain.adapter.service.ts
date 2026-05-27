import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { RpcException } from '@nestjs/microservices';
import { status as GrpcStatus } from '@grpc/grpc-js';
import axios, { AxiosError, AxiosInstance } from 'axios';
import {
	createHash,
	createPrivateKey,
	createPublicKey,
	generateKeyPairSync,
	type KeyObject,
	sign as cryptoSign,
} from 'crypto';
import * as fs from 'fs';
import * as https from 'https';
import {
	createTimestampRequest,
	parseTimestampResponse,
	sendTimestampRequest,
	type TSAConfig,
} from 'pdf-rfc3161';

type AnchorTransferRequest = {
	transactionId: string;
	fromUserId: string;
	toUserId?: string;
	amount: number;
	memo?: string;
	internalRef?: string;
	settlementRef?: string;
	timestamp?: string | number;
	nonce: string;
	idempotencyKey: string;
	riskFlag?: string;
};

type AnchorTransferResult = {
	chainStatus: 'ANCHORED' | 'PENDING' | 'FAILED';
	txId: string;
	blockNumber: number;
	commitmentHash: string;
	receiptJson: string;
};

@Injectable()
export class ChainAdapterService {
	private readonly logger = new Logger(ChainAdapterService.name);
	private readonly client: AxiosInstance;
	private readonly observerClients: AxiosInstance[];
	private readonly requireTransparencyQuorum: boolean;
	private readonly receiptSigningEnabled: boolean;
	private readonly receiptSigningKeyId: string;
	private readonly receiptSigningPrivateKey: KeyObject | null;
	private readonly receiptSigningPublicKeyFingerprint: string;
	private readonly receiptTsaEnabled: boolean;
	private readonly receiptTsaFailOpen: boolean;
	private readonly receiptTsaConfig: TSAConfig;

	constructor(private readonly cfg: ConfigService) {
		const baseURL = (this.cfg.get('CHAIN_NODE_URL') as string | undefined)?.trim();
		if (!baseURL) {
			throw new Error('CHAIN_NODE_URL is required');
		}
		const timeout = Number(this.cfg.get('CHAIN_REQUEST_TIMEOUT_MS') ?? 8000);
		const certPath = this.cfg.get('CHAIN_CLIENT_CERT_PATH') ?? '';
		const keyPath = this.cfg.get('CHAIN_CLIENT_KEY_PATH') ?? '';
		const caPath = this.cfg.get('CHAIN_CA_CERT_PATH') ?? '';
		const skipVerify =
			String(this.cfg.get('CHAIN_SKIP_TLS_VERIFY') ?? 'false').toLowerCase() ===
			'true';

		const httpsAgent = new https.Agent({
			cert: certPath ? fs.readFileSync(certPath) : undefined,
			key: keyPath ? fs.readFileSync(keyPath) : undefined,
			ca: caPath ? fs.readFileSync(caPath) : undefined,
			rejectUnauthorized: !skipVerify,
			keepAlive: true,
			maxSockets: 256,
		});

		this.client = axios.create({
			baseURL,
			timeout,
			httpsAgent,
			headers: { 'Content-Type': 'application/json' },
		});

		const observerUrlsRaw =
			(this.cfg.get('CHAIN_OBSERVER_URLS') as string | undefined) ?? '';
		const observerUrls = observerUrlsRaw
			.split(',')
			.map((v) => v.trim())
			.filter((v) => v.length > 0 && v !== baseURL);
		this.observerClients = observerUrls.map((url) =>
			axios.create({
				baseURL: url,
				timeout,
				httpsAgent,
				headers: { 'Content-Type': 'application/json' },
			}),
		);
		this.requireTransparencyQuorum =
			String(this.cfg.get('CHAIN_REQUIRE_TRANSPARENCY_QUORUM') ?? 'false').toLowerCase() ===
			'true';

		this.receiptSigningEnabled =
			String(this.cfg.get('RECEIPT_SIGNING_ENABLED') ?? 'true').toLowerCase() !==
			'false';
		this.receiptSigningKeyId =
			(this.cfg.get('RECEIPT_SIGNING_KEY_ID') as string | undefined)?.trim() ||
			'kufi-receipt-ed25519-v1';

		const signingMaterial = this.loadOrCreateReceiptSigningKeyPair();
		this.receiptSigningPrivateKey = signingMaterial.privateKey;
		this.receiptSigningPublicKeyFingerprint = signingMaterial.publicKeyFingerprint;
		this.receiptTsaEnabled =
			String(this.cfg.get('RECEIPT_TSA_ENABLED') ?? 'false').toLowerCase() === 'true';
		this.receiptTsaFailOpen =
			String(this.cfg.get('RECEIPT_TSA_FAIL_OPEN') ?? 'true').toLowerCase() !== 'false';
		this.receiptTsaConfig = {
			url: (this.cfg.get('RECEIPT_TSA_URL') as string | undefined)?.trim() || 'https://freetsa.org/tsr',
			hashAlgorithm: 'SHA-256',
			requestCertificate: true,
			timeout: Number(this.cfg.get('RECEIPT_TSA_TIMEOUT_MS') ?? 12000),
			retry: Number(this.cfg.get('RECEIPT_TSA_RETRY') ?? 1),
			retryDelay: Number(this.cfg.get('RECEIPT_TSA_RETRY_DELAY_MS') ?? 750),
		};
	}

	async anchorTransfer(data: AnchorTransferRequest): Promise<AnchorTransferResult> {
		const riskFlag = this.normalizeRiskFlag(data.riskFlag);
		const toId = data.toUserId || 'external';
		const internalRef = data.internalRef || data.transactionId;
		const settlementRef = data.settlementRef || data.transactionId;
		const amount = this.normalizeAmount(data.amount);
		if (!Number.isInteger(amount) || amount <= 0) {
			throw new RpcException({
				code: GrpcStatus.INVALID_ARGUMENT,
				message: 'amount must be a positive integer',
			});
		}

		// Detect transfer type: if toUserId looks like 'external' or is empty,
		// it's external (inter-bank). Otherwise it's an internal (intra-bank) transfer.
		const isInternalTransfer =
			data.toUserId != null &&
			data.toUserId.trim() !== '' &&
			data.toUserId.trim().toLowerCase() !== 'external';
		const transferType = isInternalTransfer ? 'intra_bank' : 'inter_bank';

		const payload = {
			from_id: data.fromUserId,
			to_id: toId,
			amount_vnd: amount,
			memo: data.memo || '',
			internal_ref: internalRef,
			settlement_ref: settlementRef,
			idempotency_key: data.idempotencyKey,
			nonce: data.nonce,
			timestamp: this.toUnixMillis(data.timestamp),
			transfer_type: transferType,
			risk_flag: riskFlag,
		};

		const maxRetries = 2;
		let lastError: Error | null = null;

		for (let attempt = 0; attempt <= maxRetries; attempt++) {
			try {
				const response = await this.client.post('/v1/transfer', payload);
				const parsed = this.parseAnchorTransferResponse(response.data);
				if (parsed.chainStatus === 'ANCHORED') {
					this.logger.log(
						`Anchored tx=${data.transactionId} chainTx=${parsed.txId} block=${parsed.blockNumber}`,
					);
				} else {
					this.logger.warn(
						`Chain accepted but still processing tx=${data.transactionId} chainTx=${parsed.txId || 'unknown'}`,
					);
				}
				return await this.enrichWithObserverConfirmations(parsed);
			} catch (err) {
				lastError = err instanceof Error ? err : new Error(String(err));
				if (this.isTransientError(err) && attempt < maxRetries) {
					const delay = Math.min(500 * Math.pow(2, attempt), 2000);
					this.logger.warn(
						`Transient chain error (attempt ${attempt + 1}/${maxRetries + 1}), retrying in ${delay}ms: ${lastError.message}`,
					);
					await this.sleep(delay);
					continue;
				}
				throw this.toGrpcException(err);
			}
		}

		throw this.toGrpcException(lastError);
	}

	async getReceipt(txId: string): Promise<AnchorTransferResult> {
		const normalizedTxId = txId?.trim();
		if (!normalizedTxId) {
			throw new RpcException({
				code: GrpcStatus.INVALID_ARGUMENT,
				message: 'txId is required',
			});
		}

		try {
			const response = await this.client.get(
				`/v1/receipt/${encodeURIComponent(normalizedTxId)}`,
			);
			const parsed = this.parseReceiptLookupResponse(response.data, normalizedTxId);
			return await this.enrichWithObserverConfirmations(parsed);
		} catch (err) {
			if (axios.isAxiosError(err) && err.response?.status === 404) {
				return this.buildPendingResult(normalizedTxId);
			}
			throw this.toGrpcException(err);
		}
	}

	private parseAnchorTransferResponse(body: any): AnchorTransferResult {
		if (!body) {
			throw new Error('empty gateway response');
		}

		const pending = this.isPendingPayload(body);
		if (body.success === false && !pending) {
			const errMsg =
				this.asString(body?.error?.message) ??
				this.asString(body?.error?.details) ??
				'gateway returned unsuccessful result';
			throw new Error(errMsg);
		}

		const receiptPayload = this.extractReceiptPayload(body);
		const txId =
			this.asString(body?.tx_id) ??
			this.asString(body?.txId) ??
			this.asString(receiptPayload?.tx_id) ??
			'';

		if (receiptPayload) {
			const parsed = this.buildResultFromReceipt(receiptPayload, body, txId);
			if (parsed.chainStatus !== 'PENDING') {
				return parsed;
			}
		}

		if (pending || txId !== '') {
			return this.buildPendingResult(txId);
		}

		throw new Error('missing tx_id in gateway response');
	}

	private parseReceiptLookupResponse(body: any, txId: string): AnchorTransferResult {
		if (!body) {
			return this.buildPendingResult(txId);
		}

		const pending = this.isPendingPayload(body);
		if (body.success === false && !pending) {
			const errCode = this.asString(body?.error?.code);
			if (errCode === 'NOT_FOUND') {
				return this.buildPendingResult(txId);
			}
			const errMsg =
				this.asString(body?.error?.message) ??
				this.asString(body?.error?.details) ??
				'gateway returned unsuccessful result';
			throw new Error(errMsg);
		}

		const receiptPayload = this.extractReceiptPayload(body);
		if (!receiptPayload) {
			return this.buildPendingResult(txId);
		}

		const parsed = this.buildResultFromReceipt(receiptPayload, body, txId);
		if (parsed.chainStatus !== 'PENDING') {
			return parsed;
		}

		return this.buildPendingResult(parsed.txId || txId, receiptPayload);
	}

	private extractReceiptPayload(body: any): Record<string, any> | null {
		if (!body || typeof body !== 'object') {
			return null;
		}

		if (body.receipt && typeof body.receipt === 'object') {
			return body.receipt as Record<string, any>;
		}

		const maybeDirectReceipt =
			this.asString(body?.tx_id) ||
			this.asString(body?.receipt_hash) ||
			this.asString(body?.commitment_hash) ||
			this.asString(body?.schema_version);
		if (maybeDirectReceipt) {
			return body as Record<string, any>;
		}

		return null;
	}

	private buildResultFromReceipt(
		receipt: Record<string, any>,
		envelope: Record<string, any> | null,
		fallbackTxId: string,
	): AnchorTransferResult {
		const txId =
			this.asString(receipt?.tx_id) ??
			this.asString(envelope?.tx_id) ??
			fallbackTxId;
		const blockNumber = Number(receipt?.block_number ?? 0);
		const commitmentHash = this.asString(receipt?.commitment_hash) ?? '';

		const validationCode = Number(receipt?.validation_code);
		const validationCodeName =
			(this.asString(receipt?.validation_code_name) ?? '').toUpperCase();
		const isValidationSuccess =
			(Number.isFinite(validationCode) && validationCode === 0) ||
			validationCodeName === 'VALID';
		const isValidationFailure =
			(Number.isFinite(validationCode) && validationCode > 0) ||
			(validationCodeName !== '' &&
				validationCodeName !== 'VALID' &&
				validationCodeName !== 'NOT_VALIDATED');
		const hasBlockProof =
			blockNumber > 0 || this.asString(receipt?.block_hash) !== null;
		const hasReceiptHash = this.asString(receipt?.receipt_hash) !== null;
		const hasPolicyInfo =
			this.asString(receipt?.policy_id) !== null &&
			Array.isArray(receipt?.endorsements);
		const endorsements = Array.isArray(receipt?.endorsements)
			? (receipt.endorsements as Array<Record<string, any>>)
			: [];
		const originMsp =
			(this.asString(receipt?.origin_msp_id) ?? '').toUpperCase();
		const distinctMsps = new Set(
			endorsements
				.map((e) => (this.asString(e?.msp_id) ?? '').toUpperCase())
				.filter((msp) => msp.length > 0),
		);
		const hasIndependentEndorser =
			originMsp.length > 0
				? Array.from(distinctMsps).some((msp) => msp !== originMsp)
				: distinctMsps.size >= 2;
		const hasTransparencyQuorum = distinctMsps.size >= 2 && hasIndependentEndorser;
		const policyMetFlag = receipt?.policy_met === true;
		const hasCommitment = commitmentHash !== '';
		const hasSchemaVersion = this.asString(receipt?.schema_version) !== null;
		const hasVerifiableBundle =
			txId !== '' &&
			hasCommitment &&
			hasBlockProof &&
			hasReceiptHash &&
			hasPolicyInfo &&
			hasSchemaVersion;

		const flat =
			envelope && envelope.receipt
				? {
						...envelope,
						...receipt,
					}
				: { ...receipt };
		const hasReceiptBody = Object.keys(flat).length > 0;

		if (isValidationSuccess && hasVerifiableBundle) {
			return {
				chainStatus: 'ANCHORED',
				txId,
				blockNumber,
				commitmentHash,
				receiptJson: hasReceiptBody ? JSON.stringify(flat) : '',
			};
		}
		if (isValidationSuccess && !hasVerifiableBundle) {
			this.logger.warn(
				`Receipt is valid but incomplete for self-verification tx=${txId || 'unknown'}; waiting for full receipt bundle`,
			);
		}
		if (isValidationSuccess && (!policyMetFlag || !hasTransparencyQuorum)) {
			this.logger.warn(
				`Receipt committed without independent endorsement quorum tx=${txId || 'unknown'} origin=${originMsp || 'unknown'} endorsers=${Array.from(distinctMsps).join(',')}`,
			);
		}

		if (isValidationFailure) {
			return {
				chainStatus: 'FAILED',
				txId,
				blockNumber,
				commitmentHash,
				receiptJson: hasReceiptBody ? JSON.stringify(flat) : '',
			};
		}

		return this.buildPendingResult(txId, hasReceiptBody ? flat : undefined);
	}

	private buildPendingResult(
		txId: string,
		body?: Record<string, any>,
	): AnchorTransferResult {
		return {
			chainStatus: 'PENDING',
			txId: txId || '',
			blockNumber: Number(body?.block_number ?? 0),
			commitmentHash: this.asString(body?.commitment_hash) ?? '',
			receiptJson: body && Object.keys(body).length > 0 ? JSON.stringify(body) : '',
		};
	}

	private async enrichWithObserverConfirmations(
		result: AnchorTransferResult,
	): Promise<AnchorTransferResult> {
		if (!result.receiptJson || this.observerClients.length === 0 || !result.txId) {
			return this.enrichWithReceiptIntegrity(result);
		}

		let receipt: Record<string, any> | null = null;
		try {
			const decoded = JSON.parse(result.receiptJson);
			if (decoded && typeof decoded === 'object') {
				receipt = decoded as Record<string, any>;
			}
		} catch {
			return result;
		}
		if (!receipt) {
			return this.enrichWithReceiptIntegrity(result);
		}

		const txId = this.asString(receipt.tx_id) ?? result.txId;
		const blockHash = this.asString(receipt.block_hash) ?? '';
		const originMsp = (this.asString(receipt.origin_msp_id) ?? '').toUpperCase();
		const confirmations = await this.collectObserverConfirmations(txId, blockHash, originMsp);
		receipt.observer_confirmations = confirmations;

		const totalNodes = 1 + this.observerClients.length;
		const requiredQuorum = Math.floor(totalNodes / 2) + 1;
		const confirmedNodes = 1 + confirmations.length;
		const quorumMet = confirmedNodes >= requiredQuorum;
		receipt.transparency = {
			total_nodes: totalNodes,
			required_quorum: requiredQuorum,
			confirmed_nodes: confirmedNodes,
			quorum_met: quorumMet,
		};
		result.receiptJson = JSON.stringify(receipt);

		if (result.chainStatus === 'ANCHORED' && this.requireTransparencyQuorum && !quorumMet) {
			result.chainStatus = 'PENDING';
		}
		return this.enrichWithReceiptIntegrity(result);
	}

	private async enrichWithReceiptIntegrity(
		result: AnchorTransferResult,
	): Promise<AnchorTransferResult> {
		if (!this.receiptSigningEnabled || !result.receiptJson) {
			return result;
		}
		if (!this.receiptSigningPrivateKey) {
			this.logger.warn('Receipt signing is enabled but private key is unavailable');
			return result;
		}

		let receipt: Record<string, unknown> | null = null;
		try {
			const decoded = JSON.parse(result.receiptJson);
			if (decoded && typeof decoded === 'object') {
				receipt = decoded as Record<string, unknown>;
			}
		} catch {
			return result;
		}
		if (!receipt) {
			return result;
		}

		try {
			const payload: Record<string, unknown> = { ...receipt };
			delete payload.receipt_integrity;

			const canonicalPayload = this.canonicalStringify(payload);
			const canonicalBytes = Buffer.from(canonicalPayload, 'utf8');
			const hashSha256 = createHash('sha256').update(canonicalBytes).digest('hex');
			const hashSha3 = createHash('sha3-256').update(canonicalBytes).digest('hex');
			const combinedHash = createHash('sha256')
				.update(`${hashSha256}:${hashSha3}`, 'utf8')
				.digest('hex');
			const signature = cryptoSign(null, canonicalBytes, this.receiptSigningPrivateKey);
			const signedAt = Date.now();

			const receiptIntegrity: Record<string, unknown> = {
				version: 'v1',
				canonicalization: 'json-sorted-v1',
				hashes: {
					sha256: hashSha256,
					sha3_256: hashSha3,
					combined_sha256: combinedHash,
				},
				signature: {
					algorithm: 'ed25519',
					key_id: this.receiptSigningKeyId,
					signature_base64: signature.toString('base64'),
					signed_at: signedAt,
				},
				signer: {
					public_key_fingerprint_sha256:
						this.receiptSigningPublicKeyFingerprint,
				},
			};
			const tsaAttestation = await this.createTsaAttestation(canonicalBytes, hashSha256);
			if (tsaAttestation) {
				receiptIntegrity.tsa_attestation = tsaAttestation;
			}
			receipt.receipt_integrity = receiptIntegrity;
			result.receiptJson = JSON.stringify(receipt);
		} catch (error) {
			const msg = error instanceof Error ? error.message : String(error);
			this.logger.warn(`Could not attach receipt integrity signature: ${msg}`);
		}
		return result;
	}

	private async collectObserverConfirmations(
		txId: string,
		expectedBlockHash: string,
		originMsp: string,
	): Promise<Array<Record<string, any>>> {
		const confirmations: Array<Record<string, any>> = [];
		for (const client of this.observerClients) {
			try {
				const response = await client.get(`/v1/observe/${encodeURIComponent(txId)}`);
				const data =
					response?.data && typeof response.data === 'object'
						? (response.data as Record<string, any>)
						: null;
				if (!data) continue;
				const validationCode = Number(data.validation_code);
				if (!Number.isFinite(validationCode) || validationCode !== 0) continue;
				const blockHash = this.asString(data.block_hash) ?? '';
				if (expectedBlockHash && blockHash && blockHash !== expectedBlockHash) continue;
				const mspId = (this.asString(data.msp_id) ?? '').toUpperCase();
				if (!mspId || (originMsp && mspId === originMsp)) continue;
				confirmations.push(data);
			} catch (err) {
				const msg = err instanceof Error ? err.message : String(err);
				this.logger.warn(`Observer confirmation failed tx=${txId}: ${msg}`);
			}
		}
		return confirmations;
	}

	private isPendingPayload(body: any): boolean {
		const markers = [
			this.asString(body?.status),
			this.asString(body?.state),
			this.asString(body?.chain_status),
			this.asString(body?.chainStatus),
			this.asString(body?.error?.code),
			this.asString(body?.error?.message),
		]
			.filter(Boolean)
			.map((value) => String(value).toUpperCase());

		return markers.some(
			(value) =>
				value.includes('PENDING') ||
				value.includes('PROCESSING') ||
				value.includes('SUBMITTED') ||
				value.includes('IN_PROGRESS') ||
				value.includes('NOT_FOUND'),
		);
	}

	private toUnixMillis(value?: string | number): number {
		if (typeof value === 'number' && Number.isFinite(value) && value > 0) {
			return Math.floor(value);
		}
		if (typeof value === 'string' && value.trim() !== '') {
			const maybeNum = Number(value);
			if (Number.isFinite(maybeNum) && maybeNum > 0) {
				return Math.floor(maybeNum);
			}
			const parsed = Date.parse(value);
			if (!Number.isNaN(parsed)) {
				return parsed;
			}
		}
		return Date.now();
	}

	private normalizeAmount(raw: unknown): number {
		if (typeof raw === 'number' && Number.isFinite(raw)) {
			return Math.floor(raw);
		}
		if (typeof raw === 'string' && raw.trim() !== '') {
			const parsed = Number(raw);
			if (Number.isFinite(parsed)) {
				return Math.floor(parsed);
			}
		}
		if (raw && typeof raw === 'object') {
			const asLong = raw as { low?: unknown; high?: unknown; unsigned?: unknown };
			if (typeof asLong.low === 'number') {
				const high = Number(asLong.high ?? 0);
				if (high === 0) {
					const low = Number(asLong.low);
					return asLong.unsigned ? low >>> 0 : low;
				}
			}
		}
		return Number.NaN;
	}

	private asString(value: unknown): string | null {
		return typeof value === 'string' && value.trim() !== '' ? value : null;
	}

	private canonicalStringify(value: unknown): string {
		if (value === null || value === undefined) {
			return 'null';
		}
		if (typeof value === 'number') {
			return Number.isFinite(value) ? JSON.stringify(value) : 'null';
		}
		if (typeof value === 'boolean') {
			return value ? 'true' : 'false';
		}
		if (typeof value === 'string') {
			return JSON.stringify(value);
		}
		if (Array.isArray(value)) {
			return `[${value.map((item) => this.canonicalStringify(item)).join(',')}]`;
		}
		if (typeof value === 'object') {
			const record = value as Record<string, unknown>;
			const keys = Object.keys(record).sort((a, b) => a.localeCompare(b));
			const entries = keys.map(
				(k) => `${JSON.stringify(k)}:${this.canonicalStringify(record[k])}`,
			);
			return `{${entries.join(',')}}`;
		}
		return JSON.stringify(String(value));
	}

	private loadOrCreateReceiptSigningKeyPair(): {
		privateKey: KeyObject | null;
		publicKeyFingerprint: string;
	} {
		if (!this.receiptSigningEnabled) {
			return {
				privateKey: null,
				publicKeyFingerprint: '',
			};
		}

		const envPrivatePem = (
			this.cfg.get('RECEIPT_SIGNING_PRIVATE_KEY_PEM') as string | undefined
		)?.trim();
		const envPublicPem = (
			this.cfg.get('RECEIPT_SIGNING_PUBLIC_KEY_PEM') as string | undefined
		)?.trim();
		if (envPrivatePem) {
			const privateKey = createPrivateKey(envPrivatePem);
			const publicKey = envPublicPem
				? createPublicKey(envPublicPem)
				: createPublicKey(privateKey);
			const fingerprint = createHash('sha256')
				.update(publicKey.export({ type: 'spki', format: 'der' }))
				.digest('hex');
			return {
				privateKey,
				publicKeyFingerprint: fingerprint,
			};
		}

		const privateKeyPath =
			(this.cfg.get('RECEIPT_SIGNING_PRIVATE_KEY_PATH') as string | undefined)?.trim() ||
			'/workspace/e-wallet/chain-service/keys/receipt-ed25519-private.pem';
		const publicKeyPath =
			(this.cfg.get('RECEIPT_SIGNING_PUBLIC_KEY_PATH') as string | undefined)?.trim() ||
			'/workspace/e-wallet/chain-service/keys/receipt-ed25519-public.pem';

		let privateKeyPem = '';
		let publicKeyPem = '';
		try {
			if (fs.existsSync(privateKeyPath)) {
				privateKeyPem = fs.readFileSync(privateKeyPath, 'utf8');
			}
			if (fs.existsSync(publicKeyPath)) {
				publicKeyPem = fs.readFileSync(publicKeyPath, 'utf8');
			}
		} catch (error) {
			const msg = error instanceof Error ? error.message : String(error);
			this.logger.warn(`Could not read receipt signing key files: ${msg}`);
		}

		if (!privateKeyPem) {
			const generated = generateKeyPairSync('ed25519');
			privateKeyPem = generated.privateKey.export({
				type: 'pkcs8',
				format: 'pem',
			}) as string;
			publicKeyPem = generated.publicKey.export({
				type: 'spki',
				format: 'pem',
			}) as string;
			try {
				const privateDir = privateKeyPath.includes('/')
					? privateKeyPath.substring(0, privateKeyPath.lastIndexOf('/'))
					: '.';
				if (privateDir) {
					fs.mkdirSync(privateDir, { recursive: true });
				}
				fs.writeFileSync(privateKeyPath, privateKeyPem, { mode: 0o600 });
				fs.writeFileSync(publicKeyPath, publicKeyPem, { mode: 0o644 });
				this.logger.warn(
					`Generated development receipt signing key pair at ${privateKeyPath}`,
				);
			} catch (error) {
				const msg = error instanceof Error ? error.message : String(error);
				this.logger.warn(`Could not persist generated signing key pair: ${msg}`);
			}
		}

		const privateKey = createPrivateKey(privateKeyPem);
		const publicKey = publicKeyPem
			? createPublicKey(publicKeyPem)
			: createPublicKey(privateKey);
		const fingerprint = createHash('sha256')
			.update(publicKey.export({ type: 'spki', format: 'der' }))
			.digest('hex');
		return {
			privateKey,
			publicKeyFingerprint: fingerprint,
		};
	}

	private async createTsaAttestation(
		payloadBytes: Uint8Array,
		expectedSha256Hex: string,
	): Promise<Record<string, unknown> | null> {
		if (!this.receiptTsaEnabled) {
			return null;
		}

		try {
			const tsq = await createTimestampRequest(payloadBytes, {
				hashAlgorithm: 'SHA-256',
				requestCertificate: true,
			});
			const tsr = await sendTimestampRequest(tsq, this.receiptTsaConfig);
			const parsed = parseTimestampResponse(tsr);
			if (!parsed.token || !parsed.info) {
				throw new Error('TSA response has no token/info');
			}
			const reportedDigest = (parsed.info.messageDigest || '').toLowerCase();

			return {
				provider: 'FreeTSA',
				url: this.receiptTsaConfig.url,
				status: parsed.status,
				status_text: parsed.statusString ?? '',
				token_der_base64: Buffer.from(parsed.token).toString('base64'),
				response_der_base64: Buffer.from(tsr).toString('base64'),
				gen_time: parsed.info.genTime.toISOString(),
				serial_number: parsed.info.serialNumber,
				policy: parsed.info.policy,
				hash_algorithm: parsed.info.hashAlgorithm,
				message_imprint_sha256: expectedSha256Hex.toLowerCase(),
				reported_message_digest: reportedDigest,
			};
		} catch (error) {
			const msg = error instanceof Error ? error.message : String(error);
			if (this.receiptTsaFailOpen) {
				this.logger.warn(`TSA attestation failed (fail-open): ${msg}`);
				return {
					provider: 'FreeTSA',
					url: this.receiptTsaConfig.url,
					error: msg,
				};
			}
			throw error;
		}
	}

	/** Returns true for errors that are safe to retry (timeouts, connection issues). */
	private isTransientError(err: unknown): boolean {
		if (axios.isAxiosError(err)) {
			const axiosErr = err as AxiosError;
			if (!axiosErr.response) {
				return true;
			}
			const status = axiosErr.response.status;
			return status === 408 || status === 429 || status === 502 || status === 503 || status === 504;
		}
		return false;
	}

	/** Maps HTTP / application errors to appropriate gRPC status codes. */
	private toGrpcException(err: unknown): RpcException {
		if (err instanceof RpcException) return err;

		let code = GrpcStatus.INTERNAL;
		let message = 'chain service error';

		if (axios.isAxiosError(err)) {
			const axiosErr = err as AxiosError<any>;
			const status = axiosErr.response?.status;
			const payload = axiosErr.response?.data;
			const payloadText =
				typeof payload === 'string'
					? payload
					: payload
						? JSON.stringify(payload)
						: '';

			message = [status ? `HTTP ${status}` : null, payloadText, axiosErr.message]
				.filter(Boolean)
				.join(' | ');

			if (!status) {
				// Network error or timeout
				code = GrpcStatus.UNAVAILABLE;
			} else if (status === 400) {
				code = GrpcStatus.INVALID_ARGUMENT;
			} else if (status === 404) {
				code = GrpcStatus.NOT_FOUND;
			} else if (status === 409) {
				code = GrpcStatus.ALREADY_EXISTS;
			} else if (status === 429) {
				code = GrpcStatus.RESOURCE_EXHAUSTED;
			} else if (status === 502 || status === 503 || status === 504) {
				code = GrpcStatus.UNAVAILABLE;
			} else if (status >= 500) {
				code = GrpcStatus.INTERNAL;
			}
		} else if (err instanceof Error) {
			message = err.message;
		}

		return new RpcException({ code, message });
	}

	private sleep(ms: number): Promise<void> {
		return new Promise((resolve) => setTimeout(resolve, ms));
	}

	private normalizeRiskFlag(riskFlag?: string): string {
		if (riskFlag === 'MED' || riskFlag === 'HIGH') {
			return riskFlag;
		}
		return 'LOW';
	}
}
