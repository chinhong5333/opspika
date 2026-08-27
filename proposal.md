# OpsPika Server Monitoring Platform Proposal

**Status:** Proposed for development planning
**Proposal date:** 2026-08-26
**Development planning kickoff:** 2026-08-27

## 1. Executive Summary

OpsPika is a self-hosted monitoring platform for Ubuntu servers. It provides complete host statistics without requiring PM2. On servers already running PM2, it additionally provides per-process statistics and searchable PM2 logs. The platform also provides dashboards, alerts, and organization-scoped user administration. PM2 is an optional integration and does not host OpsPika.

The recommended simplified architecture is:

- **OpenObserve** on one central monitoring server for storage, full-text log search, metric history, dashboards, alerts, retention, and the web interface.
- **OpenTelemetry Collector Contrib** on every monitored PM2 server for host metrics, PM2 log tailing, durable offsets, batching, and delivery to OpenObserve.
- **A small PM2 metrics exporter** on every monitored PM2 server. It is managed by the existing PM2 daemon, uses the official `pm2 jlist` contract, and exposes only approved process measurements to the local collector.
- **pm2-logrotate** on every monitored PM2 server to prevent unbounded local log growth.

This replaces the earlier Grafana + Prometheus + OpenSearch design. The required functionality is retained while the central deployment is reduced from three monitoring products to one operational backend.

## 2. Goals

1. Monitor complete server health, not only PM2.
2. Monitor every PM2 application and instance independently.
3. Tail and ingest only new PM2 log content; do not import existing large files such as the current 21 GB+ log.
4. Provide fast full-text log search and near-real-time/live log viewing.
5. Retain historical metrics so incidents, memory leaks, restart loops, and capacity trends can be investigated.
6. Provide dashboards and alerts from one web interface.
7. Support root, organization administrator, and member logins.
8. Install the central platform with one container deployment and each monitored server with one idempotent installer.
9. Require no crontab for collection, delivery, retention, or process supervision.

## 3. Non-Goals for the Initial Release

- Importing or indexing existing PM2 log history.
- Replacing PM2 as the process manager.
- Remotely starting, stopping, restarting, or deleting PM2 applications.
- Distributed high availability, multi-region federation, or object-storage deployment.
- Fine-grained custom RBAC such as restricting a user to selected servers within one organization.
- SSO, custom branding, or other OpenObserve Enterprise-only functionality.
- Application tracing or browser real-user monitoring in the first release.

## 4. Proposed Architecture

```text
PM2 Server A
├── OpenTelemetry Collector
│   ├── hostmetrics receiver ───────────────┐
│   ├── prometheus receiver                 │
│   │   └── scrape local PM2 exporter       ├── OTLP/HTTPS ──┐
│   └── filelog receiver                    │                │
│       └── ~/.pm2/logs/*.log ──────────────┘                │
├── PM2 metrics exporter                                      │
└── pm2-logrotate                                              │
                                                               ▼
PM2 Server B                                               OpenObserve
├── Same collector bundle                               ├── Metrics history
└── Same outbound data flow                             ├── Indexed PM2 logs
                                                        ├── Live log view
                                                        ├── Dashboards
                                                        ├── Alerts
                                                        ├── Users/organizations
                                                        └── Retention
```

All monitored-server connections are outbound to the central server. OpenObserve and the PM2 exporter must not be exposed directly to the public internet.

## 5. Components

### 5.1 Central OpenObserve

OpenObserve provides the single operational backend and interface for:

- Host and PM2 metric ingestion and history.
- PromQL-compatible metric queries.
- PM2 log ingestion, full-text search, and SQL queries.
- Full-text/inverted indexing of selected log fields.
- Dashboards and visualizations.
- Metric- and log-based alerts.
- Retention policies.
- Organizations and local user accounts.

For the proof of concept, OpenObserve will run as a pinned Docker image with a persistent local volume. S3-compatible object storage and a highly available deployment are deferred until scale or recovery requirements justify them.

### 5.2 OpenTelemetry Collector Contrib

One collector runs as a `systemd` service on every PM2 server. Its configuration includes:

- `hostmetrics` receiver for Linux server statistics.
- `prometheus` receiver for the local PM2 exporter.
- `filelog` receiver for PM2 stdout and stderr files.
- `file_storage` extension for persistent file offsets and durable queues.
- `memory_limiter` and `batch` processors.
- Retry and persistent sending queues.
- OTLP/HTTP export to the correct OpenObserve organization.

The collector starts automatically at boot and restarts after failure. It does not use cron.

### 5.3 PM2 Metrics Exporter

The exporter is a small, dependency-free Node.js process managed by the existing PM2 daemon. It uses the official `pm2 jlist` JSON contract, runs under the same Unix user as the target PM2 daemon, and binds only to `127.0.0.1:9988`. It is excluded from its own exported process measurements.

It must whitelist and expose only canonical measurements. It must never log or export the complete result of `pm2 jlist`, because PM2 environment data may contain credentials or other secrets.

Initial PM2 measurements:

- Application name and stable instance identifier.
- Process state: online, stopped, stopping, launching, or errored.
- CPU usage per application instance.
- Memory usage per application instance.
- Uptime.
- Restart count and unstable restart count.
- Configured instance count and currently running instance count.
- PM2 daemon availability.
- Optional Node.js heap, event-loop, request-rate, and latency metrics when the application exposes them.

### 5.4 PM2 Log Rotation

`pm2-logrotate` limits local disk consumption. The initial policy target is:

- Rotate by size and/or daily interval.
- Compress rotated files.
- Retain a small local safety window, initially 2–7 days.
- Use OpenObserve as the searchable retained copy.
- Do not make manual `pm2 flush` part of routine operations.

## 6. What Is Installed Where

| Location | Required installation | Purpose |
|---|---|---|
| Central monitoring server | Docker Engine and Docker Compose | Runs the central deployment |
| Central monitoring server | OpenObserve container, pinned version | UI, metric storage, indexed log storage, dashboards, alerts, users, and retention |
| Central monitoring server | Persistent local data volume | Retains OpenObserve data across container recreation |
| Central monitoring server | TLS reverse proxy, if one is not already available | Secures browser and agent traffic in production |
| Every monitored PM2 server | Existing PM2 installation | Runs the monitored Node.js applications |
| Every monitored PM2 server | OpenTelemetry Collector Contrib | Captures host metrics, scrapes PM2 metrics, tails PM2 logs, buffers, and exports telemetry |
| Every monitored PM2 server | Project-owned PM2 metrics exporter, managed by PM2 | Converts official PM2 process information to Prometheus-format metrics without adding another systemd service |
| Every monitored PM2 server | `pm2-logrotate` | Rotates, compresses, and retains local PM2 logs |
| Administrator workstation | Modern web browser only | Logs in to OpenObserve and views monitoring data |

If the central monitoring server also runs PM2 workloads, it receives both the central installation and the monitored-server agent bundle.

If the central monitoring server does not run PM2, it still receives the same OpenObserve Agent in host-only mode so its CPU, memory, disk, network, and uptime are visible. PM2 modules are not installed in host-only mode.

### Explicitly Not Required

The simplified design does **not** require separate installations of:

- Grafana.
- Prometheus.
- OpenSearch.
- MySQL or PostgreSQL for the proof of concept.
- node_exporter as a separate process.
- Fluent Bit as a separate process.
- Crontab entries for monitoring.

## 7. Data Captured from Every PM2 Server

### 7.1 Host Measurements

- CPU utilization, including per-core statistics where supported.
- Load average.
- Memory and swap utilization.
- Disk capacity, free space, filesystem utilization, and inode usage.
- Disk reads, writes, throughput, and I/O behavior exposed by the host metrics receiver.
- Network throughput, errors, and dropped packets by interface.
- Host uptime and boot time.
- Process counts and relevant operating-system statistics.

Optional collectors can later add Docker/container metrics, GPU metrics, hardware temperature, fan speed, and SMART disk health.

### 7.2 PM2 Measurements

- State and availability of every PM2 application and instance.
- CPU and memory per process.
- Uptime and restart history.
- Desired and active instance counts.
- Optional Node.js runtime metrics.

### 7.3 PM2 Logs

Both stdout and stderr are collected. Each record should contain:

```json
{
  "timestamp": "2026-08-26T12:30:00Z",
  "organization": "default",
  "server_name": "server-01",
  "environment": "production",
  "pm2_app": "api",
  "stream": "error",
  "level": "error",
  "message": "Database connection timed out",
  "source_file": "/home/nodeapp/.pm2/logs/api-error.log"
}
```

Use stable low-cardinality fields for filtering. Operating-system PID, request ID, user ID, and other unbounded values must not be used as primary partition keys. Applications should emit one JSON event per line with a timestamp where practical. Multiline Node.js stack traces must be joined by the collector before ingestion.

## 8. Existing 21 GB+ PM2 Log

The existing content is intentionally excluded.

- Configure the file receiver explicitly with `start_at: end`.
- Persist offsets using the `file_storage` extension.
- Begin ingesting only lines appended after the collector starts.
- Confirm a unique test log entry reaches OpenObserve.
- Remove or rotate the old content only during a controlled maintenance action.
- Continue with automatic rotation instead of routinely flushing active files.

The collector must use durable buffering so a temporary OpenObserve or network outage does not require the active PM2 file to remain the only copy.

## 9. Storage and Retention

OpenObserve is the only separately managed monitoring data backend in the simplified design.

- Logs and metrics are retained in the OpenObserve data volume for the proof of concept.
- The collector's local file storage contains checkpoints and pending delivery buffers only; it is not a second monitoring database.
- Initial metric retention target: 180 days (approximately six months), configurable.
- Initial searchable log retention target: 180 days (approximately six months), configurable.
- Initial local rotated PM2 log retention: 2–7 days as a delivery safety buffer.
- Storage consumption, ingest rate, and retention must be measured during the proof of concept before final production sizing.

## 10. Authentication and Administration

OpenObserve OSS provides local login and organization-scoped access with these roles:

| Role | Intended use |
|---|---|
| `root` | Controls the complete OpenObserve instance and all organizations |
| `admin` | Organization-level administrator; views monitoring data and manages users in that organization |
| `member` | Uses monitoring data and dashboards within the assigned organization |

An organization administrator satisfies the current "sub-admin" requirement when the administrator should be restricted to one organization.

OpenObserve OSS does not provide fine-grained custom RBAC for selected servers or individual permissions. Advanced RBAC and SSO are Enterprise features. If fine-grained permissions become mandatory, choose one of these explicitly during a later phase:

1. OpenObserve Enterprise.
2. A custom control-plane/UI authorization layer in front of OpenObserve.
3. Separate organizations with separate ingestion streams and users.

## 11. Installation and Runtime Model

### 11.1 Central Server

The target operator experience is:

```bash
sudo ./install.sh central
```

The wrapper installs Docker when needed, invokes the pinned Compose deployment, verifies health, and safely reuses existing configuration on subsequent runs. The Compose deployment must use pinned image versions, persistent volumes, health checks, non-default credentials, and documented backup/restore steps. Production deployment must use TLS.

### 11.2 Each PM2 Server

The target operator experience is one idempotent command:

```bash
sudo ./install.sh agent
```

The wrapper automatically selects host or PM2 mode from active PM2 daemons, uses the Ubuntu hostname as the server name, labels data as `production`, uses the `default` OpenObserve organization, and detects the PM2 daemon owner. It prompts only for the client-facing OpenObserve base URL and protected authorization key unless multiple PM2 daemon owners make a user choice necessary. Advanced or automated deployments can invoke `agent/install-monitoring-agent.sh` directly with its canonical options.

Each value has one canonical option name. The installer must not guess aliases or alternate spellings.

The installer will:

1. Validate the operating system, architecture, PM2 user, log directory, and outbound connectivity.
2. Install pinned, checksum-verified collector and exporter artifacts.
3. Write collector, exporter, and log-rotation configuration.
4. Create restricted state, buffer, and credential paths.
5. Install `systemd` units with automatic restart.
6. Start the services and validate their health.
7. Verify host metrics, PM2 metrics, and a synthetic new log entry in OpenObserve.
8. Support safe re-execution and a documented uninstall path.

No monitoring function requires crontab. Updates should be explicit and versioned rather than silently installed on a nightly schedule.

## 12. Network and Security Baseline

- Agents make outbound OTLP/HTTPS connections to the central server.
- The initial design requires no inbound monitoring port on PM2 servers.
- The PM2 exporter binds to `127.0.0.1` only.
- Use one least-privilege ingestion credential per organization, and preferably per server when supported.
- Store tokens in files readable only by the collector service account.
- Never send the full PM2 environment or application secrets as metrics or log attributes.
- Protect the OpenObserve UI/API with TLS and firewall rules.
- Pin container and agent versions; do not use `latest` in production.
- Back up the OpenObserve data volume and configuration before upgrades.

## 13. Initial Alerts

- Server/collector unavailable.
- CPU remains above the agreed threshold for a sustained duration.
- Memory or swap utilization remains high.
- Disk utilization approaches capacity.
- Abnormal disk or network behavior.
- PM2 daemon unavailable.
- PM2 application stopped or errored.
- PM2 restart count exceeds a threshold within a time window.
- Error-log volume or a selected error pattern exceeds a threshold.
- Collector delivery errors, dropped records, or persistent queue growth.

Thresholds and notification destinations will be finalized during development planning.

## 14. Acceptance Criteria for the Proof of Concept

1. OpenObserve starts from the central Compose deployment and survives container recreation with its data intact.
2. Root can log in, create an organization admin, and create a member.
3. One Linux PM2 server appears with CPU, load, memory, swap, disk, network, and uptime history.
4. Every PM2 application appears with status, CPU, memory, uptime, and restart count.
5. An old marker in the existing 21 GB+ file is not ingested.
6. A new unique PM2 log marker becomes searchable within an agreed target, initially five seconds.
7. Logs can be filtered by server, environment, PM2 application, stream, time range, and text.
8. Collector restart resumes from its persisted file offset without rereading the old file.
9. A temporary central outage queues data locally and delivers it after recovery without silently dropping records.
10. PM2 log rotation occurs without interrupting collection.
11. At least one host alert, one PM2 alert, and one log-pattern alert are verified using synthetic data.
12. Rebooting the PM2 server automatically restarts the collector and exporter without cron.

## 15. Tradeoffs and Risks

- OpenObserve has a smaller ecosystem than Grafana, Prometheus, and OpenSearch, even though it covers the required functionality in one platform.
- OpenObserve OSS is AGPL-3.0. License obligations must be reviewed before offering a modified hosted or redistributed product.
- Advanced RBAC, SSO, and custom branding are not part of the OSS role model.
- The PM2 exporter is project-owned code and becomes a maintained component, although it has no third-party runtime dependencies.
- Poorly structured or timestamp-free application logs reduce search quality.
- Incorrect collector queue/storage settings can cause data loss during long outages.
- Local single-node storage is appropriate for the proof of concept but not automatically highly available.

## 16. Development Planning Kickoff

The development plan on 2026-08-27 should begin by confirming:

1. Number of PM2 servers and their Linux distributions/architectures.
2. PM2 Unix users and whether one server can host multiple PM2 daemons.
3. Central server CPU, memory, SSD capacity, hostname, and TLS approach.
4. Expected daily PM2 log volume after rotation.
5. Required metric and log retention.
6. Organization/sub-admin model.
7. Required alert channels.
8. Whether true streaming live tail is mandatory or a sub-five-second view is acceptable.

Recommended implementation order:

1. Central OpenObserve proof of concept.
2. Collector host metrics from one PM2 server.
3. PM2 metrics exporter.
4. New-content-only PM2 log ingestion and search.
5. Dashboards and roles.
6. Alerts and rotation.
7. Failure/restart tests, security hardening, backups, and documentation.

## 17. Reference Projects and Documentation

- [OpenObserve repository](https://github.com/openobserve/openobserve)
- [OpenObserve documentation](https://openobserve.ai/docs/)
- [OpenObserve Linux server monitoring](https://openobserve.ai/docs/integration/system/linux/)
- [OpenObserve metrics](https://openobserve.ai/docs/features/metrics/)
- [OpenObserve logs](https://openobserve.ai/docs/features/logs/)
- [OpenObserve agents](https://github.com/openobserve/agents)
- [OpenTelemetry filelog receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/filelogreceiver)
- [PM2 programmatic API](https://pm2.keymetrics.io/docs/usage/pm2-api/)
- [PM2 log management](https://pm2.keymetrics.io/docs/usage/log-management/)
