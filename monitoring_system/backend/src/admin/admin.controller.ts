import { Body, Controller, Get, Patch, Post, Req, Param } from '@nestjs/common';
import { AuthenticatedUser } from '../auth/auth.types';
import { Permissions } from '../common/decorators/permissions.decorator';
import { Permission } from '../common/constants/permissions';
import { AdminService } from './admin.service';
import { CreateAdminUserDto } from './dto/create-admin-user.dto';
import { UpdateAdminUserDto } from './dto/update-admin-user.dto';

@Controller('admin')
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Permissions(Permission.ADMIN_USERS_MANAGE)
  @Get('users')
  listUsers() {
    return this.adminService.listUsers();
  }

  @Permissions(Permission.ADMIN_USERS_MANAGE)
  @Get('roles')
  listRoles() {
    return this.adminService.listRoles();
  }

  @Permissions(Permission.ADMIN_USERS_MANAGE)
  @Get('permissions')
  listPermissions() {
    return this.adminService.listPermissions();
  }

  @Permissions(Permission.ADMIN_USERS_MANAGE)
  @Post('users')
  createUser(
    @Body() dto: CreateAdminUserDto,
    @Req() request: { user: AuthenticatedUser },
  ) {
    return this.adminService.createUser(dto, request.user);
  }

  @Permissions(Permission.ADMIN_USERS_MANAGE)
  @Patch('users/:id')
  updateUser(@Param('id') id: string, @Body() dto: UpdateAdminUserDto) {
    return this.adminService.updateUser(id, dto);
  }
}
