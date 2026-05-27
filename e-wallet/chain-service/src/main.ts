import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { Transport } from '@nestjs/microservices';
import { join } from 'path';

async function bootstrap() {
	const app = await NestFactory.create(AppModule);
	app.connectMicroservice({
		transport: Transport.GRPC,
		options: {
			url: process.env.GRPC_URL ?? '0.0.0.0:50054',
			package: 'chain',
			protoPath: join(__dirname, '../../proto/chain.proto'),
		},
	});
	await app.startAllMicroservices();
	await app.listen(process.env.PORT ?? 3004);
}

bootstrap().catch((error) => {
	console.error(error);
	process.exit(1);
});
