import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { scrypt, randomBytes, timingSafeEqual } from 'crypto';
import { Repository } from 'typeorm';
import { AccountStatus, User } from './entities/user.entity/user.entity';

export type FirebaseUserPayload = {
	firebaseUid: string;
	email?: string | null;
	phone?: string | null;
	displayName?: string | null;
};

@Injectable()
export class UsersService {
	constructor(
		@InjectRepository(User)
		private readonly usersRepo: Repository<User>,
	) {}

	async findById(id: string): Promise<User | null> {
		return this.usersRepo.findOne({ where: { id } });
	}

	async findByFirebaseUid(firebaseUid: string): Promise<User | null> {
		return this.usersRepo.findOne({ where: { firebaseUid } });
	}

	async findByEmail(email: string): Promise<User | null> {
		const normalized = email.trim().toLowerCase();
		if (!normalized) {
			return null;
		}
		const user = await this.usersRepo.findOne({ where: { email: normalized } });
		if (!user || this.isMockUser(user)) {
			return null;
		}
		return user;
	}

	async findByPhone(identifier: string): Promise<User | null> {
		const normalized = this.normalizePhone(identifier);
		if (!normalized) {
			return null;
		}

		// Legacy rows may keep +84, 84, or 0-prefixed formats.
		const variants = new Set<string>();
		variants.add(normalized);
		if (normalized.startsWith('0') && normalized.length >= 10) {
			variants.add(`84${normalized.substring(1)}`);
			variants.add(`+84${normalized.substring(1)}`);
		}
		if (normalized.startsWith('84') && normalized.length >= 10) {
			variants.add(`0${normalized.substring(2)}`);
			variants.add(`+${normalized}`);
		}
		if (normalized.startsWith('+84') && normalized.length >= 11) {
			variants.add(`0${normalized.substring(3)}`);
			variants.add(normalized.substring(1));
		}

		const candidates = await this.usersRepo
			.createQueryBuilder('user')
			.where('user.phone IN (:...phones)', {
				phones: Array.from(variants),
			})
			.orderBy(
				`CASE
          WHEN LOWER(COALESCE(user.email, '')) LIKE '%@mock.local'
            OR LOWER(COALESCE("user"."firebaseUid", '')) LIKE 'mock-%'
            OR LOWER(COALESCE("user"."firebaseUid", '')) LIKE 'smoke-user%'
            OR LOWER(COALESCE("user"."displayName", '')) = 'mock user'
          THEN 1
          ELSE 0
        END`,
				'ASC',
			)
			.addOrderBy('"user"."createdAt"', 'DESC')
			.getMany();

		for (const candidate of candidates) {
			if (!this.isMockUser(candidate)) {
				return candidate;
			}
		}
		return null;
	}

	async upsertFromFirebase(payload: FirebaseUserPayload): Promise<User> {
		const existing = await this.usersRepo.findOne({
			where: { firebaseUid: payload.firebaseUid },
		});

		if (existing) {
			existing.email =
				payload.email?.trim().toLowerCase() ?? existing.email ?? null;
			existing.phone = payload.phone?.trim() ?? existing.phone ?? null;
			existing.displayName =
				payload.displayName ?? existing.displayName ?? null;
			return this.usersRepo.save(existing);
		}

		const user = this.usersRepo.create({
			firebaseUid: payload.firebaseUid,
			email: payload.email?.trim().toLowerCase() ?? null,
			phone: payload.phone?.trim() ?? null,
			displayName: payload.displayName ?? null,
			kycStatus: 'pending',
		});

		return this.usersRepo.save(user);
	}

	async resolveRecipientByPhone(
		phoneRaw: string,
		requesterUserId?: string,
	): Promise<{
		found: boolean;
		recipient?: {
			userId: string;
			phone: string;
			displayName: string;
			accountStatus: string;
			kycStatus: string;
		};
	}> {
		const user = await this.findByPhone(phoneRaw);
		if (!user) {
			return { found: false };
		}
		if (this.isMockUser(user)) {
			return { found: false };
		}
		if (requesterUserId && user.id === requesterUserId) {
			return { found: false };
		}
		if (user.accountStatus !== AccountStatus.ACTIVE) {
			return { found: false };
		}
		return {
			found: true,
			recipient: {
				userId: user.id,
				phone: user.phone ?? '',
				displayName: user.displayName ?? user.email ?? 'Người dùng',
				accountStatus: user.accountStatus,
				kycStatus: user.kycStatus,
			},
		};
	}

	async getProfile(userId: string): Promise<{
		userId: string;
		email: string;
		phone: string;
		displayName: string;
		kycStatus: string;
		accountStatus: string;
	}> {
		const user = await this.findById(userId);
		if (!user) {
			throw new Error('User not found');
		}
		return this.toProfile(user);
	}

	async updateProfile(
		userId: string,
		payload: { displayName?: string; phone?: string },
	): Promise<{
		userId: string;
		email: string;
		phone: string;
		displayName: string;
		kycStatus: string;
		accountStatus: string;
	}> {
		const user = await this.findById(userId);
		if (!user) {
			throw new Error('User not found');
		}
		const nextDisplayName = payload.displayName?.trim();
		if (nextDisplayName) {
			user.displayName = nextDisplayName;
		}
		const nextPhone = payload.phone?.trim();
		if (nextPhone) {
			const normalized = this.normalizePhoneForStore(nextPhone);
			if (!normalized || !/^(0\d{9,10}|84\d{8,10}|\+84\d{8,10})$/.test(normalized)) {
				throw new Error('Invalid phone format');
			}
			const existing = await this.findByPhone(normalized);
			if (existing && existing.id !== user.id) {
				throw new Error('Phone number already in use');
			}
			user.phone = normalized;
		}
		const saved = await this.usersRepo.save(user);
		return this.toProfile(saved);
	}

	private toProfile(user: User): {
		userId: string;
		email: string;
		phone: string;
		displayName: string;
		kycStatus: string;
		accountStatus: string;
	} {
		return {
			userId: user.id,
			email: user.email ?? '',
			phone: user.phone ?? '',
			displayName: user.displayName ?? user.email ?? '',
			kycStatus: user.kycStatus ?? 'pending',
			accountStatus: user.accountStatus,
		};
	}

	private normalizePhoneForStore(raw: string): string {
		const trimmed = raw.trim();
		if (!trimmed) {
			return '';
		}
		const hasPlus = trimmed.startsWith('+');
		const digits = trimmed.replace(/\D/g, '');
		if (!digits) {
			return '';
		}
		if (hasPlus && digits.startsWith('84')) {
			return `+${digits}`;
		}
		if (digits.startsWith('84') && digits.length === 11) {
			return `0${digits.substring(2)}`;
		}
		return digits;
	}

	private normalizePhone(raw: string): string {
		const trimmed = raw.trim();
		if (!trimmed) {
			return '';
		}
		const hasPlus = trimmed.startsWith('+');
		const digits = trimmed.replace(/\D/g, '');
		if (!digits) {
			return '';
		}
		if (hasPlus && digits.startsWith('84')) {
			return `+${digits}`;
		}
		return digits;
	}

	private isMockUser(user: User): boolean {
		const email = `${user.email ?? ''}`.trim().toLowerCase();
		const firebaseUid = `${user.firebaseUid ?? ''}`.trim().toLowerCase();
		const displayName = `${user.displayName ?? ''}`.trim().toLowerCase();
		if (email.endsWith('@mock.local')) {
			return true;
		}
		if (firebaseUid.startsWith('mock-') || firebaseUid.startsWith('smoke-user')) {
			return true;
		}
		if (displayName == 'mock user' && email.includes('mock')) {
			return true;
		}
		return false;
	}

	async setPin(userId: string, pin: string): Promise<void> {
		const user = await this.findById(userId);
		if (!user) {
			throw new Error('User not found');
		}
		if (!/^\d{6}$/.test(pin)) {
			throw new Error('PIN must be exactly 6 digits');
		}
		const hashedPin = await this.hashPin(pin);
		user.hashedPin = hashedPin;
		await this.usersRepo.save(user);
	}

	async verifyPin(userId: string, pin: string): Promise<boolean> {
		const user = await this.findById(userId);
		if (!user || !user.hashedPin) {
			return false;
		}
		return this.verifyPinHash(pin, user.hashedPin);
	}

	hasPin(user: User): boolean {
		return !!user.hashedPin && user.hashedPin.trim().length > 0;
	}

	private hashPin(pin: string): Promise<string> {
		return new Promise((resolve, reject) => {
			const salt = randomBytes(16).toString('hex');
			scrypt(pin, salt, 64, (err, derivedKey) => {
				if (err) {
					reject(err);
					return;
				}
				resolve(`${salt}:${derivedKey.toString('hex')}`);
			});
		});
	}

	private verifyPinHash(pin: string, hash: string): Promise<boolean> {
		return new Promise((resolve, reject) => {
			const parts = hash.split(':');
			if (parts.length !== 2) {
				resolve(false);
				return;
			}
			const [salt, key] = parts;
			scrypt(pin, salt, 64, (err, derivedKey) => {
				if (err) {
					reject(err);
					return;
				}
				const keyBuffer = Buffer.from(key, 'hex');
				resolve(
					keyBuffer.length === derivedKey.length &&
						timingSafeEqual(keyBuffer, derivedKey),
				);
			});
		});
	}
}
