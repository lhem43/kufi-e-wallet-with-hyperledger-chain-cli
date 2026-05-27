import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import SnappyCodec from 'kafkajs-snappy';
import { CompressionCodecs, CompressionTypes, Consumer, Kafka } from 'kafkajs';
import nodemailer from 'nodemailer';
import { DataSource, Repository } from 'typeorm';

import { NotificationChannel, NotificationEntity } from './entities/notification.entity';
import { NotificationPreferenceEntity } from './entities/notification-preference.entity';

@Injectable()
export class NotificationsService implements OnModuleInit, OnModuleDestroy {
	private readonly logger = new Logger(NotificationsService.name);
	private consumer: Consumer;
	private kafkaEnabled = true;

	constructor(
		private readonly cfg: ConfigService,
		private readonly dataSource: DataSource,
		@InjectRepository(NotificationEntity)
		private readonly notificationRepo: Repository<NotificationEntity>,
		@InjectRepository(NotificationPreferenceEntity)
		private readonly preferenceRepo: Repository<NotificationPreferenceEntity>,
	) {}

	async onModuleInit() {
		this.kafkaEnabled =
			String(this.cfg.get('KAFKA_ENABLED') ?? 'true').toLowerCase() !== 'false';

		if (!this.kafkaEnabled) {
			this.logger.warn('Kafka consumer disabled by KAFKA_ENABLED=false');
			return;
		}

		const brokers = (this.cfg.get('KAFKA_BROKERS') ?? 'localhost:9092')
			.split(',')
			.map((v: string) => v.trim())
			.filter(Boolean);

		const topic = this.cfg.get('TRANSACTION_EVENTS_TOPIC') ?? 'wallet.transaction.events';
		CompressionCodecs[CompressionTypes.Snappy] = SnappyCodec;

		const kafka = new Kafka({ clientId: 'notification-service', brokers });
		this.consumer = kafka.consumer({
			groupId: this.cfg.get('KAFKA_CONSUMER_GROUP') ?? 'notification-group',
			allowAutoTopicCreation: true,
		});

		await this.consumer.connect();
		await this.consumer.subscribe({ topic, fromBeginning: false });
		await this.consumer.run({
			eachMessage: async ({ message }) => {
				if (!message.value) return;
				const payload = JSON.parse(message.value.toString('utf8'));
				await this.handleTransactionEvent(payload);
			},
		});

		this.logger.log(`Kafka consumer connected brokers=${brokers.join(',')} topic=${topic}`);
	}

	async onModuleDestroy() {
		if (this.consumer) {
			await this.consumer.disconnect();
		}
	}

	// ── gRPC methods ──────────────────────────────────────────

	async listNotifications(userId: string, limit = 20, offset = 0): Promise<NotificationEntity[]> {
		const take = Math.min(Math.max(limit, 1), 100);
		const skip = Math.max(offset, 0);
		return this.notificationRepo.find({
			where: { userId },
			order: { createdAt: 'DESC' },
			take,
			skip,
		});
	}

	async getNotificationSettings(userId: string): Promise<NotificationPreferenceEntity> {
		let row = await this.preferenceRepo.findOne({ where: { userId } });
		if (!row) {
			row = this.preferenceRepo.create({
				userId,
				appEnabled: true,
				emailEnabled: false,
				smsEnabled: false,
			});
			row = await this.preferenceRepo.save(row);
		}
		return row;
	}

	async updateNotificationSettings(
		userId: string,
		payload: { emailEnabled?: boolean; smsEnabled?: boolean },
	): Promise<NotificationPreferenceEntity> {
		const current = await this.getNotificationSettings(userId);
		if (typeof payload?.emailEnabled === 'boolean') {
			current.emailEnabled = payload.emailEnabled;
		}
		if (typeof payload?.smsEnabled === 'boolean') {
			if (payload.smsEnabled) {
				this.logger.warn(
					`SMS notification setting requested but feature is unavailable userId=${userId}`,
				);
			}
			current.smsEnabled = false;
		}
		return this.preferenceRepo.save(current);
	}

	async sendEmailOtp(params: {
		recipientEmail: string;
		otpCode: string;
		expiresInSeconds: number;
		purpose?: string;
	}): Promise<{ sent: boolean; deliveryMode: 'email' }> {
		const recipientEmail = `${params.recipientEmail ?? ''}`.trim().toLowerCase();
		const otpCode = `${params.otpCode ?? ''}`.trim();
		const expiresInSeconds = Math.max(60, Number(params.expiresInSeconds ?? 180));
		const purpose = `${params.purpose ?? ''}`.trim().toLowerCase();
		if (!recipientEmail || !otpCode) {
			throw new Error('recipientEmail and otpCode are required');
		}

		const host = `${this.cfg.get<string>('SMTP_HOST') ?? 'smtp.gmail.com'}`.trim();
		const port = Number(this.cfg.get<string>('SMTP_PORT') ?? 587);
		const secure =
			`${this.cfg.get<string>('SMTP_SECURE') ?? 'false'}`.trim().toLowerCase() === 'true';
		const user = `${this.cfg.get<string>('SMTP_USER') ?? ''}`.trim();
		const pass = `${this.cfg.get<string>('SMTP_PASS') ?? ''}`.trim();
		const from = `${this.cfg.get<string>('SMTP_FROM') ?? user}`.trim();

		if (!user || !pass || !from) {
			throw new Error(
				'SMTP is not configured for email OTP (missing SMTP_USER/SMTP_PASS/SMTP_FROM)',
			);
		}

		const transporter = nodemailer.createTransport({
			host,
			port,
			secure,
			auth: {
				user,
				pass,
			},
		});

		const expireMinutes = Math.max(1, Math.ceil(expiresInSeconds / 60));
		const isSignUp = purpose === 'signup';
		const subject = isSignUp
			? 'Kufi | Mã OTP xác thực đăng ký tài khoản'
			: 'Kufi | Mã OTP xác thực giao dịch của bạn';
		const leadText = isSignUp
			? 'Bạn vừa yêu cầu xác thực đăng ký tài khoản Kufi.'
			: 'Bạn vừa thực hiện xác thực giao dịch trên Kufi.';

		await transporter.sendMail({
			from,
			to: recipientEmail,
			subject,
			text:
				`Xin chào,\n\n` +
				`${leadText}\n` +
				`Mã OTP của bạn là: ${otpCode}\n` +
				`Mã có hiệu lực trong ${expireMinutes} phút.\n\n` +
				`Nếu bạn không thực hiện thao tác này, vui lòng bỏ qua email.\n\n` +
				`Kufi`,
			html: `
        <div style="margin:0;padding:24px;background:#ffffff;font-family:Arial,sans-serif;color:#1f2937;">
          <div style="max-width:560px;margin:0 auto;background:#ffffff;border:1px solid #dbe3ee;border-radius:16px;overflow:hidden;">
            <div style="padding:28px 24px 12px;background:#ffffff;text-align:center;">
              <h2 style="margin:0;font-size:34px;line-height:1.25;color:#c5163d;font-weight:800;">${isSignUp ? 'Xác thực đăng ký tài khoản' : 'Xác thực giao dịch'}</h2>
            </div>
            <div style="padding:8px 24px 24px;">
              <p style="margin:0 0 12px;font-size:15px;line-height:1.6;color:#334155;">
                Xin chào,<br />
                ${leadText}
              </p>
              <div style="margin:16px 0;padding:16px;border-radius:12px;border:1px dashed #d3dfef;background:#f8fbff;text-align:center;">
                <div style="font-size:13px;color:#64748b;margin-bottom:8px;">Mã OTP của bạn</div>
                <div style="font-size:34px;letter-spacing:8px;font-weight:700;color:#7a123f;">${otpCode}</div>
              </div>
              <p style="margin:0 0 10px;font-size:14px;line-height:1.6;color:#475569;">
                Mã có hiệu lực trong <b>${expireMinutes} phút</b>.
              </p>
              <p style="margin:0;font-size:13px;line-height:1.6;color:#64748b;">
                Nếu bạn không thực hiện thao tác này, bạn có thể bỏ qua email.
              </p>
            </div>
          </div>
        </div>
      `,
		});

		this.logger.log(`Sent OTP email purpose=${purpose || 'step_up'} to ${recipientEmail}`);
		return {
			sent: true,
			deliveryMode: 'email',
		};
	}

	// ── Kafka event handler ───────────────────────────────────

	private async handleTransactionEvent(payload: any) {
		if (payload.eventType === 'transaction.chain.completed') {
			const notifications: NotificationEntity[] = [
				this.notificationRepo.create({
					userId: payload.fromUserId,
					channel: NotificationChannel.APP,
					title: `Hóa đơn điện tử đã sẵn sàng cho giao dịch ${payload.transactionId}`,
					content: `Giao dịch ${payload.transactionId} đã được xác nhận on-chain`,
					payloadJson: JSON.stringify(payload),
				}),
			];

			if (payload.toUserId && payload.toUserId !== payload.fromUserId) {
				notifications.push(
					this.notificationRepo.create({
						userId: payload.toUserId,
						channel: NotificationChannel.APP,
						title: `Hóa đơn điện tử đã sẵn sàng cho giao dịch ${payload.transactionId}`,
						content: `Giao dịch ${payload.transactionId} đã được xác nhận on-chain`,
						payloadJson: JSON.stringify(payload),
					}),
				);
			}

			await this.notificationRepo.save(notifications);
			return;
		}

		const senderTitle =
			payload.eventType === 'transaction.failed'
				? 'Giao dịch thất bại'
				: 'Giao dịch thành công';

		const senderContent =
			payload.eventType === 'transaction.failed'
				? `Giao dịch ${payload.transactionId} thất bại`
				: `Bạn đã chuyển ${Number(payload.amount).toLocaleString('vi-VN')} ${payload.currency}`;

		const senderNotification = this.notificationRepo.create({
			userId: payload.fromUserId,
			channel: NotificationChannel.APP,
			title: senderTitle,
			content: senderContent,
			payloadJson: JSON.stringify(payload),
		});

		const notifications: NotificationEntity[] = [senderNotification];

		if (
			payload.eventType === 'transaction.completed' &&
			payload.toUserId &&
			payload.toUserId !== payload.fromUserId
		) {
			notifications.push(
				this.notificationRepo.create({
					userId: payload.toUserId,
					channel: NotificationChannel.APP,
					title: 'Nhận tiền thành công',
					content: `Bạn vừa nhận ${Number(payload.amount).toLocaleString('vi-VN')} ${payload.currency}`,
					payloadJson: JSON.stringify(payload),
				}),
			);
		}

		await this.notificationRepo.save(notifications);

		const enrichedPayload = await this.enrichPayloadForEmail(payload);
		if (this.isInternalTransferCompleted(enrichedPayload)) {
			await this.sendBalanceChangeEmailIfEnabled(enrichedPayload, 'sender');
			await this.sendBalanceChangeEmailIfEnabled(enrichedPayload, 'receiver');
		} else if (payload?.eventType === 'transaction.completed') {
			this.logger.log(
				`Skip balance email tx=${payload?.transactionId ?? ''} type=${payload?.type ?? ''} isExternal=${payload?.isExternal ?? ''}`,
			);
		}
	}

	private async enrichPayloadForEmail(payload: any): Promise<any> {
		const txId = `${payload?.transactionId ?? ''}`.trim();
		if (!txId) {
			return payload;
		}
		if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(txId)) {
			return payload;
		}
		const needsTxMeta =
			`${payload?.type ?? ''}`.trim().length === 0 ||
			typeof payload?.isExternal !== 'boolean' ||
			`${payload?.fromUserId ?? ''}`.trim().length === 0 ||
			`${payload?.toUserId ?? ''}`.trim().length === 0;
		const needsBalances =
			(payload?.senderBalance == null || payload?.receiverBalance == null) &&
			`${payload?.currency ?? ''}`.trim().length > 0;
		const needsReceipt =
			`${payload?.receiptJson ?? ''}`.trim().length === 0 ||
			`${payload?.chainTxId ?? ''}`.trim().length === 0;
		if (!needsTxMeta && !needsBalances && !needsReceipt) {
			return payload;
		}

		try {
			const txRows = await this.dataSource.query(
				`SELECT "type", "isExternal", "fromUserId", "toUserId", "currency", "amount", "chainStatus", "chainTxId", "receiptJson"
         FROM transactions
         WHERE id = $1
         LIMIT 1`,
				[txId],
			);
			const tx = txRows?.[0];
			if (!tx) {
				return payload;
			}

			const merged: any = {
				...payload,
				type: payload?.type ?? tx.type,
				isExternal:
					typeof payload?.isExternal === 'boolean'
						? payload.isExternal
						: tx.isExternal === true,
				fromUserId: payload?.fromUserId ?? tx.fromUserId,
				toUserId: payload?.toUserId ?? tx.toUserId,
				currency: payload?.currency ?? tx.currency,
				amount: payload?.amount ?? Number(tx.amount ?? 0),
				chainStatus: payload?.chainStatus ?? tx.chainStatus,
				chainTxId: payload?.chainTxId ?? tx.chainTxId,
				receiptJson: payload?.receiptJson ?? tx.receiptJson,
			};

			if (
				merged.currency &&
				(merged.senderBalance == null || merged.receiverBalance == null)
			) {
				const walletRows = await this.dataSource.query(
					`SELECT "userId", "balance"
           FROM wallets
           WHERE currency = $1 AND "userId" = ANY($2::uuid[])`,
					[
						`${merged.currency}`.trim().toUpperCase(),
						[`${merged.fromUserId ?? ''}`, `${merged.toUserId ?? ''}`].filter(
							Boolean,
						),
					],
				);
				const byUser = new Map<string, number>();
				for (const row of walletRows ?? []) {
					byUser.set(`${row.userId}`, Number(row.balance ?? 0));
				}
				if (merged.senderBalance == null && merged.fromUserId) {
					merged.senderBalance =
						byUser.get(`${merged.fromUserId}`) ?? merged.senderBalance;
				}
				if (merged.receiverBalance == null && merged.toUserId) {
					merged.receiverBalance =
						byUser.get(`${merged.toUserId}`) ?? merged.receiverBalance;
				}
			}

			return merged;
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			this.logger.warn(
				`Failed to enrich transaction event tx=${txId}: ${message}`,
			);
			return payload;
		}
	}

	private isInternalTransferCompleted(payload: any): boolean {
		return (
			payload?.eventType === 'transaction.completed' &&
			`${payload?.type ?? ''}`.toUpperCase() === 'TRANSFER' &&
			payload?.isExternal !== true &&
			`${payload?.fromUserId ?? ''}`.trim().length > 0 &&
			`${payload?.toUserId ?? ''}`.trim().length > 0 &&
			`${payload?.fromUserId ?? ''}` !== `${payload?.toUserId ?? ''}`
		);
	}

	private async sendBalanceChangeEmailIfEnabled(
		payload: any,
		target: 'sender' | 'receiver',
	) {
		try {
			const userId = `${target === 'sender' ? payload?.fromUserId : payload?.toUserId ?? ''}`.trim();
			if (!userId) {
				return;
			}
			if (target === 'receiver' && `${payload?.fromUserId ?? ''}` === userId) {
				return;
			}

			const settings = await this.getNotificationSettings(userId);
			if (!settings.emailEnabled) {
				return;
			}

			const profile = await this.fetchUserProfile(userId);
			const recipientEmail = `${profile?.email ?? ''}`.trim().toLowerCase();
			if (!recipientEmail) {
				this.logger.warn(
					`Skip balance email target=${target} tx=${payload?.transactionId ?? ''}: user ${userId} has no email profile`,
				);
				return;
			}

			const displayName =
				`${profile?.displayName ?? ''}`.trim() ||
				`${profile?.email ?? ''}`.trim() ||
				'Khách hàng';
			const amount = Number(payload?.amount ?? 0);
			const currency = `${payload?.currency ?? 'VND'}`.trim().toUpperCase() || 'VND';
			const txId = `${payload?.transactionId ?? ''}`.trim();
			const balanceAfterRaw =
				target === 'sender' ? payload?.senderBalance : payload?.receiverBalance;
			const balanceAfter =
				typeof balanceAfterRaw === 'number'
					? balanceAfterRaw
					: Number.parseFloat(`${balanceAfterRaw ?? ''}`);

			const absoluteAmount = Number.isFinite(amount)
				? Math.abs(amount)
				: Number.parseFloat(`${payload?.amount ?? ''}`);
			const amountText = Number.isFinite(absoluteAmount)
				? absoluteAmount.toLocaleString('vi-VN')
				: `${payload?.amount ?? ''}`;
			const signedAmountText = `${target === 'sender' ? '-' : '+'}${amountText}`;
			const balanceAfterText = Number.isFinite(balanceAfter)
				? `${balanceAfter.toLocaleString('vi-VN')} ${currency}`
				: '';
			const actionLabel = target === 'sender' ? 'chuyển tiền' : 'nhận tiền';
			const subject =
				target === 'sender'
					? 'Kufi | Chuyển tiền thành công'
					: 'Kufi | Nhận tiền thành công';
			const receiptAttachment = this.buildReceiptAttachment(payload);

			const transporter = this.createSmtpTransport();
			const from = `${this.cfg.get<string>('SMTP_FROM') ?? this.cfg.get<string>('SMTP_USER') ?? ''}`.trim();
			if (!from) {
				throw new Error('SMTP_FROM or SMTP_USER is required for sending balance email');
			}

			await transporter.sendMail({
				from,
				to: recipientEmail,
				subject,
				text:
					`Xin chào ${displayName},\n\n` +
					`Bạn vừa ${actionLabel} thành công ${signedAmountText} ${currency}.\n` +
					(balanceAfterText ? `Số dư hiện tại: ${balanceAfterText}.\n` : '') +
					(txId ? `Mã giao dịch: ${txId}\n` : '') +
					`\nKufi`,
				html: `
        <div style="margin:0;padding:24px;background:#ffffff;font-family:Arial,sans-serif;color:#111827;">
          <div style="max-width:560px;margin:0 auto;background:#ffffff;border:1px solid #e2e8f0;border-radius:16px;overflow:hidden;">
            <div style="padding:24px 24px 16px;background:#ffffff;text-align:center;">
              <div style="font-size:14px;font-weight:700;letter-spacing:0.4px;color:#9f1239;margin-bottom:8px;">Kufi Wallet</div>
              <h2 style="margin:0;font-size:30px;line-height:1.25;color:#c5163d;font-weight:800;">${subject}</h2>
            </div>
            <div style="height:1px;background:#e2e8f0;"></div>
            <div style="padding:18px 24px 24px;">
              <p style="margin:0 0 12px;font-size:16px;line-height:1.6;color:#1f2937;">Xin chào ${displayName},</p>
              <div style="margin:0 0 14px;padding:14px 16px;border-radius:12px;background:#fff5f7;border:1px solid #ffd6e0;">
                <div style="font-size:14px;color:#9f1239;margin-bottom:6px;">Biến động số dư</div>
                <div style="font-size:24px;line-height:1.3;color:#b91c1c;font-weight:800;">${signedAmountText} ${currency}</div>
                <div style="margin-top:4px;font-size:14px;color:#475569;">Bạn vừa <b>${actionLabel}</b> thành công</div>
              </div>
              <p style="margin:0 0 10px;font-size:15px;line-height:1.6;color:#334155;">
                ${balanceAfterText ? `Số dư hiện tại: <b>${balanceAfterText}</b>.` : ''}
              </p>
              ${
								txId
									? `<p style="margin:0;font-size:13px;line-height:1.6;color:#64748b;">Mã giao dịch: ${txId}</p>`
									: ''
							}
            </div>
          </div>
        </div>
      `,
				attachments: receiptAttachment ? [receiptAttachment] : [],
			});

			await this.notificationRepo.save(
				this.notificationRepo.create({
					userId,
					channel: NotificationChannel.EMAIL,
					title: subject,
					content:
						`Bạn vừa ${actionLabel} thành công ${signedAmountText} ${currency}.` +
						(balanceAfterText ? ` Số dư hiện tại: ${balanceAfterText}.` : ''),
					payloadJson: JSON.stringify({
						transactionId: txId,
						currency,
						amount,
						balanceAfter: Number.isFinite(balanceAfter) ? balanceAfter : null,
						email: recipientEmail,
					}),
				}),
			);
			this.logger.log(
				`Sent balance-change email target=${target} userId=${userId} tx=${txId} to=${recipientEmail} attachment=${receiptAttachment?.filename ?? 'none'}`,
			);
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			this.logger.warn(
				`Failed to send balance-change email target=${target} tx=${payload?.transactionId ?? ''}: ${message}`,
			);
		}
	}

	private buildReceiptAttachment(payload: any): {
		filename: string;
		content: string;
		contentType: string;
	} | null {
		const transactionId = `${payload?.transactionId ?? ''}`.trim();
		if (!transactionId) {
			return null;
		}

		const rawReceiptJson = `${payload?.receiptJson ?? ''}`.trim();
		let parsedReceipt: Record<string, unknown> | null = null;
		if (rawReceiptJson) {
			try {
				const decoded = JSON.parse(rawReceiptJson);
				if (decoded && typeof decoded === 'object' && !Array.isArray(decoded)) {
					parsedReceipt = decoded as Record<string, unknown>;
				}
				} catch {
				parsedReceipt = null;
			}
		}

		const chainTxId = `${payload?.chainTxId ?? ''}`.trim();
		const receiptId = chainTxId || transactionId;
		const safeReceiptId = receiptId.replace(/[^a-zA-Z0-9_-]/g, '_');
		const fallbackReceipt = {
			tx_id: chainTxId,
			chain_status: `${payload?.chainStatus ?? ''}`.trim(),
			transaction_status: `${payload?.status ?? ''}`.trim(),
			settlement_status: `${payload?.settlementStatus ?? ''}`.trim(),
		};
		const exportPayload = {
			exported_at: new Date().toISOString(),
			receipt_id: receiptId,
			transaction_id: transactionId,
			security_notice: [
				'Secured by Kufi and timestamped by FreeTSA',
				'Any modification will be detected',
			],
			receipt: parsedReceipt ?? fallbackReceipt,
		};

		return {
			filename: `receipt_${safeReceiptId}.json`,
			content: JSON.stringify(exportPayload, null, 2),
			contentType: 'application/json; charset=utf-8',
		};
	}

	private createSmtpTransport() {
		const host = `${this.cfg.get<string>('SMTP_HOST') ?? 'smtp.gmail.com'}`.trim();
		const port = Number(this.cfg.get<string>('SMTP_PORT') ?? 587);
		const secure =
			`${this.cfg.get<string>('SMTP_SECURE') ?? 'false'}`.trim().toLowerCase() === 'true';
		const user = `${this.cfg.get<string>('SMTP_USER') ?? ''}`.trim();
		const pass = `${this.cfg.get<string>('SMTP_PASS') ?? ''}`.trim();
		if (!user || !pass) {
			throw new Error('SMTP_USER and SMTP_PASS are required');
		}

		return nodemailer.createTransport({
			host,
			port,
			secure,
			auth: {
				user,
				pass,
			},
		});
	}

	private async fetchUserProfile(userId: string): Promise<{
		userId: string;
		email: string;
		displayName: string;
	} | null> {
		const base = `${this.cfg.get<string>('AUTH_HTTP_URL') ?? this.cfg.get<string>('AUTH_INTERNAL_BASE_URL') ?? 'http://auth-service:3001'}`
			.trim()
			.replace(/\/+$/, '');
		const url = `${base}/internal/auth/profile/${encodeURIComponent(userId)}`;
		try {
			const response = await fetch(url, {
				method: 'GET',
				headers: { Accept: 'application/json' },
				signal: AbortSignal.timeout(5000),
			});
			if (!response.ok) {
				return null;
			}
			const body = (await response.json()) as Record<string, unknown>;
			return {
				userId: `${body.userId ?? userId}`,
				email: `${body.email ?? ''}`,
				displayName: `${body.displayName ?? ''}`,
			};
			} catch {
			return null;
		}
	}
}
