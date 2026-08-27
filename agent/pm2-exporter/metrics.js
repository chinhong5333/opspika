'use strict';

const EXPORTER_PROCESS_NAME = process.env.PM2_EXPORTER_PROCESS_NAME || 'opspika-process-exporter';
const KNOWN_STATUSES = new Set([
  'online',
  'stopped',
  'stopping',
  'launching',
  'errored',
  'one-launch-status',
]);

function escapeLabel(value) {
  return String(value)
    .replaceAll('\\', '\\\\')
    .replaceAll('\n', '\\n')
    .replaceAll('"', '\\"');
}

function finiteNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function metricLine(name, labels, value) {
  const encodedLabels = Object.entries(labels)
    .map(([key, labelValue]) => `${key}="${escapeLabel(labelValue)}"`)
    .join(',');
  const suffix = encodedLabels.length > 0 ? `{${encodedLabels}}` : '';
  return `${name}${suffix} ${finiteNumber(value)}`;
}

function processIdentity(proc) {
  const env = proc?.pm2_env;
  if (!env || typeof proc.name !== 'string' || proc.name.length === 0) {
    return null;
  }

  const rawInstance = env.NODE_APP_INSTANCE;
  const fallbackInstance = proc.pm_id;
  const instance = rawInstance === undefined || rawInstance === null
    ? String(fallbackInstance ?? '0')
    : String(rawInstance);
  const rawStatus = typeof env.status === 'string' ? env.status : 'unknown';
  const status = KNOWN_STATUSES.has(rawStatus) ? rawStatus : 'unknown';

  return {
    app: proc.name,
    instance,
    status,
    execMode: typeof env.exec_mode === 'string' ? env.exec_mode : 'unknown',
    env,
  };
}

function renderMetrics(processes, state = {}) {
  const nowMs = Number.isFinite(state.nowMs) ? state.nowMs : Date.now();
  const collectSuccess = state.collectSuccess === false ? 0 : 1;
  const lastCollectMs = Number.isFinite(state.lastCollectMs) ? state.lastCollectMs : nowMs;
  const safeProcesses = Array.isArray(processes) ? processes : [];
  const rows = [];
  const appSummary = new Map();

  rows.push('# HELP pm2_exporter_collect_success Whether the latest PM2 collection succeeded.');
  rows.push('# TYPE pm2_exporter_collect_success gauge');
  rows.push(`pm2_exporter_collect_success ${collectSuccess}`);
  rows.push('# HELP pm2_exporter_last_collect_timestamp_seconds Unix timestamp of the latest PM2 collection attempt.');
  rows.push('# TYPE pm2_exporter_last_collect_timestamp_seconds gauge');
  rows.push(`pm2_exporter_last_collect_timestamp_seconds ${Math.floor(lastCollectMs / 1000)}`);

  const metricHeaders = [
    ['pm2_process_info', 'Static PM2 process information.'],
    ['pm2_process_up', 'Whether the PM2 process is online.'],
    ['pm2_process_cpu_percent', 'PM2 process CPU utilization percentage.'],
    ['pm2_process_memory_bytes', 'PM2 process resident memory in bytes.'],
    ['pm2_process_uptime_seconds', 'Seconds since the PM2 process started.'],
    ['pm2_process_restarts', 'Restart count reported by PM2.'],
    ['pm2_process_unstable_restarts', 'Unstable restart count reported by PM2.'],
  ];
  for (const [name, help] of metricHeaders) {
    rows.push(`# HELP ${name} ${help}`);
    rows.push(`# TYPE ${name} gauge`);
  }

  const sortedProcesses = safeProcesses
    .filter((proc) => proc?.name !== EXPORTER_PROCESS_NAME)
    .map((proc) => ({ proc, identity: processIdentity(proc) }))
    .filter(({ identity }) => identity !== null)
    .sort((left, right) => {
      const appOrder = left.identity.app.localeCompare(right.identity.app);
      return appOrder !== 0
        ? appOrder
        : left.identity.instance.localeCompare(right.identity.instance);
    });

  for (const { proc, identity } of sortedProcesses) {
    const { app, instance, status, execMode, env } = identity;
    const labels = { app, instance };
    const infoLabels = { app, instance, status, exec_mode: execMode };
    const uptimeSeconds = Number.isFinite(Number(env.pm_uptime)) && Number(env.pm_uptime) > 0
      ? Math.max(0, (nowMs - Number(env.pm_uptime)) / 1000)
      : 0;

    rows.push(metricLine('pm2_process_info', infoLabels, 1));
    rows.push(metricLine('pm2_process_up', labels, status === 'online' ? 1 : 0));
    rows.push(metricLine('pm2_process_cpu_percent', labels, proc?.monit?.cpu));
    rows.push(metricLine('pm2_process_memory_bytes', labels, proc?.monit?.memory));
    rows.push(metricLine('pm2_process_uptime_seconds', labels, uptimeSeconds));
    rows.push(metricLine('pm2_process_restarts', labels, env.restart_time));
    rows.push(metricLine('pm2_process_unstable_restarts', labels, env.unstable_restarts));

    const current = appSummary.get(app) || {
      configured: finiteNumber(env.instances, 1),
      running: 0,
    };
    current.configured = Math.max(current.configured, finiteNumber(env.instances, 1));
    if (status === 'online') {
      current.running += 1;
    }
    appSummary.set(app, current);
  }

  rows.push('# HELP pm2_app_instances_configured Configured PM2 instance count for an application.');
  rows.push('# TYPE pm2_app_instances_configured gauge');
  rows.push('# HELP pm2_app_instances_running Currently online PM2 instance count for an application.');
  rows.push('# TYPE pm2_app_instances_running gauge');
  for (const [app, summary] of [...appSummary.entries()].sort(([left], [right]) => left.localeCompare(right))) {
    rows.push(metricLine('pm2_app_instances_configured', { app }, summary.configured));
    rows.push(metricLine('pm2_app_instances_running', { app }, summary.running));
  }

  return `${rows.join('\n')}\n`;
}

module.exports = {
  escapeLabel,
  finiteNumber,
  renderMetrics,
};
