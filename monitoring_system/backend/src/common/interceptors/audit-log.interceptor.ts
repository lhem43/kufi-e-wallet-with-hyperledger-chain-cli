import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable, tap } from 'rxjs';
import { AuthenticatedUser } from '../../auth/auth.types';
import { AuditService } from '../../audit/audit.service';

@Injectable()
export class AuditLogInterceptor implements NestInterceptor {
  constructor(private readonly auditService: AuditService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<{
      method: string;
      originalUrl?: string;
      url?: string;
      body?: Record<string, unknown>;
      ip?: string;
      user?: AuthenticatedUser;
    }>();
    const response = context.switchToHttp().getResponse<{ statusCode?: number }>();

    if (['GET', 'HEAD', 'OPTIONS'].includes(request.method)) {
      return next.handle();
    }

    const path = request.originalUrl ?? request.url ?? 'unknown';
    const segments = path.split('/').filter(Boolean);
    const normalizedSegments = segments[0] === 'api' ? segments.slice(1) : segments;
    const [resource = 'unknown', action = 'unknown'] = normalizedSegments;

    return next.handle().pipe(
      tap({
        next: () => {
          void this.auditService.createLog({
            actorUserId: request.user?.id ?? null,
            actorEmail: request.user?.email ?? null,
            method: request.method,
            path,
            action,
            resource,
            statusCode: response.statusCode ?? 200,
            ipAddress: request.ip ?? null,
            payload: sanitizePayload(request.body),
            outcome: 'success',
          });
        },
        error: (error: { message?: string; status?: number }) => {
          void this.auditService.createLog({
            actorUserId: request.user?.id ?? null,
            actorEmail: request.user?.email ?? null,
            method: request.method,
            path,
            action,
            resource,
            statusCode: error?.status ?? response.statusCode ?? 500,
            ipAddress: request.ip ?? null,
            payload: sanitizePayload(request.body),
            outcome: error?.message ?? 'error',
          });
        },
      }),
    );
  }
}

function sanitizePayload(
  payload?: Record<string, unknown>,
): Record<string, unknown> | null {
  if (!payload) {
    return null;
  }

  const clone: Record<string, unknown> = { ...payload };
  for (const key of ['password', 'passwordHash', 'refreshToken', 'accessToken']) {
    if (key in clone) {
      clone[key] = '[redacted]';
    }
  }
  return clone;
}
