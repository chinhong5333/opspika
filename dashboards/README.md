# OpsPika Dashboards and Alerts

OpsPika ships three original OpenObserve v8 dashboard assets:

| File | Purpose |
|---|---|
| `opspika-host-health.dashboard.json` | CPU, load, memory, swap, filesystem, disk, network, process count, and uptime |
| `opspika-pm2-applications.dashboard.json` | Optional PM2 exporter health and per-application metrics |
| `opspika-process-logs.dashboard.json` | Error volume, application volume, and latest searchable process logs |

The central installer imports missing dashboards automatically. Provisioning is
idempotent and preserves an existing dashboard with the same exact title:

```bash
sudo ./central/scripts/provision-dashboards.sh
```

The JSON follows the OpenObserve v8 dashboard contract used by the pinned
OpenObserve `v0.90.3` API. The disposable API test imports each asset into a
clean server and executes all 21 panel queries.

## Variables

Host and PM2 dashboards use:

- `environment`
- `host_name`

PM2 application and log dashboards also use:

- `app`

## Process Log Search

The `pm2_logs` stream is configured for full-text search on `body` and indexed
exact-match filtering on:

- `host_name`
- `deployment_environment_name`
- `pm2_app`
- `pm2_stream`
- `log_file_name`

Apply the settings after the stream first appears:

```bash
sudo ./central/scripts/configure-streams.sh
```

## Alert Templates

Destination-neutral templates live in `../alerts/`:

- Sustained high CPU.
- Sustained high memory.
- Filesystem near capacity.
- Per-host telemetry missing.
- PM2 application instance not online.
- Excessive PM2 restarts.
- PM2 stderr records detected.

Repository templates are intentionally disabled and contain no webhook, email,
or other environment-specific destination. After creating and testing a real
OpenObserve destination, provision enabled alerts with:

```bash
sudo ./central/scripts/provision-alerts.sh \
  --destination YOUR_TESTED_DESTINATION \
  --enable
```

The provisioner creates one telemetry-loss alert per discovered host, preserves
same-name alerts, and skips templates whose stream does not exist yet.

## Validation

```bash
node ./scripts/validate-assets.js
```

For live API validation, provide the pinned OpenObserve binary in a disposable
Ubuntu environment:

```bash
sudo OPENOBSERVE_BINARY=/path/to/openobserve \
  ./scripts/test-openobserve-api.sh
```

The live test uses only a unique `/tmp` data directory and removes it afterward.
No third-party dashboard JSON, screenshots, logos, fonts, or visual assets are
included in OpsPika.
