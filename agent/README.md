# OpsPika Agent

The installer supports two explicit modes:

- `host` — host metrics only, used to monitor the central OpenObserve server.
- `pm2` — host metrics, PM2 metrics, PM2 logs, and PM2 log rotation.

One OpenTelemetry Collector Contrib process runs as the
`opspika-agent.service` systemd unit. PM2 mode additionally installs the
dependency-free project exporter as a PM2-managed process and installs
`pm2-logrotate`.

The Collector binary is verified against an architecture-specific SHA-256 pin.
Re-running the installer validates the rendered configuration and restarts the
existing service so upgrades do not leave the old process running.

Security properties:

- Agents make outbound requests only.
- The PM2 exporter binds to `127.0.0.1:9988`.
- The collector health endpoint binds to `127.0.0.1:13134`.
- Authorization material is stored in a root-owned configuration file.
- PM2 environment values are never exported.
- PM2 log access is granted to the dedicated agent account through ACLs.
- The systemd service uses filesystem, home, kernel, and privilege hardening.

The quick installer runs `run-acceptance-test.sh` automatically. It verifies
current host metrics through the OpenObserve API. PM2 mode also uses a new,
disposable synthetic log file to verify search delivery exactly once across a
Collector restart; it never modifies or truncates an application log.

See the root [installation guide](../INSTALLATION_GUIDE.md) for exact commands.
