import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AppController } from './app.controller';
import { NotificationEntity } from './notifications/entities/notification.entity';
import { NotificationPreferenceEntity } from './notifications/entities/notification-preference.entity';
import { NotificationsService } from './notifications/notifications.service';
import { NotificationsGrpcController } from './notifications/notifications.grpc.controller';

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
          max: Number(cfg.get('DB_POOL_MAX') ?? 40),
          min: Number(cfg.get('DB_POOL_MIN') ?? 5),
          idleTimeoutMillis: Number(cfg.get('DB_POOL_IDLE_MS') ?? 30000),
          connectionTimeoutMillis: Number(
            cfg.get('DB_POOL_CONN_TIMEOUT_MS') ?? 5000,
          ),
        },
      }),
    }),
    TypeOrmModule.forFeature([NotificationEntity, NotificationPreferenceEntity]),
  ],
  controllers: [AppController, NotificationsGrpcController],
  providers: [NotificationsService],
})
export class AppModule {}
