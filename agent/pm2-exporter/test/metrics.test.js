'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { escapeLabel, renderMetrics } = require('../metrics');

test('escapes Prometheus label values', () => {
  assert.equal(escapeLabel('api"one\\two\nnext'), 'api\\"one\\\\two\\nnext');
});

test('renders whitelisted PM2 metrics without leaking environment values', () => {
  const nowMs = Date.UTC(2026, 7, 27, 10, 0, 0);
  const metrics = renderMetrics([
    {
      name: 'api',
      pm_id: 2,
      monit: { cpu: 12.5, memory: 134217728 },
      pm2_env: {
        NODE_APP_INSTANCE: '0',
        status: 'online',
        exec_mode: 'cluster_mode',
        pm_uptime: nowMs - 60000,
        restart_time: 3,
        unstable_restarts: 1,
        instances: 2,
        SECRET_TOKEN: 'must-never-appear',
      },
    },
    {
      name: 'api',
      pm_id: 3,
      monit: { cpu: 4, memory: 67108864 },
      pm2_env: {
        NODE_APP_INSTANCE: '1',
        status: 'errored',
        exec_mode: 'cluster_mode',
        pm_uptime: nowMs - 30000,
        restart_time: 8,
        unstable_restarts: 2,
        instances: 2,
      },
    },
    {
      name: 'opspika-process-exporter',
      pm_id: 99,
      monit: { cpu: 1, memory: 1024 },
      pm2_env: { status: 'online' },
    },
  ], {
    collectSuccess: true,
    lastCollectMs: nowMs,
    nowMs,
  });

  assert.match(metrics, /pm2_process_up\{app="api",instance="0"\} 1/);
  assert.match(metrics, /pm2_process_up\{app="api",instance="1"\} 0/);
  assert.match(metrics, /pm2_process_memory_bytes\{app="api",instance="0"\} 134217728/);
  assert.match(metrics, /pm2_process_uptime_seconds\{app="api",instance="0"\} 60/);
  assert.match(metrics, /pm2_app_instances_configured\{app="api"\} 2/);
  assert.match(metrics, /pm2_app_instances_running\{app="api"\} 1/);
  assert.doesNotMatch(metrics, /SECRET_TOKEN/);
  assert.doesNotMatch(metrics, /must-never-appear/);
  assert.doesNotMatch(metrics, /opspika-process-exporter/);
});

test('reports collection failure while retaining previous process values', () => {
  const metrics = renderMetrics([], {
    collectSuccess: false,
    lastCollectMs: 1000,
    nowMs: 1000,
  });
  assert.match(metrics, /pm2_exporter_collect_success 0/);
});
