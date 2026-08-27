# Third-Party Notices

OpsPika's original source code and documentation are licensed under the MIT
License in [LICENSE](LICENSE).

OpsPika does not vendor or redistribute the third-party programs listed below.
Its installation scripts download or invoke separately distributed official
packages and container images. Those programs remain governed by their own
licenses.

| Component | How OpsPika uses it | Upstream license | Upstream source |
|---|---|---|---|
| OpenObserve OSS | Central observability container, pulled at installation | [AGPL-3.0](https://github.com/openobserve/openobserve/blob/main/LICENSE) | [openobserve/openobserve](https://github.com/openobserve/openobserve) |
| OpenTelemetry Collector Contrib | Agent binary, downloaded from an official pinned release | [Apache-2.0](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/LICENSE) | [open-telemetry/opentelemetry-collector-contrib](https://github.com/open-telemetry/opentelemetry-collector-contrib) |
| PM2 | Existing process manager invoked through its documented CLI | [AGPL-3.0](https://github.com/Unitech/pm2/blob/master/GNU-AGPL-3.0.txt) | [Unitech/pm2](https://github.com/Unitech/pm2) |
| pm2-logrotate | PM2 module installed from npm at a pinned version | [MIT](https://github.com/keymetrics/pm2-logrotate/blob/master/package.json) | [keymetrics/pm2-logrotate](https://github.com/keymetrics/pm2-logrotate) |
| Docker Engine / Moby | Container runtime installed from Docker's official Ubuntu repository | [Apache-2.0](https://github.com/moby/moby/blob/master/LICENSE) | [moby/moby](https://github.com/moby/moby) |
| Docker Compose | Applies the central deployment specification | [Apache-2.0](https://github.com/docker/compose/blob/main/LICENSE) | [docker/compose](https://github.com/docker/compose) |
| BusyBox container | Temporary helper used by backup and guarded restore scripts | [GPL-2.0](https://github.com/mirror/busybox/blob/master/LICENSE) | [BusyBox source mirror](https://github.com/mirror/busybox) |
| Node.js | Executes the project-owned process exporter on PM2 hosts | [MIT](https://github.com/nodejs/node/blob/main/LICENSE) | [nodejs/node](https://github.com/nodejs/node) |

Ubuntu packages such as `curl`, `tar`, `acl`, `sudo`, `ca-certificates`, and
OpenSSL are installed from or expected from the operating system and retain the
licenses published by their Ubuntu/upstream maintainers.

## Distribution Boundary

This repository contains configuration, original scripts, original exporter
code, tests, and documentation. It intentionally does not contain:

- OpenObserve source code or container layers.
- OpenTelemetry Collector binaries.
- PM2 or pm2-logrotate source/packages.
- Docker, BusyBox, Node.js, or Ubuntu package binaries.
- Third-party dashboard JSON or visual assets.

If a future release vendors, modifies, or redistributes any third-party
component, its license text, notices, corresponding source obligations, and
distribution method must be reviewed again before publication.

## Trademarks and Affiliation

OpenObserve, OpenTelemetry, PM2, Docker, Node.js, BusyBox, and other third-party
names and marks belong to their respective owners. OpsPika is an independent
community project and is not endorsed by or affiliated with those projects or
their maintainers.

The MIT License grants copyright permissions for OpsPika's source code. It does
not grant rights to any project name, logo, domain, or trademark. The OpsPika
name should receive a formal trademark/domain clearance review before material
commercial launch.
