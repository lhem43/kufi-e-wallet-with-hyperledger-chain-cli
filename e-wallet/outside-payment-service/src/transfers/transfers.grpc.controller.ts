import { Controller } from '@nestjs/common';
import { GrpcMethod } from '@nestjs/microservices';
import { TransfersService } from './transfers.service';

@Controller()
export class TransfersGrpcController {
  constructor(private readonly transfersService: TransfersService) {}

  @GrpcMethod('OutsidePaymentService', 'InitiateTransfer')
  initiateTransfer(data: any) {
    return this.transfersService.initiateTransfer(data);
  }

  @GrpcMethod('OutsidePaymentService', 'CheckTransfer')
  checkTransfer(data: any) {
    return this.transfersService.checkTransfer(data);
  }
}
