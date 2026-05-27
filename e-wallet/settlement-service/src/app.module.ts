import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ClientsModule, Transport } from '@nestjs/microservices';
import { ScheduleModule } from '@nestjs/schedule';
import { join } from 'path';
import { AppController } from './app.controller';
import { SettlementService } from './settlement/settlement.service';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ScheduleModule.forRoot(),
    ClientsModule.register([
      {
        name: 'TRANSACTION_PACKAGE',
        transport: Transport.GRPC,
        options: {
          url: process.env.TRANSACTION_GRPC_URL ?? 'localhost:50052',
          package: 'transaction',
          protoPath: join(__dirname, '../../proto/transaction.proto'),
        },
      },
      {
        name: 'OUTSIDE_PAYMENT_PACKAGE',
        transport: Transport.GRPC,
        options: {
          url: process.env.OUTSIDE_PAYMENT_GRPC_URL ?? 'localhost:50053',
          package: 'outsidepayment',
          protoPath: join(__dirname, '../../proto/outside-payment.proto'),
        },
      },
    ]),
  ],
  controllers: [AppController],
  providers: [SettlementService],
})
export class AppModule {}
