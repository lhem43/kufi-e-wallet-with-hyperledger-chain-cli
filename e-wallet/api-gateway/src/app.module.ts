import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { ClientsModule, Transport } from '@nestjs/microservices';
import { join } from 'path';
import { AppController } from './app.controller';
import { GatewayAuthController } from './auth/auth.controller';
import { WalletsController } from './wallets/wallets.controller';
import { TransactionsController } from './transactions/transactions.controller';
import { NotificationsController } from './notifications/notifications.controller';
import { GrpcClientsService } from './common/grpc-clients.service';
import { AuthGuard } from './common/auth.guard';

@Module({
	imports: [
		ConfigModule.forRoot({ isGlobal: true }),
		JwtModule.register({
			secret: process.env.JWT_SECRET,
		}),
		ClientsModule.register([
			{
				name: 'AUTH_PACKAGE',
				transport: Transport.GRPC,
				options: {
					url: process.env.AUTH_GRPC_URL ?? 'localhost:50051',
					package: 'auth',
					protoPath: join(__dirname, '../../proto/auth.proto'),
				},
			},
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
				name: 'NOTIFICATION_PACKAGE',
				transport: Transport.GRPC,
				options: {
					url: process.env.NOTIFICATION_GRPC_URL ?? 'localhost:50055',
					package: 'notification',
					protoPath: join(__dirname, '../../proto/notification.proto'),
				},
			},
		]),
	],
	controllers: [
		AppController,
		GatewayAuthController,
		WalletsController,
		TransactionsController,
		NotificationsController,
	],
	providers: [GrpcClientsService, AuthGuard],
})
export class AppModule {}
