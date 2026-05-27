#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLAN="${PLAN:-${ROOT_DIR}/evaluation/jmeter/system-evaluation.jmx}"
RESULT_BASE="${RESULT_BASE:-${ROOT_DIR}/evaluation/results}"

if ! command -v jmeter >/dev/null 2>&1; then
  echo "[run] jmeter command not found. Install Apache JMeter first." >&2
  exit 1
fi

SCENARIO_NAME="${SCENARIO_NAME:-adhoc}"
TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_DIR:-${RESULT_BASE}/${TS}-${SCENARIO_NAME}}"
mkdir -p "${OUT_DIR}"

JTL_FILE="${OUT_DIR}/result.jtl"
DASHBOARD_DIR="${OUT_DIR}/dashboard"
SUMMARY_JSON="${OUT_DIR}/summary.json"
SUMMARY_MD="${OUT_DIR}/summary.md"

# Default profile (can be overridden by scenario .env)
WALLET_USERS="${WALLET_USERS:-80}"
WALLET_RAMP="${WALLET_RAMP:-90}"
WALLET_LOOPS="${WALLET_LOOPS:-80}"
MONITOR_USERS="${MONITOR_USERS:-15}"
MONITOR_RAMP="${MONITOR_RAMP:-90}"
MONITOR_LOOPS="${MONITOR_LOOPS:-70}"
CHAIN_PROBE_USERS="${CHAIN_PROBE_USERS:-5}"
CHAIN_PROBE_RAMP="${CHAIN_PROBE_RAMP:-60}"
CHAIN_PROBE_LOOPS="${CHAIN_PROBE_LOOPS:-90}"

WALLET_HOST="${WALLET_HOST:-203.0.113.10}"
WALLET_PORT="${WALLET_PORT:-3000}"
MONITOR_HOST="${MONITOR_HOST:-203.0.113.20}"
MONITOR_PORT="${MONITOR_PORT:-4300}"
CHAIN_GATEWAY_HOST="${CHAIN_GATEWAY_HOST:-203.0.113.30}"
CHAIN_GATEWAY_PORT="${CHAIN_GATEWAY_PORT:-8080}"
ORDERER_MGMT_HOST="${ORDERER_MGMT_HOST:-203.0.113.40}"
ORDERER_MGMT_PORT="${ORDERER_MGMT_PORT:-9500}"
MONITOR_ADMIN_EMAIL="${MONITOR_ADMIN_EMAIL:-admin@example.com}"
MONITOR_ADMIN_PASSWORD="${MONITOR_ADMIN_PASSWORD:-}"

if [[ -z "${MONITOR_ADMIN_PASSWORD}" ]]; then
  echo "[run] MONITOR_ADMIN_PASSWORD is required." >&2
  exit 1
fi

MAX_P95_MS="${MAX_P95_MS:-1800}"
MAX_ERROR_PCT="${MAX_ERROR_PCT:-2}"

echo "[run] plan: ${PLAN}"
echo "[run] output: ${OUT_DIR}"
echo "[run] scenario: ${SCENARIO_NAME}"

jmeter -n \
  -t "${PLAN}" \
  -l "${JTL_FILE}" \
  -e -o "${DASHBOARD_DIR}" \
  -Jwallet_users="${WALLET_USERS}" \
  -Jwallet_ramp="${WALLET_RAMP}" \
  -Jwallet_loops="${WALLET_LOOPS}" \
  -Jmonitor_users="${MONITOR_USERS}" \
  -Jmonitor_ramp="${MONITOR_RAMP}" \
  -Jmonitor_loops="${MONITOR_LOOPS}" \
  -Jchain_probe_users="${CHAIN_PROBE_USERS}" \
  -Jchain_probe_ramp="${CHAIN_PROBE_RAMP}" \
  -Jchain_probe_loops="${CHAIN_PROBE_LOOPS}" \
  -Jwallet_host="${WALLET_HOST}" \
  -Jwallet_port="${WALLET_PORT}" \
  -Jmonitor_host="${MONITOR_HOST}" \
  -Jmonitor_port="${MONITOR_PORT}" \
  -Jchain_gateway_host="${CHAIN_GATEWAY_HOST}" \
  -Jchain_gateway_port="${CHAIN_GATEWAY_PORT}" \
  -Jorderer_mgmt_host="${ORDERER_MGMT_HOST}" \
  -Jorderer_mgmt_port="${ORDERER_MGMT_PORT}" \
  -Jmonitor_admin_email="${MONITOR_ADMIN_EMAIL}" \
  -Jmonitor_admin_password="${MONITOR_ADMIN_PASSWORD}"

set +e
python3 "${ROOT_DIR}/evaluation/scripts/evaluate_jtl.py" \
  --jtl "${JTL_FILE}" \
  --out-json "${SUMMARY_JSON}" \
  --out-md "${SUMMARY_MD}" \
  --max-p95-ms "${MAX_P95_MS}" \
  --max-error-pct "${MAX_ERROR_PCT}"
EVAL_EXIT=$?
set -e

cat > "${OUT_DIR}/meta.env" <<META
RUN_AT=${TS}
SCENARIO_NAME=${SCENARIO_NAME}
WALLET_USERS=${WALLET_USERS}
WALLET_RAMP=${WALLET_RAMP}
WALLET_LOOPS=${WALLET_LOOPS}
MONITOR_USERS=${MONITOR_USERS}
MONITOR_RAMP=${MONITOR_RAMP}
MONITOR_LOOPS=${MONITOR_LOOPS}
CHAIN_PROBE_USERS=${CHAIN_PROBE_USERS}
CHAIN_PROBE_RAMP=${CHAIN_PROBE_RAMP}
CHAIN_PROBE_LOOPS=${CHAIN_PROBE_LOOPS}
WALLET_HOST=${WALLET_HOST}
WALLET_PORT=${WALLET_PORT}
MONITOR_HOST=${MONITOR_HOST}
MONITOR_PORT=${MONITOR_PORT}
CHAIN_GATEWAY_HOST=${CHAIN_GATEWAY_HOST}
CHAIN_GATEWAY_PORT=${CHAIN_GATEWAY_PORT}
ORDERER_MGMT_HOST=${ORDERER_MGMT_HOST}
ORDERER_MGMT_PORT=${ORDERER_MGMT_PORT}
MAX_P95_MS=${MAX_P95_MS}
MAX_ERROR_PCT=${MAX_ERROR_PCT}
META

echo "[run] done"
echo "[run] dashboard: ${DASHBOARD_DIR}/index.html"
echo "[run] summary: ${SUMMARY_MD}"
echo "[run] scenario: ${SCENARIO_NAME}"
echo "[run] evaluation_exit: ${EVAL_EXIT}"

exit "${EVAL_EXIT}"
