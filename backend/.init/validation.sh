#!/usr/bin/env bash
set -euo pipefail
# validation: install deps if missing, start app, poll /health, capture logs, smoke test, stop
WORKSPACE="/home/kavia/workspace/code-generation/simple-tic-tac-toe-51780-51800/backend"
cd "$WORKSPACE"
# install deps unless skipped and node_modules exists
if [ "${SKIP_LOCAL_DEPS:-false}" != "true" ] && [ ! -d node_modules ]; then
  # prefer npm ci when lockfile present
  if [ -f package-lock.json ]; then
    npm ci --no-audit --no-fund --silent || { npm i --no-audit --no-fund --silent; }
  else
    npm i --no-audit --no-fund --silent
  fi
fi
TS=$(date -u +%s)
LOG=$(mktemp /tmp/tictactoe.$TS.XXXXXX)
PORT=${PORT:-$((3000 + (RANDOM % 1000)))}
NODE_ENV=${NODE_ENV:-development}
# start server in background (no nohup) to capture PID reliably
PORT="$PORT" NODE_ENV="$NODE_ENV" node index.js >"$LOG" 2>&1 &
PID=$!
# ensure child is cleaned up and original exit code re-raised
cleanup() { local rc=${1:-0}; if kill -0 "$PID" >/dev/null 2>&1; then kill -TERM "$PID" >/dev/null 2>&1 || true; fi; wait "$PID" 2>/dev/null || true; echo "validation log: $LOG"; exit "$rc"; }
trap 'cleanup $?' INT TERM EXIT
# poll health endpoint with backoff up to HEALTH_TIMEOUT seconds (default 15)
HEALTH_TIMEOUT=${HEALTH_TIMEOUT:-15}
interval=0.5
elapsed=0
until curl -sS --fail "http://127.0.0.1:$PORT/health" -o /dev/null 2>&1; do
  sleep "$interval"
  elapsed=$(awk "BEGIN {print $elapsed + $interval}")
  if (( $(echo "$elapsed >= $HEALTH_TIMEOUT" | bc -l) )); then
    echo "ERROR: health check timed out after ${HEALTH_TIMEOUT}s, see $LOG" >&2
    cat "$LOG" >&2 || true
    trap - INT TERM EXIT
    cleanup 30
  fi
done
# fetch health JSON to temp file and print compact evidence
HEALTH_JSON=/tmp/health.${TS}.json
if ! curl -sS --fail "http://127.0.0.1:$PORT/health" -o "$HEALTH_JSON"; then
  echo "ERROR: failed to fetch /health, see $LOG" >&2
  cat "$LOG" >&2 || true
  trap - INT TERM EXIT
  cleanup 31
fi
# output the health JSON and log path as compact evidence
cat "$HEALTH_JSON"
echo "validation log: $LOG" >&2
# graceful shutdown and exit success
trap - INT TERM EXIT
cleanup 0
