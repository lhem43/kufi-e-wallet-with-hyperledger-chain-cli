import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

interface RiskProfile {
	avgAmount: number;
	seenDevices: Set<string>;
}

@Injectable()
export class RiskEngineService {
	private profiles = new Map<string, RiskProfile>();
	private hardAmountThreshold: number;
	private anomalyMultiple: number;
	private minHistoryAmount: number;

	constructor(private readonly cfg: ConfigService) {
		const hardThreshold = this.cfg.get('RISK_HARD_AMOUNT_THRESHOLD');
		if (hardThreshold == null) {
			console.warn('[RiskEngine] RISK_HARD_AMOUNT_THRESHOLD not configured — defaulting to 50,000,000 VND');
		}
		this.hardAmountThreshold = Number(hardThreshold ?? 50_000_000);
		this.anomalyMultiple = Number(
			this.cfg.get('RISK_ANOMALY_MULTIPLE') ?? 3,
		);
		const minHistory = this.cfg.get('RISK_MIN_HISTORY_AMOUNT');
		if (minHistory == null) {
			console.warn('[RiskEngine] RISK_MIN_HISTORY_AMOUNT not configured — defaulting to 5,000,000 VND');
		}
		this.minHistoryAmount = Number(minHistory ?? 5_000_000);
	}

	evaluate(
		userId: string,
		deviceId: string,
		amount: number,
	): { requiresStepUp: boolean; reasons: string[] } {
		const profile = this.profiles.get(userId);
		const reasons: string[] = [];
		if (amount >= this.hardAmountThreshold) {
			reasons.push('amount_over_hard_threshold');
		}
		if (profile) {
			if (deviceId && !profile.seenDevices.has(deviceId)) {
				reasons.push('new_device_detected');
			}
			if (
				profile.avgAmount >= this.minHistoryAmount &&
				amount >= profile.avgAmount * this.anomalyMultiple
			) {
				reasons.push('amount_anomaly_detected');
			}
		}
		return { requiresStepUp: reasons.length > 0, reasons };
	}

	rememberTransaction(userId: string, deviceId: string, amount: number) {
		const existing = this.profiles.get(userId) ?? {
			avgAmount: amount,
			seenDevices: new Set<string>(),
		};
		if (deviceId) {
			existing.seenDevices.add(deviceId);
			if (existing.seenDevices.size > 10) {
				const keep = Array.from(existing.seenDevices).slice(-10);
				existing.seenDevices = new Set(keep);
			}
		}
		existing.avgAmount = existing.avgAmount * 0.7 + amount * 0.3;
		this.profiles.set(userId, existing);
	}
}
