import "@fontsource/be-vietnam-pro/400.css";
import "@fontsource/be-vietnam-pro/500.css";
import "@fontsource/be-vietnam-pro/600.css";
import "@fontsource/be-vietnam-pro/700.css";
import "@fontsource/be-vietnam-pro/800.css";
import {
  startTransition,
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import type { FormEvent } from "react";
import { ApiError, api } from "./api";
import { t } from "./i18n";
import type {
  AmlAccountTransaction,
  AmlOverview,
  AdminRole,
  AdminUser,
  AuditLog,
  Locale,
  LogSource,
  LogTail,
  MonitoringOverview,
  Session,
  TimeseriesResponse,
} from "./types";

type TabKey =
  | "overview"
  | "walletBackend"
  | "chain"
  | "aml"
  | "logs"
  | "admins";

const SESSION_STORAGE_KEY = "kufi_monitoring_session";
const LOCALE_STORAGE_KEY = "kufi_monitoring_locale";
const TREND_METRICS = [
  "system.cpuPercent",
  "system.memoryPercent",
  "wallet.concurrentUsersEstimate",
] as const;

const COPY: Record<
  Locale,
  {
    commandDeck: string;
    attentionLane: string;
    walletCoverage: string;
    warehouseLane: string;
    lastSnapshot: string;
    sourceLabel: string;
    logFile: string;
    logLines: string;
    operatorProfile: string;
    accountRoster: string;
    connectedNodes: string;
    averagePeers: string;
    governanceQueue: string;
    serviceExposure: string;
    activeUsersLabel: string;
    totalUsersLabel: string;
    telemetryReady: string;
    telemetryError: string;
    telemetryWaiting: string;
    noAuditResults: string;
    trendWindow: string;
    responseLatency: string;
    chainFocus: string;
    permissionsMatrix: string;
    createAdminHint: string;
    never: string;
    inspectCriticalNode: string;
    reviewChainWarning: string;
  }
> = {
  vi: {
    commandDeck: "Điều hành",
    attentionLane: "Cảnh báo",
    walletCoverage: "Nguồn dữ liệu ví",
    warehouseLane: "Kho dữ liệu",
    lastSnapshot: "Snapshot mới nhất",
    sourceLabel: "Nguồn log",
    logFile: "Tệp",
    logLines: "Số dòng",
    operatorProfile: "Tài khoản",
    accountRoster: "Danh sách tài khoản",
    connectedNodes: "Node kết nối",
    averagePeers: "Peer trung bình",
    governanceQueue: "Hàng chờ governance",
    serviceExposure: "Dịch vụ bất thường",
    activeUsersLabel: "Người dùng hoạt động",
    totalUsersLabel: "Tổng người dùng",
    telemetryReady: "CSDL chỉ đọc",
    telemetryError: "Telemetry suy giảm",
    telemetryWaiting: "Chưa cấu hình",
    noAuditResults: "Không có audit log khớp bộ lọc hiện tại.",
    trendWindow: "3 giờ gần nhất",
    responseLatency: "Độ trễ",
    chainFocus: "Kufi chain",
    permissionsMatrix: "Quyền truy cập",
    createAdminHint:
      "Bắt đầu từ role nền, chỉ cấp thêm những quyền thực sự cần.",
    never: "Chưa từng",
    inspectCriticalNode: "Kiểm tra node liên quan ngay.",
    reviewChainWarning: "Rà topology và các sự kiện governance gần nhất.",
  },
  en: {
    commandDeck: "Console",
    attentionLane: "Alerts",
    walletCoverage: "Telemetry source",
    warehouseLane: "Warehouse",
    lastSnapshot: "Latest snapshot",
    sourceLabel: "Log source",
    logFile: "File",
    logLines: "Lines",
    operatorProfile: "Account",
    accountRoster: "Account roster",
    connectedNodes: "Connected nodes",
    averagePeers: "Average peers",
    governanceQueue: "Governance queue",
    serviceExposure: "At-risk services",
    activeUsersLabel: "Active users",
    totalUsersLabel: "Total users",
    telemetryReady: "Read-only DB",
    telemetryError: "Telemetry degraded",
    telemetryWaiting: "Unconfigured",
    noAuditResults: "No audit log matches the current filter.",
    trendWindow: "3-hour trend window",
    responseLatency: "Response latency",
    chainFocus: "Kufi chain",
    permissionsMatrix: "Access control",
    createAdminHint:
      "Start with the baseline role, then grant only the permissions that are actually needed.",
    never: "Never",
    inspectCriticalNode: "Inspect the related nodes immediately.",
    reviewChainWarning: "Review the topology and recent governance events.",
  },
};

function App() {
  const [session, setSession] = useState<Session | null>(loadSession());
  const [locale, setLocale] = useState<Locale>(loadLocale());
  const [sessionReady, setSessionReady] = useState(false);

  useEffect(() => {
    if (!session?.accessToken) {
      setSessionReady(true);
      return;
    }

    let active = true;

    const bootstrap = async () => {
      try {
        const user = await api.me(session.accessToken);
        if (!active) {
          return;
        }

        const hasProfileChange =
          session.user.id !== user.id ||
          session.user.email !== user.email ||
          session.user.displayName !== user.displayName ||
          session.user.title !== user.title ||
          session.user.locale !== user.locale ||
          session.user.roleCode !== user.roleCode ||
          session.user.permissions.join("|") !== user.permissions.join("|");

        if (hasProfileChange) {
          const nextSession = { ...session, user };
          setSession(nextSession);
          persistSession(nextSession);
        }

        if (!localStorage.getItem(LOCALE_STORAGE_KEY)) {
          setLocale(resolveLocale(user.locale));
        }
      } catch (reason) {
        if (
          active &&
          reason instanceof ApiError &&
          reason.status === 401
        ) {
          clearSessionStorage();
          setSession(null);
        }
      } finally {
        if (active) {
          setSessionReady(true);
        }
      }
    };

    void bootstrap();

    return () => {
      active = false;
    };
  }, [session]);

  useEffect(() => {
    localStorage.setItem(LOCALE_STORAGE_KEY, locale);
  }, [locale]);

  if (!sessionReady) {
    return (
      <div className="splash-screen">
        <div className="splash-card">Kufi Monitoring Console</div>
      </div>
    );
  }

  if (!session) {
    return (
      <LoginScreen
        locale={locale}
        onLocaleChange={setLocale}
        onSignedIn={(nextSession) => {
          setSession(nextSession);
          persistSession(nextSession);
          if (!localStorage.getItem(LOCALE_STORAGE_KEY)) {
            setLocale(resolveLocale(nextSession.user.locale));
          }
        }}
      />
    );
  }

  return (
    <Dashboard
      session={session}
      locale={locale}
      onLocaleChange={(nextLocale) => {
        startTransition(() => setLocale(nextLocale));
      }}
      onLogout={() => {
        clearSessionStorage();
        setSession(null);
      }}
    />
  );
}

function LoginScreen({
  locale,
  onLocaleChange,
  onSignedIn,
}: {
  locale: Locale;
  onLocaleChange: (locale: Locale) => void;
  onSignedIn: (session: Session) => void;
}) {
  const [email, setEmail] = useState("admin@kufi.monitor");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [isLocaleMenuOpen, setIsLocaleMenuOpen] = useState(false);
  const localeMenuRef = useRef<HTMLDivElement | null>(null);

  const localeOptions =
    locale === "vi"
      ? [
          { code: "vi" as const, label: "Tiếng Việt", flag: "/flags/vn.png" },
          { code: "en" as const, label: "English", flag: "/flags/us.png" },
        ]
      : [
          { code: "vi" as const, label: "Vietnamese", flag: "/flags/vn.png" },
          { code: "en" as const, label: "English", flag: "/flags/us.png" },
        ];

  const activeLocaleOption =
    localeOptions.find((option) => option.code === locale) ?? localeOptions[0];

  useEffect(() => {
    const handlePointerDown = (event: PointerEvent) => {
      if (
        localeMenuRef.current &&
        !localeMenuRef.current.contains(event.target as Node)
      ) {
        setIsLocaleMenuOpen(false);
      }
    };
    window.addEventListener("pointerdown", handlePointerDown);
    return () => window.removeEventListener("pointerdown", handlePointerDown);
  }, []);

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true);
    setError("");
    try {
      const session = await api.login(email, password);
      onSignedIn(session);
    } catch (reason) {
      setError(
        reason instanceof ApiError && reason.status === 401
          ? t(locale, "invalidCredentials")
          : t(locale, "apiError"),
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-shell">
      <section className="auth-hero">
        <div className="auth-hero__ground" aria-hidden="true" />
        <img src="/kufi-cat.png" alt="Kufi Cat" className="auth-hero__cat auth-hero__cat--center" />
        <div className="auth-hero__brand">
          <h1>{t(locale, "appName")}</h1>
        </div>
      </section>

      <section className="auth-panel">
        <div className="auth-locale" ref={localeMenuRef}>
          <button
            className="auth-locale__trigger"
            onClick={() => setIsLocaleMenuOpen((current) => !current)}
            type="button"
          >
            <img
              src={activeLocaleOption.flag}
              alt={activeLocaleOption.code.toUpperCase()}
              className="auth-locale__flag"
            />
            <span className="auth-locale__code">
              {activeLocaleOption.code.toUpperCase()}
            </span>
            <span className="auth-locale__chevron">▾</span>
          </button>
          {isLocaleMenuOpen ? (
            <div className="auth-locale__menu">
              {localeOptions.map((option) => (
                <button
                  key={option.code}
                  className={
                    option.code === locale
                      ? "auth-locale__item active"
                      : "auth-locale__item"
                  }
                  onClick={() => {
                    onLocaleChange(option.code);
                    setIsLocaleMenuOpen(false);
                  }}
                  type="button"
                >
                  <img
                    src={option.flag}
                    alt={option.code.toUpperCase()}
                    className="auth-locale__flag"
                  />
                  <span>{option.label}</span>
                  {option.code === locale ? (
                    <span className="auth-locale__check">✓</span>
                  ) : null}
                </button>
              ))}
            </div>
          ) : null}
        </div>

        <div className="auth-panel__header">
          <h2>{t(locale, "signIn")}</h2>
        </div>

        <form className="auth-form" onSubmit={submit}>
          <label className="field">
            <span>{t(locale, "email")}</span>
            <input
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
          </label>
          <label className="field">
            <span>{t(locale, "password")}</span>
            <input
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </label>
          {error ? (
            <div className="inline-banner inline-banner--error">{error}</div>
          ) : null}
          <button className="primary-button" disabled={loading} type="submit">
            {loading ? t(locale, "signingIn") : t(locale, "signIn")}
          </button>
        </form>
      </section>
    </div>
  );
}

function Dashboard({
  session,
  locale,
  onLocaleChange,
  onLogout,
}: {
  session: Session;
  locale: Locale;
  onLocaleChange: (locale: Locale) => void;
  onLogout: () => void;
}) {
  const [activeTab, setActiveTab] = useState<TabKey>("overview");
  const [overview, setOverview] = useState<MonitoringOverview | null>(null);
  const [trendCpu, setTrendCpu] = useState<TimeseriesResponse | null>(null);
  const [trendMemory, setTrendMemory] = useState<TimeseriesResponse | null>(
    null,
  );
  const [trendConcurrent, setTrendConcurrent] =
    useState<TimeseriesResponse | null>(null);
  const [amlOverview, setAmlOverview] = useState<AmlOverview | null>(null);
  const [amlSelectedAccountId, setAmlSelectedAccountId] = useState("");
  const [amlTransactions, setAmlTransactions] = useState<AmlAccountTransaction[]>(
    [],
  );
  const [amlTransactionsTotal, setAmlTransactionsTotal] = useState(0);
  const [auditLogs, setAuditLogs] = useState<AuditLog[]>([]);
  const [auditSearch, setAuditSearch] = useState("");
  const [logSources, setLogSources] = useState<LogSource[]>([]);
  const [selectedLogSource, setSelectedLogSource] = useState("");
  const [logTail, setLogTail] = useState<LogTail | null>(null);
  const [adminUsers, setAdminUsers] = useState<AdminUser[]>([]);
  const [roles, setRoles] = useState<AdminRole[]>([]);
  const [permissions, setPermissions] = useState<string[]>([]);
  const [loadingState, setLoadingState] = useState({
    overview: true,
    detail: false,
    action: false,
  });
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const deferredAuditSearch = useDeferredValue(auditSearch);
  const copy = COPY[locale];
  const overviewRequestId = useRef(0);
  const amlOverviewRequestId = useRef(0);
  const amlTransactionsRequestId = useRef(0);
  const logTailRequestId = useRef(0);
  const selectedLogSourceRef = useRef("");
  const refreshOverviewRef = useRef<
    ((options?: { refresh?: boolean; refreshTrends?: boolean }) => Promise<void>) | null
  >(null);
  const apiFailureRef = useRef<(reason: unknown) => boolean>(() => false);

  apiFailureRef.current = (reason: unknown) => {
    if (reason instanceof ApiError && reason.status === 401) {
      onLogout();
      return true;
    }

    setError(
      reason instanceof ApiError ? reason.message : t(locale, "apiError"),
    );
    return false;
  };
  selectedLogSourceRef.current = selectedLogSource;

  const navItems = useMemo(() => {
    const userPermissions = new Set(session.user.permissions);
    return [
      userPermissions.has("dashboard:view") && {
        key: "overview" as const,
        label: t(locale, "overview"),
        code: "01",
      },
      userPermissions.has("dashboard:view") && {
        key: "walletBackend" as const,
        label: t(locale, "walletBackend"),
        code: "02",
      },
      userPermissions.has("chain:view") && {
        key: "chain" as const,
        label: t(locale, "chain"),
        code: "03",
      },
      userPermissions.has("metrics:view") && {
        key: "aml" as const,
        label: t(locale, "aml"),
        code: "04",
      },
      userPermissions.has("logs:view") && {
        key: "logs" as const,
        label: t(locale, "logs"),
        code: "05",
      },
      userPermissions.has("admin-users:manage") && {
        key: "admins" as const,
        label: t(locale, "admins"),
        code: "06",
      },
    ].filter(Boolean) as Array<{ key: TabKey; label: string; code: string }>;
  }, [locale, session.user.permissions]);

  useEffect(() => {
    if (!navItems.some((item) => item.key === activeTab) && navItems[0]) {
      setActiveTab(navItems[0].key);
    }
  }, [activeTab, navItems]);

  const numberFormatter = useMemo(
    () =>
      new Intl.NumberFormat(locale === "vi" ? "vi-VN" : "en-US", {
        maximumFractionDigits: 1,
      }),
    [locale],
  );

  const compactFormatter = useMemo(
    () =>
      new Intl.NumberFormat(locale === "vi" ? "vi-VN" : "en-US", {
        notation: "compact",
        maximumFractionDigits: 1,
      }),
    [locale],
  );

  const refreshOverview = async ({
    refresh = false,
    refreshTrends = false,
  }: {
    refresh?: boolean;
    refreshTrends?: boolean;
  } = {}) => {
    const requestId = overviewRequestId.current + 1;
    overviewRequestId.current = requestId;
    setLoadingState((current) => ({
      ...current,
      overview: current.overview || !overview,
      detail: true,
    }));

    try {
      setError("");
      const shouldLoadTrends =
        refreshTrends || !trendCpu || !trendMemory || !trendConcurrent;
      const [nextOverview, nextTrends] = await Promise.all([
        api.overview(session.accessToken, refresh),
        shouldLoadTrends
          ? api.trends(session.accessToken, [...TREND_METRICS])
          : Promise.resolve(null),
      ]);

      if (requestId !== overviewRequestId.current) {
        return;
      }

      setOverview(nextOverview);

      if (nextTrends) {
        setTrendCpu(nextTrends.series["system.cpuPercent"] ?? null);
        setTrendMemory(nextTrends.series["system.memoryPercent"] ?? null);
        setTrendConcurrent(
          nextTrends.series["wallet.concurrentUsersEstimate"] ?? null,
        );
      }
    } catch (reason) {
      if (requestId !== overviewRequestId.current) {
        return;
      }
      if (apiFailureRef.current(reason)) {
        return;
      }
    } finally {
      if (requestId === overviewRequestId.current) {
        setLoadingState((current) => ({
          ...current,
          overview: false,
          detail: false,
        }));
      }
    }
  };

  refreshOverviewRef.current = refreshOverview;

  useEffect(() => {
    void refreshOverviewRef.current?.({ refreshTrends: true });
    const interval = window.setInterval(() => {
      void refreshOverviewRef.current?.();
    }, 30_000);
    return () => window.clearInterval(interval);
  }, [session.accessToken]);

  useEffect(() => {
    if (activeTab !== "logs") {
      return;
    }

    let active = true;

    const loadLogsWorkspace = async () => {
      setLoadingState((current) => ({ ...current, detail: true }));
      try {
        setError("");
        const [sources, audits] = await Promise.all([
          api.logSources(session.accessToken),
          api.auditLogs(session.accessToken),
        ]);

        if (!active) {
          return;
        }

        setLogSources(sources);
        setAuditLogs(audits);
        const nextSource =
          selectedLogSourceRef.current &&
          sources.some((source) => source.name === selectedLogSourceRef.current)
            ? selectedLogSourceRef.current
            : (sources[0]?.name ?? "");
        setSelectedLogSource(nextSource);
      } catch (reason) {
        if (apiFailureRef.current(reason)) {
          return;
        }
      } finally {
        if (active) {
          setLoadingState((current) => ({ ...current, detail: false }));
        }
      }
    };

    void loadLogsWorkspace();

    return () => {
      active = false;
    };
  }, [activeTab, session.accessToken]);

  useEffect(() => {
    if (activeTab !== "logs" || !selectedLogSource) {
      return;
    }

    let active = true;
    const loadTail = async (withLoading: boolean) => {
      const requestId = logTailRequestId.current + 1;
      logTailRequestId.current = requestId;

      if (withLoading) {
        setLoadingState((current) => ({ ...current, detail: true }));
      }

      try {
        const nextTail = await api.logTail(session.accessToken, selectedLogSource);
        if (!active || requestId !== logTailRequestId.current) {
          return;
        }
        setLogTail(nextTail);
      } catch (reason) {
        if (!active || requestId !== logTailRequestId.current) {
          return;
        }
        if (apiFailureRef.current(reason)) {
          return;
        }
      } finally {
        if (withLoading && active && requestId === logTailRequestId.current) {
          setLoadingState((current) => ({ ...current, detail: false }));
        }
      }
    };

    void loadTail(true);
    const interval = window.setInterval(() => {
      void loadTail(false);
    }, 5000);

    return () => {
      active = false;
      window.clearInterval(interval);
    };
  }, [activeTab, selectedLogSource, session.accessToken]);

  useEffect(() => {
    if (activeTab !== "admins") {
      return;
    }

    let active = true;

    const loadAdminData = async () => {
      setLoadingState((current) => ({ ...current, detail: true }));
      try {
        setError("");
        const [nextUsers, nextRoles, nextPermissions] = await Promise.all([
          api.adminUsers(session.accessToken),
          api.adminRoles(session.accessToken),
          api.permissions(session.accessToken),
        ]);
        if (!active) {
          return;
        }
        setAdminUsers(nextUsers);
        setRoles(nextRoles);
        setPermissions(nextPermissions);
      } catch (reason) {
        if (apiFailureRef.current(reason)) {
          return;
        }
      } finally {
        if (active) {
          setLoadingState((current) => ({ ...current, detail: false }));
        }
      }
    };

    void loadAdminData();

    return () => {
      active = false;
    };
  }, [activeTab, session.accessToken]);

  useEffect(() => {
    if (activeTab !== "aml") {
      return;
    }

    let active = true;

    const loadAmlOverview = async (withLoading = true) => {
      const requestId = amlOverviewRequestId.current + 1;
      amlOverviewRequestId.current = requestId;

      if (withLoading) {
        setLoadingState((current) => ({ ...current, detail: true }));
      }

      try {
        setError("");
        const nextOverview = await api.amlOverview(session.accessToken, 100);
        if (!active || requestId !== amlOverviewRequestId.current) {
          return;
        }
        setAmlOverview(nextOverview);
        const accountIds = nextOverview.accounts.map((item) => item.accountId);
        setAmlSelectedAccountId((current) => {
          if (current && accountIds.includes(current)) {
            return current;
          }
          return accountIds[0] ?? "";
        });
      } catch (reason) {
        if (!active || requestId !== amlOverviewRequestId.current) {
          return;
        }
        apiFailureRef.current(reason);
      } finally {
        if (
          withLoading &&
          active &&
          requestId === amlOverviewRequestId.current
        ) {
          setLoadingState((current) => ({ ...current, detail: false }));
        }
      }
    };

    void loadAmlOverview(true);
    const interval = window.setInterval(() => {
      void loadAmlOverview(false);
    }, 30_000);

    return () => {
      active = false;
      window.clearInterval(interval);
    };
  }, [activeTab, session.accessToken]);

  useEffect(() => {
    if (activeTab !== "aml" || !amlSelectedAccountId) {
      setAmlTransactions([]);
      setAmlTransactionsTotal(0);
      return;
    }

    let active = true;
    const requestId = amlTransactionsRequestId.current + 1;
    amlTransactionsRequestId.current = requestId;

    const loadTransactions = async () => {
      setLoadingState((current) => ({ ...current, detail: true }));
      try {
        setError("");
        const payload = await api.amlAccountTransactions(
          session.accessToken,
          amlSelectedAccountId,
          200,
        );
        if (!active || requestId !== amlTransactionsRequestId.current) {
          return;
        }
        setAmlTransactions(payload.items);
        setAmlTransactionsTotal(payload.total);
      } catch (reason) {
        if (!active || requestId !== amlTransactionsRequestId.current) {
          return;
        }
        apiFailureRef.current(reason);
      } finally {
        if (active && requestId === amlTransactionsRequestId.current) {
          setLoadingState((current) => ({ ...current, detail: false }));
        }
      }
    };

    void loadTransactions();

    return () => {
      active = false;
    };
  }, [activeTab, amlSelectedAccountId, session.accessToken]);


  const filteredAuditLogs = useMemo(() => {
    if (!deferredAuditSearch.trim()) {
      return auditLogs;
    }
    const query = deferredAuditSearch.toLowerCase();
    return auditLogs.filter((log) =>
      [log.actorEmail, log.path, log.outcome, log.action, log.resource]
        .join(" ")
        .toLowerCase()
        .includes(query),
    );
  }, [auditLogs, deferredAuditSearch]);

  const serviceRiskCount =
    overview?.services.items.filter((item) => item.status !== "healthy")
      .length ?? 0;

  const visibleContent = (() => {
    if (!overview) {
      return <StatePanel title={t(locale, "loading")} />;
    }

    switch (activeTab) {
      case "walletBackend":
        return (
          <WalletBackendView
            overview={overview}
            locale={locale}
            compactFormatter={compactFormatter}
            numberFormatter={numberFormatter}
          />
        );
      case "chain":
        return (
          <ChainView
            overview={overview}
            locale={locale}
            compactFormatter={compactFormatter}
            copy={copy}
          />
        );
      case "aml":
        return (
          <AmlView
            locale={locale}
            amlOverview={amlOverview}
            selectedAccountId={amlSelectedAccountId}
            transactions={amlTransactions}
            transactionsTotal={amlTransactionsTotal}
            compactFormatter={compactFormatter}
            numberFormatter={numberFormatter}
            loading={loadingState.detail}
            onSelectAccount={setAmlSelectedAccountId}
            onScanNow={async () => {
              setLoadingState((current) => ({ ...current, detail: true }));
              try {
                setError("");
                const nextOverview = await api.amlScan(session.accessToken);
                setAmlOverview(nextOverview);
                const accountIds = nextOverview.accounts.map(
                  (item) => item.accountId,
                );
                setAmlSelectedAccountId((current) => {
                  if (current && accountIds.includes(current)) {
                    return current;
                  }
                  return accountIds[0] ?? "";
                });
              } catch (reason) {
                apiFailureRef.current(reason);
              } finally {
                setLoadingState((current) => ({ ...current, detail: false }));
              }
            }}
          />
        );
      case "logs":
        return (
          <LogsView
            locale={locale}
            copy={copy}
            logSources={logSources}
            selectedLogSource={selectedLogSource}
            onSelectLogSource={setSelectedLogSource}
            logTail={logTail}
            auditLogs={filteredAuditLogs}
            auditSearch={auditSearch}
            onAuditSearchChange={setAuditSearch}
            onReloadLogs={async () => {
              if (!selectedLogSource) {
                return;
              }
              setLoadingState((current) => ({ ...current, detail: true }));
              try {
                setError("");
                const [tail, audits] = await Promise.all([
                  api.logTail(session.accessToken, selectedLogSource),
                  api.auditLogs(session.accessToken),
                ]);
                setLogTail(tail);
                setAuditLogs(audits);
              } catch (reason) {
                apiFailureRef.current(reason);
              } finally {
                setLoadingState((current) => ({ ...current, detail: false }));
              }
            }}
          />
        );
      case "admins":
        return (
          <AdminsView
            locale={locale}
            copy={copy}
            roles={roles}
            users={adminUsers}
            permissions={permissions}
            actionLoading={loadingState.action}
            onCreate={async (payload) => {
              setLoadingState((current) => ({ ...current, action: true }));
              setMessage("");
              try {
                setError("");
                await api.createAdminUser(session.accessToken, payload);
                setAdminUsers(await api.adminUsers(session.accessToken));
                setMessage(t(locale, "createAccount"));
                return true;
              } catch (reason) {
                apiFailureRef.current(reason);
                return false;
              } finally {
                setLoadingState((current) => ({ ...current, action: false }));
              }
            }}
            onToggleUser={async (user) => {
              setLoadingState((current) => ({ ...current, action: true }));
              try {
                setError("");
                const updated = await api.updateAdminUser(
                  session.accessToken,
                  user.id,
                  {
                    isActive: !user.isActive,
                  },
                );
                setAdminUsers((current) =>
                  current.map((item) =>
                    item.id === updated.id ? updated : item,
                  ),
                );
              } catch (reason) {
                apiFailureRef.current(reason);
              } finally {
                setLoadingState((current) => ({ ...current, action: false }));
              }
            }}
          />
        );
      case "overview":
      default:
        return (
          <OverviewView
            overview={overview}
            locale={locale}
            compactFormatter={compactFormatter}
            numberFormatter={numberFormatter}
            trendCpu={trendCpu}
            trendMemory={trendMemory}
            trendConcurrent={trendConcurrent}
            copy={copy}
          />
        );
    }
  })();

  return (
    <div className="dashboard-shell">
      <aside className="side-rail">
        <div className="side-rail__header">
          <div className="side-rail__brand">
            <img src="/logo.png" alt="Kufi Logo" className="kufi-logo" />
            <span>Kufi Monitoring<br />System</span>
          </div>
        </div>

        <div className="rail-status-card">
          <StatusBadge locale={locale} status={overview?.status ?? "warning"} />
          <dl className="rail-status-card__grid">
            <div>
              <dt>{t(locale, "activeAlerts")}</dt>
              <dd>{overview ? overview.alerts.length : "n/a"}</dd>
            </div>
            <div>
              <dt>{copy.serviceExposure}</dt>
              <dd>{overview ? serviceRiskCount : "n/a"}</dd>
            </div>
            <div>
              <dt>{COPY[locale].connectedNodes}</dt>
              <dd>{overview ? overview.chain.activeNodes : "n/a"}</dd>
            </div>
            <div>
              <dt>{t(locale, "activeSessions")}</dt>
              <dd>
                {overview
                  ? formatMetric(
                      compactFormatter,
                      overview.wallet.activeSessions,
                    )
                  : "n/a"}
              </dd>
            </div>
          </dl>
        </div>

        <nav className="side-rail__nav">
          {navItems.map((item) => (
            <button
              key={item.key}
              className={
                item.key === activeTab ? "nav-card active" : "nav-card"
              }
              onClick={() => startTransition(() => setActiveTab(item.key))}
              type="button"
            >
              <span className="nav-card__indicator" />
              <span className="nav-card__label">{item.label}</span>
            </button>
          ))}
        </nav>

        <div className="operator-card">
          <span className="eyebrow">{copy.operatorProfile}</span>
          <strong>{session.user.displayName}</strong>
          <small>{session.user.title}</small>
        </div>
      </aside>

      <main className={`workspace workspace--${activeTab}`}>
        <header className="masthead">
          <div className="masthead__topbar">
            <div className="masthead__copy">
              <span className="eyebrow">Kufi Monitoring</span>
              <div className="masthead__title-row">
                <h1>{navItems.find((item) => item.key === activeTab)?.label}</h1>
                <StatusBadge
                  locale={locale}
                  status={overview?.status ?? "warning"}
                />
              </div>
            </div>

            <div className="masthead__controls">
              <div className="locale-switch locale-switch--compact">
                <button
                  className={
                    locale === "vi"
                      ? "locale-switch__button active"
                      : "locale-switch__button"
                  }
                  onClick={() => onLocaleChange("vi")}
                  type="button"
                  aria-label="Tiếng Việt"
                  title="Tiếng Việt"
                >
                  <span className="locale-switch__emoji" aria-hidden="true">
                    {flagEmoji("vi")}
                  </span>
                </button>
                <button
                  className={
                    locale === "en"
                      ? "locale-switch__button active"
                      : "locale-switch__button"
                  }
                  onClick={() => onLocaleChange("en")}
                  type="button"
                  aria-label="English"
                  title="English"
                >
                  <span className="locale-switch__emoji" aria-hidden="true">
                    {flagEmoji("en")}
                  </span>
                </button>
              </div>

              <div className="masthead__actions">
                <button
                  className="secondary-button"
                  disabled={loadingState.detail}
                  onClick={() => {
                    setMessage("");
                    void refreshOverview({ refresh: true, refreshTrends: true });
                  }}
                  type="button"
                >
                  {loadingState.detail ? t(locale, "loading") : t(locale, "refreshNow")}
                </button>
                <button className="ghost-button" onClick={onLogout} type="button">
                  {t(locale, "signOut")}
                </button>
              </div>
            </div>
          </div>

          <div className="masthead__meta">
            <div className="masthead__chips">
              <ValuePill
                label={t(locale, "activeAlerts")}
                value={overview ? String(overview.alerts.length) : "n/a"}
              />
              <ValuePill
                label={t(locale, "concurrentUsers")}
                value={
                  overview
                    ? formatMetric(
                        compactFormatter,
                        overview.wallet.concurrentUsersEstimate,
                      )
                    : "n/a"
                }
              />
              <ValuePill
                label={copy.serviceExposure}
                value={overview ? String(serviceRiskCount) : "n/a"}
              />
              <ValuePill
                label={COPY[locale].connectedNodes}
                value={overview ? String(overview.chain.activeNodes) : "n/a"}
              />
            </div>

            <section className="command-card">
              <span className="eyebrow">{copy.lastSnapshot}</span>
              <strong>
                {overview
                  ? formatCompactDateTime(locale, overview.generatedAt)
                  : t(locale, "loading")}
              </strong>
              <p>
                {overview
                  ? locale === "vi"
                    ? `${overview.services.totalCount} dịch vụ · ${overview.chain.configuredNodes} node chain`
                    : `${overview.services.totalCount} services · ${overview.chain.configuredNodes} chain nodes`
                  : t(locale, "loading")}
              </p>
            </section>
          </div>

        </header>

        {message ? (
          <div className="inline-banner inline-banner--success">{message}</div>
        ) : null}
        {error ? (
          <div className="inline-banner inline-banner--error">{error}</div>
        ) : null}

        {visibleContent}
      </main>
    </div>
  );
}

function OverviewView({
  overview,
  locale,
  compactFormatter,
  numberFormatter,
  trendCpu,
  trendMemory,
  trendConcurrent,
  copy,
}: {
  overview: MonitoringOverview;
  locale: Locale;
  compactFormatter: Intl.NumberFormat;
  numberFormatter: Intl.NumberFormat;
  trendCpu: TimeseriesResponse | null;
  trendMemory: TimeseriesResponse | null;
  trendConcurrent: TimeseriesResponse | null;
  copy: (typeof COPY)[Locale];
}) {
  const firstAlert = overview.alerts[0];
  const orderedServices = [...overview.services.items].sort(compareStatusOrder);
  const walletNote = resolveWalletNote(
    locale,
    overview.wallet.source,
    overview.wallet.note,
  );
  const warehouseNote = resolveWarehouseNote(locale, overview.dataWarehouse.note);
  const attentionNote = firstAlert
    ? firstAlert.recommendedAction
    : overview.status === "critical"
      ? t(locale, "systemCriticalSummary")
      : overview.status === "warning"
        ? t(locale, "systemWarningSummary")
        : t(locale, "systemStableSummary");

  return (
    <div className="page-grid page-grid--overview">
      <section className="panel panel--wide overview-brief">
        <div className="overview-brief__content">
          <div>
            <span className="eyebrow">{t(locale, "currentStatus")}</span>
            <h2>
              {overview.alerts.length > 0
                ? (firstAlert?.title ?? "n/a")
                : t(locale, "noAlerts")}
            </h2>
            <p>{attentionNote}</p>
          </div>

          <div className="overview-brief__chips">
            <ValuePill
              label={copy.walletCoverage}
              value={resolveWalletSourceLabel(overview.wallet.source, copy)}
            />
            <ValuePill
              label={copy.warehouseLane}
              value={
                overview.dataWarehouse.ready
                  ? t(locale, "dwReady")
                  : t(locale, "dwPending")
              }
            />
          </div>
        </div>
      </section>

      <div className="metric-grid">
        <MetricCard
          label={t(locale, "activeAlerts")}
          value={String(overview.alerts.length)}
          caption={firstAlert ? firstAlert.severity : t(locale, "statusHealthy")}
          tone={overview.alerts.length > 0 ? "critical" : "healthy"}
        />
        <MetricCard
          label={t(locale, "activeSessions")}
          value={formatMetric(compactFormatter, overview.wallet.activeSessions)}
          caption={t(locale, "sessionSource")}
          tone="neutral"
        />
        <MetricCard
          label={t(locale, "concurrentUsers")}
          value={formatMetric(
            compactFormatter,
            overview.wallet.concurrentUsersEstimate,
          )}
          caption={t(locale, "rollingWindow")}
          tone={toneFromThreshold(
            overview.wallet.concurrentUsersEstimate,
            250,
            500,
          )}
        />
        <MetricCard
          label={t(locale, "activeChainNodes")}
          value={String(overview.chain.activeNodes)}
          caption={`${overview.chain.activeNodes}/${overview.chain.configuredNodes}`}
          tone={
            overview.chain.activeNodes === overview.chain.configuredNodes
              ? "healthy"
              : "warning"
          }
        />
        <MetricCard
          label={t(locale, "cpu")}
          value={`${numberFormatter.format(overview.system.cpuPercent)}%`}
          caption={`${t(locale, "loadAverage1m")} · ${numberFormatter.format(overview.system.loadAverage1m)}`}
          tone={toneFromThreshold(overview.system.cpuPercent, 65, 85)}
        />
        <MetricCard
          label={t(locale, "memory")}
          value={`${numberFormatter.format(overview.system.memoryPercent)}%`}
          caption={`${numberFormatter.format(overview.system.memoryUsedGb)} / ${numberFormatter.format(overview.system.memoryTotalGb)} GB`}
          tone={toneFromThreshold(overview.system.memoryPercent, 70, 85)}
        />
        <MetricCard
          label={t(locale, "disk")}
          value={`${numberFormatter.format(overview.system.diskPercent)}%`}
          caption={`${numberFormatter.format(overview.system.diskUsedGb)} / ${numberFormatter.format(overview.system.diskTotalGb)} GB`}
          tone={toneFromThreshold(overview.system.diskPercent, 75, 90)}
        />
        <MetricCard
          label={t(locale, "networkIn")}
          value={`${numberFormatter.format(overview.system.networkRxMbps)} Mbps`}
          caption={t(locale, "live")}
          tone="neutral"
        />
        <MetricCard
          label={t(locale, "networkOut")}
          value={`${numberFormatter.format(overview.system.networkTxMbps)} Mbps`}
          caption={t(locale, "live")}
          tone="neutral"
        />
        <MetricCard
          label={t(locale, "uptime")}
          value={formatHours(locale, numberFormatter, overview.system.uptimeHours)}
          caption={t(locale, "sinceBoot")}
          tone="healthy"
        />
      </div>

      <div className="split-grid split-grid--analytics">
        <section className="panel">
          <div className="panel__header">
            <div>
              <span className="eyebrow">{copy.trendWindow}</span>
              <h2>{t(locale, "serviceHealth")}</h2>
            </div>
          </div>
          <div className="trend-grid">
            <SparklineCard
              locale={locale}
              label={t(locale, "cpu")}
              unit="%"
              series={trendCpu}
            />
            <SparklineCard
              locale={locale}
              label={t(locale, "memory")}
              unit="%"
              series={trendMemory}
            />
            <SparklineCard
              locale={locale}
              label={t(locale, "concurrentUsers")}
              unit=""
              series={trendConcurrent}
            />
          </div>
        </section>

        <section className="panel">
          <div className="panel__header">
            <div>
              <span className="eyebrow">{copy.attentionLane}</span>
              <h2>{t(locale, "activeAlerts")}</h2>
            </div>
            <strong>{overview.alerts.length}</strong>
          </div>
          <AlertList locale={locale} alerts={overview.alerts} />
        </section>
      </div>

      <div className="insight-grid">
        <section className="panel">
          <div className="panel__header">
            <div>
              <span className="eyebrow">{copy.walletCoverage}</span>
              <h2>{t(locale, "walletTelemetry")}</h2>
            </div>
            <StatusBadge locale={locale} status={overview.status} />
          </div>
          <div className="mini-metric-grid">
            <MiniMetric
              label={t(locale, "activeSessions")}
              value={formatMetric(
                compactFormatter,
                overview.wallet.activeSessions,
              )}
            />
            <MiniMetric
              label={t(locale, "concurrentUsers")}
              value={formatMetric(
                compactFormatter,
                overview.wallet.concurrentUsersEstimate,
              )}
            />
            <MiniMetric
              label={copy.activeUsersLabel}
              value={formatMetric(
                compactFormatter,
                overview.wallet.activeUsers,
              )}
            />
            <MiniMetric
              label={copy.totalUsersLabel}
              value={formatMetric(compactFormatter, overview.wallet.totalUsers)}
            />
          </div>
          {overview.wallet.source !== "readonly_db" ? (
            <p className="panel__note">{walletNote}</p>
          ) : null}
        </section>

        <section className="panel">
          <div className="panel__header">
            <div>
              <span className="eyebrow">{copy.warehouseLane}</span>
              <h2>{t(locale, "dataWarehouse")}</h2>
            </div>
            <StatusBadge
              locale={locale}
              status={overview.dataWarehouse.ready ? "healthy" : "warning"}
            />
          </div>
          <p className="panel__note">{warehouseNote}</p>
        </section>
      </div>

      <section className="panel panel--wide">
        <div className="panel__header">
          <div>
            <span className="eyebrow">{t(locale, "serviceGrid")}</span>
            <h2>{t(locale, "serviceGrid")}</h2>
          </div>
          <strong>
            {overview.services.healthyCount}/{overview.services.totalCount}
          </strong>
        </div>
        <div className="table-shell">
          <table>
            <thead>
              <tr>
                <th>{t(locale, "serviceGrid")}</th>
                <th>{t(locale, "statusHealthy")}</th>
                <th>{t(locale, "latency")}</th>
                <th>{t(locale, "httpStatus")}</th>
                <th>URL</th>
                <th>{t(locale, "detail")}</th>
              </tr>
            </thead>
            <tbody>
              {orderedServices.map((item) => (
                <tr key={item.name}>
                  <td>{item.name}</td>
                  <td>
                    <StatusBadge locale={locale} status={item.status} />
                  </td>
                  <td>{item.latencyMs ? `${item.latencyMs} ms` : "n/a"}</td>
                  <td>{item.httpStatus ?? "n/a"}</td>
                  <td>{item.url}</td>
                  <td>{item.detail ?? "n/a"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

function WalletBackendView({
  overview,
  locale,
  compactFormatter,
  numberFormatter,
}: {
  overview: MonitoringOverview;
  locale: Locale;
  compactFormatter: Intl.NumberFormat;
  numberFormatter: Intl.NumberFormat;
}) {
  const services = [...overview.services.items].sort(compareStatusOrder);
  const healthyCount = services.filter((item) => item.status === "healthy").length;
  const warningCount = services.filter((item) => item.status === "warning").length;
  const criticalCount = services.filter((item) => item.status === "critical").length;
  const unknownCount = services.filter((item) => item.status === "unknown").length;
  const totalCount = services.length;

  const availabilityRatio =
    totalCount === 0 ? null : (healthyCount / totalCount) * 100;
  const latencyValues = services
    .map((item) => item.latencyMs)
    .filter((value): value is number => typeof value === "number")
    .sort((left, right) => left - right);
  const averageLatency =
    latencyValues.length === 0
      ? null
      : latencyValues.reduce((sum, value) => sum + value, 0) /
        latencyValues.length;
  const p95Latency = percentile(latencyValues, 95);
  const slowestService = services
    .filter((item) => typeof item.latencyMs === "number")
    .sort((left, right) => (right.latencyMs ?? 0) - (left.latencyMs ?? 0))[0];

  const statusHeadline =
    criticalCount > 0
      ? locale === "vi"
        ? `Phát hiện ${criticalCount} dịch vụ đang ở trạng thái nghiêm trọng.`
        : `${criticalCount} service(s) are in critical state.`
      : warningCount > 0
        ? locale === "vi"
          ? `Có ${warningCount} dịch vụ cần theo dõi thêm.`
          : `${warningCount} service(s) require close monitoring.`
        : locale === "vi"
          ? "Tất cả dịch vụ wallet backend đang ổn định."
          : "All wallet backend services are healthy.";

  return (
    <div className="page-grid page-grid--wallet">
      <section className="panel panel--wide overview-brief">
        <div className="overview-brief__content">
          <div>
            <span className="eyebrow">Kufi wallet backend</span>
            <h2>{statusHeadline}</h2>
          </div>

          <div className="overview-brief__chips">
            <ValuePill
              label={locale === "vi" ? "Tổng dịch vụ" : "Total services"}
              value={String(totalCount)}
            />
            <ValuePill
              label={locale === "vi" ? "Ổn định" : "Healthy"}
              value={String(healthyCount)}
            />
            <ValuePill
              label={locale === "vi" ? "Cảnh báo/Nghiêm trọng" : "Warning/Critical"}
              value={`${warningCount}/${criticalCount}`}
            />
          </div>
        </div>
      </section>

      <div className="metric-grid">
        <MetricCard
          label={locale === "vi" ? "Dịch vụ ổn định" : "Healthy services"}
          value={`${healthyCount}/${totalCount}`}
          caption={
            locale === "vi"
              ? "Toàn bộ microservices"
              : "Across all microservices"
          }
          tone={healthyCount === totalCount && totalCount > 0 ? "healthy" : "warning"}
        />
        <MetricCard
          label={locale === "vi" ? "Dịch vụ cảnh báo" : "Warning services"}
          value={String(warningCount)}
          caption={
            locale === "vi" ? "Cần giám sát gần" : "Require close monitoring"
          }
          tone={warningCount > 0 ? "warning" : "healthy"}
        />
        <MetricCard
          label={locale === "vi" ? "Dịch vụ nghiêm trọng" : "Critical services"}
          value={String(criticalCount)}
          caption={
            locale === "vi" ? "Cần xử lý ngay" : "Need immediate response"
          }
          tone={criticalCount > 0 ? "critical" : "healthy"}
        />
        <MetricCard
          label={locale === "vi" ? "Dịch vụ chưa rõ trạng thái" : "Unknown services"}
          value={String(unknownCount)}
          caption={
            locale === "vi" ? "Trạng thái chưa xác định" : "State not confirmed"
          }
          tone={unknownCount > 0 ? "warning" : "neutral"}
        />
        <MetricCard
          label="Availability"
          value={
            typeof availabilityRatio === "number"
              ? `${numberFormatter.format(availabilityRatio)}%`
              : "n/a"
          }
          caption={
            locale === "vi" ? "Ổn định / tổng dịch vụ" : "Healthy / total services"
          }
          tone={
            typeof availabilityRatio === "number"
              ? toneFromThreshold(availabilityRatio, 95, 99)
              : "neutral"
          }
        />
        <MetricCard
          label={locale === "vi" ? "Độ trễ trung bình" : "Average latency"}
          value={
            typeof averageLatency === "number"
              ? `${numberFormatter.format(averageLatency)} ms`
              : "n/a"
          }
          caption="Health endpoint"
          tone={
            typeof averageLatency === "number"
              ? toneFromThreshold(averageLatency, 600, 1500)
              : "neutral"
          }
        />
        <MetricCard
          label={locale === "vi" ? "Độ trễ p95" : "P95 latency"}
          value={
            typeof p95Latency === "number"
              ? `${numberFormatter.format(p95Latency)} ms`
              : "n/a"
          }
          caption="Tail latency"
          tone={
            typeof p95Latency === "number"
              ? toneFromThreshold(p95Latency, 900, 1800)
              : "neutral"
          }
        />
        <MetricCard
          label={locale === "vi" ? "Dịch vụ chậm nhất" : "Slowest service"}
          value={slowestService?.name ?? "n/a"}
          caption={
            typeof slowestService?.latencyMs === "number"
              ? `${compactFormatter.format(slowestService.latencyMs)} ms`
              : locale === "vi"
                ? "Không có dữ liệu"
                : "No latency data"
          }
          tone={
            typeof slowestService?.latencyMs === "number"
              ? toneFromThreshold(slowestService.latencyMs, 900, 1800)
              : "neutral"
          }
        />
      </div>

      <section className="panel panel--wide">
        <div className="panel__header">
          <div>
            <span className="eyebrow">Kufi wallet backend</span>
            <h2>{locale === "vi" ? "Tình trạng từng dịch vụ" : "Per-service health"}</h2>
          </div>
          <strong>{totalCount}</strong>
        </div>

        <div className="table-shell">
          <table>
            <thead>
              <tr>
                <th>{t(locale, "serviceGrid")}</th>
                <th>{t(locale, "statusHealthy")}</th>
                <th>{t(locale, "httpStatus")}</th>
                <th>{t(locale, "latency")}</th>
                <th>{t(locale, "lastChecked")}</th>
                <th>{t(locale, "endpoint")}</th>
                <th>{t(locale, "detail")}</th>
              </tr>
            </thead>
            <tbody>
              {services.map((service) => (
                <tr key={service.name}>
                  <td>{service.name}</td>
                  <td>
                    <StatusBadge locale={locale} status={service.status} />
                  </td>
                  <td>{service.httpStatus ?? "n/a"}</td>
                  <td>
                    {typeof service.latencyMs === "number"
                      ? `${compactFormatter.format(service.latencyMs)} ms`
                      : "n/a"}
                  </td>
                  <td>{formatDate(locale, service.lastCheckedAt)}</td>
                  <td>{service.url}</td>
                  <td>{service.detail ?? "n/a"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

function ChainView({
  overview,
  locale,
  compactFormatter,
  copy,
}: {
  overview: MonitoringOverview;
  locale: Locale;
  compactFormatter: Intl.NumberFormat;
  copy: (typeof COPY)[Locale];
}) {
  const orderedNodes = [...overview.chain.nodes].sort(compareStatusOrder);
  const totalPendingRequests = overview.chain.nodes.reduce(
    (sum, node) => sum + node.pendingRequests,
    0,
  );
  const averagePeers = average(
    overview.chain.nodes
      .filter((node) => node.status !== "critical")
      .map((node) => node.knownPeers),
  );
  const ordererNodes = overview.chain.nodes.filter((node) => {
    const role = node.role.toLowerCase();
    const name = node.name.toLowerCase();
    return (
      role.includes("orderer") ||
      name.includes("orderer") ||
      node.url.includes(":9500")
    );
  });
  const activeOrdererCount = ordererNodes.filter(
    (node) => node.status === "healthy",
  ).length;
  const ordererStatus =
    ordererNodes.length === 0
      ? "unknown"
      : ordererNodes.some((node) => node.status === "critical")
        ? "critical"
        : ordererNodes.some(
              (node) => node.status === "warning" || node.status === "unknown",
            )
          ? "warning"
          : "healthy";
  const ordererLabel = locale === "vi" ? "Trạng thái orderer" : "Orderer status";
  const nodeLabel = locale === "vi" ? "Node" : "Node";

  return (
    <div className="page-grid page-grid--chain">
      <section className="panel panel--wide overview-brief">
        <div className="overview-brief__content">
          <div>
            <span className="eyebrow">{copy.chainFocus}</span>
            <h2>
              {overview.chain.anomalies[0]?.message ?? t(locale, "noAnomalies")}
            </h2>
            <p>
              Gateway {statusLabel(locale, overview.chain.gatewayStatus).toLowerCase()}
              {" · "}
              Fabric {overview.chain.fabricStatus}
            </p>
          </div>

          <div className="overview-brief__chips">
            <ValuePill
              label={copy.connectedNodes}
              value={`${overview.chain.activeNodes}/${overview.chain.configuredNodes}`}
            />
            <ValuePill
              label={copy.governanceQueue}
              value={String(totalPendingRequests)}
            />
            <ValuePill
              label={copy.averagePeers}
              value={compactFormatter.format(averagePeers)}
            />
          </div>
        </div>
      </section>

      <div className="metric-grid">
        <MetricCard
          label={t(locale, "chainGateway")}
          value={statusLabel(locale, overview.chain.gatewayStatus)}
          caption={overview.chain.fabricStatus}
          tone={toneFromStatus(overview.chain.gatewayStatus)}
        />
        <MetricCard
          label={COPY[locale].connectedNodes}
          value={String(overview.chain.activeNodes)}
          caption={`${overview.chain.activeNodes}/${overview.chain.configuredNodes}`}
          tone={
            overview.chain.activeNodes === overview.chain.configuredNodes
              ? "healthy"
              : "warning"
          }
        />
        <MetricCard
          label={copy.governanceQueue}
          value={String(totalPendingRequests)}
          caption={t(locale, "pendingRequests")}
          tone={totalPendingRequests > 0 ? "warning" : "healthy"}
        />
        <MetricCard
          label={copy.averagePeers}
          value={compactFormatter.format(averagePeers)}
          caption={copy.chainFocus}
          tone="neutral"
        />
        <MetricCard
          label={ordererLabel}
          value={`${activeOrdererCount}/${ordererNodes.length}`}
          caption={statusLabel(locale, ordererStatus)}
          tone={toneFromStatus(ordererStatus)}
        />
      </div>

      <div className="split-grid">
        <section className="panel">
          <div className="panel__header">
            <div>
              <span className="eyebrow">{copy.chainFocus}</span>
              <h2>{t(locale, "anomalies")}</h2>
            </div>
            <strong>{overview.chain.anomalies.length}</strong>
          </div>
          <AlertList
            locale={locale}
            alerts={overview.chain.anomalies.map((item) => ({
              code: item.code,
              severity: item.severity,
              title: item.message,
              recommendedAction:
                item.severity === "critical"
                  ? copy.inspectCriticalNode
                  : copy.reviewChainWarning,
              metric: "chain",
              currentValue: item.message,
              threshold: "stable",
            }))}
          />
        </section>

        <section className="panel">
          <div className="panel__header">
            <div>
              <span className="eyebrow">{copy.commandDeck}</span>
              <h2>{t(locale, "chainTopology")}</h2>
            </div>
            <StatusBadge
              locale={locale}
              status={overview.chain.gatewayStatus}
            />
          </div>
          <div className="mini-metric-grid">
            <MiniMetric
              label={t(locale, "gatewayFabric")}
              value={overview.chain.fabricStatus}
            />
            <MiniMetric
              label={copy.connectedNodes}
              value={`${overview.chain.activeNodes}/${overview.chain.configuredNodes}`}
            />
            <MiniMetric
              label={copy.governanceQueue}
              value={String(totalPendingRequests)}
            />
            <MiniMetric
              label={copy.averagePeers}
              value={compactFormatter.format(averagePeers)}
            />
            <MiniMetric
              label={ordererLabel}
              value={`${activeOrdererCount}/${ordererNodes.length}`}
            />
          </div>
        </section>
      </div>

      <section className="panel panel--wide">
        <div className="panel__header">
          <div>
            <span className="eyebrow">{t(locale, "chainTopology")}</span>
            <h2>{t(locale, "chainTopology")}</h2>
          </div>
        </div>
        <div className="table-shell">
          <table>
            <thead>
              <tr>
                <th>{nodeLabel}</th>
                <th>{t(locale, "statusHealthy")}</th>
                <th>{t(locale, "role")}</th>
                <th>MSP</th>
                <th>{t(locale, "knownPeers")}</th>
                <th>{t(locale, "pendingRequests")}</th>
                <th>{t(locale, "latency")}</th>
                <th>URL</th>
              </tr>
            </thead>
            <tbody>
              {orderedNodes.map((node) => (
                <tr key={node.name}>
                  <td>{node.name}</td>
                  <td>
                    <StatusBadge locale={locale} status={node.status} />
                  </td>
                  <td>{node.role}</td>
                  <td>{node.mspId}</td>
                  <td>{node.knownPeers}</td>
                  <td>{node.pendingRequests}</td>
                  <td>{node.latencyMs ? `${node.latencyMs} ms` : "n/a"}</td>
                  <td>{node.url}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

function AmlView({
  locale,
  amlOverview,
  selectedAccountId,
  transactions,
  transactionsTotal,
  compactFormatter,
  numberFormatter,
  loading,
  onSelectAccount,
  onScanNow,
}: {
  locale: Locale;
  amlOverview: AmlOverview | null;
  selectedAccountId: string;
  transactions: AmlAccountTransaction[];
  transactionsTotal: number;
  compactFormatter: Intl.NumberFormat;
  numberFormatter: Intl.NumberFormat;
  loading: boolean;
  onSelectAccount: (accountId: string) => void;
  onScanNow: () => void;
}) {
  if (!amlOverview) {
    return <StatePanel title={t(locale, "loading")} />;
  }

  const selectedAccount =
    amlOverview.accounts.find((item) => item.accountId === selectedAccountId) ??
    null;
  const orderedAccounts = [...amlOverview.accounts].sort(
    (left, right) => right.maxFraudProbability - left.maxFraudProbability,
  );
  const topRisk =
    orderedAccounts.length === 0
      ? "LOW"
      : orderedAccounts[0]?.riskLevel ?? "LOW";

  const amlStatusTone =
    amlOverview.status === "error"
      ? "critical"
      : amlOverview.status === "busy"
        ? "warning"
        : "healthy";

  return (
    <div className="page-grid page-grid--aml aml-layout">
      <section className="panel panel--wide overview-brief aml-hero">
        <div className="overview-brief__content">
          <div>
            <span className="eyebrow">{t(locale, "amlOverview")}</span>
            <h2>
              {amlOverview.configured
                ? amlOverview.error
                  ? t(locale, "amlScanError")
                  : t(locale, "amlFlaggedAccounts")
                : t(locale, "amlNotConfigured")}
            </h2>
            <p>
              {amlOverview.generatedAt
                ? `${t(locale, "amlLastScan")}: ${formatDate(locale, amlOverview.generatedAt)}`
                : t(locale, "amlSelectAccountHint")}
            </p>
          </div>
          <div className="overview-brief__chips aml-overview-grid">
            <ValuePill
              label={t(locale, "amlFlaggedAccounts")}
              value={String(amlOverview.flaggedAccounts)}
            />
            <ValuePill
              label={t(locale, "amlFlaggedTransactions")}
              value={String(amlOverview.flaggedTransactions)}
            />
            <ValuePill
              label={t(locale, "amlRiskLevel")}
              value={topRisk}
            />
          </div>
        </div>
      </section>

      <div className="metric-grid">
        <MetricCard
          label={t(locale, "amlFlaggedAccounts")}
          value={String(amlOverview.flaggedAccounts)}
          caption={t(locale, "amlOverview")}
          tone={
            amlOverview.flaggedAccounts > 0
              ? "warning"
              : "healthy"
          }
        />
        <MetricCard
          label={t(locale, "amlFlaggedTransactions")}
          value={String(amlOverview.flaggedTransactions)}
          caption={t(locale, "amlTransactions")}
          tone={
            amlOverview.flaggedTransactions > 0
              ? "warning"
              : "healthy"
          }
        />
        <MetricCard
          label={t(locale, "serviceGrid")}
          value={String(amlOverview.totalTransactions)}
          caption={t(locale, "amlLookbackHours")}
          tone="neutral"
        />
        <MetricCard
          label={t(locale, "amlLookbackHours")}
          value={`${numberFormatter.format(amlOverview.lookbackHours)}h`}
          caption={t(locale, "amlOverview")}
          tone="neutral"
        />
        <MetricCard
          label={t(locale, "amlLastScan")}
          value={
            amlOverview.generatedAt
              ? formatCompactDateTime(locale, amlOverview.generatedAt)
              : "n/a"
          }
          caption={
            amlOverview.scanDurationMs != null
              ? `${numberFormatter.format(amlOverview.scanDurationMs)} ms`
              : "n/a"
          }
          tone={amlStatusTone}
        />
        <MetricCard
          label={t(locale, "currentStatus")}
          value={amlOverview.status}
          caption={amlOverview.error ?? "ok"}
          tone={amlStatusTone}
        />
      </div>

      <div className="split-grid">
        <section className="panel">
          <div className="panel__header">
            <div>
              <span className="eyebrow">{t(locale, "amlOverview")}</span>
              <h2>{t(locale, "amlFlaggedAccounts")}</h2>
            </div>
            <button
              className="secondary-button"
              onClick={onScanNow}
              disabled={loading || !amlOverview.configured}
              type="button"
            >
              {t(locale, "amlRunScan")}
            </button>
          </div>

          {!amlOverview.configured ? (
            <EmptyState message={t(locale, "amlNotConfigured")} />
          ) : orderedAccounts.length === 0 ? (
            <EmptyState message={t(locale, "amlNoFlaggedAccounts")} />
          ) : (
            <div className="table-shell">
              <table>
                <thead>
                  <tr>
                    <th>{t(locale, "amlAccount")}</th>
                    <th>{t(locale, "amlRiskLevel")}</th>
                    <th>{t(locale, "amlFlaggedTransactions")}</th>
                    <th>{t(locale, "serviceGrid")}</th>
                    <th>p(max)</th>
                  </tr>
                </thead>
                <tbody>
                  {orderedAccounts.map((account) => (
                    <tr key={account.accountId}>
                      <td className="aml-account-id">
                        <button
                          className={
                            account.accountId === selectedAccountId
                              ? "ghost-button ghost-button--compact active-row-button"
                              : "ghost-button ghost-button--compact active-row-button"
                          }
                          onClick={() => onSelectAccount(account.accountId)}
                          type="button"
                        >
                          {account.accountId}
                        </button>
                      </td>
                      <td>
                        <span
                          className={`status-badge status-badge--${toneFromAmlRisk(account.riskLevel)}`}
                        >
                          <span
                            aria-hidden="true"
                            className="status-badge__dot"
                          />
                          {account.riskLevel}
                        </span>
                      </td>
                      <td>
                        {account.flaggedTransactions}/{account.totalTransactions}
                      </td>
                      <td>{numberFormatter.format(account.totalTransactions)}</td>
                      <td>{account.maxFraudProbability.toFixed(6)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <section className="panel">
          <div className="panel__header">
            <div>
              <span className="eyebrow">{t(locale, "amlTransactions")}</span>
              <h2>{selectedAccount?.accountId ?? t(locale, "amlTransactions")}</h2>
              <p className="panel__note">
                {locale === "vi"
                  ? "Tất cả số tiền được hiển thị theo đơn vị VND."
                  : "All monetary values are displayed in VND."}
              </p>
            </div>
            <strong>{compactFormatter.format(transactionsTotal)}</strong>
          </div>

          {!selectedAccount ? (
            <EmptyState message={t(locale, "amlSelectAccountHint")} />
          ) : (
            <>
              <div className="mini-metric-grid">
                <MiniMetric
                  label={t(locale, "amlFlaggedTransactions")}
                  value={`${selectedAccount.flaggedTransactions}/${selectedAccount.totalTransactions}`}
                />
                <MiniMetric
                  label={t(locale, "amlRiskLevel")}
                  value={selectedAccount.riskLevel}
                />
                <MiniMetric
                  label={t(locale, "amlMuleAccount")}
                  value={
                    selectedAccount.isMuleAccount
                      ? t(locale, "yes")
                      : t(locale, "no")
                  }
                />
                <MiniMetric
                  label={t(locale, "latency")}
                  value={
                    amlOverview.scanDurationMs != null
                      ? `${numberFormatter.format(amlOverview.scanDurationMs)} ms`
                      : "n/a"
                  }
                />
              </div>

              <div className="table-shell">
                <table>
                  <thead>
                    <tr>
                      <th>{t(locale, "timestamp")}</th>
                      <th>{t(locale, "amlDirection")}</th>
                      <th>{t(locale, "amlCounterparty")}</th>
                      <th>{t(locale, "amlFlaggedTransactions")}</th>
                      <th>{t(locale, "amlRiskLevel")}</th>
                      <th>{t(locale, "amount")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {transactions.length === 0 ? (
                      <tr>
                        <td colSpan={6}>
                          <div className="table-empty">
                            {t(locale, "amlSelectAccountHint")}
                          </div>
                        </td>
                      </tr>
                    ) : (
                      transactions.map((tx) => (
                        <tr key={`${tx.transactionId}-${tx.timestamp}`}>
                          <td>{formatDate(locale, tx.timestamp)}</td>
                          <td>
                            {tx.direction === "inbound"
                              ? t(locale, "amlInbound")
                              : t(locale, "amlOutbound")}
                          </td>
                          <td>{tx.counterpartyAccount}</td>
                          <td>
                            <span
                              className={
                                tx.isFlagged
                                  ? "mini-pill aml-flag-pill aml-flag-pill--flagged"
                                  : "mini-pill aml-flag-pill"
                              }
                            >
                              {tx.isFlagged
                                ? t(locale, "flagged")
                                : t(locale, "normal")}
                            </span>
                          </td>
                          <td>{tx.riskLevel}</td>
                          <td className="aml-amount">
                            {formatCurrencyVnd(
                              locale,
                              tx.direction === "inbound"
                                ? tx.amountReceived
                                : tx.amountPaid,
                            )}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </section>
      </div>
    </div>
  );
}

function LogsView({
  locale,
  copy,
  logSources,
  selectedLogSource,
  onSelectLogSource,
  logTail,
  auditLogs,
  auditSearch,
  onAuditSearchChange,
  onReloadLogs,
}: {
  locale: Locale;
  copy: (typeof COPY)[Locale];
  logSources: LogSource[];
  selectedLogSource: string;
  onSelectLogSource: (source: string) => void;
  logTail: LogTail | null;
  auditLogs: AuditLog[];
  auditSearch: string;
  onAuditSearchChange: (value: string) => void;
  onReloadLogs: () => void;
}) {
  const logConsoleRef = useRef<HTMLDivElement | null>(null);
  const lastLine = logTail?.lines.at(-1) ?? "";

  useEffect(() => {
    const node = logConsoleRef.current;
    if (!node) {
      return;
    }
    node.scrollTop = node.scrollHeight;
  }, [selectedLogSource, logTail?.lines.length, lastLine]);

  return (
    <div className="page-grid page-grid--logs">
      <section className="panel panel--wide">
        <div className="panel__header">
          <div>
            <span className="eyebrow">{copy.sourceLabel}</span>
            <h2>{t(locale, "serverLogs")}</h2>
          </div>
          <button
            className="secondary-button"
            onClick={onReloadLogs}
            type="button"
          >
            {t(locale, "reloadLogs")}
          </button>
        </div>

        {logSources.length === 0 ? (
          <EmptyState message={t(locale, "noLogSource")} />
        ) : (
          <>
            <div className="toolbar-grid toolbar-grid--logs">
              <label className="field">
                <span>{copy.sourceLabel}</span>
                <select
                  className="app-select"
                  value={selectedLogSource}
                  onChange={(event) => onSelectLogSource(event.target.value)}
                >
                  {logSources.map((source) => (
                    <option key={source.name} value={source.name}>
                      {describeLogKind(locale, source.kind)} · {source.name}
                    </option>
                  ))}
                </select>
              </label>
              <div className="pill-row pill-row--compact">
                <ValuePill
                  compact
                  label={copy.logFile}
                  value={logTail?.fileName ?? "n/a"}
                />
                <ValuePill
                  compact
                  label={copy.logLines}
                  value={String(logTail?.lines.length ?? 0)}
                />
              </div>
            </div>

            <div className="log-console" ref={logConsoleRef}>
              {(logTail?.lines ?? []).map((line, index) => (
                <div key={`${index}-${line}`} className="log-console__line">
                  {line}
                </div>
              ))}
            </div>
          </>
        )}
      </section>

      <section className="panel panel--wide">
        <div className="panel__header">
          <div>
            <span className="eyebrow">{t(locale, "auditTrail")}</span>
            <h2>{t(locale, "auditTrail")}</h2>
          </div>
          <input
            className="app-input app-input--compact"
            placeholder={t(locale, "auditSearch")}
            value={auditSearch}
            onChange={(event) => onAuditSearchChange(event.target.value)}
          />
        </div>

        <div className="table-shell">
          <table>
            <thead>
              <tr>
                <th>{t(locale, "timestamp")}</th>
                <th>{t(locale, "actor")}</th>
                <th>{t(locale, "method")}</th>
                <th>{t(locale, "path")}</th>
                <th>{t(locale, "outcome")}</th>
              </tr>
            </thead>
            <tbody>
              {auditLogs.length === 0 ? (
                <tr>
                  <td colSpan={5}>
                    <div className="table-empty">{copy.noAuditResults}</div>
                  </td>
                </tr>
              ) : (
                auditLogs.map((log) => (
                  <tr key={log.id}>
                    <td>{formatDate(locale, log.createdAt)}</td>
                    <td>{log.actorEmail ?? localizeSystemActor(locale)}</td>
                    <td>{log.method}</td>
                    <td>{log.path}</td>
                    <td>{localizeAuditOutcome(locale, log.outcome)}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

function AdminsView({
  locale,
  copy,
  roles,
  users,
  permissions,
  actionLoading,
  onCreate,
  onToggleUser,
}: {
  locale: Locale;
  copy: (typeof COPY)[Locale];
  roles: AdminRole[];
  users: AdminUser[];
  permissions: string[];
  actionLoading: boolean;
  onCreate: (payload: {
    email: string;
    password: string;
    displayName: string;
    title: string;
    roleId: string;
    locale: string;
    extraPermissions: string[];
  }) => Promise<boolean>;
  onToggleUser: (user: AdminUser) => Promise<void>;
}) {
  const [form, setForm] = useState({
    email: "",
    password: "",
    displayName: "",
    title: "",
    roleId: "",
    locale: "vi",
    extraPermissions: [] as string[],
  });
  const effectiveRoleId = form.roleId || roles[0]?.id || "";

  return (
    <div className="page-grid page-grid--admins">
      <div className="split-grid">
        <section className="panel">
          <div className="panel__header">
            <div>
              <span className="eyebrow">{copy.permissionsMatrix}</span>
              <h2>{t(locale, "createSubAdmin")}</h2>
            </div>
          </div>

          <form
            className="admin-form"
            onSubmit={(event) => {
              event.preventDefault();
              void onCreate({
                ...form,
                roleId: effectiveRoleId,
              }).then((created) => {
                if (!created) {
                  return;
                }

                setForm({
                  email: "",
                  password: "",
                  displayName: "",
                  title: "",
                  roleId: "",
                  locale: "vi",
                  extraPermissions: [],
                });
              });
            }}
          >
            <div className="field-grid">
              <label className="field">
                <span>{t(locale, "email")}</span>
                <input
                  className="app-input"
                  value={form.email}
                  onChange={(event) =>
                    setForm((current) => ({
                      ...current,
                      email: event.target.value,
                    }))
                  }
                />
              </label>
              <label className="field">
                <span>{t(locale, "password")}</span>
                <input
                  className="app-input"
                  type="password"
                  value={form.password}
                  onChange={(event) =>
                    setForm((current) => ({
                      ...current,
                      password: event.target.value,
                    }))
                  }
                />
              </label>
              <label className="field">
                <span>{t(locale, "displayName")}</span>
                <input
                  className="app-input"
                  value={form.displayName}
                  onChange={(event) =>
                    setForm((current) => ({
                      ...current,
                      displayName: event.target.value,
                    }))
                  }
                />
              </label>
              <label className="field">
                <span>{t(locale, "title")}</span>
                <input
                  className="app-input"
                  value={form.title}
                  onChange={(event) =>
                    setForm((current) => ({
                      ...current,
                      title: event.target.value,
                    }))
                  }
                />
              </label>
              <label className="field">
                <span>{t(locale, "role")}</span>
                <select
                  className="app-select"
                  value={effectiveRoleId}
                  onChange={(event) =>
                    setForm((current) => ({
                      ...current,
                      roleId: event.target.value,
                    }))
                  }
                >
                  {roles.map((role) => (
                    <option key={role.id} value={role.id}>
                      {role.name}
                    </option>
                  ))}
                </select>
              </label>
              <label className="field">
                <span>{t(locale, "locale")}</span>
                <select
                  className="app-select"
                  value={form.locale}
                  onChange={(event) =>
                    setForm((current) => ({
                      ...current,
                      locale: event.target.value,
                    }))
                  }
                >
                  <option value="vi">VI</option>
                  <option value="en">EN</option>
                </select>
              </label>
            </div>

            <div className="panel__subheader">
              <strong>{copy.permissionsMatrix}</strong>
              <span>{copy.createAdminHint}</span>
            </div>

            <div className="permission-grid">
              {permissions.map((permission) => (
                <label key={permission} className="permission-card">
                  <input
                    checked={form.extraPermissions.includes(permission)}
                    onChange={(event) =>
                      setForm((current) => ({
                        ...current,
                        extraPermissions: event.target.checked
                          ? [...current.extraPermissions, permission]
                          : current.extraPermissions.filter(
                              (item) => item !== permission,
                            ),
                      }))
                    }
                    type="checkbox"
                  />
                  <span>{permission}</span>
                </label>
              ))}
            </div>

            <button
              className="primary-button"
              disabled={actionLoading}
              type="submit"
            >
              {actionLoading
                ? t(locale, "creating")
                : t(locale, "createAccount")}
            </button>
          </form>
        </section>

      </div>

      <section className="panel panel--wide">
        <div className="panel__header">
          <div>
            <span className="eyebrow">{copy.accountRoster}</span>
            <h2>{t(locale, "adminUsers")}</h2>
          </div>
          <strong>{users.length}</strong>
        </div>

        <div className="table-shell">
          <table>
            <thead>
              <tr>
                <th>{t(locale, "displayName")}</th>
                <th>{t(locale, "email")}</th>
                <th>{t(locale, "role")}</th>
                <th>{t(locale, "lastLogin")}</th>
                <th>{t(locale, "statusHealthy")}</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {users.map((user) => (
                <tr key={user.id}>
                  <td>{user.displayName}</td>
                  <td>{user.email}</td>
                  <td>{user.role?.name ?? "n/a"}</td>
                  <td>
                    {user.lastLoginAt
                      ? formatDate(locale, user.lastLoginAt)
                      : copy.never}
                  </td>
                  <td>
                    {user.isActive
                      ? t(locale, "enabled")
                      : t(locale, "disabled")}
                  </td>
                  <td>
                    <button
                      className="ghost-button ghost-button--compact"
                      onClick={() => {
                        void onToggleUser(user);
                      }}
                      type="button"
                    >
                      {user.isActive
                        ? t(locale, "disable")
                        : t(locale, "enable")}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

function SparklineCard({
  locale,
  label,
  unit,
  series,
}: {
  locale: Locale;
  label: string;
  unit: string;
  series: TimeseriesResponse | null;
}) {
  const points = series?.points ?? [];
  const numericPoints = points
    .map((point) =>
      typeof point.value === "number"
        ? { at: point.at, value: point.value }
        : null,
    )
    .filter(Boolean) as Array<{ at: string; value: number }>;
  const gradientId = `sparkline-${label
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")}`;
  const latestPoint = numericPoints.at(-1) ?? null;
  const values = numericPoints.map((point) => point.value);
  const max = Math.max(...values, 1);
  const min = Math.min(...values, 0);
  const polyline =
    numericPoints.length === 0
      ? ""
      : numericPoints
          .map((point, index) => {
            const x = (index / Math.max(numericPoints.length - 1, 1)) * 100;
            const y =
              100 - ((point.value - min) / Math.max(max - min, 1)) * 100;
            return `${x},${y}`;
          })
          .join(" ");

  return (
    <article className="trend-card">
      <div className="trend-card__header">
        <div>
          <span>{label}</span>
          <strong>
            {latestPoint
              ? `${trimNumber(latestPoint.value)}${unit}`
              : "n/a"}
          </strong>
        </div>
        <small>{numericPoints.length}</small>
      </div>
      <svg
        className="sparkline"
        viewBox="0 0 100 100"
        preserveAspectRatio="none"
      >
        <defs>
          <linearGradient id={gradientId} x1="0" x2="1" y1="0" y2="0">
            <stop offset="0%" stopColor="#f2a1b5" />
            <stop offset="100%" stopColor="#9f1f43" />
          </linearGradient>
        </defs>
        <polyline
          fill="none"
          points={polyline}
          stroke={`url(#${gradientId})`}
          strokeWidth="3"
        />
      </svg>
      <p className="muted-text">
        {latestPoint ? formatDate(locale, latestPoint.at) : ""}
      </p>
    </article>
  );
}

function AlertList({
  locale,
  alerts,
}: {
  locale: Locale;
  alerts: Array<{
    code: string;
    severity: "warning" | "critical";
    title: string;
    recommendedAction: string;
  }>;
}) {
  if (alerts.length === 0) {
    return <EmptyState message={t(locale, "noAlerts")} />;
  }

  const orderedAlerts = [...alerts].sort(
    (left, right) => severityWeight(right.severity) - severityWeight(left.severity),
  );

  return (
    <div className="alert-list">
      {orderedAlerts.map((alert) => (
        <article
          key={alert.code}
          className={`alert-card alert-card--${alert.severity}`}
        >
          <strong>{alert.title}</strong>
          <p>{alert.recommendedAction}</p>
        </article>
      ))}
    </div>
  );
}

function StatusBadge({ locale, status }: { locale: Locale; status: string }) {
  return (
    <span className={`status-badge status-badge--${toneFromStatus(status)}`}>
      <span aria-hidden="true" className="status-badge__dot" />
      {statusLabel(locale, status)}
    </span>
  );
}

function MetricCard({
  label,
  value,
  caption,
  tone,
}: {
  label: string;
  value: string;
  caption: string;
  tone: "healthy" | "warning" | "critical" | "neutral";
}) {
  const textual = isTextualMetricValue(value);
  return (
    <article
      className={
        textual
          ? `metric-card metric-card--${tone} metric-card--textual`
          : `metric-card metric-card--${tone}`
      }
    >
      <span>{label}</span>
      <strong className={textual ? "metric-card__value metric-card__value--textual" : "metric-card__value"}>
        {value}
      </strong>
      <small>{caption}</small>
    </article>
  );
}

function MiniMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="mini-metric">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function ValuePill({
  label,
  value,
  compact = false,
}: {
  label: string;
  value: string;
  compact?: boolean;
}) {
  const textual = isTextualMetricValue(value);
  return (
    <div
      className={
        compact
          ? textual
            ? "value-pill value-pill--compact value-pill--textual"
            : "value-pill value-pill--compact"
          : textual
            ? "value-pill value-pill--textual"
            : "value-pill"
      }
    >
      <span>{label}</span>
      <strong className={textual ? "value-pill__value value-pill__value--textual" : "value-pill__value"}>
        {value}
      </strong>
    </div>
  );
}

function EmptyState({ message }: { message: string }) {
  return <div className="empty-state">{message}</div>;
}

function StatePanel({ title }: { title: string }) {
  return (
    <section className="panel state-panel">
      <EmptyState message={title} />
    </section>
  );
}

function resolveWalletSourceLabel(
  source: MonitoringOverview["wallet"]["source"],
  copy: (typeof COPY)[Locale],
) {
  switch (source) {
    case "readonly_db":
      return copy.telemetryReady;
    case "error":
      return copy.telemetryError;
    case "unconfigured":
    default:
      return copy.telemetryWaiting;
  }
}

function describeLogKind(locale: Locale, kind: LogSource["kind"]) {
  switch (kind) {
    case "wallet":
      return t(locale, "logKindWallet");
    case "chain":
      return t(locale, "logKindChain");
    case "system":
    default:
      return t(locale, "logKindSystem");
  }
}

function localizeSystemActor(locale: Locale) {
  return locale === "vi" ? "hệ thống" : "system";
}

function localizeAuditOutcome(locale: Locale, outcome: string | null) {
  if (!outcome) {
    return "n/a";
  }

  if (locale !== "vi") {
    return outcome;
  }

  switch (outcome.toLowerCase()) {
    case "success":
      return "thành công";
    case "failure":
      return "thất bại";
    default:
      return outcome;
  }
}

function resolveWalletNote(
  locale: Locale,
  source: MonitoringOverview["wallet"]["source"],
  note: string | null,
) {
  if (source === "readonly_db") {
    return t(locale, "walletEstimateNote");
  }

  if (source === "unconfigured") {
    return t(locale, "walletNoteFallback");
  }

  if (!note) {
    return t(locale, "walletNoteFallback");
  }

  if (
    locale === "vi" &&
    note.startsWith("Wallet analytics unavailable:")
  ) {
    return note.replace(
      "Wallet analytics unavailable:",
      "Không đọc được telemetry ví:",
    );
  }

  if (
    locale === "vi" &&
    note === "Wallet read-only database is not configured."
  ) {
    return t(locale, "walletNoteFallback");
  }

  if (
    locale === "en" &&
    note === "Wallet read-only database is not configured."
  ) {
    return t(locale, "walletNoteFallback");
  }

  if (
    note === "Concurrent users are estimated from sessions active in the last 5 minutes."
  ) {
    return t(locale, "walletEstimateNote");
  }

  return note;
}

function resolveWarehouseNote(locale: Locale, note: string) {
  if (
    note
      .toLowerCase()
      .startsWith("reserved for future data warehouse feeds")
  ) {
    return t(locale, "warehouseReservedNote");
  }

  return note;
}

function statusLabel(locale: Locale, status: string) {
  switch (status) {
    case "healthy":
    case "connected":
    case "ok":
      return t(locale, "statusHealthy");
    case "warning":
      return t(locale, "statusWarning");
    case "critical":
    case "unreachable":
    case "disconnected":
      return t(locale, "statusCritical");
    default:
      return status;
  }
}

function toneFromStatus(
  status: string,
): "healthy" | "warning" | "critical" | "neutral" {
  switch (status) {
    case "healthy":
    case "connected":
    case "ok":
      return "healthy";
    case "warning":
      return "warning";
    case "critical":
    case "unreachable":
    case "disconnected":
      return "critical";
    default:
      return "neutral";
  }
}

function toneFromAmlRisk(
  riskLevel: string,
): "healthy" | "warning" | "critical" | "neutral" {
  switch (`${riskLevel}`.toUpperCase()) {
    case "CRITICAL":
      return "critical";
    case "HIGH":
      return "warning";
    case "MEDIUM":
      return "warning";
    case "LOW":
      return "healthy";
    default:
      return "neutral";
  }
}

function toneFromThreshold(
  value: number | null,
  warning: number,
  critical: number,
): "healthy" | "warning" | "critical" | "neutral" {
  if (typeof value !== "number") {
    return "neutral";
  }
  if (value >= critical) {
    return "critical";
  }
  if (value >= warning) {
    return "warning";
  }
  return "healthy";
}

function average(values: number[]) {
  if (values.length === 0) {
    return 0;
  }
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function percentile(values: number[], percentileRank: number) {
  if (values.length === 0) {
    return null;
  }

  const rank = Math.min(Math.max(percentileRank, 0), 100) / 100;
  const index = Math.ceil(rank * values.length) - 1;
  return values[Math.max(0, index)] ?? values[values.length - 1] ?? null;
}

function flagEmoji(locale: Locale) {
  return locale === "vi" ? "🇻🇳" : "🇺🇸";
}

function formatDate(locale: Locale, input: string) {
  if (!input) {
    return "";
  }
  const date = new Date(input);
  const datePart = new Intl.DateTimeFormat(
    locale === "vi" ? "vi-VN" : "en-US",
    locale === "vi"
      ? {
          day: "2-digit",
          month: "2-digit",
          year: "numeric",
        }
      : {
          month: "short",
          day: "numeric",
          year: "numeric",
        },
  ).format(date);
  const timePart = new Intl.DateTimeFormat(
    locale === "vi" ? "vi-VN" : "en-US",
    {
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    },
  ).format(date);

  return locale === "vi"
    ? `${timePart} ${datePart}`
    : `${datePart}, ${timePart}`;
}

function formatCompactDateTime(locale: Locale, input: string) {
  if (!input) {
    return "";
  }

  const date = new Date(input);
  const timePart = new Intl.DateTimeFormat(
    locale === "vi" ? "vi-VN" : "en-US",
    {
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    },
  ).format(date);
  const datePart = new Intl.DateTimeFormat(
    locale === "vi" ? "vi-VN" : "en-US",
    locale === "vi"
      ? {
          day: "2-digit",
          month: "2-digit",
          year: "numeric",
        }
      : {
          month: "short",
          day: "numeric",
          year: "numeric",
        },
  ).format(date);

  return `${timePart} · ${datePart}`;
}

function formatMetric(formatter: Intl.NumberFormat, value: number | null) {
  return typeof value === "number" ? formatter.format(value) : "n/a";
}

function formatHours(
  locale: Locale,
  formatter: Intl.NumberFormat,
  value: number,
) {
  if (!Number.isFinite(value)) {
    return "n/a";
  }
  return locale === "vi"
    ? `${formatter.format(value)} giờ`
    : `${formatter.format(value)} h`;
}

function formatCurrencyVnd(locale: Locale, value: number) {
  if (!Number.isFinite(value)) {
    return "n/a";
  }
  const formatted = new Intl.NumberFormat(locale === "vi" ? "vi-VN" : "en-US", {
    maximumFractionDigits: 0,
  }).format(value);
  return locale === "vi" ? `${formatted} đ` : `${formatted} VND`;
}

function trimNumber(value: number) {
  return Number(value.toFixed(value % 1 === 0 ? 0 : 1)).toString();
}

function isTextualMetricValue(value: string) {
  const normalized = value.trim().toLowerCase();
  if (!normalized || normalized === "n/a" || normalized === "na") {
    return true;
  }
  if (/[a-zA-ZÀ-ỹ]/u.test(normalized)) {
    return true;
  }
  // pure numeric/sign symbols should remain numeric styling.
  return !/^[\d.,:/%+-]+$/.test(normalized);
}

function compareStatusOrder<
  T extends { status: "healthy" | "warning" | "critical" | "unknown" },
>(left: T, right: T) {
  return severityWeight(right.status) - severityWeight(left.status);
}

function severityWeight(status: string) {
  switch (status) {
    case "critical":
      return 3;
    case "warning":
      return 2;
    case "unknown":
      return 1;
    case "healthy":
    case "connected":
    case "ok":
    default:
      return 0;
  }
}

function loadSession(): Session | null {
  try {
    const raw = localStorage.getItem(SESSION_STORAGE_KEY);
    return raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    return null;
  }
}

function persistSession(session: Session) {
  localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session));
}

function clearSessionStorage() {
  localStorage.removeItem(SESSION_STORAGE_KEY);
}

function loadLocale(): Locale {
  const stored = localStorage.getItem(LOCALE_STORAGE_KEY);
  return stored === "en" ? "en" : "vi";
}

function resolveLocale(input: string): Locale {
  return input === "en" ? "en" : "vi";
}

export default App;
