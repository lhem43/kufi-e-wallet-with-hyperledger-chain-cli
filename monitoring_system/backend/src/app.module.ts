import { Module } from '@nestjs/common';
import { APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from './auth/auth.module';
import { AdminModule } from './admin/admin.module';
import { AuditModule } from './audit/audit.module';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { PermissionsGuard } from './common/guards/permissions.guard';
import { AuditLogInterceptor } from './common/interceptors/audit-log.interceptor';
import { HealthController } from './health.controller';
import { LogsModule } from './logs/logs.module';
import { MonitoringModule } from './monitoring/monitoring.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env'],
    }),
    ScheduleModule.forRoot(),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => {
        const dbHost = configService.get<string>('DB_HOST')?.trim();
        const dbPort = configService.get<string>('DB_PORT')?.trim();
        const dbUser = configService.get<string>('DB_USER')?.trim();
        const dbPass = configService.get<string>('DB_PASS')?.trim();
        const dbName = configService.get<string>('DB_NAME')?.trim();

        if (!dbHost || !dbPort || !dbUser || !dbPass || !dbName) {
          throw new Error(
            'DB_HOST, DB_PORT, DB_USER, DB_PASS, DB_NAME are required.',
          );
        }

        return {
          type: 'postgres',
          host: dbHost,
          port: Number(dbPort),
          username: dbUser,
          password: dbPass,
          database: dbName,
          autoLoadEntities: true,
          synchronize: configService.get<string>('DB_SYNC', 'true') === 'true',
        };
      },
    }),
    AuthModule,
    AdminModule,
    AuditModule,
    MonitoringModule,
    LogsModule,
  ],
  controllers: [HealthController],
  providers: [
    {
      provide: APP_GUARD,
      useClass: JwtAuthGuard,
    },
    {
      provide: APP_GUARD,
      useClass: PermissionsGuard,
    },
    {
      provide: APP_INTERCEPTOR,
      useClass: AuditLogInterceptor,
    },
  ],
})
export class AppModule {}
