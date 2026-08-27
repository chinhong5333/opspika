# OpsPika Process Exporter

A dependency-free, local-only Prometheus exporter for PM2. It invokes the
official `pm2 jlist` command, reads only documented process fields, and never
exports the PM2 environment object.

The Ubuntu agent installer deploys this exporter as a PM2-managed process named
`opspika-process-exporter`. The exporter binds to `127.0.0.1:9988`, where the local
OpenObserve Agent scrapes it.

Endpoints:

- `GET /metrics` — Prometheus text format.
- `GET /healthz` — collection health.

Configuration:

| Variable | Default | Purpose |
|---|---|---|
| `PM2_EXPORTER_HOST` | `127.0.0.1` | Listen address |
| `PM2_EXPORTER_PORT` | `9988` | Listen port |
| `PM2_EXPORTER_INTERVAL_MS` | `5000` | PM2 collection interval |
| `PM2_EXPORTER_COMMAND_TIMEOUT_MS` | `5000` | `pm2 jlist` timeout |
| `PM2_BINARY` | `pm2` | Canonical PM2 executable |

Run tests with `npm test`. No npm dependencies are required.
