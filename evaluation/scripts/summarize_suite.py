#!/usr/bin/env python3
import argparse
import csv
import json
import math
import os
from typing import Dict, Any, List

KEY_LABELS = [
    "Wallet - GET /healthz",
    "Wallet - GET /v1/transactions",
    "Monitor - GET /api/monitoring/overview",
    "Chain Gateway - GET /health",
    "Orderer MGMT - GET /api/status",
]


def safe_get_metric(summary: Dict[str, Any], label: str, metric: str):
    data = summary.get(label)
    if not data:
        return None
    return data.get(metric)


def worst_p95(summary: Dict[str, Any]):
    vals = [v.get("p95_ms") for v in summary.values() if isinstance(v.get("p95_ms"), (int, float))]
    if not vals:
        return None
    return max(vals)


def load_status(path: str) -> List[Dict[str, Any]]:
    rows = []
    with open(path, encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            row["exit_code"] = int(row["exit_code"])
            rows.append(row)
    return rows


def main():
    parser = argparse.ArgumentParser(description="Summarize evaluation suite")
    parser.add_argument("--suite-dir", required=True)
    parser.add_argument("--status-tsv", required=True)
    parser.add_argument("--out-md", required=True)
    parser.add_argument("--out-json", required=True)
    args = parser.parse_args()

    statuses = load_status(args.status_tsv)
    scenarios = []

    for s in statuses:
        out_dir = s["out_dir"]
        summary_path = os.path.join(out_dir, "summary.json")
        data = {
            "scenario": s["scenario"],
            "scenario_file": s["scenario_file"],
            "exit_code": s["exit_code"],
            "out_dir": out_dir,
            "summary_found": os.path.isfile(summary_path),
        }

        if data["summary_found"]:
            with open(summary_path, encoding="utf-8") as f:
                summary_json = json.load(f)
            summary = summary_json.get("summary", {})
            failed = summary_json.get("failed", [])
            data.update(
                {
                    "pass": bool(summary_json.get("pass", False)),
                    "failed_count": len(failed),
                    "labels_count": len(summary),
                    "worst_p95_ms": worst_p95(summary),
                    "key_metrics": {
                        label: {
                            "p95_ms": safe_get_metric(summary, label, "p95_ms"),
                            "error_rate_pct": safe_get_metric(summary, label, "error_rate_pct"),
                        }
                        for label in KEY_LABELS
                    },
                }
            )
        else:
            data.update(
                {
                    "pass": False,
                    "failed_count": None,
                    "labels_count": None,
                    "worst_p95_ms": None,
                    "key_metrics": {},
                }
            )

        scenarios.append(data)

    suite_pass = all(item["pass"] for item in scenarios) if scenarios else False

    os.makedirs(os.path.dirname(args.out_json), exist_ok=True)
    with open(args.out_json, "w", encoding="utf-8") as f:
        json.dump(
            {
                "suite_dir": args.suite_dir,
                "suite_pass": suite_pass,
                "scenario_count": len(scenarios),
                "scenarios": scenarios,
            },
            f,
            indent=2,
            ensure_ascii=False,
        )

    md = []
    md.append("# Evaluation Suite Summary")
    md.append("")
    md.append(f"- Suite dir: `{args.suite_dir}`")
    md.append(f"- Overall result: **{'PASS' if suite_pass else 'FAIL'}**")
    md.append("")
    md.append("| Scenario | Result | Labels | Failed labels | Worst p95 (ms) | Output |")
    md.append("|---|---|---:|---:|---:|---|")

    for item in scenarios:
      res = "PASS" if item["pass"] else "FAIL"
      labels = item["labels_count"] if item["labels_count"] is not None else "-"
      failed = item["failed_count"] if item["failed_count"] is not None else "-"
      worst = (
          f"{item['worst_p95_ms']:.2f}"
          if isinstance(item["worst_p95_ms"], (int, float))
          else "-"
      )
      md.append(
          f"| {item['scenario']} | {res} | {labels} | {failed} | {worst} | `{item['out_dir']}` |"
      )

    md.append("")
    md.append("## Key Endpoint Metrics")

    for item in scenarios:
        md.append("")
        md.append(f"### {item['scenario']}")
        if not item["key_metrics"]:
            md.append("- No metrics available.")
            continue
        md.append("| Label | p95 (ms) | Error % |")
        md.append("|---|---:|---:|")
        for label in KEY_LABELS:
            metric = item["key_metrics"].get(label, {})
            p95 = metric.get("p95_ms")
            err = metric.get("error_rate_pct")
            p95_text = f"{p95:.2f}" if isinstance(p95, (int, float)) else "-"
            err_text = f"{err:.2f}" if isinstance(err, (int, float)) else "-"
            md.append(f"| {label} | {p95_text} | {err_text} |")

    with open(args.out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")


if __name__ == "__main__":
    main()
