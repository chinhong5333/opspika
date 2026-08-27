# OpsPika Production Readiness

This document defines when an OpsPika release and a specific installation may
be called production-ready. Passing source tests alone is not sufficient.

## Supported Deployment Scope

The initial supported production topology is:

- One Ubuntu 22.04 or 24.04 LTS x86-64 central server.
- One OpenObserve OSS single-node container with a local named Docker volume.
- Any number of Ubuntu 22.04 or 24.04 LTS monitored servers within the central
  server's tested ingest and storage capacity.
- Host-only monitoring on servers without PM2.
- Optional PM2 metrics, new-log collection, and log rotation on servers with an
  active PM2 daemon and Node.js 18 or newer.
- HTTPS terminated by an operator-managed reverse proxy.

The single-node topology is production-capable but is not highly available. A
central-server or local-volume failure causes monitoring downtime until restore.
Organizations requiring central-service HA, an SLA, SSO, granular RBAC, or
durable object storage must deploy the appropriate OpenObserve architecture
instead of treating this Compose topology as HA.

## Automated Release Gates

The GitHub Actions workflow must be green for the exact commit being deployed.
It verifies:

1. Bash syntax, ShellCheck, JavaScript tests, and asset contracts.
2. Both Collector profiles against the pinned Collector binary.
3. Exporter behavior against pinned PM2 7, including secret exclusion.
4. OpenObserve startup from the digest-pinned image.
5. Dashboard creation, log-index settings, alert creation, and dashboard queries.
6. The Ubuntu installer using systemd, ACLs, persistent offsets, and real OTLP.
7. Existing-log exclusion and exactly-once synthetic log delivery across a
   Collector restart.
8. Consistent backup, guarded restore, and post-restore health.

The runtime job runs independently on Ubuntu 22.04 and Ubuntu 24.04.

## Site Acceptance Gates

Complete these checks on the intended infrastructure before adding all servers:

- [ ] The exact deployed Git commit has green CI.
- [ ] The central server and its data volume use reliable SSD storage.
- [ ] Disk capacity covers measured daily ingest multiplied by retention, plus
      compaction, backup, and safety headroom.
- [ ] Disk-usage monitoring alerts before OpenObserve can fill the filesystem.
- [ ] The UI and agent endpoint are reachable only through valid HTTPS.
- [ ] Port 5080 remains loopback-only unless a separately reviewed private
      network design requires otherwise.
- [ ] Root credentials are stored in a password manager and `central/.env`
      remains mode `0600`.
- [ ] Each alert destination has been tested, then alerts were provisioned with
      `--enable`.
- [ ] One host-only server passes `agent/run-acceptance-test.sh`.
- [ ] One PM2 server passes `agent/run-acceptance-test.sh` without importing an
      existing old-log marker.
- [ ] A reboot automatically restores Docker, OpenObserve, the agent, the
      exporter, and existing PM2 applications.
- [ ] Backups are copied off-host and a restore is tested on disposable storage.
- [ ] Queue and disk behavior is observed during an outage longer than the
      normal maintenance window.
- [ ] Initial PM2 log rotation is watched for adequate free disk, especially
      when legacy logs are many gigabytes.

Expand to the remaining servers only after these checks pass.

## Capacity and Retention

The 180-day default is a policy, not a sizing guarantee. Before broad rollout:

1. Measure daily log and metric ingest for at least 24 hours on representative
   servers.
2. Measure the OpenObserve volume's actual growth after compaction.
3. Include temporary compaction space and at least one local backup in the disk
   budget.
4. Lower per-stream retention when the calculated requirement exceeds safe disk
   capacity.
5. Place backups on separate storage; a backup in the same volume or host does
   not protect against host loss.

## Alerts

Dashboards are installed with the central service. Alerts require a real
notification destination and telemetry streams, so they are a deliberate
post-ingestion step:

```bash
sudo ./central/scripts/configure-streams.sh
sudo ./central/scripts/provision-alerts.sh \
  --destination YOUR_TESTED_DESTINATION \
  --enable
```

Provisioning is idempotent and preserves existing same-name alerts. PM2-specific
alerts are skipped on a host-only deployment and can be added by rerunning the
command after PM2 telemetry appears.

## Backup and Upgrade Policy

- Run `backup-central.sh` before every OpenObserve upgrade.
- Schedule regular backups with an operator-owned systemd timer or backup
  platform and copy the resulting archive plus checksum off-host.
- Never change image, Collector, PM2 module, or backup-helper pins directly in
  production. Update them in the repository, review upstream changes, run CI,
  back up, and deploy the tested commit.
- Restore only with `--confirm-restoration`; the restore script creates a
  pre-restore backup before replacing data.

## Release Decision

OpsPika is production-ready only within the supported scope when both sets of
gates are satisfied:

```text
green automated release gates + completed site acceptance gates
```

If either side is incomplete, the installation remains a production candidate.
