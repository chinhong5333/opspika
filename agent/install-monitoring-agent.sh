#!/usr/bin/env bash
set -Eeuo pipefail

readonly OTEL_VERSION="0.156.0"
readonly OTEL_SHA256_AMD64="ee70d7b1221be8a9cc4700f48bf985c04b1ab8aaeef24409fe79623849e2f9f2"
readonly OTEL_SHA256_ARM64="1f9afe1d245b4babbb4bcb7d6b57ba2836b3b23c5f61b38abc00ab461f049288"
readonly PM2_LOGROTATE_VERSION="3.0.0"
readonly AGENT_USER="opspika-agent"
readonly AGENT_GROUP="opspika-agent"
readonly CONFIG_DIR="/etc/opspika-agent"
readonly STATE_DIR="/var/lib/opspika-agent"
readonly OTEL_BINARY="/usr/local/bin/opspika-otelcol"
readonly SERVICE_FILE="/etc/systemd/system/opspika-agent.service"
readonly EXPORTER_DIR="/opt/opspika-process-exporter"
readonly OTEL_CANDIDATE="${OTEL_BINARY}.opspika-new"
readonly CONFIG_CANDIDATE="${CONFIG_DIR}/config.yaml.opspika-new"
readonly ENV_CANDIDATE="${CONFIG_DIR}/agent.env.opspika-new"
readonly INSTALL_CONFIG_CANDIDATE="${CONFIG_DIR}/install.conf.opspika-new"
readonly SERVICE_CANDIDATE="${SERVICE_FILE}.opspika-new"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
template_dir="${script_dir}/templates"
exporter_source_dir="${script_dir}/pm2-exporter"

mode=""
server_name=""
environment_name=""
openobserve_url=""
authorization_key_file=""
pm2_user=""
pm2_home=""
allow_insecure_http=false

cleanup_candidates() {
  rm -f -- \
    "${OTEL_CANDIDATE}" \
    "${CONFIG_CANDIDATE}" \
    "${ENV_CANDIDATE}" \
    "${INSTALL_CONFIG_CANDIDATE}" \
    "${SERVICE_CANDIDATE}"
}
trap cleanup_candidates EXIT

usage() {
  cat <<'EOF'
Usage:
  Host-only mode (for the central server or a non-PM2 Ubuntu server):
    sudo ./agent/install-monitoring-agent.sh \
      --mode host \
      --server-name NAME \
      --environment ENVIRONMENT \
      --openobserve-url URL \
      --authorization-key-file PATH

  PM2 mode:
    sudo ./agent/install-monitoring-agent.sh \
      --mode pm2 \
      --server-name NAME \
      --environment ENVIRONMENT \
      --openobserve-url URL \
      --authorization-key-file PATH \
      --pm2-user USER [--pm2-home ABSOLUTE_PATH]

Required options:
  --mode host|pm2               Select the exact installation profile.
  --server-name NAME            Stable server identifier used in telemetry.
  --environment ENVIRONMENT     Environment such as production or staging.
  --openobserve-url URL         OTLP base URL ending in /api/ORGANIZATION.
  --authorization-key-file PATH File containing only the base64 authorization key.

PM2 mode options:
  --pm2-user USER               Unix user that owns the PM2 daemon.
  --pm2-home ABSOLUTE_PATH      PM2 home; defaults to USER_HOME/.pm2.

Security option:
  --allow-insecure-http         Explicitly permit non-loopback HTTP for a private
                                network evaluation. Production must use HTTPS.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || { echo "--mode requires a value." >&2; exit 2; }
      mode=$2
      shift 2
      ;;
    --server-name)
      [[ $# -ge 2 ]] || { echo "--server-name requires a value." >&2; exit 2; }
      server_name=$2
      shift 2
      ;;
    --environment)
      [[ $# -ge 2 ]] || { echo "--environment requires a value." >&2; exit 2; }
      environment_name=$2
      shift 2
      ;;
    --openobserve-url)
      [[ $# -ge 2 ]] || { echo "--openobserve-url requires a value." >&2; exit 2; }
      openobserve_url=$2
      shift 2
      ;;
    --authorization-key-file)
      [[ $# -ge 2 ]] || { echo "--authorization-key-file requires a value." >&2; exit 2; }
      authorization_key_file=$2
      shift 2
      ;;
    --pm2-user)
      [[ $# -ge 2 ]] || { echo "--pm2-user requires a value." >&2; exit 2; }
      pm2_user=$2
      shift 2
      ;;
    --pm2-home)
      [[ $# -ge 2 ]] || { echo "--pm2-home requires a value." >&2; exit 2; }
      pm2_home=$2
      shift 2
      ;;
    --allow-insecure-http)
      allow_insecure_http=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

run_pm2() {
  sudo -Hiu "${pm2_user}" env PM2_HOME="${pm2_home}" "${pm2_binary}" "$@"
}

validate_inputs() {
  [[ ${EUID} -eq 0 ]] || fail "Run this installer as root with sudo."
  [[ -d /run/systemd/system ]] || fail "systemd must be running as PID 1 on this Ubuntu server."
  [[ ${mode} == "host" || ${mode} == "pm2" ]] || fail "--mode must be host or pm2."
  [[ ${server_name} =~ ^[A-Za-z0-9._-]+$ ]] || fail "--server-name may contain only letters, digits, dot, underscore, and hyphen."
  [[ ${environment_name} =~ ^[A-Za-z0-9._-]+$ ]] || fail "--environment may contain only letters, digits, dot, underscore, and hyphen."
  [[ ${openobserve_url} =~ ^https?://([A-Za-z0-9.-]+|\[[A-Fa-f0-9:]+\])(:[0-9]{1,5})?/api/[A-Za-z0-9_-]+$ ]] \
    || fail "--openobserve-url must be https://HOST[:PORT]/api/ORGANIZATION without credentials, a path prefix, query, fragment, or trailing slash."
  url_authority=${openobserve_url#*://}
  url_authority=${url_authority%%/api/*}
  if [[ ${url_authority} =~ :([0-9]+)$ ]]; then
    url_port=${BASH_REMATCH[1]}
    url_port_number=$((10#${url_port}))
    (( url_port_number >= 1 && url_port_number <= 65535 )) \
      || fail "The OpenObserve URL port must be between 1 and 65535."
  fi
  if [[ ${openobserve_url} == http://* ]] \
    && [[ ${openobserve_url} != http://127.0.0.1/* ]] \
    && [[ ${openobserve_url} != http://127.0.0.1:* ]] \
    && [[ ${openobserve_url} != http://localhost/* ]] \
    && [[ ${openobserve_url} != http://localhost:* ]] \
    && [[ ${openobserve_url} != http://\[::1\]/* ]] \
    && [[ ${openobserve_url} != http://\[::1\]:* ]] \
    && [[ ${allow_insecure_http} != true ]]; then
    fail "Non-loopback HTTP requires --allow-insecure-http. Use HTTPS in production."
  fi
  [[ -f ${authorization_key_file} && -r ${authorization_key_file} ]] \
    || fail "Cannot read --authorization-key-file: ${authorization_key_file}"
  mapfile -t authorization_lines <"${authorization_key_file}"
  [[ ${#authorization_lines[@]} -eq 1 && -n ${authorization_lines[0]} ]] \
    || fail "The authorization key file must contain exactly one non-empty line."
  authorization_key=${authorization_lines[0]}
  [[ ${authorization_key} =~ ^[A-Za-z0-9+/=]+$ ]] \
    || fail "The authorization key file must contain only the base64 key, without the word Basic."
  decoded_authorization=$(printf '%s' "${authorization_key}" | base64 --decode 2>/dev/null) \
    || fail "The authorization key is not valid base64."
  [[ ${decoded_authorization} == *:* && ${decoded_authorization} != *$'\n'* && ${decoded_authorization} != *$'\r'* ]] \
    || fail "The authorization key must decode to one username:password line."
  unset decoded_authorization

  [[ -r /etc/os-release ]] || fail "/etc/os-release is missing."
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == "ubuntu" ]] || fail "This installer supports Ubuntu only; detected ID=${ID:-unknown}."
  case "${VERSION_ID:-}" in
    22.04|24.04) ;;
    *) fail "Supported production releases are Ubuntu 22.04 and 24.04 LTS; detected VERSION_ID=${VERSION_ID:-unknown}." ;;
  esac

  if [[ ${mode} == "pm2" ]]; then
    [[ -n ${pm2_user} ]] || fail "--pm2-user is required in PM2 mode."
    [[ ${pm2_user} =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || fail "--pm2-user is not a safe Linux username."
    getent passwd "${pm2_user}" >/dev/null || fail "PM2 user does not exist: ${pm2_user}"
    pm2_user_home=$(getent passwd "${pm2_user}" | cut -d: -f6)
    [[ -d ${pm2_user_home} ]] || fail "PM2 user home does not exist: ${pm2_user_home}"
    if [[ -z ${pm2_home} ]]; then
      pm2_home="${pm2_user_home}/.pm2"
    fi
    [[ ${pm2_home} == /* && ${pm2_home} =~ ^[A-Za-z0-9_./-]+$ ]] \
      || fail "--pm2-home must be a safe absolute path."
    pm2_home=$(realpath -e -- "${pm2_home}") || fail "Cannot resolve PM2 home: ${pm2_home}"
    [[ -d ${pm2_home}/logs ]] || fail "PM2 log directory does not exist: ${pm2_home}/logs"
  fi
}

install_dependencies() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl tar acl jq sudo
}

install_collector_binary() {
  (
    case "$(uname -m)" in
      x86_64)
        collector_arch="amd64"
        expected_sha256=${OTEL_SHA256_AMD64}
        ;;
      aarch64|arm64)
        collector_arch="arm64"
        expected_sha256=${OTEL_SHA256_ARM64}
        ;;
      *) fail "Unsupported architecture: $(uname -m)" ;;
    esac

    local asset="otelcol-contrib_${OTEL_VERSION}_linux_${collector_arch}.tar.gz"
    local release_base="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}"
    local work_dir
    work_dir=$(mktemp -d)
    trap 'rm -rf "${work_dir}"' EXIT

    curl -fL "${release_base}/${asset}" -o "${work_dir}/${asset}"
    (
      cd "${work_dir}"
      printf '%s  %s\n' "${expected_sha256}" "${asset}" | sha256sum --check --strict -
    )
    tar -xzf "${work_dir}/${asset}" -C "${work_dir}"
    install -m 0755 "${work_dir}/otelcol-contrib" "${OTEL_CANDIDATE}"
  )
  "${OTEL_CANDIDATE}" --version
}

install_agent_account() {
  if ! getent group "${AGENT_GROUP}" >/dev/null; then
    groupadd --system "${AGENT_GROUP}"
  fi
  if ! id -u "${AGENT_USER}" >/dev/null 2>&1; then
    useradd --system \
      --gid "${AGENT_GROUP}" \
      --home-dir "${STATE_DIR}" \
      --shell /usr/sbin/nologin \
      "${AGENT_USER}"
  fi
  usermod -aG systemd-journal "${AGENT_USER}"
  if getent group adm >/dev/null; then
    usermod -aG adm "${AGENT_USER}"
  fi
  install -d -o "${AGENT_USER}" -g "${AGENT_GROUP}" -m 0750 \
    "${STATE_DIR}" "${STATE_DIR}/storage" "${STATE_DIR}/compaction"
  install -d -o root -g "${AGENT_GROUP}" -m 0750 "${CONFIG_DIR}"
}

render_agent_config() {
  local template
  if [[ ${mode} == "pm2" ]]; then
    template="${template_dir}/otel-config-pm2.yaml"
  else
    template="${template_dir}/otel-config-host.yaml"
  fi
  [[ -f ${template} ]] || fail "Missing collector template: ${template}"

  sed \
    -e "s|__SERVER_NAME__|${server_name}|g" \
    -e "s|__ENVIRONMENT__|${environment_name}|g" \
    -e "s|__PM2_HOME__|${pm2_home}|g" \
    "${template}" >"${CONFIG_CANDIDATE}"
  chmod 0640 "${CONFIG_CANDIDATE}"
  chown root:"${AGENT_GROUP}" "${CONFIG_CANDIDATE}"

  umask 077
  cat >"${ENV_CANDIDATE}" <<EOF
OPENOBSERVE_OTLP_ENDPOINT=${openobserve_url}
OPENOBSERVE_AUTHORIZATION_KEY=${authorization_key}
EOF
  chmod 0640 "${ENV_CANDIDATE}"
  chown root:"${AGENT_GROUP}" "${ENV_CANDIDATE}"

  cat >"${INSTALL_CONFIG_CANDIDATE}" <<EOF
MODE=${mode}
SERVER_NAME=${server_name}
ENVIRONMENT_NAME=${environment_name}
PM2_USER=${pm2_user}
PM2_HOME=${pm2_home}
PM2_BINARY=${pm2_binary:-}
EOF
  chmod 0640 "${INSTALL_CONFIG_CANDIDATE}"
  chown root:"${AGENT_GROUP}" "${INSTALL_CONFIG_CANDIDATE}"

  install -m 0644 "${template_dir}/opspika-agent.service" "${SERVICE_CANDIDATE}"
  env \
    OPENOBSERVE_OTLP_ENDPOINT="${openobserve_url}" \
    OPENOBSERVE_AUTHORIZATION_KEY="${authorization_key}" \
    "${OTEL_CANDIDATE}" validate --config="${CONFIG_CANDIDATE}"
  unset authorization_key authorization_lines
}

grant_pm2_log_access() {
  setfacl -m "u:${AGENT_USER}:--x" "${pm2_user_home}"
  setfacl -m "u:${AGENT_USER}:r-x" "${pm2_home}"
  setfacl -R -m "u:${AGENT_USER}:r-X" "${pm2_home}/logs"
  setfacl -m "d:u:${AGENT_USER}:r-X" "${pm2_home}/logs"
}

resolve_pm2_runtime() {
  pm2_binary=$(sudo -Hiu "${pm2_user}" bash -lc 'command -v pm2')
  node_binary=$(sudo -Hiu "${pm2_user}" bash -lc 'command -v node')
  [[ -x ${pm2_binary} ]] || fail "Cannot find an executable PM2 binary for ${pm2_user}."
  [[ -x ${node_binary} ]] || fail "Cannot find an executable Node.js binary for ${pm2_user}."
  [[ ${pm2_binary} =~ ^/[A-Za-z0-9_./-]+$ ]] || fail "PM2 resolved to an unsafe executable path: ${pm2_binary}"
  [[ ${node_binary} =~ ^/[A-Za-z0-9_./-]+$ ]] || fail "Node.js resolved to an unsafe executable path: ${node_binary}"

  node_version=$(sudo -Hiu "${pm2_user}" "${node_binary}" -p 'process.versions.node.split(".")[0]')
  [[ ${node_version} =~ ^[0-9]+$ ]] || fail "Cannot determine Node.js version for ${pm2_user}."
  (( node_version >= 18 )) || fail "PM2 exporter requires Node.js 18 or newer; found major ${node_version}."
}

install_pm2_exporter() {

  install -d -o "${pm2_user}" -g "$(id -gn "${pm2_user}")" -m 0755 "${EXPORTER_DIR}"
  install -o "${pm2_user}" -g "$(id -gn "${pm2_user}")" -m 0644 \
    "${exporter_source_dir}/server.js" \
    "${exporter_source_dir}/metrics.js" \
    "${exporter_source_dir}/package.json" \
    "${EXPORTER_DIR}/"

  sed \
    -e "s|__EXPORTER_DIR__|${EXPORTER_DIR}|g" \
    -e "s|__NODE_BINARY__|${node_binary}|g" \
    -e "s|__PM2_BINARY__|${pm2_binary}|g" \
    "${template_dir}/pm2-exporter.ecosystem.config.cjs" \
    >"${EXPORTER_DIR}/ecosystem.config.cjs"
  chown "${pm2_user}:$(id -gn "${pm2_user}")" "${EXPORTER_DIR}/ecosystem.config.cjs"
  chmod 0644 "${EXPORTER_DIR}/ecosystem.config.cjs"

  if [[ -f ${pm2_home}/dump.pm2 ]]; then
    cp -a "${pm2_home}/dump.pm2" "${pm2_home}/dump.pm2.monitoring-backup.$(date -u +%Y%m%dT%H%M%SZ)"
  fi

  run_pm2 startOrReload "${EXPORTER_DIR}/ecosystem.config.cjs" --update-env
  # Re-installing the exact version is intentional: it upgrades older modules
  # and prevents a moving npm `latest` target on subsequent installations.
  run_pm2 install "pm2-logrotate@${PM2_LOGROTATE_VERSION}"
  run_pm2 set pm2-logrotate:max_size 100M
  run_pm2 set pm2-logrotate:retain 7
  run_pm2 set pm2-logrotate:compress true
  run_pm2 set pm2-logrotate:workerInterval 30
  run_pm2 set pm2-logrotate:rotateInterval '0 0 * * *'
  run_pm2 save

  for _ in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:9988/healthz >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  fail "PM2 exporter did not become healthy on 127.0.0.1:9988."
}

start_agent() {
  systemctl daemon-reload
  systemctl enable opspika-agent.service
  systemctl restart opspika-agent.service
  for _ in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:13134/ >/dev/null 2>&1 \
      || curl -fsS http://127.0.0.1:13134/status >/dev/null 2>&1; then
      echo "OpsPika Agent is healthy."
      return 0
    fi
    sleep 1
  done
  systemctl status opspika-agent.service --no-pager >&2 || true
  journalctl -u opspika-agent.service -n 100 --no-pager >&2 || true
  echo "ERROR: The monitoring agent did not become healthy." >&2
  return 1
}

activate_agent() {
  local rollback_dir
  local service_was_active=false
  local -a candidates=(
    "${OTEL_CANDIDATE}"
    "${CONFIG_CANDIDATE}"
    "${ENV_CANDIDATE}"
    "${INSTALL_CONFIG_CANDIDATE}"
    "${SERVICE_CANDIDATE}"
  )
  local -a targets=(
    "${OTEL_BINARY}"
    "${CONFIG_DIR}/config.yaml"
    "${CONFIG_DIR}/agent.env"
    "${CONFIG_DIR}/install.conf"
    "${SERVICE_FILE}"
  )

  rollback_dir=$(mktemp -d /tmp/opspika-agent-rollback.XXXXXX)
  if systemctl is-active --quiet opspika-agent.service; then
    service_was_active=true
  fi

  for index in "${!targets[@]}"; do
    if [[ -e ${targets[index]} ]]; then
      cp -a -- "${targets[index]}" "${rollback_dir}/${index}"
      printf 'present\n' >"${rollback_dir}/${index}.state"
    else
      printf 'absent\n' >"${rollback_dir}/${index}.state"
    fi
    mv -f -- "${candidates[index]}" "${targets[index]}"
  done

  if start_agent; then
    rm -r -- "${rollback_dir}"
    return 0
  fi

  echo "Restoring the previous OpsPika Agent release after failed activation." >&2
  if [[ ${service_was_active} != true ]]; then
    systemctl disable --now opspika-agent.service >/dev/null 2>&1 || true
  fi
  for index in "${!targets[@]}"; do
    if [[ $(<"${rollback_dir}/${index}.state") == "present" ]]; then
      cp -a -- "${rollback_dir}/${index}" "${targets[index]}"
    else
      rm -f -- "${targets[index]}"
    fi
  done
  systemctl daemon-reload
  if [[ ${service_was_active} == true ]]; then
    systemctl restart opspika-agent.service || true
  fi
  rm -r -- "${rollback_dir}"
  return 1
}

validate_inputs
install_dependencies
rm -f -- \
  "${OTEL_CANDIDATE}" \
  "${CONFIG_CANDIDATE}" \
  "${ENV_CANDIDATE}" \
  "${INSTALL_CONFIG_CANDIDATE}" \
  "${SERVICE_CANDIDATE}"
install_collector_binary
install_agent_account
if [[ ${mode} == "pm2" ]]; then
  resolve_pm2_runtime
  grant_pm2_log_access
fi
render_agent_config
activate_agent || fail "Agent activation failed; the previous release was restored."
if [[ ${mode} == "pm2" ]]; then
  install_pm2_exporter
fi

echo
echo "Installation complete."
echo "Mode: ${mode}"
echo "Server name: ${server_name}"
echo "OpenObserve endpoint: ${openobserve_url}"
echo "Run run-acceptance-test.sh to verify metrics, logs, and restart recovery end to end."
