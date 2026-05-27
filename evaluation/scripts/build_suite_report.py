#!/usr/bin/env python3
"""Build publication-ready evaluation assets from a suite run.

Outputs:
- CSV tables for direct insertion into thesis/report appendices.
- PNG charts (load vs throughput/latency/error + endpoint hotspot chart).
- Markdown report with key findings and file links.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple


def percentile(values: List[float], p: float) -> float:
    if not values:
        return math.nan
    vals = sorted(values)
    k = (len(vals) - 1) * p
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return float(vals[int(k)])
    return float(vals[f] * (c - k) + vals[c] * (k - f))


def parse_meta_env(path: Path) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if not path.is_file():
        return out
    with path.open(encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def to_int(text: str | None, default: int = 0) -> int:
    if text is None:
        return default
    try:
        return int(float(str(text).strip()))
    except Exception:
        return default


def to_float(text: str | None, default: float = math.nan) -> float:
    if text is None:
        return default
    try:
        return float(str(text).strip())
    except Exception:
        return default


def parse_jtl_overall(jtl_path: Path) -> Dict[str, float]:
    if not jtl_path.is_file():
        return {
            "samples": 0,
            "error_rate_pct": math.nan,
            "avg_ms": math.nan,
            "p50_ms": math.nan,
            "p95_ms": math.nan,
            "p99_ms": math.nan,
            "max_ms": math.nan,
            "duration_s": math.nan,
            "throughput_rps": math.nan,
        }

    latencies: List[float] = []
    total = 0
    ok = 0
    first_ts: float | None = None
    last_ts: float | None = None

    with jtl_path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            total += 1
            success = str(row.get("success", "")).lower() == "true"
            if success:
                ok += 1
            latencies.append(to_float(row.get("elapsed"), 0.0))
            ts = to_float(row.get("timeStamp"), math.nan)
            if not math.isnan(ts):
                first_ts = ts if first_ts is None else min(first_ts, ts)
                last_ts = ts if last_ts is None else max(last_ts, ts)

    err = total - ok
    err_rate = (err / total * 100.0) if total else math.nan
    avg = (sum(latencies) / total) if total else math.nan
    duration_s = math.nan
    throughput_rps = math.nan
    if first_ts is not None and last_ts is not None and last_ts > first_ts:
        duration_s = (last_ts - first_ts) / 1000.0
        if duration_s > 0:
            throughput_rps = total / duration_s

    return {
        "samples": float(total),
        "error_rate_pct": err_rate,
        "avg_ms": avg,
        "p50_ms": percentile(latencies, 0.50),
        "p95_ms": percentile(latencies, 0.95),
        "p99_ms": percentile(latencies, 0.99),
        "max_ms": max(latencies) if latencies else math.nan,
        "duration_s": duration_s,
        "throughput_rps": throughput_rps,
    }


def load_status_tsv(path: Path) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    with path.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            rows.append(row)
    return rows


def safe_rel(path: Path, base: Path) -> str:
    try:
        return str(path.resolve().relative_to(base.resolve()))
    except Exception:
        return str(path)


@dataclass
class ScenarioOverview:
    scenario: str
    users_total: int
    wallet_users: int
    monitor_users: int
    chain_probe_users: int
    samples_total: int
    throughput_rps: float
    error_rate_pct: float
    p95_ms: float
    p99_ms: float
    max_ms: float
    worst_endpoint: str
    worst_endpoint_p95_ms: float
    pass_flag: bool
    out_dir: Path


def scenario_sort_key(name: str, users_total: int) -> Tuple[int, str]:
    m = re.search(r"(\d+)$", name)
    if m:
        return (to_int(m.group(1), users_total), name)
    return (users_total, name)


def fmt(v: float, digits: int = 2) -> str:
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return "-"
    return f"{v:.{digits}f}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Build consolidated report assets from evaluation suite")
    parser.add_argument("--suite-dir", required=True, help="Path to evaluation/results/suites/<suite-id>")
    parser.add_argument("--status-tsv", default="", help="Path to suite-status.tsv (default: <suite-dir>/suite-status.tsv)")
    parser.add_argument("--out-dir", default="", help="Output directory (default: <suite-dir>/report)")
    args = parser.parse_args()

    suite_dir = Path(args.suite_dir).resolve()
    status_tsv = Path(args.status_tsv).resolve() if args.status_tsv else (suite_dir / "suite-status.tsv")
    out_dir = Path(args.out_dir).resolve() if args.out_dir else (suite_dir / "report")
    charts_dir = out_dir / "charts"
    out_dir.mkdir(parents=True, exist_ok=True)
    charts_dir.mkdir(parents=True, exist_ok=True)

    rows = load_status_tsv(status_tsv)
    if not rows:
        raise SystemExit(f"No scenarios found in {status_tsv}")

    overview: List[ScenarioOverview] = []
    endpoint_rows: List[Dict[str, object]] = []

    for row in rows:
        scenario = row.get("scenario", "unknown")
        out_path = Path(row.get("out_dir", "")).resolve()

        meta = parse_meta_env(out_path / "meta.env")
        wallet_users = to_int(meta.get("WALLET_USERS"), 0)
        monitor_users = to_int(meta.get("MONITOR_USERS"), 0)
        chain_users = to_int(meta.get("CHAIN_PROBE_USERS"), 0)
        users_total = wallet_users + monitor_users + chain_users

        summary_path = out_path / "summary.json"
        summary_json: Dict[str, object] = {}
        if summary_path.is_file():
            summary_json = json.loads(summary_path.read_text(encoding="utf-8"))
        label_summary: Dict[str, Dict[str, float]] = dict(summary_json.get("summary", {}) if isinstance(summary_json.get("summary"), dict) else {})
        pass_flag = bool(summary_json.get("pass", False))

        stats_path = out_path / "dashboard" / "statistics.json"
        stats: Dict[str, object] = {}
        if stats_path.is_file():
            stats = json.loads(stats_path.read_text(encoding="utf-8"))
        total_stats: Dict[str, object] = dict(stats.get("Total", {}) if isinstance(stats.get("Total"), dict) else {})

        overall = parse_jtl_overall(out_path / "result.jtl")
        throughput = to_float(total_stats.get("throughput"), math.nan)
        if math.isnan(throughput):
            throughput = to_float(overall.get("throughput_rps"), math.nan)

        # Endpoint rows for tables/charts
        worst_label = "-"
        worst_p95 = -1.0
        for label, metrics in label_summary.items():
            p95 = to_float(metrics.get("p95_ms"), math.nan)
            p99 = to_float(metrics.get("p99_ms"), math.nan)
            err = to_float(metrics.get("error_rate_pct"), math.nan)
            samples = to_int(str(metrics.get("samples", 0)), 0)
            avg = to_float(metrics.get("avg_ms"), math.nan)
            max_ms = to_float(metrics.get("max_ms"), math.nan)

            endpoint_rows.append(
                {
                    "scenario": scenario,
                    "users_total": users_total,
                    "label": label,
                    "samples": samples,
                    "error_rate_pct": err,
                    "avg_ms": avg,
                    "p95_ms": p95,
                    "p99_ms": p99,
                    "max_ms": max_ms,
                }
            )

            is_noise = "warmup" in label.lower()
            if not is_noise and not math.isnan(p95) and p95 > worst_p95:
                worst_p95 = p95
                worst_label = label

        overview.append(
            ScenarioOverview(
                scenario=scenario,
                users_total=users_total,
                wallet_users=wallet_users,
                monitor_users=monitor_users,
                chain_probe_users=chain_users,
                samples_total=to_int(str(overall["samples"]), 0),
                throughput_rps=throughput,
                error_rate_pct=to_float(overall["error_rate_pct"]),
                p95_ms=to_float(overall["p95_ms"]),
                p99_ms=to_float(overall["p99_ms"]),
                max_ms=to_float(overall["max_ms"]),
                worst_endpoint=worst_label,
                worst_endpoint_p95_ms=(worst_p95 if worst_p95 >= 0 else math.nan),
                pass_flag=pass_flag,
                out_dir=out_path,
            )
        )

    overview.sort(key=lambda r: scenario_sort_key(r.scenario, r.users_total))

    # Write CSV tables
    overview_csv = out_dir / "scenario_overview.csv"
    with overview_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "scenario",
                "users_total",
                "wallet_users",
                "monitor_users",
                "chain_probe_users",
                "samples_total",
                "throughput_rps",
                "error_rate_pct",
                "p95_ms",
                "p99_ms",
                "max_ms",
                "worst_endpoint",
                "worst_endpoint_p95_ms",
                "pass",
                "out_dir",
            ]
        )
        for r in overview:
            writer.writerow(
                [
                    r.scenario,
                    r.users_total,
                    r.wallet_users,
                    r.monitor_users,
                    r.chain_probe_users,
                    r.samples_total,
                    fmt(r.throughput_rps),
                    fmt(r.error_rate_pct),
                    fmt(r.p95_ms),
                    fmt(r.p99_ms),
                    fmt(r.max_ms),
                    r.worst_endpoint,
                    fmt(r.worst_endpoint_p95_ms),
                    "PASS" if r.pass_flag else "FAIL",
                    str(r.out_dir),
                ]
            )

    endpoints_csv = out_dir / "endpoint_metrics.csv"
    with endpoints_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "scenario",
                "users_total",
                "label",
                "samples",
                "error_rate_pct",
                "avg_ms",
                "p95_ms",
                "p99_ms",
                "max_ms",
            ]
        )
        for row in sorted(endpoint_rows, key=lambda x: (to_int(str(x["users_total"]), 0), str(x["scenario"]), str(x["label"]))):
            writer.writerow(
                [
                    row["scenario"],
                    row["users_total"],
                    row["label"],
                    row["samples"],
                    fmt(to_float(str(row["error_rate_pct"]))),
                    fmt(to_float(str(row["avg_ms"]))),
                    fmt(to_float(str(row["p95_ms"]))),
                    fmt(to_float(str(row["p99_ms"]))),
                    fmt(to_float(str(row["max_ms"]))),
                ]
            )

    # Chart generation
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as exc:  # pragma: no cover
        raise SystemExit(
            "matplotlib is required to build PNG charts. Install with: python3 -m pip install matplotlib\n"
            f"detail: {exc}"
        )

    x = [r.users_total for r in overview]
    thr = [r.throughput_rps for r in overview]
    p95 = [r.p95_ms for r in overview]
    err = [r.error_rate_pct for r in overview]
    worst_p95 = [r.worst_endpoint_p95_ms for r in overview]

    def line_chart(y: List[float], title: str, y_label: str, out_png: Path) -> None:
        plt.figure(figsize=(9, 5), dpi=140)
        plt.plot(x, y, marker="o", linewidth=2)
        for i, yv in enumerate(y):
            if not (isinstance(yv, float) and math.isnan(yv)):
                plt.text(x[i], yv, f" {yv:.2f}", fontsize=8)
        plt.title(title)
        plt.xlabel("Total virtual users")
        plt.ylabel(y_label)
        plt.grid(alpha=0.3)
        plt.tight_layout()
        plt.savefig(out_png)
        plt.close()

    line_chart(thr, "Throughput vs Load", "Requests per second", charts_dir / "throughput_vs_load.png")
    line_chart(p95, "Overall p95 Latency vs Load", "Milliseconds", charts_dir / "p95_vs_load.png")
    line_chart(err, "Overall Error Rate vs Load", "Percent", charts_dir / "error_rate_vs_load.png")
    line_chart(worst_p95, "Worst Endpoint p95 vs Load", "Milliseconds", charts_dir / "worst_endpoint_p95_vs_load.png")

    # Per-scenario top-10 endpoint p95 bar charts
    by_scenario: Dict[str, List[Dict[str, object]]] = {}
    for row in endpoint_rows:
        by_scenario.setdefault(str(row["scenario"]), []).append(row)

    for scenario, items in by_scenario.items():
        filtered = [
            r
            for r in items
            if not math.isnan(to_float(r.get("p95_ms")))
            and "warmup" not in str(r.get("label", "")).lower()
        ]
        filtered.sort(key=lambda r: to_float(r.get("p95_ms")), reverse=True)
        top = filtered[:10]
        if not top:
            continue

        labels = [str(r["label"]) for r in top]
        vals = [to_float(str(r["p95_ms"])) for r in top]

        plt.figure(figsize=(11, 5), dpi=140)
        plt.bar(range(len(top)), vals)
        plt.xticks(range(len(top)), labels, rotation=30, ha="right", fontsize=8)
        plt.ylabel("p95 latency (ms)")
        plt.title(f"Top endpoint p95 - {scenario}")
        plt.tight_layout()
        plt.savefig(charts_dir / f"{scenario}_top10_endpoint_p95.png")
        plt.close()

    # Markdown report
    md_path = out_dir / "report.md"
    md: List[str] = []
    md.append("# Evaluation Capacity Report")
    md.append("")
    md.append(f"- Suite directory: `{suite_dir}`")
    md.append(f"- Source status file: `{status_tsv}`")
    md.append("")
    md.append("## Scenario Overview")
    md.append("")
    md.append("| Scenario | Users | Samples | Throughput (req/s) | Error % | p95 (ms) | p99 (ms) | Worst Endpoint p95 (ms) | Result |")
    md.append("|---|---:|---:|---:|---:|---:|---:|---:|---|")
    for r in overview:
        md.append(
            f"| {r.scenario} | {r.users_total} | {r.samples_total} | {fmt(r.throughput_rps)} | {fmt(r.error_rate_pct)} | {fmt(r.p95_ms)} | {fmt(r.p99_ms)} | {fmt(r.worst_endpoint_p95_ms)} ({r.worst_endpoint}) | {'PASS' if r.pass_flag else 'FAIL'} |"
        )

    md.append("")
    md.append("## Charts")
    md.append("")
    md.append("- Throughput vs Load")
    md.append("  - ![Throughput vs Load](charts/throughput_vs_load.png)")
    md.append("- Overall p95 vs Load")
    md.append("  - ![p95 vs Load](charts/p95_vs_load.png)")
    md.append("- Overall Error Rate vs Load")
    md.append("  - ![Error vs Load](charts/error_rate_vs_load.png)")
    md.append("- Worst Endpoint p95 vs Load")
    md.append("  - ![Worst Endpoint p95 vs Load](charts/worst_endpoint_p95_vs_load.png)")

    md.append("")
    md.append("## Data Files")
    md.append("")
    md.append("- `scenario_overview.csv` (table for scenario-level KPIs)")
    md.append("- `endpoint_metrics.csv` (table for endpoint-level KPIs)")
    md.append("- `charts/*` (PNG charts for thesis/report figures)")

    md_path.write_text("\n".join(md) + "\n", encoding="utf-8")

    output_manifest = {
        "suite_dir": str(suite_dir),
        "report_dir": str(out_dir),
        "files": {
            "scenario_overview_csv": str(overview_csv),
            "endpoint_metrics_csv": str(endpoints_csv),
            "markdown_report": str(md_path),
            "charts_dir": str(charts_dir),
        },
        "scenarios": [
            {
                "scenario": r.scenario,
                "users_total": r.users_total,
                "throughput_rps": r.throughput_rps,
                "error_rate_pct": r.error_rate_pct,
                "p95_ms": r.p95_ms,
                "p99_ms": r.p99_ms,
                "pass": r.pass_flag,
                "out_dir": str(r.out_dir),
            }
            for r in overview
        ],
    }
    (out_dir / "report.json").write_text(json.dumps(output_manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"[report] markdown: {md_path}")
    print(f"[report] csv: {overview_csv}")
    print(f"[report] csv: {endpoints_csv}")
    print(f"[report] charts: {charts_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
