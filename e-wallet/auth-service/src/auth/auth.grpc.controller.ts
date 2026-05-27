import { Controller } from '@nestjs/common';
import { GrpcMethod, RpcException } from '@nestjs/microservices';
import { status } from '@grpc/grpc-js';
import { AuthService, VerifyTokenResult } from './auth.service';

type VerifyTokenRequest = {
	accessToken: string;
};

type VerifyFirebaseTokenRequest = {
	idToken: string;
	userAgent?: string;
	ipAddress?: string;
	email?: string;
	phone?: string;
	displayName?: string;
};

type DevLoginRequest = {
	firebaseUid: string;
	email?: string;
	phone?: string;
	displayName?: string;
	userAgent?: string;
	ipAddress?: string;
};

type RefreshTokenRequest = {
	refreshToken: string;
	userAgent?: string;
	ipAddress?: string;
};

type ResolveLoginIdentifierRequest = {
	identifier: string;
};

type LogoutRequest = {
	refreshToken: string;
};

type LogoutAllRequest = {
	accessToken: string;
};

@Controller()
export class AuthGrpcController {
	constructor(private readonly authService: AuthService) {}

	@GrpcMethod('AuthService', 'VerifyToken')
	async verifyToken(data: VerifyTokenRequest): Promise<VerifyTokenResult> {
		if (!data?.accessToken) {
			throw new RpcException({
				code: status.INVALID_ARGUMENT,
				message: 'accessToken required',
			});
		}
		try {
			return await this.authService.verifyInternalToken(data.accessToken);
		} catch {
			throw new RpcException({
				code: status.UNAUTHENTICATED,
				message: 'Invalid access token',
			});
		}
	}

	@GrpcMethod('AuthService', 'VerifyFirebaseToken')
	async verifyFirebaseToken(data: VerifyFirebaseTokenRequest) {
		if (!data?.idToken) {
			throw new RpcException({
				code: status.INVALID_ARGUMENT,
				message: 'idToken required',
			});
		}
		try {
			const result = await this.authService.verifyFirebaseIdToken(
				data.idToken,
				{ userAgent: data.userAgent, ipAddress: data.ipAddress },
				{
					email: data.email,
					phone: data.phone,
					displayName: data.displayName,
				},
			);
			return {
				accessToken: result.accessToken,
				refreshToken: result.refreshToken,
				expiresIn: result.expiresIn,
				userId: result.user.id,
				user: result.user,
			};
		} catch (e: any) {
			throw new RpcException({
				code: status.UNAUTHENTICATED,
				message: e.message || 'Authentication failed',
			});
		}
	}

	@GrpcMethod('AuthService', 'DevLogin')
	async devLogin(data: DevLoginRequest) {
		if (!data?.firebaseUid) {
			throw new RpcException({
				code: status.INVALID_ARGUMENT,
				message: 'firebaseUid required',
			});
		}
		try {
			const result = await this.authService.devLogin(
				data.firebaseUid,
				{ userAgent: data.userAgent, ipAddress: data.ipAddress },
				{ email: data.email, phone: data.phone, displayName: data.displayName },
			);
			return {
				accessToken: result.accessToken,
				refreshToken: result.refreshToken,
				expiresIn: result.expiresIn,
				userId: result.user.id,
				user: result.user,
			};
		} catch (e: any) {
			throw new RpcException({
				code: status.INTERNAL,
				message: e.message || 'Dev login failed',
			});
		}
	}

	@GrpcMethod('AuthService', 'RefreshToken')
	async refreshToken(data: RefreshTokenRequest) {
		if (!data?.refreshToken) {
			throw new RpcException({
				code: status.INVALID_ARGUMENT,
				message: 'refreshToken required',
			});
		}
		try {
			const result = await this.authService.refreshAccessToken(
				data.refreshToken,
				{ userAgent: data.userAgent, ipAddress: data.ipAddress },
			);
			return {
				accessToken: result.accessToken,
				refreshToken: result.refreshToken,
				expiresIn: result.expiresIn,
				userId: result.user.id,
				user: result.user,
			};
		} catch (e: any) {
			throw new RpcException({
				code: status.UNAUTHENTICATED,
				message: e.message || 'Refresh failed',
			});
		}
	}

	@GrpcMethod('AuthService', 'ResolveLoginIdentifier')
	async resolveLoginIdentifier(data: ResolveLoginIdentifierRequest) {
		const identifier = data?.identifier?.trim();
		if (!identifier) {
			throw new RpcException({
				code: status.INVALID_ARGUMENT,
				message: 'identifier required',
			});
		}
		try {
			return this.authService.resolveLoginIdentifier(identifier);
		} catch (e: any) {
			throw new RpcException({
				code: status.INTERNAL,
				message: e.message || 'Resolve identifier failed',
			});
		}
	}

	@GrpcMethod('AuthService', 'Logout')
	async logout(data: LogoutRequest) {
		if (!data?.refreshToken) {
			throw new RpcException({
				code: status.INVALID_ARGUMENT,
				message: 'refreshToken required',
			});
		}
		try {
			await this.authService.revokeRefreshToken(data.refreshToken);
			return {};
		} catch (e: any) {
			throw new RpcException({
				code: status.INTERNAL,
				message: e.message || 'Logout failed',
			});
		}
	}

	@GrpcMethod('AuthService', 'LogoutAll')
	async logoutAll(data: LogoutAllRequest) {
		if (!data?.accessToken) {
			throw new RpcException({
				code: status.INVALID_ARGUMENT,
				message: 'accessToken required',
			});
		}
		try {
			await this.authService.revokeAllSessionsByAccessToken(data.accessToken);
			return {};
		} catch (e: any) {
			throw new RpcException({
				code: status.INTERNAL,
				message: e.message || 'Logout all failed',
			});
		}
	}
}
