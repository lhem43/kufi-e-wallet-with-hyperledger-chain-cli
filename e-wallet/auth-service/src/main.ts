import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { ValidationPipe } from '@nestjs/common';
import { MicroserviceOptions, Transport } from '@nestjs/microservices';
import { join } from 'path';

async function bootstrap() {
	const app = await NestFactory.create(AppModule);
	app.useGlobalPipes(
		new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }),
	);

	app.connectMicroservice<MicroserviceOptions>({
		transport: Transport.GRPC,
		options: {
			url: process.env.GRPC_URL ?? '0.0.0.0:50051',
			package: 'auth',
			protoPath: join(__dirname, '../../proto/auth.proto'),
		},
	});

	await app.startAllMicroservices();
	await app.listen(process.env.PORT ?? 3001);
}

bootstrap().catch((err) => {
	console.error(err);
	process.exit(1);
});
