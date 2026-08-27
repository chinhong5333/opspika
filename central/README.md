# OpsPika Central

The central deployment runs one pinned OpenObserve OSS container and one named
Docker volume.

Scripts:

- `scripts/install-docker-ubuntu.sh` — installs Docker from Docker's official
  Ubuntu repository.
- `scripts/install-central.sh` — creates protected configuration, pulls the
  pinned image, starts OpenObserve, and waits for health.
- `scripts/verify-central.sh` — verifies the container, health endpoint, and
  persistent volume.
- `scripts/backup-central.sh` — briefly stops OpenObserve and creates a
  checksummed, consistent volume backup.
- `scripts/restore-central.sh` — validates an archive, creates a pre-restore
  backup, and restores the volume only with an explicit confirmation flag.

The default binding is `127.0.0.1:5080`. The installation guide uses a private
interface for the initial proof of concept and requires HTTPS before internet
exposure.

Runtime data lives in the named volume:

```text
opspika-openobserve-data
```

Configuration and root credentials live in `central/.env`, mode `0600`. That
file is intentionally ignored by Git.
