#!/usr/bin/env bash
set -euo pipefail

# Canonical workspace path from container context
WORKSPACE="/home/kavia/workspace/code-generation/simple-tic-tac-toe-51780-51800/backend"
cd "$WORKSPACE"

# Ensure tests dir exists
mkdir -p __tests__
TS=$(date -u +%s)

# Generate per-run randomized TEST_PORT unless provided
TEST_PORT_ENV=${TEST_PORT:-$((3000 + (RANDOM % 1000)))}
TEST_TIMEOUT_MS=${TEST_TIMEOUT_MS:-10000}

TEST_FILE=__tests__/app.test.js
[ -f "$TEST_FILE" ] && mv "$TEST_FILE" "$TEST_FILE.bak.$TS"

# Per-run temp logs to avoid accumulation
OUTLOG=$(mktemp /tmp/tictac_out.XXXXXX)
ERRLOG=$(mktemp /tmp/tictac_err.XXXXXX)

# Write the minimal Jest test
cat > "$TEST_FILE" <<'TEST'
const http = require('http');
const cp = require('child_process');
const fs = require('fs');
const PORT = Number(process.env.TEST_PORT || 3000);
const TIMEOUT_MS = Number(process.env.TEST_TIMEOUT_MS || 10000);
let proc;

const waitForHealth = async (timeoutMs=TIMEOUT_MS) => {
  const start = Date.now();
  while (Date.now()-start < timeoutMs) {
    try {
      const res = await new Promise((res,rej)=>{
        const req = http.get({host:'127.0.0.1',port:PORT,path:'/health',timeout:2000}, r=>{
          let b=''; r.on('data',d=>b+=d); r.on('end',()=>res({status:r.statusCode,body:b}));
        });
        req.on('error', rej);
      });
      if (res && res.status===200) return res;
    } catch(e){}
    await new Promise(r=>setTimeout(r,300));
  }
  throw new Error('health timeout');
};

beforeAll(async ()=>{
  const out = fs.openSync(process.env.TEST_OUTLOG, 'a');
  const err = fs.openSync(process.env.TEST_ERRLOG, 'a');
  proc = cp.spawn('node', ['index.js'], { env: Object.assign({}, process.env, { PORT: String(PORT), NODE_ENV: 'test' }), stdio: ['ignore', out, err] });
  await waitForHealth(TIMEOUT_MS);
});

afterAll(async ()=>{
  if (proc) {
    try { proc.kill('SIGTERM'); } catch(e){}
    await new Promise(res=>proc.on('exit', res));
  }
});

test('health returns 200', async ()=>{
  const res = await new Promise((res,rej)=>{
    const req = http.get({host:'127.0.0.1',port:PORT,path:'/health',timeout:2000}, r=>{
      let b=''; r.on('data',d=>b+=d); r.on('end',()=>res({status:r.statusCode,body:b}));
    });
    req.on('error', rej);
  });
  expect(res.status).toBe(200);
  const js = JSON.parse(res.body);
  expect(js.ok).toBe(true);
});
TEST

# Export envs reliably for the test run
export TEST_PORT="$TEST_PORT_ENV"
export TEST_TIMEOUT_MS="$TEST_TIMEOUT_MS"
export TEST_OUTLOG="$OUTLOG"
export TEST_ERRLOG="$ERRLOG"

# Prefer local jest binary if present, else fall back to npm test
if [ -x "node_modules/.bin/jest" ]; then
  TEST_PORT="$TEST_PORT_ENV" TEST_TIMEOUT_MS="$TEST_TIMEOUT_MS" TEST_OUTLOG="$OUTLOG" TEST_ERRLOG="$ERRLOG" node_modules/.bin/jest --runInBand --silent
else
  TEST_PORT="$TEST_PORT_ENV" TEST_TIMEOUT_MS="$TEST_TIMEOUT_MS" TEST_OUTLOG="$OUTLOG" TEST_ERRLOG="$ERRLOG" npm test --silent
fi
