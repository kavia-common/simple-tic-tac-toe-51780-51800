#!/usr/bin/env bash
set -euo pipefail
# Minimal, idempotent scaffolding for Node.js project
WORKSPACE="/home/kavia/workspace/code-generation/simple-tic-tac-toe-51780-51800/backend"
cd "$WORKSPACE"
TS=$(date -u +%s)
backup_if_exists(){ [ -f "$1" ] && mv "$1" "$1.bak.$TS"; }
# Backup existing files
backup_if_exists package.json
backup_if_exists index.js
backup_if_exists jest.config.js
backup_if_exists .env.example
backup_if_exists .gitignore
# Write package.json
cat > package.json <<'JSON'
{
  "name": "simple-tic-tac-toe",
  "version": "0.1.0",
  "private": true,
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "dev": "nodemon index.js",
    "test": "jest --runInBand"
  },
  "dependencies": {
    "express": "^4.18.2"
  },
  "devDependencies": {
    "nodemon": "^2.0.22",
    "jest": "^29.6.1"
  }
}
JSON
# Write index.js implementing express server with in-memory state and improved shutdown handling
cat > index.js <<'JS'
const express = require('express');
const app = express();
app.use(express.json());
const games = {};
app.get('/health', (req, res) => res.json({ ok: true }));
app.post('/games', (req, res) => {
  const id = Date.now().toString();
  games[id] = { board: Array(9).fill(null), turn: 'X', status: 'playing' };
  res.json({ id, game: games[id] });
});
app.get('/games/:id', (req, res) => res.json({ id: req.params.id, game: games[req.params.id] || null }));

const PORT = process.env.PORT || 3000;
const server = app.listen(PORT, () => console.log(`listening ${PORT} env=${process.env.NODE_ENV||''}`));

let shuttingDown = false;
const shutdown = (signal) => {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`Received ${signal}, shutting down...`);
  const timeout = setTimeout(() => {
    console.warn('Graceful shutdown timed out, forcing exit');
    process.exit(1);
  }, 5000).unref();

  server.close((err) => {
    clearTimeout(timeout);
    if (err) {
      console.error('Error during server.close:', err);
      process.exit(1);
    }
    console.log('Shutdown complete');
    process.exit(0);
  });
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('uncaughtException', (err) => {
  console.error('uncaughtException:', err);
  shutdown('uncaughtException');
});
JS
# Write .gitignore and .env.example and jest.config.js if missing
[ -f .gitignore ] || cat > .gitignore <<'GIT'
node_modules/
.env
GIT
[ -f .env.example ] || cat > .env.example <<'ENV'
PORT=3000
ENV=development
ENV
[ -f jest.config.js ] || cat > jest.config.js <<'JST'
module.exports = { testEnvironment: 'node' };
JST
# Generate package-lock.json non-interactively so deps step has a lockfile
if [ "${SKIP_LOCAL_DEPS:-false}" != "true" ]; then
  npm --package-lock-only --silent --no-audit --no-fund || true
fi
