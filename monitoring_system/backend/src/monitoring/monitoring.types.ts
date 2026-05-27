export type ServiceHealthItem = {
  name: string;
  url: string;
  status: 'healthy' | 'warning' | 'critical' | 'unknown';
  latencyMs: number | null;
  httpStatus: number | null;
  lastCheckedAt: string;
  detail?: string | null;
};

export type AlertItem = {
  code: string;
  severity: 'warning' | 'critical';
  metric: string;
  currentValue: number | string;
  threshold: number | string;
  title: string;
  recommendedAction: string;
};

export type MonitoringOverview = {
  generatedAt: string;
  status: 'healthy' | 'warning' | 'critical';
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
    source: 'readonly_db' | 'unconfigured' | 'error';
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
    gatewayStatus: 'healthy' | 'warning' | 'critical' | 'unknown';
    fabricStatus: string;
    activeNodes: number;
    configuredNodes: number;
    nodes: Array<{
      name: string;
      url: string;
      status: 'healthy' | 'warning' | 'critical' | 'unknown';
      role: string;
      orgName: string;
      mspId: string;
      knownPeers: number;
      pendingRequests: number;
      latencyMs: number | null;
      lastCheckedAt: string;
      detail?: string | null;
    }>;
    anomalies: Array<{
      code: string;
      severity: 'warning' | 'critical';
      message: string;
    }>;
  };
  dataWarehouse: {
    ready: boolean;
    note: string;
  };
  alerts: AlertItem[];
};

export type AmlFlaggedAccount = {
  accountId: string;
  riskLevel: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
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
  direction: 'inbound' | 'outbound';
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
  status: 'ok' | 'error' | 'busy' | 'not_started';
  generatedAt: string | null;
  lookbackHours: number;
  totalTransactions: number;
  flaggedTransactions: number;
  flaggedAccounts: number;
  scanDurationMs: number | null;
  error: string | null;
  accounts: AmlFlaggedAccount[];
};
