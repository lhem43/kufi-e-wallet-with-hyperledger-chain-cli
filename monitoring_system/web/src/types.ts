export type Locale = "vi" | "en";

export type AuthUser = {
  id: string;
  email: string;
  displayName: string;
  title: string;
  locale: string;
  roleCode: string;
  permissions: string[];
};

export type Session = {
  accessToken: string;
  user: AuthUser;
};

export type ServiceHealthItem = {
  name: string;
  url: string;
  status: "healthy" | "warning" | "critical" | "unknown";
  latencyMs: number | null;
  httpStatus: number | null;
  lastCheckedAt: string;
  detail?: string | null;
};

export type AlertItem = {
  code: string;
  severity: "warning" | "critical";
  metric: string;
  currentValue: number | string;
  threshold: number | string;
  title: string;
  recommendedAction: string;
};

export type ChainNode = {
  name: string;
  url: string;
  status: "healthy" | "warning" | "critical" | "unknown";
  role: string;
  orgName: string;
  mspId: string;
  knownPeers: number;
  pendingRequests: number;
  latencyMs: number | null;
  lastCheckedAt: string;
  detail?: string | null;
};

export type AmlFlaggedAccount = {
  accountId: string;
  riskLevel: "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
  isMoneyLaundering: boolean;
  maxFraudProbability: number;
  avgFraudProbability: number;
  totalTransactions: number;
  flaggedTransactions: number;
  flagRatePct: number;
  totalSent: number;
  totalReceived: number;
  isMuleAccount: boolean;
};

export type AmlAccountTransaction = {
  transactionId: string;
  timestamp: string;
  direction: "inbound" | "outbound";
  counterpartyAccount: string;
  amountPaid: number;
  amountReceived: number;
  paymentFormat: string;
  paymentCurrency: string;
  fraudProbability: number;
  riskLevel: string;
  isFlagged: boolean;
};

export type AmlOverview = {
  configured: boolean;
  status: "ok" | "error" | "busy" | "not_started";
  generatedAt: string | null;
  lookbackHours: number;
  totalTransactions: number;
  flaggedTransactions: number;
  flaggedAccounts: number;
  scanDurationMs: number | null;
  error: string | null;
  accounts: AmlFlaggedAccount[];
};

export type MonitoringOverview = {
  generatedAt: string;
  status: "healthy" | "warning" | "critical";
  system: {
    cpuPercent: number;
    memoryPercent: number;
    memoryUsedGb: number;
    memoryTotalGb: number;
    diskPercent: number;
    diskUsedGb: number;
    diskTotalGb: number;
    networkRxMbps: number;
    networkTxMbps: number;
    loadAverage1m: number;
    uptimeHours: number;
  };
  wallet: {
    configured: boolean;
    source: "readonly_db" | "unconfigured" | "error";
    activeSessions: number | null;
    concurrentUsersEstimate: number | null;
    activeUsers: number | null;
    totalUsers: number | null;
    note: string | null;
  };
  services: {
    healthyCount: number;
    totalCount: number;
    items: ServiceHealthItem[];
  };
  chain: {
    gatewayStatus: "healthy" | "warning" | "critical" | "unknown";
    fabricStatus: string;
    activeNodes: number;
    configuredNodes: number;
    nodes: ChainNode[];
    anomalies: Array<{
      code: string;
      severity: "warning" | "critical";
      message: string;
    }>;
  };
  dataWarehouse: {
    ready: boolean;
    note: string;
  };
  alerts: AlertItem[];
};

export type TimeseriesResponse = {
  metric: string;
  minutes: number;
  points: Array<{
    at: string;
    value: number | null;
  }>;
};

export type TrendCollectionResponse = {
  minutes: number;
  series: Record<string, TimeseriesResponse>;
};

export type AuditLog = {
  id: string;
  actorUserId: string | null;
  actorEmail: string | null;
  method: string;
  path: string;
  action: string;
  resource: string;
  statusCode: number;
  ipAddress: string | null;
  payload: Record<string, unknown> | null;
  outcome: string | null;
  createdAt: string;
};

export type AdminRole = {
  id: string;
  code: string;
  name: string;
  description: string | null;
  permissions: string[];
};

export type AdminUser = {
  id: string;
  email: string;
  displayName: string;
  title: string;
  locale: string;
  isActive: boolean;
  role: {
    id: string;
    code: string;
    name: string;
    permissions: string[];
  } | null;
  extraPermissions: string[];
  lastLoginAt: string | null;
  createdAt: string;
  updatedAt: string;
};

export type LogSource = {
  name: string;
  kind: "wallet" | "chain" | "system";
  path: string;
};

export type LogTail = {
  source: string;
  kind: "wallet" | "chain" | "system";
  fileName: string;
  lines: string[];
};
