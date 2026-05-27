import { Inject, Injectable, OnModuleInit } from '@nestjs/common';
import { ClientGrpc } from '@nestjs/microservices';

@Injectable()
export class GrpcClientsService implements OnModuleInit {
	auth: any;
	transaction: any;
	notification: any;

	constructor(
		@Inject('AUTH_PACKAGE') private readonly authClient: ClientGrpc,
		@Inject('TRANSACTION_PACKAGE') private readonly transactionClient: ClientGrpc,
		@Inject('NOTIFICATION_PACKAGE') private readonly notificationClient: ClientGrpc,
	) {}

	onModuleInit() {
		this.auth = this.authClient.getService('AuthService');
		this.transaction = this.transactionClient.getService('TransactionService');
		this.notification = this.notificationClient.getService('NotificationService');
	}
}
