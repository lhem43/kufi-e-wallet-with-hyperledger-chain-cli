# Evaluation (Single-Generator Capacity Benchmark)

This folder contains the benchmark pipeline used to evaluate system capacity with one load-generator machine.

It is designed to produce report-ready artifacts for thesis writing:

- raw metrics,
- structured tables,
- PNG charts,
- per-scenario dashboard HTML,
- suite-level markdown summary.

## 1) Scope and Limitations

This benchmark provides:

- maximum sustainable throughput in the current environment,
- latency/error behavior as load increases,
- knee point (where SLA starts degrading).

This benchmark does **not** directly prove 5k/10k real concurrent users because it uses a single load generator.
Use its measured throughput as the basis for capacity projection.

## 2) Request Flow in Current JMeter Plan

JMeter plan: `jmeter/system-evaluation.jmx`

### Wallet flow

- `POST /v1/auth/dev/login` (once per thread)
- `POST /v1/auth/dev/login (target)` (once per thread)
- `POST /v1/wallets` warmup (once per thread)
- loop:
  - `GET /healthz`
  - `GET /v1/auth/profile`
  - `GET /v1/wallets/VND`
  - `GET /v1/transactions`
  - `POST /v1/transactions/transfers/risk-assessment`

### Monitoring flow

- `POST /api/auth/login` (once per thread)
- loop:
  - `GET /api/healthz`
  - `GET /api/monitoring/overview`
  - `GET /api/monitoring/services`
  - `GET /api/monitoring/chain`

### Chain probe flow

- `GET /health` (gateway)
- `GET /api/status` (orderer management)

## 3) Scenario Set

Scenario profiles are in `scenarios_single_generator/`:

- `01-capacity-0100-users.env`
- `02-capacity-0250-users.env`
- `03-capacity-0500-users.env`
- `04-capacity-0800-users.env`
- `05-capacity-1200-users.env`
- `06-capacity-1600-users.env`

Each profile defines users/ramp/loops and SLO thresholds (`MAX_P95_MS`, `MAX_ERROR_PCT`).

## 4) Prerequisites

- Java 11+ (Java 17 recommended)
- Apache JMeter 5.6+
- Python 3.10+
- Python package: `matplotlib` (used to export PNG charts)
- Bash shell

Install references:

- Linux: install JDK/JMeter/Python via package manager.
- macOS: `brew install --cask temurin && brew install jmeter python`.
- Windows: install JDK + JMeter + Python, run scripts via Git Bash/WSL/PowerShell.

## 5) Run

Before running, set monitoring admin password:

```bash
export MONITOR_ADMIN_PASSWORD="<monitor_admin_password>"
```

Run full single-generator capacity suite:

```bash
cd evaluation
chmod +x scripts/*.sh
./scripts/run_single_generator_capacity_suite.sh
```

Windows PowerShell:

```powershell
cd evaluation
$env:MONITOR_ADMIN_PASSWORD="<monitor_admin_password>"
bash ./scripts/run_single_generator_capacity_suite.sh
```

Optional: capture infra snapshot before/after suite:

```bash
CAPTURE_INFRA_SNAPSHOT=true ./scripts/run_single_generator_capacity_suite.sh
```

## 6) Output Artifacts (for report writing)

Suite outputs are stored under:

- `results/suites/<suite-id>/`

Per scenario (`results/suites/<suite-id>/<scenario>/`):

- `result.jtl`: raw sample data
- `dashboard/index.html`: JMeter dashboard
- `dashboard/statistics.json`: structured dashboard metrics
- `summary.json`: endpoint-level KPI summary
- `summary.md`: endpoint-level markdown table
- `meta.env`: scenario parameters used during run

Suite-level summary:

- `suite-status.tsv`: scenario run status
- `suite-summary.json`: suite summary (machine-readable)
- `suite-summary.md`: suite summary (markdown)

Report asset bundle (`results/suites/<suite-id>/report/`):

- `scenario_overview.csv`: one row per scenario (users, throughput, p95/p99, error)
- `endpoint_metrics.csv`: endpoint-level KPI table
- `report.md`: report-ready markdown summary
- `report.json`: manifest with main paths and KPIs
- `charts/throughput_vs_load.png`
- `charts/p95_vs_load.png`
- `charts/error_rate_vs_load.png`
- `charts/worst_endpoint_p95_vs_load.png`
- `charts/<scenario>_top10_endpoint_p95.png`

## 7) Scripts

- `scripts/run_jmeter_scenario.sh`: run one scenario and produce per-scenario outputs.
- `scripts/run_single_generator_capacity_suite.sh`: run all single-generator scenarios as a suite.
- `scripts/evaluate_jtl.py`: compute endpoint-level KPI summary from JTL.
- `scripts/summarize_suite.py`: aggregate scenario results into suite summary.
- `scripts/build_suite_report.py`: generate CSV tables + PNG charts + final markdown report.
- `scripts/collect_infra_snapshot.sh`: optional host-level snapshot before/after tests.

## 8) Notes for Thesis/Capstone Report

Use these files directly in the evaluation chapter:

- tables: `report/scenario_overview.csv`, `report/endpoint_metrics.csv`
- charts: `report/charts/*.png`
- narrative summary: `report/report.md`
- traceability/raw evidence: per-scenario `result.jtl` + `dashboard/index.html`

