import {
  Injectable,
  OnModuleInit,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService, type JwtSignOptions } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import * as bcrypt from 'bcryptjs';
import { Repository } from 'typeorm';
import { ALL_PERMISSIONS, Permission } from '../common/constants/permissions';
import { AdminRoleEntity } from '../database/entities/admin-role.entity';
import { AdminUserEntity } from '../database/entities/admin-user.entity';
import {
  AccessTokenPayload,
  AuthenticatedUser,
} from './auth.types';
import { LoginDto } from './dto/login.dto';

type SeedRole = {
  code: string;
  name: string;
  description: string;
  permissions: string[];
};

@Injectable()
export class AuthService implements OnModuleInit {
  constructor(
    @InjectRepository(AdminUserEntity)
    private readonly adminUserRepository: Repository<AdminUserEntity>,
    @InjectRepository(AdminRoleEntity)
    private readonly adminRoleRepository: Repository<AdminRoleEntity>,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  async onModuleInit() {
    await this.seedDefaults();
  }

  async login(dto: LoginDto) {
    const user = await this.adminUserRepository.findOne({
      where: { email: dto.email.trim().toLowerCase() },
    });
    if (!user || !user.isActive) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const isMatch = await bcrypt.compare(dto.password, user.passwordHash);
    if (!isMatch) {
      throw new UnauthorizedException('Invalid credentials');
    }

    user.lastLoginAt = new Date();
    await this.adminUserRepository.save(user);

    const authUser = this.toAuthenticatedUser(user);
    return {
      accessToken: await this.issueAccessToken(user),
      user: authUser,
    };
  }

  async validateAccessToken(token: string): Promise<AuthenticatedUser> {
    let payload: AccessTokenPayload;
    try {
      payload = await this.jwtService.verifyAsync<AccessTokenPayload>(token, {
        secret: this.jwtSecret,
      });
    } catch {
      throw new UnauthorizedException('Invalid access token');
    }

    const user = await this.adminUserRepository.findOne({
      where: { id: payload.sub },
    });
    if (!user || !user.isActive) {
      throw new UnauthorizedException('Account is inactive');
    }

    return this.toAuthenticatedUser(user);
  }

  toAuthenticatedUser(user: AdminUserEntity): AuthenticatedUser {
    const rolePermissions = Array.isArray(user.role?.permissions)
      ? user.role.permissions
      : [];
    const extraPermissions = Array.isArray(user.extraPermissions)
      ? user.extraPermissions
      : [];

    return {
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      title: user.title,
      locale: user.locale,
      roleCode: user.role?.code ?? 'unknown',
      permissions: [...new Set([...rolePermissions, ...extraPermissions])].filter(
        Boolean,
      ),
    };
  }

  private async issueAccessToken(user: AdminUserEntity) {
    return this.jwtService.signAsync(
      {
        sub: user.id,
        email: user.email,
        roleCode: user.role?.code ?? 'unknown',
      } satisfies AccessTokenPayload,
      {
        secret: this.jwtSecret,
        expiresIn: this.configService.get<string>(
          'JWT_EXPIRES_IN',
          '12h',
        ) as JwtSignOptions['expiresIn'],
      },
    );
  }

  private get jwtSecret() {
    const secret = this.configService.get<string>('JWT_SECRET')?.trim();
    if (!secret) {
      throw new Error('JWT_SECRET is required.');
    }
    return secret;
  }

  private async seedDefaults() {
    const seedRoles: SeedRole[] = [
      {
        code: 'super_admin',
        name: 'Super Admin',
        description: 'Full access across monitoring, chain ops, and user admin.',
        permissions: ALL_PERMISSIONS,
      },
      {
        code: 'sre_operator',
        name: 'SRE Operator',
        description: 'Operational owner for infrastructure, services, and logs.',
        permissions: [
          Permission.DASHBOARD_VIEW,
          Permission.METRICS_VIEW,
          Permission.CHAIN_VIEW,
          Permission.LOGS_VIEW,
          Permission.AUDIT_VIEW,
          Permission.MOBILE_VIEW,
        ],
      },
      {
        code: 'chain_operator',
        name: 'Chain Operator',
        description: 'Focused on chain health, peer topology, and node incidents.',
        permissions: [
          Permission.DASHBOARD_VIEW,
          Permission.METRICS_VIEW,
          Permission.CHAIN_VIEW,
          Permission.LOGS_VIEW,
          Permission.MOBILE_VIEW,
        ],
      },
      {
        code: 'mobile_observer',
        name: 'Mobile Observer',
        description: 'Read-only mobile visibility for incidents and chain health.',
        permissions: [
          Permission.DASHBOARD_VIEW,
          Permission.METRICS_VIEW,
          Permission.CHAIN_VIEW,
          Permission.MOBILE_VIEW,
        ],
      },
    ];

    for (const role of seedRoles) {
      const existing = await this.adminRoleRepository.findOne({
        where: { code: role.code },
      });
      if (!existing) {
        await this.adminRoleRepository.save(
          this.adminRoleRepository.create(role),
        );
      }
    }

    const adminEmail = this.configService
      .get<string>('ADMIN_EMAIL')
      ?.trim()
      .toLowerCase();
    if (!adminEmail) {
      throw new Error('ADMIN_EMAIL is required.');
    }
    const existingAdmin = await this.adminUserRepository.findOne({
      where: { email: adminEmail },
    });
    if (existingAdmin) {
      return;
    }

    const superAdminRole = await this.adminRoleRepository.findOneOrFail({
      where: { code: 'super_admin' },
    });
    const adminPassword = this.configService
      .get<string>('ADMIN_PASSWORD')
      ?.trim();
    if (!adminPassword) {
      throw new Error('ADMIN_PASSWORD is required.');
    }
    const passwordHash = await bcrypt.hash(adminPassword, 10);

    await this.adminUserRepository.save(
      this.adminUserRepository.create({
        email: adminEmail,
        displayName: this.configService.get<string>(
          'ADMIN_DISPLAY_NAME',
          'Kufi Monitoring Owner',
        ),
        title: this.configService.get<string>('ADMIN_TITLE', 'Platform Lead'),
        locale: this.configService.get<string>('ADMIN_LOCALE', 'vi'),
        roleId: superAdminRole.id,
        role: superAdminRole,
        passwordHash,
        extraPermissions: [],
        isActive: true,
        lastLoginAt: null,
      }),
    );
  }
}
