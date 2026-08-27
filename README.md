# OpsPika

> Self-hosted server health, process metrics, and searchable logs.

OpsPika monitors Ubuntu host health and applications managed by PM2. It uses a
single OpenObserve OSS container centrally and one hardened OpenTelemetry-based
agent on every monitored server.

## Status

The deployment package is implemented and statically verified. The remaining
milestone is a live proof of concept on one central Ubuntu server and one PM2
Ubuntu server, followed by export of dashboard and alert templates verified
against the live OpenObserve schema.

## Architecture

```text
Monitored Ubuntu servers                 OpsPika Central
----------------------------------       ----------------------------
OpsPika Agent ---------------- OTLP ---> OpenObserve OSS
OpsPika Process Exporter                 Persistent Docker volume
pm2-logrotate                            OpsPika Agent (self-monitoring)
```

Installed runtime names:

- **OpsPika Central** — OpenObserve and its persistent volume.
- **OpsPika Agent** — host metrics, log collection, buffering, and delivery.
- **OpsPika Process Exporter** — local PM2 process measurements.

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
data for 180 days by default.

The agent command automatically determines:

- Host-only or PM2 mode from active PM2 daemons.
- Server identity from the Ubuntu hostname.
- PM2 ownership from the daemon's Unix account.
- `production` as the environment label.
- `default` as the OpenObserve organization.

It asks only for the OpenObserve base URL and protected authorization key unless
multiple PM2 daemon owners require an explicit choice.

## Capabilities

- CPU, load, RAM, swap, disk, filesystem, network, process-count, and uptime
  history.
- PM2 application status, CPU, memory, uptime, restarts, and instance counts.
- New PM2 stdout/stderr lines only; existing large logs are not imported.
- Persistent file offsets and disk-backed delivery queues.
- Full-text log search and near-real-time viewing in OpenObserve.
- Dashboards, alerts, organizations, and local user accounts.
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
dashboards/                 Dashboard and alert specification
scripts/validate.sh         Static and component validation
INSTALLATION_GUIDE.md       Simple Ubuntu operator guide
proposal.md                 Architecture and accepted requirements
```

Implementation plans and logs are intentionally excluded by `.gitignore` and
remain local development records.

## Pinned Components

- OpenObserve OSS: `v0.90.3`
- OpenTelemetry Collector Contrib: `v0.156.0`
- pm2-logrotate: `3.0.0`
- OpsPika Process Exporter: `0.1.0`, dependency-free

Do not replace pinned versions with `latest` without backup, changelog review,
and the full validation workflow.

## Validation

Current local validation includes:

- Bash syntax and ShellCheck.
- Node.js unit tests and syntax checks.
- Host and PM2 Collector configuration validation against the pinned Collector.
- A disposable PM2 7 integration test against the real exporter endpoint.

Live Docker, systemd, ACL, OTLP ingestion, dashboard, alert, outage, rotation,
reboot, backup, and restore validation requires the target Ubuntu servers.

## Documentation

- [Installation guide](INSTALLATION_GUIDE.md)
- [Central operations](central/README.md)
- [Agent details](agent/README.md)
- [Dashboard and alert specification](dashboards/README.md)
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
