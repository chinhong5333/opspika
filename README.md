# OpsPika

> Self-hosted server health, process metrics, and searchable logs.

OpsPika is a self-hosted Ubuntu server monitoring system. It monitors host
health on any Ubuntu server and, when PM2 is present, can additionally collect
per-application process metrics and searchable logs. PM2 is optional and does
not host OpsPika.

OpsPika Central runs as a single OpenObserve OSS container. Every monitored
server runs a hardened OpenTelemetry-based agent through `systemd`.

## Status

OpsPika is a production candidate for its documented single-node deployment
scope. The repository includes immutable runtime pins, importable dashboards,
alert templates, end-to-end agent acceptance checks, backup/restore tooling,
and Ubuntu runtime CI. A release is production-ready only when its CI is green
and the target site passes the TLS, capacity, backup, and notification checks in
[PRODUCTION_READINESS.md](PRODUCTION_READINESS.md).

## Architecture

```text
Monitored Ubuntu server                  OpsPika Central
----------------------------------       ----------------------------
OpsPika Agent (always) ------- OTLP ---> OpenObserve OSS
                                         Persistent Docker volume
Optional when PM2 is present:            OpsPika Agent (self-monitoring)
  OpsPika Process Exporter
  pm2-logrotate
```

Installed runtime names:

- **OpsPika Central** — OpenObserve and its persistent volume.
- **OpsPika Agent** — host metrics, log collection, buffering, and delivery.
- **OpsPika Process Exporter** — optional local PM2 process measurements.

## Quick Installation

Read [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md), then use:

```bash
sudo ./install.sh central
sudo ./install.sh agent
```

The central command asks only for:

- Root email.
- Local OpenObserve port, default `5080`.

It automatically binds to `127.0.0.1` for the user's reverse proxy and keeps
data for 180 days by default. It also imports the three OpsPika dashboards.

The agent command automatically determines:

- Host-only or PM2 mode from active PM2 daemons.
- Server identity from the Ubuntu hostname.
- PM2 ownership from the daemon's Unix account.
- `production` as the environment label.
- `default` as the OpenObserve organization.

It asks only for the OpenObserve base URL and protected authorization key unless
multiple PM2 daemon owners require an explicit choice. Installation finishes by
verifying current host metrics in OpenObserve. PM2 mode also writes a disposable
synthetic log, verifies exactly-once ingestion across a Collector restart, and
removes the local test file.

## Capabilities

- CPU, load, RAM, swap, disk, filesystem, network, process-count, and uptime
  history.
- PM2 application status, CPU, memory, uptime, restarts, and instance counts.
- New PM2 stdout/stderr lines only; existing large logs are not imported.
- Persistent file offsets and disk-backed delivery queues.
- Full-text log search and near-real-time viewing in OpenObserve.
- Three provisioned dashboards for host health, process applications, and logs.
- Seven idempotently provisioned alert templates with per-host telemetry alerts.
- Organizations and local user accounts.
- Automatic PM2 log rotation with seven compressed local rotations.
- Central backup, guarded restore, verification, and agent uninstall tooling.
- No monitoring cron jobs.

## Operational Defaults

| Setting | Default |
|---|---|
| Central bind address | `127.0.0.1` |
| Central port | `5080`, configurable during installation |
| Global retention | `180` days, configurable afterward globally or per stream |
| Agent environment label | `production` |
| OpenObserve organization | `default` |
| PM2 log ingestion | Start at current end; ignore existing content |
| PM2 rotation | `100M`, retain 7, gzip enabled |

OpsPika does not install a public reverse proxy or manage a domain. Point the
user's reverse proxy to `http://127.0.0.1:SELECTED_PORT` and provide the HTTPS
domain to each agent.

## Repository Layout

```text
install.sh                  Interactive central/agent entry point
central/                    OpenObserve Compose and lifecycle operations
agent/                      Ubuntu agent, exporter, templates, and verification
dashboards/                 Importable OpenObserve v8 dashboard assets
alerts/                     Destination-neutral OpenObserve alert templates
scripts/                    Static, component, and disposable API validation
.github/workflows/ci.yml    Ubuntu 22.04/24.04 production acceptance CI
INSTALLATION_GUIDE.md       Simple Ubuntu operator guide
PRODUCTION_READINESS.md     Supported scope and release gates
proposal.md                 Architecture and accepted requirements
```

Implementation plans and logs are intentionally excluded by `.gitignore` and
remain local development records.

## Pinned Components

- OpenObserve OSS: `v0.90.3`, pinned by multi-platform image digest
- OpenTelemetry Collector Contrib: `v0.156.0`, pinned by architecture-specific SHA-256
- pm2-logrotate: `3.0.0`
- BusyBox backup helper: `1.37.0`, pinned by multi-platform image digest
- OpsPika Process Exporter: `0.1.0`, dependency-free

Do not replace pinned versions with `latest` without backup, changelog review,
and the full validation workflow.

## Validation

Current local validation includes:

- Bash syntax and ShellCheck.
- Node.js unit tests and syntax checks.
- Dashboard and alert asset-contract validation.
- Host and PM2 Collector configuration validation against the pinned Collector.
- A disposable PM2 `7.0.4` integration test against the real exporter endpoint.
- A clean, disposable OpenObserve `v0.90.3` server test that imported all three
  dashboards, applied log indexes, provisioned seven alerts, and successfully
  executed all 21 dashboard queries.
- GitHub Actions runtime jobs for Ubuntu 22.04 and 24.04 covering Docker,
  systemd, ACLs, OTLP delivery, old-log exclusion, dashboards, alerts, backup,
  and guarded restore.

Site-specific TLS, notification delivery, storage sizing, off-host backups, and
reboot recovery still must be verified on the actual infrastructure before a
production rollout.

## Documentation

- [Installation guide](INSTALLATION_GUIDE.md)
- [Central operations](central/README.md)
- [Agent details](agent/README.md)
- [Dashboards and alerts](dashboards/README.md)
- [Production readiness](PRODUCTION_READINESS.md)
- [Architecture proposal](proposal.md)
- [Public release checklist](PUBLIC_RELEASE_CHECKLIST.md)

## License

OpsPika's original code and documentation are available under the
[MIT License](LICENSE). Third-party services and tools are fetched separately
and retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

OpsPika is independent and is not affiliated with OpenObserve, OpenTelemetry,
PM2, Docker, Node.js, BusyBox, or their maintainers. Project-name, domain, and
trademark clearance are separate from copyright licensing and should receive a
formal review before commercial launch.
