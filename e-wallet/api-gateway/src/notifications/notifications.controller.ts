import {
	Body,
	Controller,
	Get,
	Patch,
	Query,
	Req,
	UseGuards,
} from '@nestjs/common';
import { IsBoolean, IsOptional } from 'class-validator';
import { firstValueFrom, timeout } from 'rxjs';
import { AuthGuard } from '../common/auth.guard';
import { GrpcClientsService } from '../common/grpc-clients.service';

class UpdateNotificationSettingsDto {
	@IsOptional()
	@IsBoolean()
	emailEnabled?: boolean;

	@IsOptional()
	@IsBoolean()
	smsEnabled?: boolean;
}

@Controller('v1/notifications')
@UseGuards(AuthGuard)
export class NotificationsController {
	private readonly grpcTimeoutMs: number;

	constructor(private readonly grpcClients: GrpcClientsService) {
		this.grpcTimeoutMs = Number(process.env.GRPC_TIMEOUT_MS ?? 5000);
	}

	@Get()
	async listNotifications(
		@Req() req: any,
		@Query('limit') limit = '20',
		@Query('offset') offset = '0',
	) {
		return firstValueFrom(
			this.grpcClients.notification
				.listNotifications({
					userId: req.authUser.userId,
					limit: Number(limit),
					offset: Number(offset),
				})
				.pipe(timeout(this.grpcTimeoutMs)),
		);
	}

	@Get('settings')
	async getSettings(@Req() req: any) {
		return firstValueFrom(
			this.grpcClients.notification
				.getNotificationSettings({
					userId: req.authUser.userId,
				})
				.pipe(timeout(this.grpcTimeoutMs)),
		);
	}

	@Patch('settings')
	async updateSettings(
		@Req() req: any,
		@Body() dto: UpdateNotificationSettingsDto,
	) {
		return firstValueFrom(
			this.grpcClients.notification
				.updateNotificationSettings({
					userId: req.authUser.userId,
					hasEmailEnabled: typeof dto.emailEnabled === 'boolean',
					emailEnabled: dto.emailEnabled === true,
					hasSmsEnabled: typeof dto.smsEnabled === 'boolean',
					smsEnabled: dto.smsEnabled === true,
				})
				.pipe(timeout(this.grpcTimeoutMs)),
		);
	}
}
