import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as fs from 'fs';
import * as path from 'path';
import * as admin from 'firebase-admin';

@Injectable()
export class FirebaseService implements OnModuleInit {
	private app: admin.app.App;
	private readonly logger = new Logger(FirebaseService.name);
	private _restMode = false;
	private readonly restUserCache = new Map<string, admin.auth.UserRecord>();

	constructor(private readonly config: ConfigService) {}

	get isRestMode(): boolean {
		return this._restMode;
	}

	onModuleInit() {
		const devMode = this.config.get<string>('AUTH_DEV_MODE') === 'true';
		if (devMode) {
			this.logger.warn('AUTH_DEV_MODE=true — skipping Firebase initialization');
			this._restMode = true;
			this.app = admin.initializeApp({ projectId: 'dev-mode' });
			return;
		}
		if (!admin.apps.length) {
			let projectId = this.config.get<string>('FIREBASE_PROJECT_ID');
			let clientEmail = this.config.get<string>('FIREBASE_CLIENT_EMAIL');
			let privateKey = this.config
				.get<string>('FIREBASE_PRIVATE_KEY')
				?.replace(/\\n/g, '\n');
			const apiKey = this.config.get<string>('FIREBASE_API_KEY')?.trim();
			const serviceAccountPathRaw = this.config
				.get<string>('FIREBASE_SERVICE_ACCOUNT_PATH')
				?.trim();

			if (serviceAccountPathRaw) {
				const resolvedPath = path.isAbsolute(serviceAccountPathRaw)
					? serviceAccountPathRaw
					: path.resolve(process.cwd(), serviceAccountPathRaw);
				if (fs.existsSync(resolvedPath)) {
					try {
						const raw = fs.readFileSync(resolvedPath, 'utf8');
						const json = JSON.parse(raw) as {
							project_id?: string;
							client_email?: string;
							private_key?: string;
						};
						projectId = projectId || json.project_id;
						clientEmail = clientEmail || json.client_email;
						privateKey = privateKey || json.private_key;
						this.logger.log(
							`Loaded Firebase service account from ${resolvedPath}`,
						);
					} catch (error: any) {
						this.logger.error(
							`Failed to read FIREBASE_SERVICE_ACCOUNT_PATH (${resolvedPath}): ${error?.message ?? error}`,
						);
					}
				} else {
					this.logger.warn(
						`FIREBASE_SERVICE_ACCOUNT_PATH not found: ${resolvedPath}`,
					);
				}
			}

			if (projectId && clientEmail && privateKey) {
				this.app = admin.initializeApp({
					credential: admin.credential.cert({
						projectId,
						clientEmail,
						privateKey,
					}),
				});
				return;
			}

			if (projectId && apiKey) {
				this._restMode = true;
				this.logger.warn(
					'Firebase Admin credentials missing; running in REST VERIFICATION mode with FIREBASE_API_KEY',
				);
				this.app = admin.initializeApp({
					projectId,
				});
				return;
			}

			throw new Error(
				'Missing Firebase credentials: provide FIREBASE_CLIENT_EMAIL + FIREBASE_PRIVATE_KEY, or FIREBASE_PROJECT_ID + FIREBASE_API_KEY for REST mode',
			);
		} else {
			this.app = admin.app();
		}
	}

	get auth(): admin.auth.Auth {
		return this.app.auth();
	}

	async verifyIdToken(idToken: string, checkRevoked = false): Promise<admin.auth.DecodedIdToken> {
		if (this._restMode) {
			return this.verifyIdTokenViaRestApi(idToken);
		}
		return this.auth.verifyIdToken(idToken, checkRevoked);
	}

	async getUser(uid: string): Promise<admin.auth.UserRecord> {
		if (this._restMode) {
			const cached = this.restUserCache.get(uid);
			if (cached) {
				return cached;
			}
			return {
				uid,
				email: `${this.sanitizeForEmail(uid)}@firebase.local`,
				displayName: null,
				emailVerified: true,
				disabled: false,
				metadata: { creationTime: '', lastSignInTime: '' },
				providerData: [],
				toJSON: () => ({}),
			} as unknown as admin.auth.UserRecord;
		}
		return this.auth.getUser(uid);
	}

	private async verifyIdTokenViaRestApi(
		idToken: string,
	): Promise<admin.auth.DecodedIdToken> {
		const apiKey = this.config.get<string>('FIREBASE_API_KEY')?.trim();
		const projectId =
			this.config.get<string>('FIREBASE_PROJECT_ID')?.trim() || 'firebase-project';
		if (!apiKey) {
			throw new Error('FIREBASE_API_KEY is required for REST verification mode');
		}

		const response = await fetch(
			`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(apiKey)}`,
			{
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ idToken }),
			},
		);

		if (!response.ok) {
			this.logger.warn(
				`REST verifyIdToken failed with status ${response.status}`,
			);
			throw new Error('Invalid or expired Firebase token');
		}

		const body = (await response.json()) as {
			users?: Array<{
				localId?: string;
				email?: string;
				displayName?: string;
				phoneNumber?: string;
				disabled?: boolean;
				emailVerified?: boolean;
				createdAt?: string;
				lastLoginAt?: string;
			}>;
		};
		const user = Array.isArray(body.users) ? body.users[0] : undefined;
		const uid = `${user?.localId ?? ''}`.trim();
		if (!uid) {
			throw new Error('Invalid Firebase user profile');
		}

		const record = {
			uid,
			email: user?.email ?? undefined,
			displayName: user?.displayName ?? undefined,
			phoneNumber: user?.phoneNumber ?? undefined,
			emailVerified: user?.emailVerified === true,
			disabled: user?.disabled === true,
			metadata: {
				creationTime: user?.createdAt ?? '',
				lastSignInTime: user?.lastLoginAt ?? '',
			},
			providerData: [],
			toJSON: () => ({}),
		} as unknown as admin.auth.UserRecord;
		this.restUserCache.set(uid, record);

		const claims = this.decodeJwtClaims(idToken);
		const now = Math.floor(Date.now() / 1000);
		return {
			uid,
			email: user?.email ?? claims.email,
			aud: claims.aud ?? projectId,
			auth_time:
				typeof claims.auth_time === 'number' ? claims.auth_time : now,
			exp: typeof claims.exp === 'number' ? claims.exp : now + 3600,
			iat: typeof claims.iat === 'number' ? claims.iat : now,
			iss:
				claims.iss ??
				`https://securetoken.google.com/${projectId}`,
			sub: claims.sub ?? uid,
			firebase:
				claims.firebase ?? {
					identities: {},
					sign_in_provider: 'password',
				},
		} as admin.auth.DecodedIdToken;
	}

	private decodeJwtClaims(idToken: string): Record<string, any> {
		try {
			const parts = idToken.split('.');
			if (parts.length < 2) {
				return {};
			}
			const payload = Buffer.from(parts[1], 'base64url').toString('utf8');
			const parsed = JSON.parse(payload);
			if (!parsed || typeof parsed !== 'object') {
				return {};
			}
			return parsed as Record<string, any>;
		} catch {
			return {};
		}
	}

	private sanitizeForEmail(value: string): string {
		const cleaned = value
			.toLowerCase()
			.replace(/[^a-z0-9._-]/g, '-')
			.replace(/-+/g, '-')
			.replace(/^-+|-+$/g, '');
		return cleaned || 'user';
	}
}
