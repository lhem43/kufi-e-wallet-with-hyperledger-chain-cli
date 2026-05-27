import { Controller } from '@nestjs/common';
import { GrpcMethod } from '@nestjs/microservices';
import { ChainAdapterService } from './chain.adapter.service';

interface AnchorTransferRequest {
	transactionId: string;
	fromUserId: string;
	toUserId?: string;
	amount: number;
	memo?: string;
	internalRef?: string;
	settlementRef?: string;
	timestamp?: string | number;
	nonce: string;
	idempotencyKey: string;
	riskFlag?: string;
}

@Controller()
export class ChainGrpcController {
	constructor(private readonly chainAdapter: ChainAdapterService) {}

	@GrpcMethod('ChainService', 'AnchorTransfer')
	async anchorTransfer(data: AnchorTransferRequest) {
		return await this.chainAdapter.anchorTransfer(data);
	}

	@GrpcMethod('ChainService', 'GetReceipt')
	async getReceipt(data: { txId: string }) {
		return await this.chainAdapter.getReceipt(data.txId);
	}
}
