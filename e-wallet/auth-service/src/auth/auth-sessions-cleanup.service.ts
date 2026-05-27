import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { LessThan, Repository } from 'typeorm';
import { AuthSession } from './entities/auth-session.entity';
import { AuthOtp } from './entities/auth-otp.entity';
import { AuthStepUpToken } from './entities/auth-step-up-token.entity';

@Injectable()
export class AuthSessionsCleanupService {
    private readonly logger = new Logger(AuthSessionsCleanupService.name);

    constructor(
        @InjectRepository(AuthSession)
        private readonly sessions: Repository<AuthSession>,
        @InjectRepository(AuthOtp)
        private readonly otps: Repository<AuthOtp>,
        @InjectRepository(AuthStepUpToken)
        private readonly stepUpTokens: Repository<AuthStepUpToken>,
    ) {}

    @Cron(CronExpression.EVERY_DAY_AT_2PM)
    async cleanupExpiredAndRevokedSessions() {
        const now = new Date();
        const expiredResult = await this.sessions.delete({
            refreshTokenExpiresAt: LessThan(now),
        });
        const revokedResult = await this.sessions.delete({
            revokedAt: LessThan(now),
        });
        const expiredOtpResult = await this.otps.delete({
            expiresAt: LessThan(now),
        });
        const usedOtpResult = await this.otps.delete({
            usedAt: LessThan(now),
        });
        const expiredStepUpResult = await this.stepUpTokens.delete({
            expiresAt: LessThan(now),
        });
        this.logger.log(
            `Auth cleanup: sessions(expired=${expiredResult.affected ?? 0},revoked=${revokedResult.affected ?? 0}) otps(expired=${expiredOtpResult.affected ?? 0},used=${usedOtpResult.affected ?? 0}) stepUp(expired=${expiredStepUpResult.affected ?? 0})`,
        );
    }
}
