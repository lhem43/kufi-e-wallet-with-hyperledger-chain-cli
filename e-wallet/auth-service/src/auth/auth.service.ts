import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { createHash, randomBytes, randomUUID } from 'crypto';
import { FirebaseService } from '../firebase/firebase.service';
import { UsersService } from '../users/users.service';
import * as admin from 'firebase-admin';
import { AuthSession } from './entities/auth-session.entity';
import { AccountStatus, User } from '../users/entities/user.entity/user.entity';
import { IsNull, Repository } from 'typeorm';

export type AuthUser = {
	id: string;
	firebaseUid: string;
	email?: string | null;
	phone?: string | null;
	displayName?: string | null;
	kycStatus: string;
	hasPin: boolean;
};

export type AuthResult = {
	accessToken: string;
	expiresIn: number;
	refreshToken: string;
	refreshExpiresIn: number;
	user: AuthUser;
};

export type VerifyTokenResult = {
	userId: string;
	firebaseUid: string;
	kycStatus: string;
};

type SessionContext = {
	userAgent?: string;
	ipAddress?: string;
};

type UserProfileHints = {
	email?: string;
	phone?: string;
	displayName?: string;
};

type AccessTokenPayload = {
	sub: string;
	firebaseUid: string;
	kycStatus: string;
	jti: string;
	iss: string;
	aud: string | string[];
	exp: number;
	iat: number;
};

@Injectable()
export class AuthService {
	private readonly accessTtlSeconds: number;
	private readonly refreshTtlSeconds: number;
	private readonly jwtIssuer: string;
	private readonly jwtAudience: string;

	constructor(
		private readonly firebase: FirebaseService,
		private readonly users: UsersService,
		private readonly jwt: JwtService,
		private readonly config: ConfigService,
		@InjectRepository(AuthSession)
		private readonly sessions: Repository<AuthSession>,
	) {
		this.accessTtlSeconds = Number(
			this.config.get<string>('JWT_ACCESS_TTL_SECONDS') ?? 300,
		);
		this.refreshTtlSeconds = Number(
			this.config.get<string>('JWT_REFRESH_TTL_SECONDS') ?? 604800,
		);
		this.jwtIssuer =
			this.config.get<string>('JWT_ISSUER') ?? 'auth-service';
		this.jwtAudience =
			this.config.get<string>('JWT_AUDIENCE') ?? 'e-wallet';
	}

	async verifyFirebaseIdToken(
		idToken: string,
		context?: SessionContext,
		hints?: UserProfileHints,
	): Promise<AuthResult> {
		let decoded: admin.auth.DecodedIdToken;
		try {
			decoded = await this.firebase.verifyIdToken(idToken, true);
		} catch {
			throw new UnauthorizedException(
				'Invalid or expired Firebase token',
			);
		}

		const userRecord = await this.firebase.getUser(decoded.uid);
		if (userRecord.disabled) {
			throw new UnauthorizedException('User is disabled');
		}

		const user = await this.users.upsertFromFirebase({
			firebaseUid: userRecord.uid,
			email: userRecord.email ?? hints?.email ?? null,
			phone: userRecord.phoneNumber ?? hints?.phone ?? null,
			displayName: userRecord.displayName ?? hints?.displayName ?? null,
		});

		if (user.accountStatus !== AccountStatus.ACTIVE) {
			throw new UnauthorizedException('User is not active');
		}

		return this.issueTokens(user, context);
	}

	async resolveLoginIdentifier(
		identifierRaw: string,
	): Promise<{ found: boolean; email: string }> {
		const identifier = identifierRaw.trim();
		if (!identifier) {
			return { found: false, email: '' };
		}

		if (identifier.includes('@')) {
			const user = await this.users.findByEmail(identifier);
			if (!user?.email) {
				return { found: false, email: '' };
			}
			return { found: true, email: user.email };
		}

		const user = await this.users.findByPhone(identifier);
		if (!user?.email) {
			return { found: false, email: '' };
		}
		return { found: true, email: user.email };
	}

	async verifyInternalToken(accessToken: string): Promise<VerifyTokenResult> {
		let payload: AccessTokenPayload;
		try {
			payload = await this.jwt.verifyAsync<AccessTokenPayload>(
				accessToken,
				{
					issuer: this.jwtIssuer,
					audience: this.jwtAudience,
				},
			);
		} catch {
			throw new UnauthorizedException('Invalid access token');
		}

		if (!payload?.sub || typeof payload.sub !== 'string') {
			throw new UnauthorizedException('Invalid access token');
		}

		const user = await this.users.findById(payload.sub);
		if (!user) {
			throw new UnauthorizedException('User not found');
		}

		if (user.accountStatus !== AccountStatus.ACTIVE) {
			throw new UnauthorizedException('User is not active');
		}

		return {
			userId: user.id,
			firebaseUid: user.firebaseUid,
			kycStatus: user.kycStatus,
		};
	}

	async refreshAccessToken(
		refreshToken: string,
		context?: SessionContext,
	): Promise<AuthResult> {
		const refreshTokenHash = this.hashToken(refreshToken);
		const session = await this.sessions.findOne({
			where: { refreshTokenHash },
		});

		if (
			!session ||
			session.revokedAt ||
			session.refreshTokenExpiresAt <= new Date()
		) {
			throw new UnauthorizedException('Invalid or expired refresh token');
		}

		session.revokedAt = new Date();
		session.lastUsedAt = new Date();
		await this.sessions.save(session);

		const user = await this.users.findById(session.userId);
		if (!user) {
			throw new UnauthorizedException('User not found');
		}

		if (user.accountStatus !== AccountStatus.ACTIVE) {
			throw new UnauthorizedException('User is not active');
		}

		try {
			const firebaseUser = await this.firebase.getUser(user.firebaseUid);
			if (firebaseUser.disabled) {
				throw new UnauthorizedException('User is disabled');
			}
		} catch {
			throw new UnauthorizedException('User is disabled or invalid');
		}

		return this.issueTokens(user, context);
	}

	private async issueTokens(
		user: User,
		context?: SessionContext,
	): Promise<AuthResult> {
		const accessToken = await this.jwt.signAsync(
			{
				sub: user.id,
				firebaseUid: user.firebaseUid,
				kycStatus: user.kycStatus,
				jti: randomUUID(),
			},
			{
				expiresIn: this.accessTtlSeconds,
				issuer: this.jwtIssuer,
				audience: this.jwtAudience,
			},
		);

		const refreshToken = randomBytes(64).toString('hex');
		const refreshTokenHash = this.hashToken(refreshToken);
		const refreshTokenExpiresAt = new Date(
			Date.now() + this.refreshTtlSeconds * 1000,
		);

		const session = this.sessions.create({
			userId: user.id,
			refreshTokenHash,
			refreshTokenExpiresAt,
			userAgent: context?.userAgent ?? null,
			ipAddress: context?.ipAddress ?? null,
		});
		await this.sessions.save(session);

		return {
			accessToken,
			expiresIn: this.accessTtlSeconds,
			refreshToken,
			refreshExpiresIn: this.refreshTtlSeconds,
			user: {
				id: user.id,
				firebaseUid: user.firebaseUid,
				email: user.email ?? null,
				phone: user.phone ?? null,
				displayName: user.displayName ?? null,
				kycStatus: user.kycStatus,
				hasPin: this.users.hasPin(user),
			},
		};
	}

	private hashToken(token: string): string {
		return createHash('sha256').update(token).digest('hex');
	}

	async devLogin(
		firebaseUid: string,
		context?: SessionContext,
		hints?: UserProfileHints,
	): Promise<AuthResult> {
		const devMode = this.config.get<string>('AUTH_DEV_MODE') === 'true';
		if (!devMode) {
			throw new UnauthorizedException('Dev login is disabled');
		}

		const email = hints?.email ?? `${firebaseUid}@dev.local`;
		const phone = hints?.phone ?? null;
		const displayName = hints?.displayName ?? firebaseUid;

		let user: User;
		try {
			user = await this.users.upsertFromFirebase({
				firebaseUid,
				email,
				phone,
				displayName,
			});
		} catch (error) {
			// In dev mode, allow repeated logins with an existing phone/email instead
			// of failing hard on unique constraints.
			if (!this.isUniqueConstraintError(error)) {
				throw error;
			}
			const existingByPhone = phone
				? await this.users.findByPhone(phone)
				: null;
			if (existingByPhone) {
				user = existingByPhone;
			} else {
				const existingByEmail = email
					? await this.users.findByEmail(email)
					: null;
				if (!existingByEmail) {
					throw error;
				}
				user = existingByEmail;
			}
		}
		return this.issueTokens(user, context);
	}

	private isUniqueConstraintError(error: unknown): boolean {
		if (!error || typeof error !== 'object') {
			return false;
		}
		const maybePgCode = (error as { code?: string }).code;
		if (maybePgCode === '23505') {
			return true;
		}
		const driverCode = (error as { driverError?: { code?: string } })
			.driverError?.code;
		if (driverCode === '23505') {
			return true;
		}
		const message = (error as { message?: string }).message ?? '';
		return message.includes('duplicate key value violates unique constraint');
	}

	async revokeRefreshToken(refreshToken: string): Promise<void> {
		const refreshTokenHash = this.hashToken(refreshToken);
		const session = await this.sessions.findOne({
			where: { refreshTokenHash },
		});
		if (!session || session.revokedAt) {
			return;
		}
		session.revokedAt = new Date();
		session.lastUsedAt = new Date();
		await this.sessions.save(session);
	}

	async revokeAllSessionsByAccessToken(accessToken: string): Promise<void> {
		let payload: AccessTokenPayload;
		try {
			payload = await this.jwt.verifyAsync<AccessTokenPayload>(
				accessToken,
				{
					issuer: this.jwtIssuer,
					audience: this.jwtAudience,
				},
			);
		} catch {
			throw new UnauthorizedException('Invalid access token');
		}

		await this.sessions.update(
			{ userId: payload.sub, revokedAt: IsNull() },
			{ revokedAt: new Date(), lastUsedAt: new Date() },
		);
	}
}
