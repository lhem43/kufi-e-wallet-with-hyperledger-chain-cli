import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ClientsModule, Transport } from '@nestjs/microservices';
import { join } from 'path';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { Wallet } from './wallets/entities/wallet.entity';
import { TransactionEntity } from './transactions/entities/transaction.entity';
import { LedgerEntry } from './transactions/entities/ledger-entry.entity';
import { FundingSource } from './transactions/entities/funding-source.entity';
import { TransactionsService } from './transactions/transactions.service';
import { TransactionsGrpcController } from './transactions/transactions.grpc.controller';
import { TransactionEventProducerService } from './events/transaction-event-producer.service';
import { TransactionOutboxService } from './events/transaction-outbox.service';
import { TransactionOutboxEvent } from './events/entities/transaction-outbox-event.entity';
import { AtoRiskService } from './transactions/ato-risk.service';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (cfg: ConfigService) => ({
        type: 'postgres',
        host: cfg.get('DB_HOST') ?? 'localhost',
        port: Number(cfg.get('DB_PORT') ?? 5432),
        username: cfg.getOrThrow('DB_USER'),
        password: cfg.getOrThrow('DB_PASS'),
        database: cfg.getOrThrow('DB_NAME'),
        autoLoadEntities: true,
        synchronize: cfg.get('DB_SYNC') === 'true',
        extra: {
          max: Number(cfg.get('DB_POOL_MAX') ?? 80),
          min: Number(cfg.get('DB_POOL_MIN') ?? 10),
          idleTimeoutMillis: Number(cfg.get('DB_POOL_IDLE_MS') ?? 30000),
          connectionTimeoutMillis: Number(
            cfg.get('DB_POOL_CONN_TIMEOUT_MS') ?? 5000,
          ),
        },
      } as any),
    }),
    TypeOrmModule.forFeature([
      Wallet,
      TransactionEntity,
      LedgerEntry,
      FundingSource,
      TransactionOutboxEvent,
    ]),
    ClientsModule.register([
      {
        name: 'OUTSIDE_PAYMENT_PACKAGE',
        transport: Transport.GRPC,
        options: {
          url: process.env.OUTSIDE_PAYMENT_GRPC_URL ?? 'localhost:50053',
          package: 'outsidepayment',
          protoPath: join(__dirname, '../../proto/outside-payment.proto'),
        },
      },
      {
        name: 'CHAIN_PACKAGE',
        transport: Transport.GRPC,
        options: {
          url: process.env.CHAIN_GRPC_URL ?? 'localhost:50054',
          package: 'chain',
          protoPath: join(__dirname, '../../proto/chain.proto'),
        },
      },
    ]),
  ],
  controllers: [AppController, TransactionsGrpcController],
  providers: [
    AppService,
    TransactionsService,
    TransactionEventProducerService,
    TransactionOutboxService,
    AtoRiskService,
  ],
})
export class AppModule {}
