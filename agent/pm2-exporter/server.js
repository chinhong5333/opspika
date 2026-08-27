'use strict';

const http = require('node:http');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const { renderMetrics } = require('./metrics');

const execFileAsync = promisify(execFile);
const host = process.env.PM2_EXPORTER_HOST || '127.0.0.1';
const port = parseInteger('PM2_EXPORTER_PORT', process.env.PM2_EXPORTER_PORT || '9988', 1, 65535);
const intervalMs = parseInteger(
  'PM2_EXPORTER_INTERVAL_MS',
  process.env.PM2_EXPORTER_INTERVAL_MS || '5000',
  1000,
  300000,
);
const commandTimeoutMs = parseInteger(
  'PM2_EXPORTER_COMMAND_TIMEOUT_MS',
  process.env.PM2_EXPORTER_COMMAND_TIMEOUT_MS || '5000',
  1000,
  60000,
);
const pm2Binary = process.env.PM2_BINARY || 'pm2';

let cache = {
  processes: [],
  collectSuccess: false,
  lastCollectMs: 0,
  metrics: renderMetrics([], { collectSuccess: false, lastCollectMs: 0 }),
};
let collecting = false;

function parseInteger(name, value, min, max) {
  if (!/^\d+$/.test(String(value))) {
    throw new Error(`${name} must be an integer.`);
  }
  const number = Number(value);
  if (number < min || number > max) {
    throw new Error(`${name} must be between ${min} and ${max}.`);
  }
  return number;
}

async function collect() {
  if (collecting) {
    return;
  }
  collecting = true;
  const collectedAt = Date.now();
  try {
    const { stdout } = await execFileAsync(pm2Binary, ['jlist'], {
      encoding: 'utf8',
      env: process.env,
      maxBuffer: 16 * 1024 * 1024,
      shell: process.platform === 'win32',
      timeout: commandTimeoutMs,
      windowsHide: true,
    });
    const parsed = JSON.parse(stdout.trim());
    if (!Array.isArray(parsed)) {
      throw new Error('PM2 jlist returned a non-array JSON document.');
    }
    cache = {
      processes: parsed,
      collectSuccess: true,
      lastCollectMs: collectedAt,
      metrics: renderMetrics(parsed, {
        collectSuccess: true,
        lastCollectMs: collectedAt,
        nowMs: collectedAt,
      }),
    };
  } catch (error) {
    cache = {
      ...cache,
      collectSuccess: false,
      lastCollectMs: collectedAt,
      metrics: renderMetrics(cache.processes, {
        collectSuccess: false,
        lastCollectMs: collectedAt,
        nowMs: collectedAt,
      }),
    };
    console.error(`PM2 metric collection failed: ${error.message}`);
  } finally {
    collecting = false;
  }
}

const server = http.createServer((request, response) => {
  if (request.method !== 'GET') {
    response.writeHead(405, { Allow: 'GET' });
    response.end('Method Not Allowed\n');
    return;
  }

  if (request.url === '/metrics') {
    response.writeHead(200, {
      'Cache-Control': 'no-store',
      'Content-Type': 'text/plain; version=0.0.4; charset=utf-8',
    });
    response.end(cache.metrics);
    return;
  }

  if (request.url === '/healthz') {
    const recent = Date.now() - cache.lastCollectMs <= intervalMs * 3;
    const healthy = cache.collectSuccess && recent;
    response.writeHead(healthy ? 200 : 503, {
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
    });
    response.end(`${JSON.stringify({ status: healthy ? 'ok' : 'unhealthy' })}\n`);
    return;
  }

  response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  response.end('Not Found\n');
});

function shutdown(signal) {
  console.log(`Received ${signal}; stopping PM2 exporter.`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

server.listen(port, host, async () => {
  console.log(`PM2 exporter listening on http://${host}:${port}`);
  await collect();
  setInterval(collect, intervalMs);
});
