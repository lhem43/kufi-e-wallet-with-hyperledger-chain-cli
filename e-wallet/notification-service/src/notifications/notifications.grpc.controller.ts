import { Controller } from '@nestjs/common';
import { GrpcMethod, RpcException } from '@nestjs/microservices';
import { NotificationsService } from './notifications.service';

@Controller()
export class NotificationsGrpcController {
	constructor(private readonly notificationsService: NotificationsService) {}

	@GrpcMethod('NotificationService', 'ListNotifications')
	async listNotifications(data: any) {
		const notifications = await this.notificationsService.listNotifications(
			data.userId,
			Number(data.limit ?? 20),
			Number(data.offset ?? 0),
		);
		return {
			items: notifications.map((item) => ({
				id: item.id,
				userId: item.userId,
				channel: item.channel,
				title: item.title,
				content: item.content,
				payloadJson: item.payloadJson ?? '',
				createdAt: item.createdAt.toISOString(),
				readAt: item.readAt ? item.readAt.toISOString() : '',
			})),
		};
	}

	@GrpcMethod('NotificationService', 'GetNotificationSettings')
	async getNotificationSettings(data: any) {
		if (!data?.userId) {
			throw new RpcException({ code: 3, message: 'userId is required' });
		}
		const settings = await this.notificationsService.getNotificationSettings(data.userId);
		return {
			userId: settings.userId,
			appEnabled: settings.appEnabled,
			emailEnabled: settings.emailEnabled,
			smsEnabled: settings.smsEnabled,
			updatedAt: settings.updatedAt.toISOString(),
		};
	}

	@GrpcMethod('NotificationService', 'UpdateNotificationSettings')
	async updateNotificationSettings(data: any) {
		if (!data?.userId) {
			throw new RpcException({ code: 3, message: 'userId is required' });
		}
		const settings = await this.notificationsService.updateNotificationSettings(data.userId, {
			emailEnabled: data.hasEmailEnabled ? data.emailEnabled === true : undefined,
			smsEnabled: data.hasSmsEnabled ? data.smsEnabled === true : undefined,
		});
		return {
			userId: settings.userId,
			appEnabled: settings.appEnabled,
			emailEnabled: settings.emailEnabled,
			smsEnabled: settings.smsEnabled,
			updatedAt: settings.updatedAt.toISOString(),
		};
	}

	@GrpcMethod('NotificationService', 'SendEmailOtp')
	async sendEmailOtp(data: any) {
		const recipientEmail = `${data?.recipientEmail ?? ''}`.trim();
		const otpCode = `${data?.otpCode ?? ''}`.trim();
		if (!recipientEmail || !otpCode) {
			throw new RpcException({
				code: 3,
				message: 'recipientEmail and otpCode are required',
			});
		}

		try {
			return await this.notificationsService.sendEmailOtp({
				recipientEmail,
				otpCode,
				expiresInSeconds: Number(data?.expiresInSeconds ?? 180),
				purpose: `${data?.purpose ?? ''}`.trim(),
			});
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			throw new RpcException({
				code: 13,
				message,
			});
		}
	}
}
