import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import * as bcrypt from 'bcryptjs';
import { Repository } from 'typeorm';
import { AuthenticatedUser } from '../auth/auth.types';
import { ALL_PERMISSIONS } from '../common/constants/permissions';
import { AdminRoleEntity } from '../database/entities/admin-role.entity';
import { AdminUserEntity } from '../database/entities/admin-user.entity';
import { CreateAdminUserDto } from './dto/create-admin-user.dto';
import { UpdateAdminUserDto } from './dto/update-admin-user.dto';

@Injectable()
export class AdminService {
  constructor(
    @InjectRepository(AdminUserEntity)
    private readonly adminUserRepository: Repository<AdminUserEntity>,
    @InjectRepository(AdminRoleEntity)
    private readonly adminRoleRepository: Repository<AdminRoleEntity>,
  ) {}

  async listUsers() {
    const users = await this.adminUserRepository.find({
      order: { createdAt: 'DESC' },
    });
    return users.map((user) => this.toPublicUser(user));
  }

  async listRoles() {
    return this.adminRoleRepository.find({ order: { name: 'ASC' } });
  }

  listPermissions() {
    return ALL_PERMISSIONS;
  }

  async createUser(dto: CreateAdminUserDto, actor: AuthenticatedUser) {
    const email = dto.email.trim().toLowerCase();
    const existing = await this.adminUserRepository.findOne({ where: { email } });
    if (existing) {
      throw new ConflictException('Email already exists');
    }

    const role = await this.adminRoleRepository.findOne({ where: { id: dto.roleId } });
    if (!role) {
      throw new NotFoundException('Role not found');
    }

    const user = this.adminUserRepository.create({
      email,
      displayName: dto.displayName.trim(),
      title: dto.title.trim(),
      roleId: role.id,
      role,
      locale: dto.locale?.trim() || 'vi',
      isActive: dto.isActive ?? true,
      extraPermissions: dto.extraPermissions ?? [],
      passwordHash: await bcrypt.hash(dto.password, 10),
      lastLoginAt: null,
    });

    const saved = await this.adminUserRepository.save(user);
    return {
      createdBy: actor.email,
      user: this.toPublicUser(saved),
    };
  }

  async updateUser(id: string, dto: UpdateAdminUserDto) {
    const user = await this.adminUserRepository.findOne({ where: { id } });
    if (!user) {
      throw new NotFoundException('Admin user not found');
    }

    if (dto.email && dto.email.trim().toLowerCase() !== user.email) {
      const existing = await this.adminUserRepository.findOne({
        where: { email: dto.email.trim().toLowerCase() },
      });
      if (existing) {
        throw new ConflictException('Email already exists');
      }
      user.email = dto.email.trim().toLowerCase();
    }

    if (dto.roleId && dto.roleId !== user.roleId) {
      const role = await this.adminRoleRepository.findOne({ where: { id: dto.roleId } });
      if (!role) {
        throw new NotFoundException('Role not found');
      }
      user.roleId = role.id;
      user.role = role;
    }

    if (dto.displayName) {
      user.displayName = dto.displayName.trim();
    }
    if (dto.title) {
      user.title = dto.title.trim();
    }
    if (dto.locale) {
      user.locale = dto.locale.trim();
    }
    if (dto.extraPermissions) {
      user.extraPermissions = dto.extraPermissions;
    }
    if (typeof dto.isActive === 'boolean') {
      user.isActive = dto.isActive;
    }
    if (dto.password) {
      user.passwordHash = await bcrypt.hash(dto.password, 10);
    }

    const saved = await this.adminUserRepository.save(user);
    return this.toPublicUser(saved);
  }

  private toPublicUser(user: AdminUserEntity) {
    return {
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      title: user.title,
      locale: user.locale,
      isActive: user.isActive,
      role: user.role
        ? {
            id: user.role.id,
            code: user.role.code,
            name: user.role.name,
            permissions: user.role.permissions,
          }
        : null,
      extraPermissions: user.extraPermissions,
      lastLoginAt: user.lastLoginAt,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
    };
  }
}
