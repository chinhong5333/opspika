#!/usr/bin/env bash
set -Eeuo pipefail

readonly CONFIG_DIR="/etc/opspika-agent"
readonly INSTALL_CONFIG="${CONFIG_DIR}/install.conf"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this verifier as root with sudo." >&2
  exit 1
fi
if [[ ! -r ${INSTALL_CONFIG} || ! -r ${CONFIG_DIR}/agent.env ]]; then
  echo "The OpsPika Agent is not fully configured." >&2
  exit 1
fi

# Values in install.conf were validated by the installer before being written.
# shellcheck disable=SC1090
source "${INSTALL_CONFIG}"
# shellcheck disable=SC1091
source "${CONFIG_DIR}/agent.env"

echo "Checking systemd service..."
systemctl is-enabled opspika-agent.service
systemctl is-active opspika-agent.service

echo "Checking collector health..."
if ! curl -fsS http://127.0.0.1:13134/ >/dev/null 2>&1; then
  curl -fsS http://127.0.0.1:13134/status >/dev/null
fi

echo "Checking central OpenObserve health..."
openobserve_base=${OPENOBSERVE_OTLP_ENDPOINT%%/api/*}
curl -fsS "${openobserve_base}/healthz"
echo

echo "Checking protected configuration permissions..."
env_mode=$(stat -c '%a' "${CONFIG_DIR}/agent.env")
[[ ${env_mode} == "640" ]] || {
  echo "Expected ${CONFIG_DIR}/agent.env mode 640; found ${env_mode}." >&2
  exit 1
}

if [[ ${MODE} == "pm2" ]]; then
  echo "Checking PM2 exporter..."
  curl -fsS http://127.0.0.1:9988/healthz
  curl -fsS http://127.0.0.1:9988/metrics \
    | grep -q '^pm2_exporter_collect_success 1$'
  sudo -Hiu "${PM2_USER}" env PM2_HOME="${PM2_HOME}" "${PM2_BINARY}" \
    describe opspika-process-exporter >/dev/null
  sudo -Hiu "${PM2_USER}" env PM2_HOME="${PM2_HOME}" "${PM2_BINARY}" \
    describe pm2-logrotate >/dev/null
  echo "PM2 exporter and pm2-logrotate are online."
fi

echo "Checking recent collector logs for fatal startup errors..."
if journalctl -u opspika-agent.service --since '-5 minutes' --no-pager \
  | grep -Eiq '(^|[[:space:]])(fatal|panic)([[:space:]:]|$)'; then
  echo "A fatal or panic entry exists in the last five minutes of collector logs." >&2
  exit 1
fi

echo
echo "Local verification passed for ${SERVER_NAME} (${MODE} mode)."
echo "Open OpenObserve and confirm that metrics are current."
if [[ ${MODE} == "pm2" ]]; then
  echo "Then emit one unique PM2 test log line and confirm it appears in the pm2_logs stream."
fi
