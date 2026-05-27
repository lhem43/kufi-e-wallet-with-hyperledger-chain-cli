import {
	CanActivate,
	ExecutionContext,
	Injectable,
	UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';

type AccessTokenPayload = {
	sub: string;
	firebaseUid?: string;
	kycStatus?: string;
};

@Injectable()
export class AuthGuard implements CanActivate {
	private readonly jwtIssuer: string;
	private readonly jwtAudience: string;

	constructor(
		private readonly jwt: JwtService,
		private readonly config: ConfigService,
	) {
		this.jwtIssuer = this.config.get<string>('JWT_ISSUER') ?? 'auth-service';
		this.jwtAudience = this.config.get<string>('JWT_AUDIENCE') ?? 'e-wallet';
	}

	async canActivate(context: ExecutionContext): Promise<boolean> {
		const request = context.switchToHttp().getRequest();
		const authHeader = request.headers['authorization'];
		const token = Array.isArray(authHeader)
			? authHeader[0]
			: (authHeader ?? '');
		if (!token || !token.startsWith('Bearer ')) {
			throw new UnauthorizedException('Missing access token');
		}
		const accessToken = token.slice('Bearer '.length).trim();
		if (!accessToken) {
			throw new UnauthorizedException('Missing access token');
		}
		try {
			const payload = await this.jwt.verifyAsync<AccessTokenPayload>(
				accessToken,
				{
					issuer: this.jwtIssuer,
					audience: this.jwtAudience,
				},
			);
			if (!payload?.sub || typeof payload.sub !== 'string') {
				throw new UnauthorizedException('Invalid access token');
			}
			request.authUser = {
				userId: payload.sub,
				firebaseUid: `${payload.firebaseUid ?? ''}`,
				kycStatus: `${payload.kycStatus ?? ''}`,
			};
			return true;
		} catch {
			throw new UnauthorizedException('Invalid access token');
		}
	}
}
