import {
	BadRequestException,
	Body,
	Controller,
	Get,
	Inject,
	Logger,
	OnModuleInit,
	Param,
	Patch,
	Post,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { status as grpcStatus } from '@grpc/grpc-js';
import { ClientGrpc, RpcException } from '@nestjs/microservices';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNotEmpty, IsOptional, IsString } from 'class-validator';
import { createHash, createHmac, randomBytes, timingSafeEqual } from 'crypto';
import { firstValueFrom, timeout } from 'rxjs';
import { IsNull, MoreThan, Repository } from 'typeorm';
import { AuthOtp, OtpPurpose } from './entities/auth-otp.entity';
import { AuthStepUpToken } from './entities/auth-step-up-token.entity';
import {
	KycProfile,
	KycRiskLevel,
	KycStatus,
} from '../users/entities/kyc-profile.entity';
import { User } from '../users/entities/user.entity/user.entity';
import { UsersService } from '../users/users.service';

class ResolveRecipientByPhoneDto {
	@IsString()
	@IsNotEmpty()
	phone: string;

	@IsOptional()
	@IsString()
	requesterUserId?: string;
}

class IssueQrTokenDto {
	@IsString()
	@IsNotEmpty()
	userId: string;
}

class ResolveQrTokenDto {
	@IsString()
	@IsNotEmpty()
	token: string;
}

class UpdateProfileDto {
	@IsOptional()
	@IsString()
	displayName?: string;

	@IsOptional()
	@IsString()
	phone?: string;
}

class SubmitKycDto {
	@IsString()
	@IsNotEmpty()
	fullName: string;

	@IsString()
	@IsNotEmpty()
	nationalId: string;

	@IsString()
	@IsNotEmpty()
	dateOfBirth: string;

	@IsOptional()
	@IsString()
	idIssueDate?: string;

	@IsOptional()
	@IsString()
	idIssuePlace?: string;

	@IsString()
	@IsNotEmpty()
	residentialAddress: string;
}

class IssueOtpDto {
	@IsString()
	@IsNotEmpty()
	userId: string;

	@IsOptional()
	@IsString()
	deviceId?: string;
}

class IssueStepUpTokenDto {
	@IsString()
	@IsNotEmpty()
	userId: string;

	@IsOptional()
	@IsString()
	deviceId?: string;

	@IsOptional()
	@IsString()
	method?: string;

	@IsOptional()
	@IsString()
	otpCode?: string;
}

class VerifyStepUpTokenDto {
	@IsString()
	@IsNotEmpty()
	userId: string;

	@IsString()
	@IsNotEmpty()
	stepUpToken: string;

	@IsOptional()
	@IsString()
	deviceId?: string;
}

class SetPinDto {
	@IsString()
	@IsNotEmpty()
	userId: string;

	@IsString()
	@IsNotEmpty()
	pin: string;
}

class VerifyPinDto {
	@IsString()
	@IsNotEmpty()
	userId: string;

	@IsString()
	@IsNotEmpty()
	pin: string;
}

class SignUpAvailabilityDto {
	@IsOptional()
	@IsString()
	email?: string;

	@IsOptional()
	@IsString()
	phone?: string;
}

class SignUpEmailOtpSendDto {
	@IsString()
	@IsNotEmpty()
	email: string;
}

class SignUpEmailOtpVerifyDto {
	@IsString()
	@IsNotEmpty()
	email: string;

	@IsString()
	@IsNotEmpty()
	otpCode: string;
}

@Controller('internal/auth')
export class AuthInternalController implements OnModuleInit {
	private readonly logger = new Logger(AuthInternalController.name);
	private notificationService: any;

	constructor(
		private readonly usersService: UsersService,
		private readonly config: ConfigService,
		@Inject('NOTIFICATION_PACKAGE')
		private readonly notificationClient: ClientGrpc,
		@InjectRepository(AuthOtp)
		private readonly otpRepo: Repository<AuthOtp>,
		@InjectRepository(AuthStepUpToken)
		private readonly stepUpTokenRepo: Repository<AuthStepUpToken>,
		@InjectRepository(KycProfile)
		private readonly kycRepo: Repository<KycProfile>,
		@InjectRepository(User)
		private readonly usersRepo: Repository<User>,
	) {}

	onModuleInit() {
		this.notificationService = this.notificationClient.getService(
			'NotificationService',
		);
	}

	@Post('recipients/resolve-phone')
	async resolveRecipientByPhone(@Body() dto: ResolveRecipientByPhoneDto) {
		return this.usersService.resolveRecipientByPhone(
			dto.phone,
			dto.requesterUserId?.trim(),
		);
	}

	@Post('signup/check-availability')
	async checkSignUpAvailability(@Body() dto: SignUpAvailabilityDto) {
		const email = `${dto.email ?? ''}`.trim().toLowerCase();
		const phone = this.normalizePhone(`${dto.phone ?? ''}`);

		const emailValid = email.length === 0 || this.looksLikeEmail(email);
		const phoneValid = phone.length === 0 || this.isReadyPhone(phone);

		const emailUser =
			emailValid && email
				? await this.usersService.findByEmail(email)
				: null;
		const phoneUser =
			phoneValid && phone
				? await this.usersService.findByPhone(phone)
				: null;

		return {
			email: {
				value: email,
				valid: emailValid,
				available: emailValid && email ? !emailUser : false,
			},
			phone: {
				value: phone,
				valid: phoneValid,
				available: phoneValid && phone ? !phoneUser : false,
			},
		};
	}

	@Post('signup/email-otp/send')
	async sendSignUpEmailOtp(@Body() dto: SignUpEmailOtpSendDto) {
		const email = dto.email.trim().toLowerCase();
		if (!this.looksLikeEmail(email)) {
			throw new BadRequestException('Invalid email format');
		}
		const existing = await this.usersService.findByEmail(email);
		if (existing) {
			throw new BadRequestException('Email already in use');
		}

		const otpExpiresIn = Math.max(
			60,
			Number(this.config.get('SIGNUP_EMAIL_OTP_TTL_SECONDS') ?? 300),
		);
		const otpCode = `${Math.floor(100000 + Math.random() * 900000)}`;
		await this.storeOtpCode({
			userId: this.signUpOtpSubjectId(email),
			deviceId: email,
			purpose: OtpPurpose.STEP_UP_EMAIL,
			otpCode,
			expiresInSeconds: otpExpiresIn,
		});
		const deliveryMode = await this.sendSignUpOtpEmail(
			email,
			otpCode,
			otpExpiresIn,
		);
		return {
			sent: true,
			deliveryMode,
			expiresIn: otpExpiresIn,
		};
	}

	@Post('signup/email-otp/verify')
	async verifySignUpEmailOtp(@Body() dto: SignUpEmailOtpVerifyDto) {
		const email = dto.email.trim().toLowerCase();
		if (!this.looksLikeEmail(email)) {
			throw new BadRequestException('Invalid email format');
		}
		const valid = await this.consumeOtpCode({
			userId: this.signUpOtpSubjectId(email),
			deviceId: email,
			purpose: OtpPurpose.STEP_UP_EMAIL,
			otpCode: dto.otpCode.trim(),
		});
		return { valid };
	}

	@Post('qr-transfer/issue')
	async issueQrTransferToken(@Body() dto: IssueQrTokenDto) {
		const user = await this.usersService.findById(dto.userId);
		if (!user) {
			throw new BadRequestException('User not found');
		}
		if (!user.phone || user.phone.trim().length === 0) {
			throw new BadRequestException(
				'User phone is required for QR transfer',
			);
		}

		const expiresIn = Math.max(
			30,
			Number(this.config.get('QR_TRANSFER_TOKEN_TTL_SECONDS') ?? 120),
		);
		const nowSec = Math.floor(Date.now() / 1000);
		const payload = {
			v: 1,
			userId: user.id,
			exp: nowSec + expiresIn,
			nonce: randomBytes(12).toString('hex'),
		};
		const payloadText = JSON.stringify(payload);
		const payloadEncoded = Buffer.from(payloadText, 'utf8').toString(
			'base64url',
		);
		const signature = this.signQrPayload(payloadEncoded);
		return {
			token: `${payloadEncoded}.${signature}`,
			expiresIn,
		};
	}

	@Post('qr-transfer/resolve')
	async resolveQrTransferToken(@Body() dto: ResolveQrTokenDto) {
		const token = dto.token.trim();
		const decoded = this.verifyQrToken(token);
		if (!decoded || !decoded.userId) {
			return { found: false };
		}
		const recipient = await this.usersService.findById(decoded.userId);
		if (!recipient || recipient.accountStatus !== 'active') {
			return { found: false };
		}
		return {
			found: true,
			recipient: {
				userId: recipient.id,
				phone: recipient.phone ?? '',
				displayName:
					recipient.displayName ?? recipient.email ?? 'Người dùng',
				kycStatus: recipient.kycStatus ?? 'pending',
			},
		};
	}

	@Get('profile/:userId')
	async getProfile(@Param('userId') userId: string) {
		return this.usersService.getProfile(userId);
	}

	@Patch('profile/:userId')
	async updateProfile(
		@Param('userId') userId: string,
		@Body() dto: UpdateProfileDto,
	) {
		return this.usersService.updateProfile(userId, dto);
	}

	@Get('kyc/:userId')
	async getKycProfile(@Param('userId') userId: string) {
		const profile = await this.kycRepo.findOne({ where: { userId } });
		if (!profile) {
			const user = await this.usersService.findById(userId);
			if (!user) {
				throw new BadRequestException('User not found');
			}
			return {
				userId,
				status: user.kycStatus ?? KycStatus.UNVERIFIED,
				fullName: user.displayName ?? '',
				nationalId: '',
				dateOfBirth: '',
				idIssueDate: '',
				idIssuePlace: '',
				residentialAddress: '',
				riskLevel: KycRiskLevel.LOW,
				rejectionReason: '',
				submittedAt: '',
				reviewedAt: '',
				updatedAt: user.updatedAt?.toISOString() ?? '',
			};
		}
		return {
			userId: profile.userId,
			status: profile.status,
			fullName: profile.fullName,
			nationalId: profile.nationalId,
			dateOfBirth: profile.dateOfBirth?.toISOString() ?? '',
			idIssueDate: profile.idIssueDate?.toISOString() ?? '',
			idIssuePlace: profile.idIssuePlace ?? '',
			residentialAddress: profile.residentialAddress,
			riskLevel: profile.riskLevel,
			rejectionReason: profile.rejectionReason ?? '',
			submittedAt: profile.submittedAt?.toISOString() ?? '',
			reviewedAt: profile.reviewedAt?.toISOString() ?? '',
			updatedAt: profile.updatedAt?.toISOString() ?? '',
		};
	}

	@Post('kyc/:userId/submit')
	async submitKyc(
		@Param('userId') userId: string,
		@Body() dto: SubmitKycDto,
	) {
		const user = await this.usersService.findById(userId);
		if (!user) {
			throw new BadRequestException('User not found');
		}

		const dateOfBirth = new Date(dto.dateOfBirth);
		if (Number.isNaN(dateOfBirth.getTime())) {
			throw new BadRequestException('dateOfBirth is invalid');
		}
		const idIssueDate = dto.idIssueDate ? new Date(dto.idIssueDate) : null;
		if (dto.idIssueDate && Number.isNaN(idIssueDate!.getTime())) {
			throw new BadRequestException('idIssueDate is invalid');
		}

		const existing = await this.kycRepo.findOne({ where: { userId } });
		const profile = existing ?? this.kycRepo.create({ userId });
		profile.fullName = dto.fullName.trim();
		profile.nationalId = dto.nationalId.trim();
		profile.dateOfBirth = dateOfBirth;
		profile.idIssueDate = idIssueDate;
		profile.idIssuePlace = dto.idIssuePlace?.trim() || null;
		profile.residentialAddress = dto.residentialAddress.trim();
		profile.status = KycStatus.PENDING_REVIEW;
		profile.riskLevel = KycRiskLevel.LOW;
		profile.submittedAt = new Date();
		profile.rejectionReason = null;

		const saved = await this.kycRepo.save(profile);
		user.kycStatus = KycStatus.PENDING_REVIEW;
		await this.usersRepo.save(user);

		return {
			message: 'Đã gửi hồ sơ KYC thành công.',
			profile: {
				userId: saved.userId,
				status: saved.status,
				fullName: saved.fullName,
				nationalId: saved.nationalId,
				dateOfBirth: saved.dateOfBirth?.toISOString() ?? '',
				idIssueDate: saved.idIssueDate?.toISOString() ?? '',
				idIssuePlace: saved.idIssuePlace ?? '',
				residentialAddress: saved.residentialAddress,
				riskLevel: saved.riskLevel,
				rejectionReason: saved.rejectionReason ?? '',
				submittedAt: saved.submittedAt?.toISOString() ?? '',
				reviewedAt: saved.reviewedAt?.toISOString() ?? '',
				updatedAt: saved.updatedAt?.toISOString() ?? '',
			},
		};
	}

	@Post('otp/issue')
	async issueOtp(@Body() dto: IssueOtpDto) {
		const user = await this.usersService.findById(dto.userId);
		if (!user) {
			throw new BadRequestException('User not found');
		}
		const expiresIn = Math.max(
			60,
			Number(this.config.get('OTP_TTL_SECONDS') ?? 120),
		);
		const otpCode = `${Math.floor(100000 + Math.random() * 900000)}`;
		const deviceKey = (dto.deviceId ?? '').trim();
		await this.storeOtpCode({
			userId: dto.userId,
			deviceId: deviceKey,
			purpose: OtpPurpose.TRANSFER,
			otpCode,
			expiresInSeconds: expiresIn,
		});
		return {
			otpCode,
			expiresIn,
			deliveryMode: 'smart_otp',
		};
	}

	@Post('step-up/token')
	async issueStepUpToken(@Body() dto: IssueStepUpTokenDto) {
		const user = await this.usersService.findById(dto.userId);
		if (!user) {
			throw new BadRequestException('User not found');
		}
		const method =
			(dto.method?.trim().length ?? 0) > 0 ? dto.method!.trim() : 'face';

		if (method.toLowerCase() === 'otp_email') {
			const email = `${user.email ?? ''}`.trim().toLowerCase();
			if (!email) {
				throw new BadRequestException(
					'User email is required for step-up OTP',
				);
			}
			const deviceKey = (dto.deviceId ?? '').trim();
			const providedOtpCode = (dto.otpCode ?? '').trim();
			const otpExpiresIn = Math.max(
				60,
				Number(this.config.get('STEP_UP_EMAIL_OTP_TTL_SECONDS') ?? 180),
			);

			if (!providedOtpCode) {
				const otpCode = `${Math.floor(100000 + Math.random() * 900000)}`;
				await this.storeOtpCode({
					userId: dto.userId,
					deviceId: deviceKey,
					purpose: OtpPurpose.STEP_UP_EMAIL,
					otpCode,
					expiresInSeconds: otpExpiresIn,
				});
				await this.sendStepUpOtpEmail(email, otpCode, otpExpiresIn);
				return {
					challengeIssued: true,
					method: 'otp_email',
					deliveryMode: 'email',
					expiresIn: otpExpiresIn,
				};
			}

			const validOtp = await this.consumeOtpCode({
				userId: dto.userId,
				deviceId: deviceKey,
				purpose: OtpPurpose.STEP_UP_EMAIL,
				otpCode: providedOtpCode,
			});
			if (!validOtp) {
				throw new BadRequestException(
					'Invalid or expired OTP for step-up',
				);
			}
		}

		const stepUpToken = randomBytes(24).toString('base64url');
		const expiresIn = Math.max(
			60,
			Number(this.config.get('STEP_UP_TOKEN_TTL_SECONDS') ?? 180),
		);
		const row = this.stepUpTokenRepo.create({
			token: stepUpToken,
			userId: dto.userId,
			deviceId: (dto.deviceId ?? '').trim() || null,
			method,
			expiresAt: new Date(Date.now() + expiresIn * 1000),
		});
		await this.stepUpTokenRepo.save(row);
		return {
			stepUpToken,
			method,
			expiresIn,
		};
	}

	@Post('step-up/verify')
	async verifyStepUpToken(@Body() dto: VerifyStepUpTokenDto) {
		const token = dto.stepUpToken.trim();
		const row = await this.stepUpTokenRepo.findOne({ where: { token } });
		if (!row) {
			return { valid: false };
		}
		if (row.expiresAt.getTime() <= Date.now()) {
			await this.stepUpTokenRepo.delete({ id: row.id });
			return { valid: false };
		}
		if (row.userId !== dto.userId) {
			return { valid: false };
		}
		const requestedDeviceId = (dto.deviceId ?? '').trim();
		const savedDeviceId = `${row.deviceId ?? ''}`.trim();
		if (
			savedDeviceId &&
			requestedDeviceId &&
			savedDeviceId !== requestedDeviceId
		) {
			return { valid: false };
		}
		return { valid: true };
	}

	@Post('pin/set')
	async setPin(@Body() dto: SetPinDto) {
		const user = await this.usersService.findById(dto.userId);
		if (!user) {
			throw new BadRequestException('User not found');
		}
		await this.usersService.setPin(dto.userId, dto.pin);
		return { success: true, message: 'PIN đã được thiết lập thành công.' };
	}

	@Post('pin/verify')
	async verifyPin(@Body() dto: VerifyPinDto) {
		const valid = await this.usersService.verifyPin(dto.userId, dto.pin);
		return { valid };
	}

	@Get('pin/status/:userId')
	async getPinStatus(@Param('userId') userId: string) {
		const user = await this.usersService.findById(userId);
		if (!user) {
			throw new BadRequestException('User not found');
		}
		return { hasPin: this.usersService.hasPin(user) };
	}

	private signQrPayload(payloadEncoded: string): string {
		const secret = this.qrTokenSecret();
		return createHmac('sha256', secret)
			.update(payloadEncoded)
			.digest('base64url');
	}

	private verifyQrToken(
		token: string,
	): { userId: string; exp: number; nonce: string; v: number } | null {
		const parts = token.split('.');
		if (parts.length !== 2) {
			return null;
		}
		const [payloadEncoded, signature] = parts;
		const expected = this.signQrPayload(payloadEncoded);
		const sigBuf = Buffer.from(signature);
		const expBuf = Buffer.from(expected);
		if (sigBuf.length !== expBuf.length) {
			return null;
		}
		if (!timingSafeEqual(sigBuf, expBuf)) {
			return null;
		}

		let payload: any;
		try {
			payload = JSON.parse(
				Buffer.from(payloadEncoded, 'base64url').toString('utf8'),
			);
		} catch {
			return null;
		}
		if (!payload || typeof payload !== 'object') {
			return null;
		}
		const exp = Number(payload.exp ?? 0);
		if (!Number.isFinite(exp) || exp <= Math.floor(Date.now() / 1000)) {
			return null;
		}
		return {
			userId: `${payload.userId ?? ''}`.trim(),
			exp,
			nonce: `${payload.nonce ?? ''}`.trim(),
			v: Number(payload.v ?? 0),
		};
	}

	private qrTokenSecret(): string {
		const fromEnv = this.config
			.get<string>('QR_TRANSFER_TOKEN_SECRET')
			?.trim();
		if (fromEnv) {
			return fromEnv;
		}
		const jwtSecret = this.config.get<string>('JWT_SECRET')?.trim();
		return jwtSecret || 'qr-transfer-fallback-secret';
	}

	private async storeOtpCode(params: {
		userId: string;
		deviceId: string;
		purpose: OtpPurpose;
		otpCode: string;
		expiresInSeconds: number;
	}) {
		const { userId, deviceId, purpose, otpCode, expiresInSeconds } = params;
		const normalizedDeviceId = (deviceId || '').trim();
		await this.otpRepo.delete({
			userId,
			purpose,
			deviceId: normalizedDeviceId || IsNull(),
		});
		const row = this.otpRepo.create({
			userId,
			purpose,
			otpHash: this.hashOtpCode({
				userId,
				deviceId: normalizedDeviceId,
				purpose,
				otpCode,
			}),
			expiresAt: new Date(Date.now() + expiresInSeconds * 1000),
			usedAt: null,
			attemptCount: 0,
			deviceId: normalizedDeviceId || null,
		});
		await this.otpRepo.save(row);
	}

	private async consumeOtpCode(params: {
		userId: string;
		deviceId: string;
		purpose: OtpPurpose;
		otpCode: string;
	}): Promise<boolean> {
		const { userId, deviceId, purpose, otpCode } = params;
		const normalizedDeviceId = (deviceId || '').trim();
		const row = await this.otpRepo.findOne({
			where: {
				userId,
				purpose,
				deviceId: normalizedDeviceId || IsNull(),
				usedAt: IsNull(),
				expiresAt: MoreThan(new Date()),
			},
			order: { createdAt: 'DESC' },
		});
		if (!row) {
			return false;
		}
		const expectedHash = this.hashOtpCode({
			userId,
			deviceId: normalizedDeviceId,
			purpose,
			otpCode,
		});
		const valid = this.constantTimeEquals(row.otpHash, expectedHash);
		if (!valid) {
			row.attemptCount = Math.max(0, Number(row.attemptCount ?? 0)) + 1;
			await this.otpRepo.save(row);
			return false;
		}
		row.usedAt = new Date();
		await this.otpRepo.save(row);
		return true;
	}

	private hashOtpCode(params: {
		userId: string;
		deviceId: string;
		purpose: OtpPurpose;
		otpCode: string;
	}): string {
		const secret = this.otpHashSecret();
		const payload = [
			params.userId.trim(),
			params.deviceId.trim(),
			params.purpose,
			params.otpCode.trim(),
		].join(':');
		return createHmac('sha256', secret).update(payload).digest('hex');
	}

	private otpHashSecret(): string {
		const fromEnv =
			`${this.config.get<string>('OTP_HASH_SECRET') ?? ''}`.trim();
		if (fromEnv) {
			return fromEnv;
		}
		return this.qrTokenSecret();
	}

	private constantTimeEquals(a: string, b: string): boolean {
		const aBuf = Buffer.from(a);
		const bBuf = Buffer.from(b);
		if (aBuf.length !== bBuf.length) {
			return false;
		}
		return timingSafeEqual(aBuf, bBuf);
	}

	private normalizePhone(raw: string): string {
		const digitsOnly = raw.replace(/[^\d]/g, '');
		if (digitsOnly.startsWith('84') && digitsOnly.length == 11) {
			return `0${digitsOnly.substring(2)}`;
		}
		return digitsOnly;
	}

	private isReadyPhone(value: string): boolean {
		return /^(0\d{9,10}|84\d{8,10})$/.test(value);
	}

	private looksLikeEmail(value: string): boolean {
		return /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$/.test(
			value,
		);
	}

	private signUpOtpSubjectId(email: string): string {
		const hex = createHash('sha256')
			.update(`signup-email:${email.trim().toLowerCase()}`)
			.digest('hex')
			.substring(0, 32);
		return `${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}`;
	}

	private async sendSignUpOtpEmail(
		recipientEmail: string,
		otpCode: string,
		expiresInSeconds: number,
	): Promise<'email'> {
		return this.sendEmailOtpViaNotification({
			recipientEmail,
			otpCode,
			expiresInSeconds,
			purpose: 'signup',
		});
	}

	private async sendStepUpOtpEmail(
		recipientEmail: string,
		otpCode: string,
		expiresInSeconds: number,
	): Promise<'email'> {
		return this.sendEmailOtpViaNotification({
			recipientEmail,
			otpCode,
			expiresInSeconds,
			purpose: 'step_up',
		});
	}

	private async sendEmailOtpViaNotification(params: {
		recipientEmail: string;
		otpCode: string;
		expiresInSeconds: number;
		purpose: 'signup' | 'step_up';
	}): Promise<'email'> {
		const grpcTimeoutMs = Number(
			this.config.get('GRPC_TIMEOUT_MS') ?? 5000,
		);
		try {
			const response = (await firstValueFrom(
				this.notificationService
					.sendEmailOtp({
						recipientEmail: params.recipientEmail,
						otpCode: params.otpCode,
						expiresInSeconds: params.expiresInSeconds,
						purpose: params.purpose,
					})
					.pipe(timeout(grpcTimeoutMs)),
			)) as Record<string, unknown>;

			if (response?.sent !== true) {
				throw new BadRequestException(
					'Notification service could not send OTP email',
				);
			}
			return 'email';
		} catch (error) {
			if (error instanceof RpcException) {
				const payload = error.getError() as any;
				const code = Number(payload?.code ?? 0);
				if (code === grpcStatus.INVALID_ARGUMENT) {
					throw new BadRequestException(
						`${payload?.message ?? 'Invalid notification request'}`,
					);
				}
				if (code === grpcStatus.UNAVAILABLE) {
					throw new BadRequestException(
						'Dịch vụ thông báo đang tạm thời không khả dụng.',
					);
				}
			}

			const message =
				error instanceof Error ? error.message : String(error);
			this.logger.error(
				`Failed to send OTP email via notification service: ${message}`,
			);
			throw new BadRequestException('Không thể gửi OTP email lúc này.');
		}
	}
}
