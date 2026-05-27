import {
	BadRequestException,
	Body,
	ConflictException,
	Controller,
	ForbiddenException,
	GatewayTimeoutException,
	Get,
	Headers,
	InternalServerErrorException,
	NotFoundException,
	Patch,
	Post,
	Req,
	ServiceUnavailableException,
	UnauthorizedException,
	UseGuards,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { IsNotEmpty, IsOptional, IsString } from 'class-validator';
import { firstValueFrom, timeout } from 'rxjs';
import { status as grpcStatus } from '@grpc/grpc-js';
import { GrpcClientsService } from '../common/grpc-clients.service';
import { AuthGuard } from '../common/auth.guard';

class FirebaseLoginDto {
	@IsString()
	@IsNotEmpty()
	idToken!: string;

	@IsString()
	@IsOptional()
	email?: string;

	@IsString()
	@IsOptional()
	phone?: string;

	@IsString()
	@IsOptional()
	displayName?: string;
}

class DevLoginDto {
	@IsString()
	@IsNotEmpty()
	firebaseUid!: string;

	@IsString()
	@IsOptional()
	email?: string;

	@IsString()
	@IsOptional()
	phone?: string;

	@IsString()
	@IsOptional()
	displayName?: string;
}

class RefreshTokenDto {
	@IsString()
	@IsNotEmpty()
	refreshToken!: string;
}

class ResolveLoginIdentifierDto {
	@IsString()
	@IsNotEmpty()
	identifier!: string;
}

class ResolveRecipientByPhoneDto {
	@IsString()
	@IsNotEmpty()
	phone!: string;
}

class ResolveQrTransferDto {
	@IsString()
	@IsNotEmpty()
	token!: string;
}

class UpdateProfileDto {
	@IsString()
	@IsOptional()
	displayName?: string;

	@IsString()
	@IsOptional()
	phone?: string;
}

class SubmitKycDto {
	@IsString()
	@IsNotEmpty()
	fullName!: string;

	@IsString()
	@IsNotEmpty()
	nationalId!: string;

	@IsString()
	@IsNotEmpty()
	dateOfBirth!: string;

	@IsString()
	@IsOptional()
	idIssueDate?: string;

	@IsString()
	@IsOptional()
	idIssuePlace?: string;

	@IsString()
	@IsNotEmpty()
	residentialAddress!: string;
}

class StepUpTokenDto {
	@IsString()
	@IsOptional()
	method?: string;

	@IsString()
	@IsOptional()
	otpCode?: string;
}

class SetPinDto {
	@IsString()
	@IsNotEmpty()
	pin!: string;
}

class VerifyPinDto {
	@IsString()
	@IsNotEmpty()
	pin!: string;
}

class SignUpAvailabilityDto {
	@IsString()
	@IsOptional()
	email?: string;

	@IsString()
	@IsOptional()
	phone?: string;
}

class SignUpEmailOtpSendDto {
	@IsString()
	@IsNotEmpty()
	email!: string;
}

class SignUpEmailOtpVerifyDto {
	@IsString()
	@IsNotEmpty()
	email!: string;

	@IsString()
	@IsNotEmpty()
	otpCode!: string;
}

@Controller('v1/auth')
export class GatewayAuthController {
	private readonly grpcTimeoutMs: number;

	constructor(
		private readonly grpcClients: GrpcClientsService,
		private readonly config: ConfigService,
	) {
		this.grpcTimeoutMs = Number(this.config.get('GRPC_TIMEOUT_MS') ?? 5000);
	}

	@Post('firebase/verify')
	async verifyFirebase(
		@Body() dto: FirebaseLoginDto,
		@Headers('user-agent') userAgent?: string,
		@Headers('x-forwarded-for') forwardedFor?: string,
	) {
		if (!dto?.idToken) {
			throw new UnauthorizedException('idToken is required');
		}
		const ipAddress = forwardedFor?.split(',')[0]?.trim();
		try {
			const result = await firstValueFrom(
				this.grpcClients.auth
					.verifyFirebaseToken({
						idToken: dto.idToken,
						userAgent,
						ipAddress,
						email: dto.email,
						phone: dto.phone,
						displayName: dto.displayName,
					})
					.pipe(timeout(this.grpcTimeoutMs)),
			);
			return this.normalizeAuthResponse(result);
		} catch (error) {
			this.rethrowGrpcError(error);
		}
	}

	@Post('dev/login')
	async devLogin(
		@Body() dto: DevLoginDto,
		@Headers('user-agent') userAgent?: string,
		@Headers('x-forwarded-for') forwardedFor?: string,
	) {
		const ipAddress = forwardedFor?.split(',')[0]?.trim();
		try {
			const result = await firstValueFrom(
				this.grpcClients.auth
					.devLogin({
						firebaseUid: dto.firebaseUid,
						email: dto.email,
						phone: dto.phone,
						displayName: dto.displayName,
						userAgent,
						ipAddress,
					})
					.pipe(timeout(this.grpcTimeoutMs)),
			);
			return this.normalizeAuthResponse(result);
		} catch (error) {
			this.rethrowGrpcError(error);
		}
	}

	@Post('refresh')
	async refresh(
		@Body() dto: RefreshTokenDto,
		@Headers('user-agent') userAgent?: string,
		@Headers('x-forwarded-for') forwardedFor?: string,
	) {
		const ipAddress = forwardedFor?.split(',')[0]?.trim();
		try {
			const result = await firstValueFrom(
				this.grpcClients.auth
					.refreshToken({
						refreshToken: dto.refreshToken,
						userAgent,
						ipAddress,
					})
					.pipe(timeout(this.grpcTimeoutMs)),
			);
			return this.normalizeAuthResponse(result);
		} catch (error) {
			this.rethrowGrpcError(error);
		}
	}

	@Post('login/resolve-identifier')
	async resolveLoginIdentifier(@Body() dto: ResolveLoginIdentifierDto) {
		try {
			return await firstValueFrom(
				this.grpcClients.auth
					.resolveLoginIdentifier({
						identifier: dto.identifier,
					})
					.pipe(timeout(this.grpcTimeoutMs)),
			);
		} catch (error) {
			this.rethrowGrpcError(error);
		}
	}

	@Post('signup/check-availability')
	async checkSignUpAvailability(@Body() dto: SignUpAvailabilityDto) {
		return this.callAuthInternal('/internal/auth/signup/check-availability', 'POST', {
			email: dto.email ?? '',
			phone: dto.phone ?? '',
		});
	}

	@Post('signup/email-otp/send')
	async sendSignUpEmailOtp(@Body() dto: SignUpEmailOtpSendDto) {
		return this.callAuthInternal('/internal/auth/signup/email-otp/send', 'POST', {
			email: dto.email,
		});
	}

	@Post('signup/email-otp/verify')
	async verifySignUpEmailOtp(@Body() dto: SignUpEmailOtpVerifyDto) {
		return this.callAuthInternal(
			'/internal/auth/signup/email-otp/verify',
			'POST',
			{
				email: dto.email,
				otpCode: dto.otpCode,
			},
		);
	}

	@Post('logout')
	async logout(@Body() dto: RefreshTokenDto) {
		try {
			return await firstValueFrom(
				this.grpcClients.auth
					.logout({ refreshToken: dto.refreshToken })
					.pipe(timeout(this.grpcTimeoutMs)),
			);
		} catch (error) {
			this.rethrowGrpcError(error);
		}
	}

	@Post('logout-all')
	async logoutAll(@Headers('authorization') auth?: string) {
		if (!auth?.startsWith('Bearer ')) {
			throw new UnauthorizedException('Missing access token');
		}
		const accessToken = auth.slice('Bearer '.length).trim();
		try {
			return await firstValueFrom(
				this.grpcClients.auth
					.logoutAll({ accessToken })
					.pipe(timeout(this.grpcTimeoutMs)),
			);
		} catch (error) {
			this.rethrowGrpcError(error);
		}
	}

	@Get('profile')
	@UseGuards(AuthGuard)
	async getProfile(@Req() req: any) {
		return this.callAuthInternal(
			`/internal/auth/profile/${encodeURIComponent(req.authUser.userId)}`,
			'GET',
		);
	}

	@Patch('profile')
	@UseGuards(AuthGuard)
	async updateProfile(@Req() req: any, @Body() dto: UpdateProfileDto) {
		return this.callAuthInternal(
			`/internal/auth/profile/${encodeURIComponent(req.authUser.userId)}`,
			'PATCH',
			{
				displayName: dto.displayName,
				phone: dto.phone,
			},
		);
	}

	@Get('kyc/profile')
	@UseGuards(AuthGuard)
	async getKycProfile(@Req() req: any) {
		return this.callAuthInternal(
			`/internal/auth/kyc/${encodeURIComponent(req.authUser.userId)}`,
			'GET',
		);
	}

	@Post('kyc/submit')
	@UseGuards(AuthGuard)
	async submitKyc(@Req() req: any, @Body() dto: SubmitKycDto) {
		return this.callAuthInternal(
			`/internal/auth/kyc/${encodeURIComponent(req.authUser.userId)}/submit`,
			'POST',
			dto as unknown as Record<string, unknown>,
		);
	}

	@Post('recipients/resolve-phone')
	@UseGuards(AuthGuard)
	async resolveRecipientByPhone(
		@Req() req: any,
		@Body() dto: ResolveRecipientByPhoneDto,
	) {
		return this.callAuthInternal(
			'/internal/auth/recipients/resolve-phone',
			'POST',
			{
				phone: dto.phone,
				requesterUserId: req.authUser.userId,
			},
		);
	}

	@Post('qr-transfer/issue')
	@UseGuards(AuthGuard)
	async issueQrTransferToken(@Req() req: any) {
		return this.callAuthInternal('/internal/auth/qr-transfer/issue', 'POST', {
			userId: req.authUser.userId,
		});
	}

	@Post('qr-transfer/resolve')
	@UseGuards(AuthGuard)
	async resolveQrTransfer(
		@Body() dto: ResolveQrTransferDto,
	) {
		return this.callAuthInternal('/internal/auth/qr-transfer/resolve', 'POST', {
			token: dto.token,
		});
	}

	@Post('otp/issue')
	@UseGuards(AuthGuard)
	async issueOtp(
		@Req() req: any,
		@Headers('x-device-id') deviceId?: string,
	) {
		return this.callAuthInternal('/internal/auth/otp/issue', 'POST', {
			userId: req.authUser.userId,
			deviceId: (deviceId ?? '').trim(),
		});
	}

	@Post('step-up/token')
	@UseGuards(AuthGuard)
	async issueStepUpToken(
		@Req() req: any,
		@Headers('x-device-id') deviceId?: string,
		@Body() dto?: StepUpTokenDto,
	) {
		return this.callAuthInternal('/internal/auth/step-up/token', 'POST', {
			userId: req.authUser.userId,
			deviceId: (deviceId ?? '').trim(),
			method: dto?.method ?? 'face',
			otpCode: dto?.otpCode ?? '',
		});
	}

	@Post('pin/set')
	@UseGuards(AuthGuard)
	async setPin(@Req() req: any, @Body() dto: SetPinDto) {
		return this.callAuthInternal('/internal/auth/pin/set', 'POST', {
			userId: req.authUser.userId,
			pin: dto.pin,
		});
	}

	@Post('pin/verify')
	@UseGuards(AuthGuard)
	async verifyPin(@Req() req: any, @Body() dto: VerifyPinDto) {
		return this.callAuthInternal('/internal/auth/pin/verify', 'POST', {
			userId: req.authUser.userId,
			pin: dto.pin,
		});
	}

	@Get('pin/status')
	@UseGuards(AuthGuard)
	async getPinStatus(@Req() req: any) {
		return this.callAuthInternal(
			`/internal/auth/pin/status/${encodeURIComponent(req.authUser.userId)}`,
			'GET',
		);
	}

	private normalizeAuthResponse(payload: any) {
		if (!payload || typeof payload !== 'object') {
			return payload;
		}
		return {
			...payload,
			expiresIn: this.int64ToNumber(payload.expiresIn),
		};
	}

	private authInternalBaseUrl(): string {
		const configured = `${this.config.get<string>('AUTH_HTTP_URL') ?? ''}`
			.trim()
			.replace(/\/+$/, '');
		if (configured) {
			return configured;
		}
		const fallback = 'http://auth-service:3001';
		this.config.get('NODE_ENV') !== 'test' &&
			console.warn('[AuthController] AUTH_HTTP_URL not configured — falling back to', fallback);
		return fallback;
	}

	private async callAuthInternal(
		path: string,
		method: 'GET' | 'POST' | 'PATCH',
		body?: Record<string, unknown>,
	) {
		const url = `${this.authInternalBaseUrl()}${path}`;
		let response: Response;
		try {
			response = await fetch(url, {
				method,
				headers: {
					'Content-Type': 'application/json',
				},
				body: method === 'GET' ? undefined : JSON.stringify(body ?? {}),
			});
		} catch {
			throw new ServiceUnavailableException('Auth service unavailable');
		}

		const raw = await response.text();
		let parsed: any = {};
		if (raw.trim().length > 0) {
			try {
				parsed = JSON.parse(raw);
			} catch {
				parsed = { message: raw };
			}
		}
		if (response.status >= 400) {
			const message = `${parsed?.message ?? 'Auth helper request failed'}`;
			if (response.status === 404) {
				throw new NotFoundException(message);
			}
			if (response.status === 401) {
				throw new UnauthorizedException(message);
			}
			if (response.status === 403) {
				throw new ForbiddenException(message);
			}
			if (response.status === 400) {
				throw new BadRequestException(message);
			}
			throw new InternalServerErrorException(message);
		}
		return parsed;
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

	private rethrowGrpcError(error: any): never {
		const code = Number(error?.code);
		const message =
			typeof error?.details === 'string' && error.details.trim()
				? error.details.trim()
				: typeof error?.message === 'string' && error.message.trim()
					? error.message.trim()
					: 'Auth service error';

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
				throw new GatewayTimeoutException('Auth service timeout');
			case grpcStatus.UNAVAILABLE:
				throw new ServiceUnavailableException('Auth service unavailable');
			default:
				throw new InternalServerErrorException(message);
		}
	}
}
