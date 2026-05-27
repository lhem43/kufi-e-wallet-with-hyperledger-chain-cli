import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import rateLimit from 'express-rate-limit';
import Redis from 'ioredis';
import { RedisStore } from 'rate-limit-redis';
import { AppModule } from './app.module';

async function bootstrap() {
	const logger = new Logger('Bootstrap');
	const app = await NestFactory.create(AppModule);
	const windowMs = Number(process.env.RATE_LIMIT_WINDOW_MS ?? 60000);
	const maxRequests = Number(process.env.RATE_LIMIT_MAX ?? 100);
	const redisUrl = (process.env.RATE_LIMIT_REDIS_URL ?? '').trim();
	const limiterConfig = {
		windowMs,
		max: maxRequests,
		standardHeaders: true,
		legacyHeaders: false,
	};
	let limiter = rateLimit(limiterConfig);

	if (redisUrl) {
		try {
			const redis = new Redis(redisUrl, {
				lazyConnect: true,
				maxRetriesPerRequest: 1,
			});
			redis.on('error', (error: unknown) => {
				const msg = error instanceof Error ? error.message : String(error);
				logger.error(`Rate-limit Redis error: ${msg}`);
			});
			await redis.connect();
			await redis.ping();
			limiter = rateLimit({
				...limiterConfig,
				store: new RedisStore({
					sendCommand: (...args: string[]) =>
						redis.call(args[0], ...args.slice(1)) as any,
					prefix: process.env.RATE_LIMIT_REDIS_PREFIX ?? 'rl:',
				}),
			});
			logger.log(`Distributed rate-limit enabled with Redis: ${redisUrl}`);
		} catch (error: unknown) {
			const msg = error instanceof Error ? error.message : String(error);
			logger.warn(
				`Rate-limit Redis is unavailable, fallback to in-memory limiter: ${msg}`,
			);
		}
	}

	app.use(limiter);
	app.useGlobalPipes(
		new ValidationPipe({
			whitelist: true,
			forbidNonWhitelisted: true,
			transform: true,
		}),
	);
	await app.listen(process.env.PORT ?? 3000);
}
bootstrap().catch((error) => {
	console.error(error);
	process.exit(1);
});
