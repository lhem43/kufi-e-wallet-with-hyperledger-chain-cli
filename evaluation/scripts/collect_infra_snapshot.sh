#!/usr/bin/env bash
set -euo pipefail

OUT="${1:-evaluation/results/infra-snapshot-$(date +%Y%m%d-%H%M%S).txt}"
mkdir -p "$(dirname "$OUT")"

SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/kufi_github_deploy}"
SSH_OPTS=(-o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
if [[ -f "$SSH_KEY_PATH" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY_PATH")
fi

WALLET_SSH_USER="${WALLET_SSH_USER:-ubuntu}"
WALLET_SSH_HOST="${WALLET_SSH_HOST:-203.0.113.10}"
MONITOR_SSH_USER="${MONITOR_SSH_USER:-ubuntu}"
MONITOR_SSH_HOST="${MONITOR_SSH_HOST:-203.0.113.20}"

collect_remote() {
  local user="$1"
  local host="$2"
  if [[ -z "$host" ]]; then
    return 0
  fi
  ssh "${SSH_OPTS[@]}" "${user}@${host}" \
    'hostname; uptime; free -h; df -h; pm2 ls; docker ps --format "table {{.Names}}\t{{.Status}}"' || true
}

{
  echo "=== $(date '+%F %T') Infra Snapshot ==="
  echo
  echo "--- Wallet VM (${WALLET_SSH_USER}@${WALLET_SSH_HOST}) ---"
  collect_remote "$WALLET_SSH_USER" "$WALLET_SSH_HOST"
  echo
  echo "--- Monitor VM (${MONITOR_SSH_USER}@${MONITOR_SSH_HOST}) ---"
  collect_remote "$MONITOR_SSH_USER" "$MONITOR_SSH_HOST"
} > "$OUT"

echo "[snapshot] wrote $OUT"
