export const Permission = {
  DASHBOARD_VIEW: 'dashboard:view',
  METRICS_VIEW: 'metrics:view',
  CHAIN_VIEW: 'chain:view',
  LOGS_VIEW: 'logs:view',
  AUDIT_VIEW: 'audit:view',
  ADMIN_USERS_MANAGE: 'admin-users:manage',
  MOBILE_VIEW: 'mobile:view',
} as const;

export type PermissionValue = (typeof Permission)[keyof typeof Permission];

export const ALL_PERMISSIONS: PermissionValue[] = Object.values(Permission);
