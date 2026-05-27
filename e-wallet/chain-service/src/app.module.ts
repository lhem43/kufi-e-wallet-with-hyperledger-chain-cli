import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller';
import { ChainAdapterService } from './chain/chain.adapter.service';
import { ChainGrpcController } from './chain/chain.grpc.controller';

@Module({
	imports: [ConfigModule.forRoot({ isGlobal: true })],
	controllers: [AppController, ChainGrpcController],
	providers: [ChainAdapterService],
})
export class AppModule {}
