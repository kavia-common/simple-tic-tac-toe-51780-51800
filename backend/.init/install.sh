#!/usr/bin/env bash
set -euo pipefail
# install: install project dependencies in workspace with robust logging and retry
WORKSPACE="/home/kavia/workspace/code-generation/simple-tic-tac-toe-51780-51800/backend"
cd "$WORKSPACE"
# ensure workspace exists
if [ ! -d "$WORKSPACE" ]; then echo "ERROR: workspace $WORKSPACE missing" >&2; exit 2; fi
# quick sanity for node/npm on PATH
command -v node >/dev/null 2>&1 || { echo "ERROR: node not found on PATH" >&2; exit 3; }
command -v npm >/dev/null 2>&1 || { echo "ERROR: npm not found on PATH" >&2; exit 4; }
# temp logfile for capturing npm output on failure
LOGTMP=$(mktemp /tmp/npm-install.XXXXXX)
# installer function prefers package-lock.json -> npm ci, otherwise npm i
_install() {
  if [ -f package-lock.json ]; then
    npm ci --no-audit --no-fund --silent >"$LOGTMP" 2>&1
  else
    npm i --no-audit --no-fund --silent >"$LOGTMP" 2>&1
  fi
}
# Fast-path: skip local devDependencies when requested
if [ "${SKIP_LOCAL_DEPS:-false}" = "true" ]; then
  if npm i --only=prod --no-audit --no-fund --silent >"$LOGTMP" 2>&1; then
    rm -f "$LOGTMP"
    exit 0
  else
    cat "$LOGTMP" >&2
    echo "ERROR: npm install --only=prod failed" >&2
    rm -f "$LOGTMP"
    exit 20
  fi
fi
# Run install with one retry on failure (short backoff)
if ! _install; then
  sleep 1
  echo "npm install failed, retrying once..." >&2
  if ! _install; then
    echo "ERROR: npm install failed twice. See $LOGTMP" >&2
    echo "--- npm log (tail) ---" >&2
    tail -n 200 "$LOGTMP" >&2 || true
    echo "--- environment diagnostics ---" >&2
    npm -v >&2 || true
    node -v >&2 || true
    ls -la . >&2 || true
    rm -f "$LOGTMP"
    exit 21
  fi
fi
rm -f "$LOGTMP"
# Warn if package-lock.json missing after install (do not fail)
if [ ! -f package-lock.json ]; then
  echo "WARN: package-lock.json not present after install. Proceeding but reproducible installs may be impacted." >&2
fi
# validate local jest binary if present (non-fatal)
if [ -x node_modules/.bin/jest ]; then
  node_modules/.bin/jest --version >/dev/null 2>&1 || true
fi
exit 0
