#!/usr/bin/env bash
set -Eeuo pipefail

readonly AGENT_USER="opspika-agent"
readonly AGENT_GROUP="opspika-agent"
readonly CONFIG_DIR="/etc/opspika-agent"
readonly STATE_DIR="/var/lib/opspika-agent"
readonly OTEL_BINARY="/usr/local/bin/opspika-otelcol"
readonly SERVICE_FILE="/etc/systemd/system/opspika-agent.service"
readonly EXPORTER_DIR="/opt/opspika-process-exporter"
readonly INSTALL_CONFIG="${CONFIG_DIR}/install.conf"

remove_logrotate=false
purge_state=false

usage() {
  cat <<'EOF'
Usage: sudo ./agent/uninstall-monitoring-agent.sh [options]

Options:
  --remove-logrotate  Also uninstall pm2-logrotate from the PM2 daemon.
  --purge-state       Delete queued telemetry and file-offset state.
  --help              Show this help.

By default, pm2-logrotate and local collector state are preserved.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove-logrotate)
      remove_logrotate=true
      shift
      ;;
    --purge-state)
      purge_state=true
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

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this uninstaller as root with sudo." >&2
  exit 1
fi
if [[ ! -r ${INSTALL_CONFIG} ]]; then
  echo "Missing ${INSTALL_CONFIG}; refusing to guess the installed PM2 user or paths." >&2
  exit 1
fi

# Values in install.conf were validated by the installer before being written.
# shellcheck disable=SC1090
source "${INSTALL_CONFIG}"

systemctl disable --now opspika-agent.service >/dev/null 2>&1 || true
rm -f -- "${SERVICE_FILE}" "${OTEL_BINARY}"
systemctl daemon-reload

if [[ ${MODE} == "pm2" && -n ${PM2_USER} && -x ${PM2_BINARY} ]]; then
  if [[ -f ${PM2_HOME}/dump.pm2 ]]; then
    cp -a "${PM2_HOME}/dump.pm2" \
      "${PM2_HOME}/dump.pm2.pre-monitoring-uninstall.$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  sudo -Hiu "${PM2_USER}" env PM2_HOME="${PM2_HOME}" "${PM2_BINARY}" \
    delete opspika-process-exporter >/dev/null 2>&1 || true
  if [[ ${remove_logrotate} == true ]]; then
    sudo -Hiu "${PM2_USER}" env PM2_HOME="${PM2_HOME}" "${PM2_BINARY}" \
      uninstall pm2-logrotate >/dev/null 2>&1 || true
  fi
  sudo -Hiu "${PM2_USER}" env PM2_HOME="${PM2_HOME}" "${PM2_BINARY}" \
    save >/dev/null 2>&1 || true

  if command -v setfacl >/dev/null 2>&1; then
    setfacl -x "u:${AGENT_USER}" "$(getent passwd "${PM2_USER}" | cut -d: -f6)" 2>/dev/null || true
    setfacl -x "u:${AGENT_USER}" "${PM2_HOME}" 2>/dev/null || true
    setfacl -R -x "u:${AGENT_USER}" "${PM2_HOME}/logs" 2>/dev/null || true
    setfacl -x "d:u:${AGENT_USER}" "${PM2_HOME}/logs" 2>/dev/null || true
  fi
  rm -rf -- "${EXPORTER_DIR}"
fi

rm -rf -- "${CONFIG_DIR}"
if [[ ${purge_state} == true ]]; then
  echo "Purging collector queue and file-offset state from ${STATE_DIR}."
  rm -rf -- "${STATE_DIR}"
  userdel "${AGENT_USER}" >/dev/null 2>&1 || true
  groupdel "${AGENT_GROUP}" >/dev/null 2>&1 || true
else
  echo "Preserved collector state at ${STATE_DIR}."
fi

echo "OpsPika Agent uninstalled."
if [[ ${remove_logrotate} != true && ${MODE} == "pm2" ]]; then
  echo "pm2-logrotate was intentionally preserved."
fi
