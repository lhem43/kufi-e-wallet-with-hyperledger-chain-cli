import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AdminRoleEntity } from '../database/entities/admin-role.entity';
import { AdminUserEntity } from '../database/entities/admin-user.entity';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';

@Module({
  imports: [TypeOrmModule.forFeature([AdminUserEntity, AdminRoleEntity])],
  controllers: [AdminController],
  providers: [AdminService],
})
export class AdminModule {}
