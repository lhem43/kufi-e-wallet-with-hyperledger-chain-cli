import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { createHmac, randomUUID } from 'crypto';
import { Repository } from 'typeorm';

import {
  ExternalTransfer,
  ExternalTransferStatus,
  ExternalTransferType,
} from './entities/external-transfer.entity';

interface PartnerConfig {
  partnerCode: string;
  baseUrl: string;
  initiatePath: string;
  statusPath: string;
  statusMethod: 'GET' | 'POST';
  requestStyle: 'MOMO' | 'BANK' | 'VNPAY' | 'ZALOPAY' | 'GENERIC';
  timeoutMs: number;
  apiKey: string;
  apiSecret: string;
  clientId: string;
  merchantId: string;
  bearerToken: string;
  apiKeyHeader: string;
  clientIdHeader: string;
  merchantIdHeader: string;
  signatureHeader: string;
  signatureMode:
    | 'LEGACY_HEADER_SHA256'
    | 'HEADER_CANONICAL'
    | 'VNPAY_QUERY_SHA512'
    | 'ZALOPAY_MAC_SHA256'
    | 'PAYLOAD_FIELDS_HMAC';
  signatureAlgorithm: 'sha256' | 'sha512';
  signaturePayloadField: string;
  signatureFields: string[];
  signatureJoiner: string;
  extraHeaders: Record<string, string>;
  initiateStaticFields: Record<string, any>;
  checkStaticFields: Record<string, any>;
  mapping: FieldMapping;
}

interface FieldMapping {
  initiateStatusPaths: string[];
  initiateReferencePaths: string[];
  initiateMessagePaths: string[];
  checkStatusPaths: string[];
  checkMessagePaths: string[];
  failedTokens: string[];
  successTokens: string[];
  pendingTokens: string[];
}

@Injectable()
export class TransfersService {
  private readonly logger = new Logger(TransfersService.name);

  constructor(
    private readonly cfg: ConfigService,
    @InjectRepository(ExternalTransfer)
    private readonly externalRepo: Repository<ExternalTransfer>,
  ) {}

  async initiateTransfer(data: any) {
    const partnerCode = this.normalizeKnownPartnerCode(data.partnerCode);
    const amount = this.parseAmount(data.amount);
    const transferType = this.parseTransferType(data.transferType);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new Error('Invalid amount');
    }

    const existed = await this.externalRepo.findOne({
      where: { transactionId: data.transactionId },
    });
    if (existed) {
      return {
        status: existed.status,
        partnerRef: existed.partnerRef,
        partnerMessage: existed.partnerMessage ?? 'Already submitted',
      };
    }

    const partnerConfig = this.resolvePartnerRuntimeConfig(partnerCode);
    let status: ExternalTransferStatus = ExternalTransferStatus.SUBMITTED;
    let partnerMessage = 'Transfer accepted';
    let partnerRef = `${partnerCode}-${Date.now()}-${Math.floor(Math.random() * 100000)}`;

    if (partnerConfig) {
      const partnerResult = await this.initiateViaPartner(partnerConfig, {
        ...data,
        partnerCode,
        amount,
      });
      status = partnerResult.status;
      partnerMessage = partnerResult.partnerMessage;
      partnerRef = partnerResult.partnerRef || partnerRef;
    } else {
      status = ExternalTransferStatus.SUBMITTED;
      partnerMessage = this.buildMockSubmittedMessage(partnerCode);
      partnerRef = `${partnerCode}-MOCK-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    }

    const transfer = this.externalRepo.create({
      transactionId: data.transactionId,
      partnerCode,
      accountNo: data.accountNo,
      transferType,
      amount,
      currency: (data.currency || 'VND').toUpperCase(),
      partnerRef,
      status,
      partnerMessage,
    });
    const saved = await this.externalRepo.save(transfer);
    return {
      status: saved.status,
      partnerRef: saved.partnerRef,
      partnerMessage: saved.partnerMessage ?? '',
    };
  }

  async checkTransfer(data: any) {
    const transfer = await this.externalRepo.findOne({
      where: { partnerRef: data.partnerRef },
    });
    if (!transfer) {
      return {
        status: ExternalTransferStatus.FAILED,
        partnerMessage: 'Partner reference not found',
      };
    }

    if (transfer.status === ExternalTransferStatus.SUBMITTED) {
      const partnerCode = this.normalizeKnownPartnerCode(
        transfer.partnerCode || data.partnerCode,
      );
      const partnerConfig = this.resolvePartnerRuntimeConfig(partnerCode);

      if (partnerConfig) {
        const remote = await this.checkViaPartner(partnerConfig, transfer);
        if (
          remote &&
          (remote.status === ExternalTransferStatus.SETTLED ||
            remote.status === ExternalTransferStatus.FAILED)
        ) {
          transfer.status = remote.status;
          transfer.partnerMessage = remote.partnerMessage;
          await this.externalRepo.save(transfer);
        }
      } else {
        const shouldSettle = this.shouldSettleMockTransfer(transfer);
        if (shouldSettle) {
          transfer.status = ExternalTransferStatus.SETTLED;
          transfer.partnerMessage = this.buildMockSettledMessage(partnerCode);
          await this.externalRepo.save(transfer);
        } else {
          transfer.partnerMessage = this.buildMockSubmittedMessage(partnerCode);
          await this.externalRepo.save(transfer);
        }
      }
    }

    return {
      status: transfer.status,
      partnerMessage: transfer.partnerMessage ?? '',
    };
  }

  // ── Partner API integration ───────────────────────────────

  private async initiateViaPartner(
    config: PartnerConfig,
    data: any,
  ): Promise<{
    status: ExternalTransferStatus;
    partnerRef: string;
    partnerMessage: string;
  }> {
    try {
      const payload = this.buildInitiatePayload(config, data);
      const response = await this.callPartnerApi(
        config,
        config.initiatePath,
        'POST',
        payload,
      );
      const extractedStatus = this.extractStatus(
        response.payload,
        'initiate',
        response.ok,
        config.mapping.initiateStatusPaths,
        config.mapping,
      );
      const extractedRef = this.extractString(
        response.payload,
        config.mapping.initiateReferencePaths,
      );
      const extractedMessage = this.extractString(
        response.payload,
        config.mapping.initiateMessagePaths,
      );

      if (
        extractedStatus === ExternalTransferStatus.FAILED ||
        (!response.ok && response.httpStatus >= 400)
      ) {
        return {
          status: ExternalTransferStatus.FAILED,
          partnerRef:
            extractedRef || `${config.partnerCode}-${Date.now()}-FAILED`,
          partnerMessage:
            extractedMessage ||
            `Partner ${config.partnerCode} rejected transfer`,
        };
      }
      return {
        status: extractedStatus,
        partnerRef:
          extractedRef ||
          `${config.partnerCode}-${Date.now()}-${randomUUID()}`,
        partnerMessage:
          extractedMessage ||
          `Partner ${config.partnerCode} accepted ${this.parseTransferType(data.transferType).toLowerCase()} request`,
      };
    } catch (error: any) {
      const message = this.getErrorMessage(error);
      this.logger.error(
        `Partner submit failed partner=${config.partnerCode}: ${message}`,
      );
      return {
        status: ExternalTransferStatus.FAILED,
        partnerRef: `${config.partnerCode}-${Date.now()}-ERROR`,
        partnerMessage: message || 'Partner service unavailable',
      };
    }
  }

  private async checkViaPartner(
    config: PartnerConfig,
    transfer: ExternalTransfer,
  ): Promise<{
    status: ExternalTransferStatus;
    partnerMessage: string;
  } | null> {
    try {
      const payload = this.buildCheckPayload(config, transfer);
      const response = await this.callPartnerApi(
        config,
        config.statusPath,
        config.statusMethod,
        payload,
      );
      const extractedStatus = this.extractStatus(
        response.payload,
        'check',
        response.ok,
        config.mapping.checkStatusPaths,
        config.mapping,
      );
      const extractedMessage = this.extractString(
        response.payload,
        config.mapping.checkMessagePaths,
      );

      if (!response.ok && response.httpStatus >= 500) {
        this.logger.warn(
          `Partner check temporary error partner=${config.partnerCode} status=${response.httpStatus}`,
        );
        return null;
      }
      return {
        status: extractedStatus,
        partnerMessage:
          extractedMessage ||
          `Partner ${config.partnerCode} status: ${extractedStatus}`,
      };
    } catch (error: any) {
      this.logger.warn(
        `Partner check failed partner=${config.partnerCode}: ${this.getErrorMessage(error)}`,
      );
      return null;
    }
  }

  // ── Payload builders ──────────────────────────────────────

  private buildInitiatePayload(config: PartnerConfig, data: any): any {
    const requestId = randomUUID();
    const requestTime = new Date().toISOString();

    if (config.requestStyle === 'MOMO') {
      return {
        requestId,
        orderId: data.transactionId,
        partnerCode:
          config.clientId || config.merchantId || data.partnerCode,
        amount: data.amount,
        orderInfo: data.note || `Transfer ${data.transactionId}`,
        extraData: '',
        lang: 'vi',
        accountNo: data.accountNo,
        currency: (data.currency || 'VND').toUpperCase(),
        transferType: this.parseTransferType(data.transferType),
        ...config.initiateStaticFields,
      };
    }
    if (config.requestStyle === 'BANK') {
      return {
        requestId,
        requestTime,
        transactionId: data.transactionId,
        referenceId: data.transactionId,
        accountNo: data.accountNo,
        amount: data.amount,
        currency: (data.currency || 'VND').toUpperCase(),
        description: data.note || '',
        transferType: this.parseTransferType(data.transferType),
        ...config.initiateStaticFields,
      };
    }
    if (config.requestStyle === 'VNPAY') {
      const txnRef = data.transactionId;
      return {
        vnp_TxnRef: txnRef,
        vnp_OrderInfo: data.note || `Transfer ${txnRef}`,
        vnp_Amount: Number(data.amount) * 100,
        vnp_CurrCode: (data.currency || 'VND').toUpperCase(),
        vnp_IpAddr: '127.0.0.1',
        transferType: this.parseTransferType(data.transferType),
        ...config.initiateStaticFields,
      };
    }
    if (config.requestStyle === 'ZALOPAY') {
      const appId =
        String(
          config.initiateStaticFields.app_id ||
            config.clientId ||
            config.merchantId,
        ).trim() || undefined;
      const appUser =
        String(config.initiateStaticFields.app_user || data.accountNo || '').trim() ||
        'kufi-user';
      const appTime = Number(config.initiateStaticFields.app_time || Date.now());
      const embedData = this.normalizeJsonField(
        config.initiateStaticFields.embed_data,
        '{}',
      );
      const item = this.normalizeJsonField(
        config.initiateStaticFields.item,
        '[]',
      );
      return {
        app_id: appId,
        app_trans_id: data.transactionId,
        app_user: appUser,
        app_time: Number.isFinite(appTime) ? appTime : Date.now(),
        amount: data.amount,
        item,
        embed_data: embedData,
        currency: (data.currency || 'VND').toUpperCase(),
        description: data.note || `Transfer ${data.transactionId}`,
        transferType: this.parseTransferType(data.transferType),
        ...config.initiateStaticFields,
      };
    }
    return {
      transactionId: data.transactionId,
      partnerCode: data.partnerCode,
      accountNo: data.accountNo,
      amount: data.amount,
      currency: (data.currency || 'VND').toUpperCase(),
      transferType: this.parseTransferType(data.transferType),
      note: data.note || '',
      requestId,
      requestTime,
      ...config.initiateStaticFields,
    };
  }

  private buildCheckPayload(
    config: PartnerConfig,
    transfer: ExternalTransfer,
  ): any {
    const requestId = randomUUID();
    const requestTime = new Date().toISOString();

    if (config.requestStyle === 'MOMO') {
      return {
        requestId,
        orderId: transfer.transactionId,
        partnerRef: transfer.partnerRef,
        ...config.checkStaticFields,
      };
    }
    if (config.requestStyle === 'BANK') {
      return {
        requestId,
        requestTime,
        transactionId: transfer.transactionId,
        referenceId: transfer.partnerRef,
        partnerRef: transfer.partnerRef,
        ...config.checkStaticFields,
      };
    }
    if (config.requestStyle === 'VNPAY') {
      return {
        vnp_TxnRef: transfer.transactionId,
        vnp_TransactionNo: transfer.partnerRef,
        ...config.checkStaticFields,
      };
    }
    if (config.requestStyle === 'ZALOPAY') {
      const appId =
        String(
          config.checkStaticFields.app_id ||
            config.initiateStaticFields.app_id ||
            config.clientId ||
            config.merchantId,
        ).trim() || undefined;
      return {
        app_id: appId,
        app_trans_id: transfer.transactionId,
        zp_trans_id: transfer.partnerRef,
        ...config.checkStaticFields,
      };
    }
    return {
      partnerCode: config.partnerCode,
      partnerRef: transfer.partnerRef,
      transactionId: transfer.transactionId,
      requestId,
      requestTime,
      ...config.checkStaticFields,
    };
  }

  // ── HTTP caller with HMAC signing ─────────────────────────

  private async callPartnerApi(
    config: PartnerConfig,
    path: string,
    method: string,
    payload: any,
  ) {
    const baseUrl = config.baseUrl.replace(/\/$/, '');
    const normalizedPath = path.startsWith('/') ? path : `/${path}`;
    const timestamp = Date.now().toString();
    const nonce = randomUUID();

    const requestPayload = this.clonePayload(payload);

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'X-Timestamp': timestamp,
      'X-Nonce': nonce,
      ...config.extraHeaders,
    };

    this.applySignature(config, {
      method,
      path: normalizedPath,
      payload: requestPayload,
      headers,
      timestamp,
      nonce,
    });

    const bodyText = JSON.stringify(requestPayload);

    if (config.apiKey) headers[config.apiKeyHeader] = config.apiKey;
    if (config.clientId) headers[config.clientIdHeader] = config.clientId;
    if (config.merchantId)
      headers[config.merchantIdHeader] = config.merchantId;
    if (config.bearerToken)
      headers.Authorization = `Bearer ${config.bearerToken}`;

    let url = `${baseUrl}${this.interpolatePath(normalizedPath, requestPayload)}`;
    let requestBody: string | undefined = bodyText;

    if (method === 'GET') {
      const params = new URLSearchParams();
      for (const [key, value] of Object.entries(requestPayload)) {
        if (
          value === undefined ||
          value === null ||
          normalizedPath.includes(`{${key}}`)
        )
          continue;
        params.set(key, String(value));
      }
      const query = params.toString();
      if (query) url = `${url}?${query}`;
      requestBody = undefined;
    }

    const controller = new AbortController();
    const timeoutHandle = setTimeout(
      () => controller.abort(),
      config.timeoutMs,
    );

    try {
      const response = await fetch(url, {
        method,
        headers,
        body: requestBody,
        signal: controller.signal,
      });
      const rawText = await response.text();
      const parsed = this.safeParseJson(rawText);
      return {
        httpStatus: response.status,
        ok: response.ok,
        payload: parsed,
        rawText,
      };
    } finally {
      clearTimeout(timeoutHandle);
    }
  }

  // ── Partner configuration ─────────────────────────────────

  private normalizeKnownPartnerCode(partnerCodeRaw: string): string {
    const raw = (partnerCodeRaw || '').trim().toUpperCase();
    if (!raw) return 'BANK_DEFAULT';
    if (raw === 'MOMO' || raw === 'MOMO_WALLET') return 'MOMO';
    if (raw === 'VNPAY' || raw === 'VN_PAY' || raw === 'VNP') return 'VNPAY';
    if (raw === 'ZALOPAY' || raw === 'ZALO_PAY' || raw === 'ZLP')
      return 'ZALOPAY';
    if (raw === 'TECHCOMBANK' || raw === 'TECHCOM' || raw === 'TCB')
      return 'TECHCOMBANK';
    if (raw === 'VIETCOMBANK' || raw === 'VIETCOM' || raw === 'VCB')
      return 'VIETCOMBANK';
    return raw;
  }

  private resolvePartnerRuntimeConfig(
    partnerCode: string,
  ): PartnerConfig | null {
    const prefix = this.partnerPrefixByCode(partnerCode);
    if (!prefix) return null;

    const enabled =
      String(this.cfg.get(`${prefix}_ENABLED`) ?? 'true').toLowerCase() ===
      'true';
    if (!enabled) return null;

    const baseUrl = (this.cfg.get(`${prefix}_API_BASE_URL`) || '').trim();
    const initiatePath = (
      this.cfg.get(`${prefix}_INITIATE_PATH`) || '/transfers'
    ).trim();
    const statusPath = (
      this.cfg.get(`${prefix}_STATUS_PATH`) || '/transfers/status'
    ).trim();
    if (!baseUrl || !initiatePath) return null;

    const statusMethodRaw = (
      this.cfg.get(`${prefix}_STATUS_METHOD`) || 'POST'
    )
      .trim()
      .toUpperCase();
    const statusMethod: 'GET' | 'POST' =
      statusMethodRaw === 'GET' ? 'GET' : 'POST';
    const timeoutMsRaw = Number(
      this.cfg.get(`${prefix}_TIMEOUT_MS`) || 8000,
    );
    const defaultMapping = this.defaultFieldMappingFor(partnerCode);
    const requestStyle = this.resolveRequestStyle(
      this.cfg.get(`${prefix}_REQUEST_STYLE`) || '',
      this.defaultRequestStyleFor(partnerCode),
    );

    return {
      partnerCode,
      baseUrl,
      initiatePath,
      statusPath,
      statusMethod,
      requestStyle,
      timeoutMs:
        Number.isFinite(timeoutMsRaw) && timeoutMsRaw > 0
          ? timeoutMsRaw
          : 8000,
      apiKey: (this.cfg.get(`${prefix}_API_KEY`) || '').trim(),
      apiSecret: (this.cfg.get(`${prefix}_API_SECRET`) || '').trim(),
      clientId: (this.cfg.get(`${prefix}_CLIENT_ID`) || '').trim(),
      merchantId: (this.cfg.get(`${prefix}_MERCHANT_ID`) || '').trim(),
      bearerToken: (this.cfg.get(`${prefix}_BEARER_TOKEN`) || '').trim(),
      apiKeyHeader: (
        this.cfg.get(`${prefix}_API_KEY_HEADER`) || 'X-API-Key'
      ).trim(),
      clientIdHeader: (
        this.cfg.get(`${prefix}_CLIENT_ID_HEADER`) || 'X-Client-Id'
      ).trim(),
      merchantIdHeader: (
        this.cfg.get(`${prefix}_MERCHANT_ID_HEADER`) || 'X-Merchant-Id'
      ).trim(),
      signatureHeader: (
        this.cfg.get(`${prefix}_SIGNATURE_HEADER`) || 'X-Signature'
      ).trim(),
      extraHeaders: this.parseHeaderPairs(
        this.cfg.get(`${prefix}_EXTRA_HEADERS`) || '',
      ),
      initiateStaticFields: this.parseJsonObject(
        this.cfg.get(`${prefix}_INITIATE_STATIC_FIELDS_JSON`) || '',
      ),
      checkStaticFields: this.parseJsonObject(
        this.cfg.get(`${prefix}_CHECK_STATIC_FIELDS_JSON`) || '',
      ),
      mapping: {
        initiateStatusPaths: this.parseStringList(
          this.cfg.get(`${prefix}_INITIATE_STATUS_PATHS`) || '',
          defaultMapping.initiateStatusPaths,
        ),
        initiateReferencePaths: this.parseStringList(
          this.cfg.get(`${prefix}_INITIATE_REFERENCE_PATHS`) || '',
          defaultMapping.initiateReferencePaths,
        ),
        initiateMessagePaths: this.parseStringList(
          this.cfg.get(`${prefix}_INITIATE_MESSAGE_PATHS`) || '',
          defaultMapping.initiateMessagePaths,
        ),
        checkStatusPaths: this.parseStringList(
          this.cfg.get(`${prefix}_CHECK_STATUS_PATHS`) || '',
          defaultMapping.checkStatusPaths,
        ),
        checkMessagePaths: this.parseStringList(
          this.cfg.get(`${prefix}_CHECK_MESSAGE_PATHS`) || '',
          defaultMapping.checkMessagePaths,
        ),
        failedTokens: this.parseTokenList(
          this.cfg.get(`${prefix}_FAILED_TOKENS`) || '',
          defaultMapping.failedTokens,
        ),
        successTokens: this.parseTokenList(
          this.cfg.get(`${prefix}_SUCCESS_TOKENS`) || '',
          defaultMapping.successTokens,
        ),
        pendingTokens: this.parseTokenList(
          this.cfg.get(`${prefix}_PENDING_TOKENS`) || '',
          defaultMapping.pendingTokens,
        ),
      },
      signatureMode: this.resolveSignatureMode(
        this.cfg.get(`${prefix}_SIGNATURE_MODE`) || '',
        this.defaultSignatureModeFor(partnerCode),
      ),
      signatureAlgorithm: this.resolveSignatureAlgorithm(
        this.cfg.get(`${prefix}_SIGNATURE_ALGORITHM`) || '',
        this.defaultSignatureAlgorithmFor(
          this.resolveSignatureMode(
            this.cfg.get(`${prefix}_SIGNATURE_MODE`) || '',
            this.defaultSignatureModeFor(partnerCode),
          ),
        ),
      ),
      signaturePayloadField: (
        this.cfg.get(`${prefix}_SIGNATURE_PAYLOAD_FIELD`) ||
        this.defaultSignaturePayloadFieldFor(partnerCode)
      ).trim(),
      signatureFields: this.parseStringList(
        this.cfg.get(`${prefix}_SIGNATURE_FIELDS`) || '',
        this.defaultSignatureFieldsFor(partnerCode),
      ),
      signatureJoiner: (
        this.cfg.get(`${prefix}_SIGNATURE_JOINER`) ||
        this.defaultSignatureJoinerFor(partnerCode)
      ).trim(),
    };
  }

  private partnerPrefixByCode(partnerCode: string): string | null {
    switch (partnerCode) {
      case 'MOMO':
        return 'MOMO';
      case 'VNPAY':
        return 'VNPAY';
      case 'ZALOPAY':
        return 'ZALOPAY';
      case 'TECHCOMBANK':
        return 'TECHCOMBANK';
      case 'VIETCOMBANK':
        return 'VIETCOMBANK';
      default:
        return null;
    }
  }

  private defaultRequestStyleFor(
    partnerCode: string,
  ): 'MOMO' | 'BANK' | 'VNPAY' | 'ZALOPAY' | 'GENERIC' {
    if (partnerCode === 'MOMO') return 'MOMO';
    if (partnerCode === 'VNPAY') return 'VNPAY';
    if (partnerCode === 'ZALOPAY') return 'ZALOPAY';
    if (partnerCode === 'TECHCOMBANK' || partnerCode === 'VIETCOMBANK')
      return 'BANK';
    return 'GENERIC';
  }

  private resolveRequestStyle(
    raw: string,
    fallback: 'MOMO' | 'BANK' | 'VNPAY' | 'ZALOPAY' | 'GENERIC',
  ): 'MOMO' | 'BANK' | 'VNPAY' | 'ZALOPAY' | 'GENERIC' {
    const normalized = (raw || '').trim().toUpperCase();
    if (normalized === 'MOMO') return 'MOMO';
    if (normalized === 'BANK') return 'BANK';
    if (normalized === 'VNPAY') return 'VNPAY';
    if (normalized === 'ZALOPAY') return 'ZALOPAY';
    if (normalized === 'GENERIC') return 'GENERIC';
    return fallback;
  }

  private defaultSignatureModeFor(
    partnerCode: string,
  ):
    | 'LEGACY_HEADER_SHA256'
    | 'HEADER_CANONICAL'
    | 'VNPAY_QUERY_SHA512'
    | 'ZALOPAY_MAC_SHA256'
    | 'PAYLOAD_FIELDS_HMAC' {
    if (partnerCode === 'VNPAY') return 'VNPAY_QUERY_SHA512';
    if (partnerCode === 'ZALOPAY') return 'ZALOPAY_MAC_SHA256';
    return 'LEGACY_HEADER_SHA256';
  }

  private resolveSignatureMode(
    raw: string,
    fallback:
      | 'LEGACY_HEADER_SHA256'
      | 'HEADER_CANONICAL'
      | 'VNPAY_QUERY_SHA512'
      | 'ZALOPAY_MAC_SHA256'
      | 'PAYLOAD_FIELDS_HMAC',
  ):
    | 'LEGACY_HEADER_SHA256'
    | 'HEADER_CANONICAL'
    | 'VNPAY_QUERY_SHA512'
    | 'ZALOPAY_MAC_SHA256'
    | 'PAYLOAD_FIELDS_HMAC' {
    const normalized = (raw || '').trim().toUpperCase();
    if (normalized === 'LEGACY_HEADER_SHA256') return 'LEGACY_HEADER_SHA256';
    if (normalized === 'HEADER_CANONICAL') return 'HEADER_CANONICAL';
    if (normalized === 'VNPAY_QUERY_SHA512') return 'VNPAY_QUERY_SHA512';
    if (normalized === 'ZALOPAY_MAC_SHA256') return 'ZALOPAY_MAC_SHA256';
    if (normalized === 'PAYLOAD_FIELDS_HMAC') return 'PAYLOAD_FIELDS_HMAC';
    return fallback;
  }

  private defaultSignatureAlgorithmFor(
    signatureMode:
      | 'LEGACY_HEADER_SHA256'
      | 'HEADER_CANONICAL'
      | 'VNPAY_QUERY_SHA512'
      | 'ZALOPAY_MAC_SHA256'
      | 'PAYLOAD_FIELDS_HMAC',
  ): 'sha256' | 'sha512' {
    return signatureMode === 'VNPAY_QUERY_SHA512' ? 'sha512' : 'sha256';
  }

  private resolveSignatureAlgorithm(
    raw: string,
    fallback: 'sha256' | 'sha512',
  ): 'sha256' | 'sha512' {
    const normalized = (raw || '').trim().toLowerCase();
    if (normalized === 'sha256') return 'sha256';
    if (normalized === 'sha512') return 'sha512';
    return fallback;
  }

  private defaultSignaturePayloadFieldFor(partnerCode: string): string {
    if (partnerCode === 'VNPAY') return 'vnp_SecureHash';
    if (partnerCode === 'ZALOPAY') return 'mac';
    return 'signature';
  }

  private defaultSignatureFieldsFor(partnerCode: string): string[] {
    if (partnerCode === 'ZALOPAY') {
      return [
        'app_id',
        'app_trans_id',
        'app_user',
        'amount',
        'app_time',
        'embed_data',
        'item',
      ];
    }
    return [];
  }

  private defaultSignatureJoinerFor(partnerCode: string): string {
    if (partnerCode === 'ZALOPAY') return '|';
    return '.';
  }

  private applySignature(
    config: PartnerConfig,
    args: {
      method: string;
      path: string;
      payload: Record<string, any>;
      headers: Record<string, string>;
      timestamp: string;
      nonce: string;
    },
  ) {
    if (!config.apiSecret) return;

    if (config.signatureMode === 'VNPAY_QUERY_SHA512') {
      const canonical = this.buildVnpayCanonical(args.payload);
      if (!canonical) return;
      const signature = createHmac('sha512', config.apiSecret)
        .update(canonical)
        .digest('hex');
      args.payload.vnp_SecureHashType = 'HmacSHA512';
      args.payload[config.signaturePayloadField || 'vnp_SecureHash'] =
        signature;
      return;
    }

    if (
      config.signatureMode === 'ZALOPAY_MAC_SHA256' ||
      config.signatureMode === 'PAYLOAD_FIELDS_HMAC'
    ) {
      const fieldName = config.signaturePayloadField || 'mac';
      const canonical = this.buildCanonicalFromFields(
        args.payload,
        config.signatureFields,
        config.signatureJoiner,
      );
      if (!canonical) return;
      args.payload[fieldName] = createHmac(
        config.signatureAlgorithm,
        config.apiSecret,
      )
        .update(canonical)
        .digest('hex');
      return;
    }

    if (config.signatureMode === 'HEADER_CANONICAL') {
      const canonical =
        this.buildCanonicalFromFields(
          args.payload,
          config.signatureFields,
          config.signatureJoiner,
        ) ||
        `${args.method.toUpperCase()}.${args.path}.${JSON.stringify(args.payload)}`;
      const signature = createHmac(config.signatureAlgorithm, config.apiSecret)
        .update(canonical)
        .digest('hex');
      args.headers[config.signatureHeader] = signature;
      return;
    }

    const legacyBody = JSON.stringify(args.payload);
    const signature = createHmac('sha256', config.apiSecret)
      .update(`${args.timestamp}.${args.nonce}.${legacyBody}`)
      .digest('hex');
    args.headers[config.signatureHeader] = signature;
  }

  private buildVnpayCanonical(payload: Record<string, any>): string {
    const keys = Object.keys(payload)
      .filter(
        (key) =>
          key !== 'vnp_SecureHash' &&
          key !== 'vnp_SecureHashType' &&
          payload[key] !== undefined &&
          payload[key] !== null,
      )
      .sort((a, b) => a.localeCompare(b));

    const parts: string[] = [];
    for (const key of keys) {
      parts.push(
        `${encodeURIComponent(key)}=${encodeURIComponent(String(payload[key]))}`,
      );
    }
    return parts.join('&');
  }

  private buildCanonicalFromFields(
    payload: Record<string, any>,
    fields: string[],
    joinerRaw: string,
  ): string {
    const list = fields.filter((item) => !!item && item.trim().length > 0);
    if (!list.length) return '';
    const joiner = joinerRaw || '|';
    return list
      .map((field) => this.normalizeCanonicalValue(payload[field]))
      .join(joiner);
  }

  private normalizeCanonicalValue(value: any): string {
    if (value === undefined || value === null) return '';
    if (typeof value === 'string') return value;
    if (typeof value === 'number' || typeof value === 'boolean') {
      return String(value);
    }
    try {
      return JSON.stringify(value);
    } catch {
      return String(value);
    }
  }

  private clonePayload(payload: any): Record<string, any> {
    if (!this.isPlainObject(payload)) return {};
    return { ...payload };
  }

  private normalizeJsonField(value: any, fallback: string): string {
    if (value === undefined || value === null) return fallback;
    if (typeof value === 'string') {
      const text = value.trim();
      return text || fallback;
    }
    try {
      return JSON.stringify(value);
    } catch {
      return fallback;
    }
  }

  private defaultFieldMappingFor(partnerCode: string): FieldMapping {
    const base: FieldMapping = {
      initiateStatusPaths: [
        'status', 'state', 'transactionStatus', 'resultStatus',
        'resultCode', 'code', 'data.status', 'data.state',
        'data.transactionStatus', 'data.resultStatus',
        'data.resultCode', 'data.code',
      ],
      initiateReferencePaths: [
        'partnerRef', 'reference', 'ref', 'transId',
        'transactionId', 'orderId', 'requestId',
        'data.partnerRef', 'data.reference', 'data.ref',
        'data.transId', 'data.transactionId', 'data.orderId',
      ],
      initiateMessagePaths: [
        'partnerMessage', 'message', 'msg', 'description',
        'errorDesc', 'errorMessage', 'data.partnerMessage',
        'data.message', 'data.msg', 'data.description',
        'data.errorDesc', 'data.errorMessage',
      ],
      checkStatusPaths: [
        'status', 'state', 'transactionStatus', 'resultStatus',
        'resultCode', 'code', 'data.status', 'data.state',
        'data.transactionStatus', 'data.resultStatus',
        'data.resultCode', 'data.code',
      ],
      checkMessagePaths: [
        'partnerMessage', 'message', 'msg', 'description',
        'errorDesc', 'errorMessage', 'data.partnerMessage',
        'data.message', 'data.msg', 'data.description',
        'data.errorDesc', 'data.errorMessage',
      ],
      failedTokens: [
        'FAIL', 'FAILED', 'ERROR', 'REJECT', 'CANCEL', 'DENY',
        'DECLINED', '400', '401', '403', '404', '429', '500',
      ],
      successTokens: [
        'SUCCESS', 'SUCCEEDED', 'SETTLED', 'COMPLETED', 'DONE',
      ],
      pendingTokens: [
        'PENDING', 'PROCESSING', 'SUBMITTED', 'QUEUED', 'ACCEPTED',
      ],
    };

    if (partnerCode === 'MOMO') {
      return {
        ...base,
        initiateStatusPaths: [
          ...base.initiateStatusPaths,
          'resultCode', 'data.resultCode',
          'transStatus', 'data.transStatus',
        ],
        checkStatusPaths: [
          ...base.checkStatusPaths,
          'resultCode', 'data.resultCode',
          'transStatus', 'data.transStatus',
        ],
        initiateReferencePaths: [
          ...base.initiateReferencePaths,
          'transId', 'data.transId',
          'orderId', 'data.orderId',
        ],
        successTokens: [...base.successTokens, '0', '00'],
        pendingTokens: [...base.pendingTokens, '1'],
      };
    }
    if (partnerCode === 'TECHCOMBANK' || partnerCode === 'VIETCOMBANK') {
      return {
        ...base,
        initiateStatusPaths: [
          ...base.initiateStatusPaths,
          'responseCode', 'data.responseCode',
          'transactionState', 'data.transactionState',
        ],
        checkStatusPaths: [
          ...base.checkStatusPaths,
          'responseCode', 'data.responseCode',
          'transactionState', 'data.transactionState',
        ],
        successTokens: [
          ...base.successTokens, '0', '00', '200', 'APPROVED',
        ],
        pendingTokens: [...base.pendingTokens, '102', '202'],
      };
    }
    if (partnerCode === 'VNPAY') {
      return {
        ...base,
        initiateStatusPaths: [
          ...base.initiateStatusPaths,
          'vnp_ResponseCode',
          'vnp_TransactionStatus',
          'data.vnp_ResponseCode',
          'data.vnp_TransactionStatus',
        ],
        checkStatusPaths: [
          ...base.checkStatusPaths,
          'vnp_ResponseCode',
          'vnp_TransactionStatus',
          'data.vnp_ResponseCode',
          'data.vnp_TransactionStatus',
        ],
        initiateReferencePaths: [
          ...base.initiateReferencePaths,
          'vnp_TransactionNo',
          'vnp_TxnRef',
          'data.vnp_TransactionNo',
          'data.vnp_TxnRef',
        ],
        successTokens: [...base.successTokens, '00'],
        pendingTokens: [...base.pendingTokens, '09'],
      };
    }
    if (partnerCode === 'ZALOPAY') {
      return {
        ...base,
        initiateStatusPaths: [
          ...base.initiateStatusPaths,
          'return_code',
          'sub_return_code',
          'data.return_code',
          'data.sub_return_code',
        ],
        checkStatusPaths: [
          ...base.checkStatusPaths,
          'return_code',
          'is_processing',
          'data.return_code',
          'data.is_processing',
        ],
        initiateReferencePaths: [
          ...base.initiateReferencePaths,
          'zp_trans_token',
          'zp_trans_id',
          'app_trans_id',
          'data.zp_trans_token',
          'data.zp_trans_id',
        ],
        successTokens: [...base.successTokens, '1'],
        pendingTokens: [...base.pendingTokens, '2'],
      };
    }
    return base;
  }

  // ── Response extractors ───────────────────────────────────

  private extractStatus(
    payload: any,
    mode: 'initiate' | 'check',
    isHttpOk: boolean,
    statusPaths: string[],
    mapping: FieldMapping,
  ): ExternalTransferStatus {
    const raw = this.extractString(payload, statusPaths).toUpperCase();
    if (!raw) {
      return isHttpOk
        ? ExternalTransferStatus.SUBMITTED
        : ExternalTransferStatus.FAILED;
    }
    if (this.matchesAnyToken(raw, mapping.failedTokens))
      return ExternalTransferStatus.FAILED;
    if (this.matchesAnyToken(raw, mapping.successTokens))
      return mode === 'initiate'
        ? ExternalTransferStatus.SUBMITTED
        : ExternalTransferStatus.SETTLED;
    if (this.matchesAnyToken(raw, mapping.pendingTokens))
      return ExternalTransferStatus.SUBMITTED;
    return isHttpOk
      ? ExternalTransferStatus.SUBMITTED
      : ExternalTransferStatus.FAILED;
  }

  private matchesAnyToken(value: string, tokens: string[]): boolean {
    for (const token of tokens) {
      const normalizedToken = (token || '').trim().toUpperCase();
      if (!normalizedToken) continue;
      if (value === normalizedToken || value.includes(normalizedToken))
        return true;
    }
    return false;
  }

  private extractString(payload: any, paths: string[]): string {
    return this.pickString(payload, paths);
  }

  private pickString(payload: any, paths: string[]): string {
    for (const path of paths) {
      const value = this.readPath(payload, path);
      if (value === undefined || value === null) continue;
      const text = `${value}`.trim();
      if (text) return text;
    }
    for (const path of paths) {
      if (path.includes('.')) continue;
      const nestedValue = this.findByKeyDeep(payload, path);
      if (nestedValue === undefined || nestedValue === null) continue;
      const text = `${nestedValue}`.trim();
      if (text) return text;
    }
    return '';
  }

  private readPath(obj: any, path: string): any {
    if (!path) return undefined;
    const segments = path
      .split('.')
      .map((item) => item.trim())
      .filter(Boolean);
    if (!segments.length) return undefined;
    let cursor = obj;
    for (const segment of segments) {
      if (!this.isPlainObject(cursor)) return undefined;
      cursor = cursor[segment];
    }
    return cursor;
  }

  private findByKeyDeep(obj: any, key: string): any {
    if (!this.isPlainObject(obj)) return undefined;
    if (Object.prototype.hasOwnProperty.call(obj, key)) return obj[key];
    for (const value of Object.values(obj)) {
      const found = this.findByKeyDeep(value, key);
      if (found !== undefined && found !== null) return found;
    }
    return undefined;
  }

  private isPlainObject(value: any): boolean {
    return !!value && typeof value === 'object' && !Array.isArray(value);
  }

  private safeParseJson(rawText: string): any {
    const trimmed = rawText.trim();
    if (!trimmed) return {};
    try {
      const parsed = JSON.parse(trimmed);
      if (this.isPlainObject(parsed)) return parsed;
      return { value: parsed };
    } catch {
      return { raw: trimmed };
    }
  }

  private interpolatePath(
    path: string,
    payload: Record<string, any>,
  ): string {
    let result = path;
    for (const [key, value] of Object.entries(payload)) {
      if (value === undefined || value === null) continue;
      const placeholder = `{${key}}`;
      if (!result.includes(placeholder)) continue;
      result = result.replaceAll(
        placeholder,
        encodeURIComponent(String(value)),
      );
    }
    return result;
  }

  private parseHeaderPairs(raw: string): Record<string, string> {
    const text = (raw || '').trim();
    if (!text) return {};
    const result: Record<string, string> = {};
    for (const item of text.split(';')) {
      const pair = item.trim();
      if (!pair) continue;
      const idx = pair.indexOf('=');
      if (idx <= 0) continue;
      const key = pair.slice(0, idx).trim();
      const value = pair.slice(idx + 1).trim();
      if (key && value) result[key] = value;
    }
    return result;
  }

  private parseJsonObject(raw: string): Record<string, any> {
    const text = (raw || '').trim();
    if (!text) return {};
    try {
      const parsed = JSON.parse(text);
      if (this.isPlainObject(parsed)) return parsed;
    } catch {
      this.logger.warn('Failed to parse partner static fields JSON');
    }
    return {};
  }

  private parseStringList(raw: string, fallback: string[]): string[] {
    const text = (raw || '').trim();
    if (!text) return fallback;
    const values = text
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean);
    return values.length ? values : fallback;
  }

  private parseTokenList(raw: string, fallback: string[]): string[] {
    return this.parseStringList(raw, fallback).map((item) =>
      item.toUpperCase(),
    );
  }

  private parseAmount(raw: any): number {
    if (typeof raw === 'number') return raw;
    if (typeof raw === 'string') return Number(raw);
    if (raw && typeof raw === 'object') {
      if (typeof raw.toNumber === 'function') return raw.toNumber();
      if (
        typeof raw.low === 'number' &&
        typeof raw.high === 'number'
      ) {
        return raw.high * 4294967296 + (raw.low >>> 0);
      }
    }
    return Number.NaN;
  }

  private parseTransferType(raw: any): ExternalTransferType {
    const normalized = `${raw ?? ''}`.trim().toUpperCase();
    return normalized === ExternalTransferType.TOPUP
      ? ExternalTransferType.TOPUP
      : ExternalTransferType.WITHDRAWAL;
  }

  private getErrorMessage(error: any): string {
    if (error instanceof Error) return error.message || 'unknown_error';
    return String(error || 'unknown_error');
  }

  private shouldSettleMockTransfer(transfer: ExternalTransfer): boolean {
    const delayMs = this.getMockSettleDelayMs();
    const createdAt = transfer.createdAt instanceof Date
      ? transfer.createdAt.getTime()
      : Date.now();
    return Date.now() - createdAt >= delayMs;
  }

  private getMockSettleDelayMs(): number {
    const rawSeconds = Number(this.cfg.get('EXTERNAL_SETTLE_DELAY_SECONDS') ?? 1);
    const seconds = Number.isFinite(rawSeconds) && rawSeconds >= 0 ? rawSeconds : 1;
    return Math.floor(seconds * 1000);
  }

  private buildMockSubmittedMessage(partnerCode: string): string {
    return `Mock partner ${partnerCode}: transfer submitted, waiting settlement`;
  }

  private buildMockSettledMessage(partnerCode: string): string {
    return `Mock partner ${partnerCode}: settlement completed`;
  }
}
