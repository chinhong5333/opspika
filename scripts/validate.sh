#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
otel_binary=${OTEL_BINARY:-}

shell_scripts=(
  install.sh
  central/scripts/install-docker-ubuntu.sh
  central/scripts/install-central.sh
  central/scripts/verify-central.sh
  central/scripts/backup-central.sh
  central/scripts/restore-central.sh
  agent/install-monitoring-agent.sh
  agent/verify-monitoring-agent.sh
  agent/uninstall-monitoring-agent.sh
  scripts/validate.sh
)

for script in "${shell_scripts[@]}"; do
  bash -n "${repo_dir}/${script}"
done
echo "Bash syntax validation passed."

node --check "${repo_dir}/agent/pm2-exporter/server.js"
node --check "${repo_dir}/agent/pm2-exporter/metrics.js"
node --test "${repo_dir}"/agent/pm2-exporter/test/*.test.js
echo "PM2 exporter validation passed."

if [[ -n ${otel_binary} ]]; then
  [[ -x ${otel_binary} ]] || {
    echo "OTEL_BINARY is not executable: ${otel_binary}" >&2
    exit 1
  }
  temp_dir=$(mktemp -d)
  trap 'rm -rf "${temp_dir}"' EXIT
  sed \
    -e 's|__SERVER_NAME__|validation-host|g' \
    -e 's|__ENVIRONMENT__|validation|g' \
    "${repo_dir}/agent/templates/otel-config-host.yaml" \
    >"${temp_dir}/host.yaml"
  sed \
    -e 's|__SERVER_NAME__|validation-pm2|g' \
    -e 's|__ENVIRONMENT__|validation|g' \
    -e 's|__PM2_HOME__|/home/validation/.pm2|g' \
    "${repo_dir}/agent/templates/otel-config-pm2.yaml" \
    >"${temp_dir}/pm2.yaml"
  export OPENOBSERVE_OTLP_ENDPOINT='http://127.0.0.1:5080/api/default'
  export OPENOBSERVE_AUTHORIZATION_KEY='dGVzdDp0ZXN0'
  "${otel_binary}" validate --config="${temp_dir}/host.yaml"
  "${otel_binary}" validate --config="${temp_dir}/pm2.yaml"
  echo "OpenTelemetry configuration validation passed."
else
  echo "Skipped Collector validation. Set OTEL_BINARY to a pinned otelcol-contrib executable to enable it."
fi

required_docs=(
  README.md
  INSTALLATION_GUIDE.md
  LICENSE
  THIRD_PARTY_NOTICES.md
  PUBLIC_RELEASE_CHECKLIST.md
  proposal.md
  _IMPLEMENTATION_PLAN.md
  _IMPLEMENTATION_LOG.md
)
for document in "${required_docs[@]}"; do
  [[ -s ${repo_dir}/${document} ]] || {
    echo "Required document is missing or empty: ${document}" >&2
    exit 1
  }
done
echo "Required documentation validation passed."
