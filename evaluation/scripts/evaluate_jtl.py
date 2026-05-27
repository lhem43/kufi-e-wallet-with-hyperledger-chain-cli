#!/usr/bin/env python3
import argparse
import csv
import json
import math
import os
from collections import defaultdict


def percentile(values, p):
    if not values:
        return math.nan
    vals = sorted(values)
    k = (len(vals) - 1) * p
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return float(vals[int(k)])
    return float(vals[f] * (c - k) + vals[c] * (k - f))


def parse_jtl(path):
    by_label = defaultdict(list)
    with open(path, newline="", encoding="utf-8") as f:
      reader = csv.DictReader(f)
      for row in reader:
        label = row.get("label", "unknown")
        elapsed = float(row.get("elapsed", 0) or 0)
        success = str(row.get("success", "")).lower() == "true"
        code = str(row.get("responseCode", ""))
        by_label[label].append({"elapsed": elapsed, "success": success, "code": code})
    return by_label


def summarize(by_label):
    summary = {}
    for label, rows in by_label.items():
        total = len(rows)
        ok = sum(1 for r in rows if r["success"])
        err = total - ok
        err_rate = (err / total * 100.0) if total else 0.0
        lat = [r["elapsed"] for r in rows]
        summary[label] = {
            "samples": total,
            "ok": ok,
            "errors": err,
            "error_rate_pct": round(err_rate, 4),
            "avg_ms": round(sum(lat) / total, 2) if total else math.nan,
            "p95_ms": round(percentile(lat, 0.95), 2),
            "p99_ms": round(percentile(lat, 0.99), 2),
            "max_ms": round(max(lat), 2) if total else math.nan,
        }
    return summary


def evaluate(summary, max_p95_ms, max_error_pct):
    failed = []
    for label, m in summary.items():
        if m["samples"] == 0:
            failed.append((label, "no samples"))
            continue
        if m["p95_ms"] > max_p95_ms:
            failed.append((label, f"p95={m['p95_ms']}ms > {max_p95_ms}ms"))
        if m["error_rate_pct"] > max_error_pct:
            failed.append((label, f"error_rate={m['error_rate_pct']}% > {max_error_pct}%"))
    return failed


def to_markdown(summary, failed, out_path):
    lines = []
    lines.append("# Evaluation Summary")
    lines.append("")
    lines.append("| Label | Samples | Error % | Avg (ms) | p95 (ms) | p99 (ms) | Max (ms) |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|")
    for label in sorted(summary.keys()):
        m = summary[label]
        lines.append(
            f"| {label} | {m['samples']} | {m['error_rate_pct']:.2f} | {m['avg_ms']:.2f} | {m['p95_ms']:.2f} | {m['p99_ms']:.2f} | {m['max_ms']:.2f} |"
        )

    lines.append("")
    if failed:
        lines.append("## Result: FAIL")
        for label, reason in failed:
            lines.append(f"- `{label}`: {reason}")
    else:
        lines.append("## Result: PASS")
        lines.append("- All labels satisfy configured SLO thresholds.")

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description="Evaluate JMeter JTL against SLO thresholds")
    parser.add_argument("--jtl", required=True, help="Path to JTL (CSV)")
    parser.add_argument("--out-json", required=True, help="Output JSON summary path")
    parser.add_argument("--out-md", required=True, help="Output Markdown summary path")
    parser.add_argument("--max-p95-ms", type=float, default=3000.0)
    parser.add_argument("--max-error-pct", type=float, default=2.0)
    args = parser.parse_args()

    by_label = parse_jtl(args.jtl)
    summary = summarize(by_label)
    failed = evaluate(summary, args.max_p95_ms, args.max_error_pct)

    os.makedirs(os.path.dirname(args.out_json), exist_ok=True)
    with open(args.out_json, "w", encoding="utf-8") as f:
        json.dump(
            {
                "thresholds": {
                    "max_p95_ms": args.max_p95_ms,
                    "max_error_pct": args.max_error_pct,
                },
                "summary": summary,
                "failed": [{"label": l, "reason": r} for l, r in failed],
                "pass": len(failed) == 0,
            },
            f,
            indent=2,
            ensure_ascii=False,
        )

    to_markdown(summary, failed, args.out_md)
    print(f"[evaluate] JSON: {args.out_json}")
    print(f"[evaluate] Markdown: {args.out_md}")

    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
