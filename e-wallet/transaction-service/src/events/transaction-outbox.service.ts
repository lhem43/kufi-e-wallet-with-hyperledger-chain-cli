import {
	Injectable,
	Logger,
	OnModuleDestroy,
	OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, EntityManager, Repository } from 'typeorm';
import { TransactionEventProducerService } from './transaction-event-producer.service';
import {
	TransactionOutboxEvent,
	TransactionOutboxStatus,
} from './entities/transaction-outbox-event.entity';

interface QueueEventInput {
	aggregateType: string;
	aggregateId: string;
	eventType: string;
	payload: Record<string, any>;
}

@Injectable()
export class TransactionOutboxService implements OnModuleInit, OnModuleDestroy {
	private readonly logger = new Logger(TransactionOutboxService.name);
	private readonly pollIntervalMs: number;
	private readonly batchSize: number;
	private readonly workers: number;
	private readonly leaseMs: number;
	private readonly maxRetries: number;
	private readonly initialBackoffMs: number;
	private readonly maxBackoffMs: number;
	private timer: NodeJS.Timeout | null = null;
	private running = false;

	constructor(
		private readonly cfg: ConfigService,
		private readonly dataSource: DataSource,
		private readonly producer: TransactionEventProducerService,
		@InjectRepository(TransactionOutboxEvent)
		private readonly outboxRepo: Repository<TransactionOutboxEvent>,
	) {
		this.pollIntervalMs = this.toInt(
			this.cfg.get<string>('OUTBOX_POLL_INTERVAL_MS'),
			500,
		);
		this.batchSize = this.toInt(this.cfg.get<string>('OUTBOX_BATCH_SIZE'), 200);
		this.workers = this.toInt(this.cfg.get<string>('OUTBOX_WORKERS'), 10);
		this.leaseMs = this.toInt(this.cfg.get<string>('OUTBOX_LEASE_MS'), 30000);
		this.maxRetries = Math.max(
			0,
			this.toInt(this.cfg.get<string>('OUTBOX_MAX_RETRIES'), 15),
		);
		this.initialBackoffMs = this.toInt(
			this.cfg.get<string>('OUTBOX_INITIAL_BACKOFF_MS'),
			500,
		);
		this.maxBackoffMs = this.toInt(
			this.cfg.get<string>('OUTBOX_MAX_BACKOFF_MS'),
			60000,
		);
	}

	onModuleInit() {
		this.timer = setInterval(() => {
			void this.dispatchTick();
		}, this.pollIntervalMs);
		void this.dispatchTick();
		this.logger.log(
			`Outbox dispatcher started (poll=${this.pollIntervalMs}ms, batch=${this.batchSize}, workers=${this.workers})`,
		);
	}

	onModuleDestroy() {
		if (this.timer) {
			clearInterval(this.timer);
			this.timer = null;
		}
	}

	async enqueue(event: QueueEventInput, manager?: EntityManager) {
		const repo = manager?.getRepository(TransactionOutboxEvent) ?? this.outboxRepo;
		const entity = repo.create({
			aggregateType: event.aggregateType,
			aggregateId: event.aggregateId,
			eventType: event.eventType,
			payload: event.payload,
			status: TransactionOutboxStatus.PENDING,
			attempts: 0,
			nextAttemptAt: new Date(),
		});
		await repo.save(entity);
	}

	private async dispatchTick() {
		if (this.running) return;
		this.running = true;
		try {
			const claimedIds = await this.claimDueEvents(this.batchSize);
			if (claimedIds.length === 0) return;

			const workerSize = Math.max(1, this.workers);
			for (let i = 0; i < claimedIds.length; i += workerSize) {
				const chunk = claimedIds.slice(i, i + workerSize);
				await Promise.all(
					chunk.map((id) =>
						this.publishClaimedEvent(id).catch((error: unknown) => {
							const msg = error instanceof Error ? error.message : String(error);
							this.logger.error(`Outbox publish failed id=${id}: ${msg}`);
						}),
					),
				);
			}
		} catch (error: unknown) {
			const msg = error instanceof Error ? error.message : String(error);
			this.logger.error(`Outbox dispatch tick failed: ${msg}`);
		} finally {
			this.running = false;
		}
	}

	private async claimDueEvents(limit: number): Promise<string[]> {
		const take = Math.max(1, limit);
		const now = new Date();
		const leaseUntil = new Date(now.getTime() + this.leaseMs);
		const qr = this.dataSource.createQueryRunner();
		await qr.connect();
		await qr.startTransaction();
		try {
			const due = await qr.manager
				.getRepository(TransactionOutboxEvent)
				.createQueryBuilder('evt')
				.setLock('pessimistic_write')
				.setOnLocked('skip_locked')
				.where('evt.status = :pendingStatus', {
					pendingStatus: TransactionOutboxStatus.PENDING,
				})
				.andWhere('evt.nextAttemptAt <= :now', { now })
				.andWhere('(evt.leasedUntil IS NULL OR evt.leasedUntil <= :now)', { now })
				.orderBy('evt.nextAttemptAt', 'ASC')
				.addOrderBy('evt.createdAt', 'ASC')
				.take(take)
				.getMany();

			if (due.length > 0) {
				for (const evt of due) {
					evt.leasedUntil = leaseUntil;
				}
				await qr.manager.save(TransactionOutboxEvent, due);
			}

			await qr.commitTransaction();
			return due.map((item) => item.id);
		} catch (error) {
			await qr.rollbackTransaction();
			throw error;
		} finally {
			await qr.release();
		}
	}

	private async publishClaimedEvent(id: string) {
		const evt = await this.outboxRepo.findOne({ where: { id } });
		if (!evt) return;
		if (evt.status !== TransactionOutboxStatus.PENDING) return;
		const now = Date.now();
		if (!evt.leasedUntil || evt.leasedUntil.getTime() < now) return;

		try {
			await this.producer.publish(evt.payload);
			evt.status = TransactionOutboxStatus.PUBLISHED;
			evt.publishedAt = new Date();
			evt.leasedUntil = null;
			evt.lastError = null;
			await this.outboxRepo.save(evt);
		} catch (error: unknown) {
			const msg = error instanceof Error ? error.message : String(error);
			evt.attempts = Math.max(0, evt.attempts ?? 0) + 1;
			evt.leasedUntil = null;
			evt.lastError = msg.slice(0, 1024);
			if (evt.attempts > this.maxRetries) {
				evt.status = TransactionOutboxStatus.FAILED;
			} else {
				evt.nextAttemptAt = this.computeNextAttemptAt(evt.attempts);
			}
			await this.outboxRepo.save(evt);
		}
	}

	private computeNextAttemptAt(attempts: number): Date {
		const exponent = Math.max(0, attempts - 1);
		const rawDelay = this.initialBackoffMs * Math.pow(2, exponent);
		const capped = Math.min(rawDelay, this.maxBackoffMs);
		const jitter = Math.floor(capped * Math.random() * 0.2);
		return new Date(Date.now() + capped + jitter);
	}

	private toInt(raw: string | undefined, fallback: number): number {
		const n = Number(raw);
		return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
	}
}
