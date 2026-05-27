import type {
  AmlAccountTransaction,
  AmlOverview,
  AdminRole,
  AdminUser,
  AuditLog,
  LogSource,
  LogTail,
  MonitoringOverview,
  Session,
  TrendCollectionResponse,
  TimeseriesResponse,
} from "./types";

const API_BASE_URL =
  (import.meta.env.VITE_API_BASE_URL as string | undefined)?.trim() ?? "";

if (!API_BASE_URL) {
  throw new Error("VITE_API_BASE_URL is required in environment.");
}

export class ApiError extends Error {
  status: number;

  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

const REQUEST_TIMEOUT_MS = 8_000;

async function request<T>(
  path: string,
  options?: RequestInit & { token?: string },
): Promise<T> {
  const controller = new AbortController();
  const timeout = window.setTimeout(
    () => controller.abort(),
    REQUEST_TIMEOUT_MS,
  );

  let response: Response;
  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      ...options,
      signal: controller.signal,
      headers: {
        "Content-Type": "application/json",
        ...(options?.token
          ? { Authorization: `Bearer ${options.token}` }
          : undefined),
        ...options?.headers,
      },
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new ApiError("Monitoring request timed out.", 408);
    }
    throw error;
  } finally {
    window.clearTimeout(timeout);
  }

  if (!response.ok) {
    const message = await response.text();
    throw new ApiError(message || response.statusText, response.status);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
}

export const api = {
  baseUrl: API_BASE_URL,
  login(email: string, password: string) {
    return request<Session>("/auth/login", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    });
  },
  me(token: string) {
    return request<Session["user"]>("/auth/me", { token });
  },
  overview(token: string, refresh = false) {
    return request<MonitoringOverview>(
      `/monitoring/overview${refresh ? "?refresh=true" : ""}`,
      { token },
    );
  },
  amlOverview(token: string, limit = 100) {
    return request<AmlOverview>(
      `/monitoring/aml?limit=${encodeURIComponent(String(limit))}`,
      { token },
    );
  },
  amlAccountTransactions(token: string, accountId: string, limit = 200) {
    return request<{
      generatedAt: string | null;
      accountId: string;
      total: number;
      items: AmlAccountTransaction[];
    }>(
      `/monitoring/aml/accounts/${encodeURIComponent(accountId)}/transactions?limit=${encodeURIComponent(String(limit))}`,
      { token },
    );
  },
  amlScan(token: string, lookbackHours?: number) {
    const query =
      typeof lookbackHours === "number" && Number.isFinite(lookbackHours)
        ? `?lookbackHours=${encodeURIComponent(String(Math.max(1, Math.floor(lookbackHours))))}`
        : "";
    return request<AmlOverview>(`/monitoring/aml/scan${query}`, {
      method: "POST",
      token,
    });
  },
  timeseries(token: string, metric: string) {
    return request<TimeseriesResponse>(
      `/monitoring/timeseries?metric=${encodeURIComponent(metric)}&minutes=180`,
      { token },
    );
  },
  trends(token: string, metrics: string[]) {
    return request<TrendCollectionResponse>(
      `/monitoring/trends?metrics=${encodeURIComponent(metrics.join(","))}&minutes=180`,
      { token },
    ).catch(async (error) => {
      if (!(error instanceof ApiError) || error.status !== 404) {
        throw error;
      }

      const responses = await Promise.all(
        metrics.map(async (metric) => [
          metric,
          await request<TimeseriesResponse>(
            `/monitoring/timeseries?metric=${encodeURIComponent(metric)}&minutes=180`,
            { token },
          ),
        ]),
      );

      return {
        minutes: 180,
        series: Object.fromEntries(responses),
      } satisfies TrendCollectionResponse;
    });
  },
  auditLogs(token: string) {
    return request<AuditLog[]>("/audit/logs?limit=100", { token });
  },
  logSources(token: string) {
    return request<LogSource[]>("/logs/sources", { token });
  },
  logTail(token: string, source: string) {
    return request<LogTail>(
      `/logs/tail?source=${encodeURIComponent(source)}&limit=180`,
      { token },
    );
  },
  adminUsers(token: string) {
    return request<AdminUser[]>("/admin/users", { token });
  },
  adminRoles(token: string) {
    return request<AdminRole[]>("/admin/roles", { token });
  },
  permissions(token: string) {
    return request<string[]>("/admin/permissions", { token });
  },
  createAdminUser(
    token: string,
    payload: {
      email: string;
      password: string;
      displayName: string;
      title: string;
      roleId: string;
      locale: string;
      extraPermissions: string[];
    },
  ) {
    return request<{ createdBy: string; user: AdminUser }>("/admin/users", {
      method: "POST",
      token,
      body: JSON.stringify(payload),
    });
  },
  updateAdminUser(
    token: string,
    id: string,
    payload: Partial<{
      email: string;
      password: string;
      displayName: string;
      title: string;
      roleId: string;
      locale: string;
      isActive: boolean;
      extraPermissions: string[];
    }>,
  ) {
    return request<AdminUser>(`/admin/users/${id}`, {
      method: "PATCH",
      token,
      body: JSON.stringify(payload),
    });
  },
};
