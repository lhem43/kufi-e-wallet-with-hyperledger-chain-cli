import {
	Body,
	Controller,
	Get,
	Param,
	Post,
	Req,
	UseGuards,
} from '@nestjs/common';
import { IsOptional, IsString } from 'class-validator';
import { firstValueFrom, timeout } from 'rxjs';
import { AuthGuard } from '../common/auth.guard';
import { GrpcClientsService } from '../common/grpc-clients.service';

class CreateWalletDto {
	@IsString()
	@IsOptional()
	currency?: string;
}

@Controller('v1/wallets')
@UseGuards(AuthGuard)
export class WalletsController {
	private readonly grpcTimeoutMs: number;

	constructor(private readonly grpcClients: GrpcClientsService) {
		this.grpcTimeoutMs = Number(process.env.GRPC_TIMEOUT_MS ?? 5000);
	}

	@Post()
	async createWallet(@Req() req: any, @Body() dto: CreateWalletDto) {
		const wallet = await firstValueFrom(
			this.grpcClients.transaction
				.createWallet({
					userId: req.authUser.userId,
					currency: dto.currency || 'VND',
				})
				.pipe(timeout(this.grpcTimeoutMs)),
		) as Record<string, any>;
		return {
			...wallet,
			balance: this.int64ToNumber((wallet as any)?.balance),
		};
	}

	@Get(':currency')
	async getWallet(@Req() req: any, @Param('currency') currency: string) {
		const wallet = await firstValueFrom(
			this.grpcClients.transaction
				.getWallet({
					userId: req.authUser.userId,
					currency,
				})
				.pipe(timeout(this.grpcTimeoutMs)),
		) as Record<string, any>;
		return {
			...wallet,
			balance: this.int64ToNumber((wallet as any)?.balance),
		};
	}

	private int64ToNumber(value: any): number {
		if (typeof value === 'number' && Number.isFinite(value)) {
			return Math.floor(value);
		}
		if (typeof value === 'string' && value.trim() !== '') {
			const parsed = Number(value);
			if (Number.isFinite(parsed)) {
				return Math.floor(parsed);
			}
		}
		if (value && typeof value === 'object' && typeof value.low === 'number') {
			const high = Number(value.high ?? 0);
			if (high === 0) {
				return value.unsigned ? value.low >>> 0 : value.low;
			}
		}
		return 0;
	}
}
