import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { MicroserviceOptions, Transport } from '@nestjs/microservices';
import { join } from 'path';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }),
  );

  app.connectMicroservice<MicroserviceOptions>({
    transport: Transport.GRPC,
    options: {
      url: process.env.GRPC_URL ?? '0.0.0.0:50052',
      package: 'transaction',
      protoPath: join(__dirname, '../../proto/transaction.proto'),
    },
  });

  await app.startAllMicroservices();
  await app.listen(process.env.PORT ?? 3002);
}

bootstrap().catch((error) => {
  console.error(error);
  process.exit(1);
});
