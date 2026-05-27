import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool } from 'pg';

@Injectable()
export class WalletAnalyticsService implements OnModuleDestroy {
  private readonly pool: Pool | null;

  constructor(private readonly configService: ConfigService) {
    const connectionString = this.configService.get<string>('WALLET_DB_URL');
    if (connectionString) {
      this.pool = new Pool({ connectionString });
      return;
    }

    const host = this.configService.get<string>('WALLET_DB_HOST');
    if (!host) {
      this.pool = null;
      return;
    }

    const port = this.configService.get<string>('WALLET_DB_PORT')?.trim();
    const user = this.configService.get<string>('WALLET_DB_USER')?.trim();
    const password = this.configService.get<string>('WALLET_DB_PASS')?.trim();
    const database = this.configService.get<string>('WALLET_DB_NAME')?.trim();
    if (!port || !user || !password || !database) {
      this.pool = null;
      return;
    }

    this.pool = new Pool({
      host,
      port: Number(port),
      user,
      password,
      database,
      max: 2,
      connectionTimeoutMillis: 2_500,
      idleTimeoutMillis: 10_000,
    });
  }

  async onModuleDestroy() {
    await this.pool?.end();
  }

  async collect() {
    if (!this.pool) {
      return {
        configured: false,
        source: 'unconfigured' as const,
        activeSessions: null,
        concurrentUsersEstimate: null,
        activeUsers: null,
        totalUsers: null,
        note: 'Wallet read-only database is not configured.',
      };
    }

    try {
      const result = await this.pool.query<{
        active_sessions: string;
        concurrent_estimate: string;
        active_users: string;
        total_users: string;
      }>(`
        with session_stats as (
          select
            count(*) filter (
              where "revokedAt" is null and "refreshTokenExpiresAt" > now()
            ) as active_sessions,
            count(*) filter (
              where "revokedAt" is null
                and "refreshTokenExpiresAt" > now()
                and coalesce("lastUsedAt", "createdAt") > now() - interval '5 minutes'
            ) as concurrent_estimate,
            count(distinct "userId") filter (
              where "revokedAt" is null and "refreshTokenExpiresAt" > now()
            ) as active_users
          from auth_sessions
        ),
        user_stats as (
          select count(*) as total_users
          from users
          where "accountStatus" = 'active'
        )
        select
          session_stats.active_sessions,
          session_stats.concurrent_estimate,
          session_stats.active_users,
          user_stats.total_users
        from session_stats
        cross join user_stats
      `);
      const row = result.rows[0];

      return {
        configured: true,
        source: 'readonly_db' as const,
        activeSessions: Number(row?.active_sessions ?? 0),
        concurrentUsersEstimate: Number(row?.concurrent_estimate ?? 0),
        activeUsers: Number(row?.active_users ?? 0),
        totalUsers: Number(row?.total_users ?? 0),
        note: 'Concurrent users are estimated from sessions active in the last 5 minutes.',
      };
    } catch (error) {
      return {
        configured: true,
        source: 'error' as const,
        activeSessions: null,
        concurrentUsersEstimate: null,
        activeUsers: null,
        totalUsers: null,
        note:
          error instanceof Error
            ? `Wallet analytics unavailable: ${error.message}`
            : 'Wallet analytics unavailable.',
      };
    }
  }
}
