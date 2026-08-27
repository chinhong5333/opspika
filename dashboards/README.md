# OpsPika Dashboard and Alert Specification

OpenObserve dashboard JSON is versioned by the running server. To avoid shipping
an unverified schema, create/export the first dashboard only after the proof of
concept has ingested real host and PM2 data. The exported JSON then becomes the
pinned dashboard template in this directory.

## Dashboard 1 — Server Fleet

Required panels:

- Server availability and last telemetry timestamp.
- CPU utilization by server.
- Load average by server.
- Used and available memory by server.
- Swap utilization.
- Root and mounted filesystem utilization.
- Disk read/write throughput.
- Network receive/transmit throughput and errors.
- Host uptime.

Variables:

- `environment`
- `host_name`

## Dashboard 2 — PM2 Applications

Required panels:

- Online/errored/stopped application table.
- CPU and memory by PM2 application and instance.
- Uptime by application and instance.
- Restart and unstable-restart counts.
- Configured versus running instance count.
- Exporter collection status.

Metrics produced by this project:

```text
pm2_exporter_collect_success
pm2_exporter_last_collect_timestamp_seconds
pm2_process_info
pm2_process_up
pm2_process_cpu_percent
pm2_process_memory_bytes
pm2_process_uptime_seconds
pm2_process_restarts
pm2_process_unstable_restarts
pm2_app_instances_configured
pm2_app_instances_running
```

Variables:

- `environment`
- `host_name`
- `app`
- `instance`

## Log View — PM2 Logs

Use stream `pm2_logs` with filters for:

- `host.name`
- `deployment.environment.name`
- `pm2_app`
- `pm2_stream`
- `log.file.name`
- full-text message search

## Initial Alerts

- Missing host telemetry.
- Sustained high CPU.
- Sustained high memory or swap.
- Filesystem near capacity.
- `pm2_exporter_collect_success != 1`.
- `pm2_process_up != 1` for an expected application.
- Restart count increase over an agreed time window.
- Error log pattern/count threshold.
- Collector persistent queue growth or export failures.

## Template Promotion Checklist

1. Confirm actual OpenObserve field names after OTLP flattening.
2. Build and visually verify panels in the pinned OpenObserve version.
3. Export the dashboard from OpenObserve.
4. Remove instance-specific server names and credentials.
5. Import into a clean organization and repeat verification.
6. Commit the verified JSON in this directory.
