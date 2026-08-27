'use strict';

const fs = require('node:fs');
const path = require('node:path');

const repoDir = path.resolve(__dirname, '..');

function jsonFiles(directory, suffix) {
  return fs.readdirSync(directory)
    .filter((name) => name.endsWith(suffix))
    .sort()
    .map((name) => path.join(directory, name));
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    throw new Error(`${path.relative(repoDir, file)} is not valid JSON: ${error.message}`);
  }
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

const dashboardFiles = jsonFiles(path.join(repoDir, 'dashboards'), '.dashboard.json');
assert(dashboardFiles.length >= 3, 'At least three OpsPika dashboards are required.');

const dashboardTitles = new Set();
for (const file of dashboardFiles) {
  const relative = path.relative(repoDir, file);
  const dashboard = readJson(file);
  assert(dashboard.version === 8, `${relative}: dashboard version must be 8.`);
  assert(typeof dashboard.title === 'string' && dashboard.title.startsWith('OpsPika '),
    `${relative}: title must start with "OpsPika ".`);
  assert(!dashboardTitles.has(dashboard.title), `${relative}: duplicate dashboard title.`);
  dashboardTitles.add(dashboard.title);
  assert(Array.isArray(dashboard.tabs) && dashboard.tabs.length > 0,
    `${relative}: at least one tab is required.`);

  const panelIds = new Set();
  for (const tab of dashboard.tabs) {
    assert(typeof tab.tabId === 'string' && tab.tabId.length > 0,
      `${relative}: every tab needs tabId.`);
    assert(Array.isArray(tab.panels) && tab.panels.length > 0,
      `${relative}: every tab needs panels.`);
    for (const panel of tab.panels) {
      assert(typeof panel.id === 'string' && panel.id.length > 0,
        `${relative}: every panel needs id.`);
      assert(!panelIds.has(panel.id), `${relative}: duplicate panel id ${panel.id}.`);
      panelIds.add(panel.id);
      assert(['promql', 'sql'].includes(panel.queryType),
        `${relative}/${panel.id}: unsupported queryType.`);
      assert(Array.isArray(panel.queries) && panel.queries.length > 0,
        `${relative}/${panel.id}: at least one query is required.`);
      assert(panel.layout && Number.isInteger(panel.layout.x) && Number.isInteger(panel.layout.y)
        && Number.isInteger(panel.layout.w) && Number.isInteger(panel.layout.h),
      `${relative}/${panel.id}: integer layout is required.`);
      for (const query of panel.queries) {
        assert(typeof query.query === 'string' && query.query.length > 0,
          `${relative}/${panel.id}: query text is required.`);
        assert(query.fields && typeof query.fields === 'object',
          `${relative}/${panel.id}: query fields are required.`);
        assert(['metrics', 'logs'].includes(query.fields.stream_type),
          `${relative}/${panel.id}: invalid stream_type.`);
        assert(Array.isArray(query.fields.x) && Array.isArray(query.fields.y)
          && Array.isArray(query.fields.z),
        `${relative}/${panel.id}: x, y, and z arrays are required.`);
        assert(query.fields.filter && !Array.isArray(query.fields.filter)
          && query.fields.filter.filterType === 'group'
          && Array.isArray(query.fields.filter.conditions),
        `${relative}/${panel.id}: v8 filter must be an empty or populated group object.`);
      }
    }
  }
  assert(!JSON.stringify(dashboard).includes('__'), `${relative}: unresolved placeholder.`);
}

const alertFiles = jsonFiles(path.join(repoDir, 'alerts'), '.alert.json');
assert(alertFiles.length >= 7, 'At least seven OpsPika alert templates are required.');

const alertNames = new Set();
for (const file of alertFiles) {
  const relative = path.relative(repoDir, file);
  const alert = readJson(file);
  assert(typeof alert.name === 'string' && /^opspika_[a-z0-9_]+$/.test(alert.name),
    `${relative}: alert name must be OpsPika snake_case.`);
  assert(!alertNames.has(alert.name), `${relative}: duplicate alert name.`);
  alertNames.add(alert.name);
  assert(['metrics', 'logs'].includes(alert.stream_type), `${relative}: invalid stream_type.`);
  assert(typeof alert.stream_name === 'string' && alert.stream_name.length > 0,
    `${relative}: stream_name is required.`);
  assert(alert.query_condition && ['promql', 'sql'].includes(alert.query_condition.type),
    `${relative}: alert query type must be promql or sql.`);
  assert(alert.trigger_condition && Number.isInteger(alert.trigger_condition.period)
    && Number.isInteger(alert.trigger_condition.frequency),
  `${relative}: trigger period and frequency are required integers.`);
  assert(Array.isArray(alert.destinations) && alert.destinations.length === 0,
    `${relative}: repository templates must not contain environment-specific destinations.`);
  assert(alert.enabled === false, `${relative}: repository templates must be disabled.`);

  const serialized = JSON.stringify(alert);
  const isHostTemplate = path.basename(file) === 'opspika-host-telemetry-missing.alert.json';
  assert(isHostTemplate === serialized.includes('__HOST_NAME__'),
    `${relative}: host placeholder may exist only in the per-host template.`);
}

console.log(`Validated ${dashboardFiles.length} dashboards and ${alertFiles.length} alert templates.`);
