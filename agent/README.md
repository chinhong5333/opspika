# OpsPika Agent

The installer supports two explicit modes:

- `host` — host metrics only, used to monitor the central OpenObserve server.
- `pm2` — host metrics, PM2 metrics, PM2 logs, and PM2 log rotation.

One OpenTelemetry Collector Contrib process runs as the
`opspika-agent.service` systemd unit. PM2 mode additionally installs the
dependency-free project exporter as a PM2-managed process and installs
`pm2-logrotate`.

Security properties:

- Agents make outbound requests only.
- The PM2 exporter binds to `127.0.0.1:9988`.
- The collector health endpoint binds to `127.0.0.1:13134`.
- Authorization material is stored in a root-owned configuration file.
- PM2 environment values are never exported.
- PM2 log access is granted to the dedicated agent account through ACLs.
- The systemd service uses filesystem, home, kernel, and privilege hardening.

See the root [installation guide](../INSTALLATION_GUIDE.md) for exact commands.
