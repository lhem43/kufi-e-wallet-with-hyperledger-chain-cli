import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UsersModule } from './users/users.module';
import { FirebaseModule } from './firebase/firebase.module';
import { AuthModule } from './auth/auth.module';
import { ScheduleModule } from '@nestjs/schedule';
import { AppController } from './app.controller';

@Module({
	controllers: [AppController],
	imports: [
		ConfigModule.forRoot({ isGlobal: true }),
		ScheduleModule.forRoot(),
		TypeOrmModule.forRootAsync({
			useFactory: (cfg: ConfigService) => ({
				type: 'postgres',
				host: cfg.get('DB_HOST'),
				port: Number(cfg.get('DB_PORT')),
				username: cfg.get('DB_USER'),
				password: cfg.get('DB_PASS'),
				database: cfg.get('DB_NAME'),
				autoLoadEntities: true,
				synchronize: cfg.get('DB_SYNC') === 'true',
				extra: {
					max: Number(cfg.get('DB_POOL_MAX') ?? 50),
					min: Number(cfg.get('DB_POOL_MIN') ?? 5),
					idleTimeoutMillis: Number(cfg.get('DB_POOL_IDLE_MS') ?? 30000),
					connectionTimeoutMillis: Number(
						cfg.get('DB_POOL_CONN_TIMEOUT_MS') ?? 5000,
					),
				},
			}),
			inject: [ConfigService],
		}),
		FirebaseModule,
		UsersModule,
		AuthModule,
	],
})
export class AppModule {}
