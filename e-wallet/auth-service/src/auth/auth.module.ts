import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { ClientsModule, Transport } from '@nestjs/microservices';
import { TypeOrmModule } from '@nestjs/typeorm';
import { join } from 'path';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { AuthSession } from './entities/auth-session.entity';
import { AuthOtp } from './entities/auth-otp.entity';
import { AuthStepUpToken } from './entities/auth-step-up-token.entity';
import { UsersModule } from '../users/users.module';
import { FirebaseModule } from '../firebase/firebase.module';
import { AuthGrpcController } from './auth.grpc.controller';
import { AuthSessionsCleanupService } from './auth-sessions-cleanup.service';
import { AuthInternalController } from './auth-internal.controller';
import { KycProfile } from '../users/entities/kyc-profile.entity';
import { User } from '../users/entities/user.entity/user.entity';

@Module({
	imports: [
		UsersModule,
		FirebaseModule,
		TypeOrmModule.forFeature([
			AuthSession,
			AuthOtp,
			AuthStepUpToken,
			KycProfile,
			User,
		]),
		JwtModule.registerAsync({
			inject: [ConfigService],
			useFactory: (config: ConfigService) => {
				const secret = config.get<string>('JWT_SECRET');
				if (!secret) {
					throw new Error('Jwt secret is required');
				}
				return { secret };
			},
		}),
		ClientsModule.register([
			{
				name: 'NOTIFICATION_PACKAGE',
				transport: Transport.GRPC,
				options: {
					url: process.env.NOTIFICATION_GRPC_URL ?? 'localhost:50055',
					package: 'notification',
					protoPath: join(
						__dirname,
						'../../../proto/notification.proto',
					),
				},
			},
		]),
	],
	providers: [AuthService, AuthSessionsCleanupService],
	controllers: [AuthController, AuthGrpcController, AuthInternalController],
})
export class AuthModule {}
