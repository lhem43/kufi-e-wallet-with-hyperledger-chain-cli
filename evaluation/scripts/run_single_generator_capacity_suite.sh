#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCENARIO_DIR="${SCENARIO_DIR:-${ROOT_DIR}/evaluation/scenarios_single_generator}"

SUITE_ID="${SUITE_ID:-$(date +%Y%m%d-%H%M%S)-single-generator}"
SUITE_DIR="${ROOT_DIR}/evaluation/results/suites/${SUITE_ID}"
STATUS_TSV="${SUITE_DIR}/suite-status.tsv"

mkdir -p "${SUITE_DIR}"

echo -e "scenario\tscenario_file\texit_code\tout_dir" > "${STATUS_TSV}"

SCENARIOS=("${SCENARIO_DIR}"/*.env)
if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  echo "[suite] no scenario files found in ${SCENARIO_DIR}" >&2
  exit 1
fi

ANY_FAIL=0

echo "[suite] id: ${SUITE_ID}"
echo "[suite] output: ${SUITE_DIR}"
echo "[suite] scenarios: ${SCENARIO_DIR}"

if [[ "${CAPTURE_INFRA_SNAPSHOT:-false}" == "true" ]]; then
  SNAPSHOT_OUT="${SUITE_DIR}/infra-snapshot-before.txt"
  bash "${ROOT_DIR}/evaluation/scripts/collect_infra_snapshot.sh" "${SNAPSHOT_OUT}" || true
fi

for scenario_file in "${SCENARIOS[@]}"; do
  [[ -f "${scenario_file}" ]] || continue

  unset SCENARIO_NAME WALLET_USERS WALLET_RAMP WALLET_LOOPS MONITOR_USERS MONITOR_RAMP MONITOR_LOOPS
  unset CHAIN_PROBE_USERS CHAIN_PROBE_RAMP CHAIN_PROBE_LOOPS MAX_P95_MS MAX_ERROR_PCT

  # shellcheck disable=SC1090
  source "${scenario_file}"

  scenario="${SCENARIO_NAME:-$(basename "${scenario_file}" .env)}"
  out_dir="${SUITE_DIR}/${scenario}"

  echo "[suite] running scenario: ${scenario}"
  set +e
  OUT_DIR="${out_dir}" \
  SCENARIO_NAME="${scenario}" \
  WALLET_USERS="${WALLET_USERS:-}" \
  WALLET_RAMP="${WALLET_RAMP:-}" \
  WALLET_LOOPS="${WALLET_LOOPS:-}" \
  MONITOR_USERS="${MONITOR_USERS:-}" \
  MONITOR_RAMP="${MONITOR_RAMP:-}" \
  MONITOR_LOOPS="${MONITOR_LOOPS:-}" \
  CHAIN_PROBE_USERS="${CHAIN_PROBE_USERS:-}" \
  CHAIN_PROBE_RAMP="${CHAIN_PROBE_RAMP:-}" \
  CHAIN_PROBE_LOOPS="${CHAIN_PROBE_LOOPS:-}" \
  MAX_P95_MS="${MAX_P95_MS:-}" \
  MAX_ERROR_PCT="${MAX_ERROR_PCT:-}" \
  WALLET_HOST="${WALLET_HOST:-}" \
  WALLET_PORT="${WALLET_PORT:-}" \
  MONITOR_HOST="${MONITOR_HOST:-}" \
  MONITOR_PORT="${MONITOR_PORT:-}" \
  CHAIN_GATEWAY_HOST="${CHAIN_GATEWAY_HOST:-}" \
  CHAIN_GATEWAY_PORT="${CHAIN_GATEWAY_PORT:-}" \
  ORDERER_MGMT_HOST="${ORDERER_MGMT_HOST:-}" \
  ORDERER_MGMT_PORT="${ORDERER_MGMT_PORT:-}" \
  MONITOR_ADMIN_EMAIL="${MONITOR_ADMIN_EMAIL:-}" \
  MONITOR_ADMIN_PASSWORD="${MONITOR_ADMIN_PASSWORD:-}" \
  bash "${ROOT_DIR}/evaluation/scripts/run_jmeter_scenario.sh"
  exit_code=$?
  set -e

  echo -e "${scenario}\t${scenario_file}\t${exit_code}\t${out_dir}" >> "${STATUS_TSV}"

  if [[ ${exit_code} -ne 0 ]]; then
    ANY_FAIL=1
  fi
done

python3 "${ROOT_DIR}/evaluation/scripts/summarize_suite.py" \
  --suite-dir "${SUITE_DIR}" \
  --status-tsv "${STATUS_TSV}" \
  --out-md "${SUITE_DIR}/suite-summary.md" \
  --out-json "${SUITE_DIR}/suite-summary.json"

python3 "${ROOT_DIR}/evaluation/scripts/build_suite_report.py" \
  --suite-dir "${SUITE_DIR}" \
  --status-tsv "${STATUS_TSV}" \
  --out-dir "${SUITE_DIR}/report"

if [[ "${CAPTURE_INFRA_SNAPSHOT:-false}" == "true" ]]; then
  SNAPSHOT_OUT="${SUITE_DIR}/infra-snapshot-after.txt"
  bash "${ROOT_DIR}/evaluation/scripts/collect_infra_snapshot.sh" "${SNAPSHOT_OUT}" || true
fi

echo "[suite] done"
echo "[suite] summary: ${SUITE_DIR}/suite-summary.md"
echo "[suite] report: ${SUITE_DIR}/report/report.md"
echo "[suite] note: this suite is single-load-generator capacity benchmarking, not direct proof of 5k/10k real concurrent users."

exit ${ANY_FAIL}
