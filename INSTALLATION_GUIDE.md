# OpsPika — Simple Ubuntu Installation Guide

The normal installation uses only two commands:

```bash
sudo ./install.sh central
sudo ./install.sh agent
```

The scripts ask for the required values interactively, install the components,
and run verification automatically. You do not manually edit generated
configuration files.

## Before Starting

You need:

- One Ubuntu server for central OpenObserve.
- This project copied or cloned to `/opt/opspika` on each server.
- Your reverse proxy/domain pointing to the central server after installation.
- The Unix username that runs PM2 on each monitored PM2 server.

OpenObserve listens on port `5080`. This project does not install or configure
your reverse proxy.

---

## 1. Copy the Project to the Central Server

```bash
sudo apt-get update
sudo apt-get install -y git
sudo git clone YOUR_REPOSITORY_URL /opt/opspika
cd /opt/opspika
sudo chmod +x install.sh central/scripts/*.sh agent/*.sh scripts/*.sh
```

If you transferred the folder without Git, place it at
`/opt/opspika`, then run only the final two commands above.

## 2. Install Central OpenObserve

```bash
cd /opt/opspika
sudo ./install.sh central
```

Answer two prompts:

```text
OpenObserve root email
OpenObserve port [5080]
```

The quick installer automatically uses:

```text
Docker bind address: 127.0.0.1
Data retention: 180 days (approximately six months)
```

Press Enter at the port prompt to use `5080`. If you choose another port, use
that same port as your reverse-proxy upstream.

These defaults match a reverse proxy running on the same server. Advanced
deployments can override them through
`central/scripts/install-central.sh --help`.

Retention does not need to be chosen during quick installation. You can change
it afterward in either of these ways:

- **Per stream:** Open **Streams** in OpenObserve, select the stream, and update
  its data-retention setting. A stream setting overrides the global default.
- **Globally:** Change `ZO_COMPACT_DATA_RETENTION_DAYS` in
  `/opt/opspika/central/.env`, then apply it with:

```bash
cd /opt/opspika
sudo docker compose --env-file central/.env -f central/compose.yaml up -d
```

Increasing retention later does not recover data that was already deleted.

Configure your reverse proxy afterward:

```text
https://monitor.yourdomain.com → http://127.0.0.1:5080
```

The example above assumes the default `5080` port.

The installer prints a generated root password. Save it immediately.

## 3. Log In and Copy the Agent Key

Open your domain in a browser and log in.

In OpenObserve:

1. Open **Data Sources → Linux**.
2. Find the generated `Authorization: Basic ...` value.
3. Copy only the base64 text after `Basic`.

The quick agent installer asks you to paste this key securely. It creates the
required protected files automatically.

### Values Detected Automatically by the Agent Installer

- **Agent mode:** If one active PM2 daemon is found, the installer uses PM2
  mode. If no PM2 daemon is found, it uses host-only mode. If several Unix users
  own PM2 daemons, it asks which one to monitor.
- **Server name:** Uses `hostname -s`, the Ubuntu machine name shown in the
  OpenObserve server list, such as `web-01` or `api-02`.
- **Environment:** Uses `production`. This is only a dashboard/filter label; it
  does not alter Ubuntu, PM2, or collection behavior.
- **Organization:** Uses OpenObserve's built-in `default` organization. An
  organization is the data/user boundary inside OpenObserve.
- **PM2 Unix user:** Detected from the owner of the active PM2 daemon. It is
  `root` only when PM2 was actually started and is managed by root. Normally it
  is an application account such as `ubuntu`, `deploy`, or `nodeapp`.

Non-default environment or organization values remain available through the
advanced `agent/install-monitoring-agent.sh` command.

## 4. Monitor the Central Server Itself

On the central server:

```bash
cd /opt/opspika
sudo ./install.sh agent
```

The installer detects host-only mode automatically when the central server does
not run PM2. Enter only:

```text
OpenObserve base URL: https://monitor.yourdomain.com
Authorization key: paste the copied base64 key
```

If the central server also has an active PM2 daemon, PM2 mode is selected
automatically.

## 5. Install Every PM2 Server

On each PM2 Ubuntu server, copy the project:

```bash
sudo apt-get update
sudo apt-get install -y git
sudo git clone YOUR_REPOSITORY_URL /opt/opspika
cd /opt/opspika
sudo chmod +x install.sh central/scripts/*.sh agent/*.sh scripts/*.sh
```

Install the agent:

```bash
pm2 list
sudo ./install.sh agent
```

Run `pm2 list` as the normal PM2 application user before invoking the installer.
This ensures the daemon is active and its Unix owner can be detected. The quick
installer then asks only for:

```text
OpenObserve base URL: https://monitor.yourdomain.com
Authorization key: paste the copied base64 key
```

The installer automatically:

- Captures CPU, load, RAM, swap, disk, filesystem, network, process counts,
  and uptime.
- Installs PM2 process metrics.
- Collects only new PM2 log lines; existing large logs are ignored.
- Installs and configures `pm2-logrotate`.
- Creates persistent log offsets and delivery queues.
- Starts services on boot.
- Runs local verification.

## 6. Check the OpenObserve UI

Within approximately one minute:

1. Open **Metrics** and confirm the server hostname appears.
2. Search for metrics beginning with `pm2_`.
3. Open **Logs** and choose the `pm2_logs` stream.
4. Wait for a new application log line and confirm it appears.

The existing 21 GB+ PM2 log content is intentionally not imported.

---

## Quick Status Commands

Central OpenObserve:

```bash
cd /opt/opspika
sudo ./central/scripts/verify-central.sh
```

Monitoring agent:

```bash
cd /opt/opspika
sudo ./agent/verify-monitoring-agent.sh
```

Create a central backup:

```bash
cd /opt/opspika
sudo ./central/scripts/backup-central.sh
```

Troubleshoot the agent:

```bash
sudo systemctl status opspika-agent --no-pager
sudo journalctl -u opspika-agent -n 100 --no-pager
```

Do not run `pm2 flush` as an installation or troubleshooting step.

## Advanced Commands

Every underlying script has built-in help:

```bash
./install.sh help
./central/scripts/install-central.sh --help
./agent/install-monitoring-agent.sh --help
./agent/uninstall-monitoring-agent.sh --help
./central/scripts/restore-central.sh --help
```
