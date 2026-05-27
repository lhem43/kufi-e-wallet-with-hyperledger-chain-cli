import {
	Body,
	Controller,
	Headers,
	Post,
	UnauthorizedException,
} from '@nestjs/common';
import { AuthService } from './auth.service';
import { RefreshTokenDto } from './dto/refresh-token.dto';

@Controller('auth')
export class AuthController {
	constructor(private readonly authService: AuthService) {}

	@Post('firebase/verify')
	async verifyFirebase(
		@Headers('authorization') auth?: string,
		@Headers('user-agent') userAgent?: string,
		@Headers('x-forwarded-for') forwardedFor?: string,
	) {
		if (!auth?.startsWith('Bearer ')) {
			throw new UnauthorizedException('Missing bearer token');
		}
		const idToken = auth.slice('Bearer '.length).trim();
		const ipAddress = forwardedFor?.split(',')[0]?.trim();
		return this.authService.verifyFirebaseIdToken(idToken, {
			userAgent,
			ipAddress,
		});
	}

	@Post('refresh')
	async refresh(
		@Body() dto: RefreshTokenDto,
		@Headers('user-agent') userAgent?: string,
		@Headers('x-forwarded-for') forwardedFor?: string,
	) {
		const ipAddress = forwardedFor?.split(',')[0]?.trim();
		return this.authService.refreshAccessToken(dto.refreshToken, {
			userAgent,
			ipAddress,
		});
	}

	@Post('logout')
	async logout(@Body() dto: RefreshTokenDto) {
		await this.authService.revokeRefreshToken(dto.refreshToken);
		return { success: true };
	}

	@Post('logout-all')
	async logoutAll(@Headers('authorization') auth?: string) {
		if (!auth?.startsWith('Bearer ')) {
			throw new UnauthorizedException('Missing bearer token');
		}
		const accessToken = auth.slice('Bearer '.length).trim();
		await this.authService.revokeAllSessionsByAccessToken(accessToken);
		return { success: true };
	}
}
