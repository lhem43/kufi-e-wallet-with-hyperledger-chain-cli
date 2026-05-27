import { NestFactory } from '@nestjs/core';
import { Transport } from '@nestjs/microservices';
import { join } from 'path';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.connectMicroservice({
    transport: Transport.GRPC,
    options: {
      url: process.env.GRPC_URL ?? '0.0.0.0:50053',
      package: 'outsidepayment',
      protoPath: join(__dirname, '../../proto/outside-payment.proto'),
    },
  });
  await app.startAllMicroservices();
  await app.listen(process.env.PORT ?? 3003);
}
bootstrap().catch((error) => {
  console.error(error);
  process.exit(1);
});
