#!/usr/bin/env bash
set -Eeuo pipefail

readonly CONFIG_DIR="/etc/opspika-agent"
readonly INSTALL_CONFIG="${CONFIG_DIR}/install.conf"

[[ ${EUID} -eq 0 ]] || { echo "Run this acceptance test as root with sudo." >&2; exit 1; }
[[ -r ${INSTALL_CONFIG} && -r ${CONFIG_DIR}/agent.env ]] || {
  echo "The OpsPika Agent is not fully configured." >&2
  exit 1
}
command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

# Values were validated by the installer before these root-owned files were written.
# shellcheck disable=SC1090
source "${INSTALL_CONFIG}"
# shellcheck disable=SC1091
source "${CONFIG_DIR}/agent.env"

[[ ${MODE} == "host" || ${MODE} == "pm2" ]] || { echo "Invalid installed mode." >&2; exit 1; }
[[ ${SERVER_NAME} =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid installed server name." >&2; exit 1; }
[[ ${OPENOBSERVE_AUTHORIZATION_KEY} =~ ^[A-Za-z0-9+/=]+$ ]] || {
  echo "Invalid installed authorization key." >&2
  exit 1
}

authorization_header="Authorization: Basic ${OPENOBSERVE_AUTHORIZATION_KEY}"
prometheus_query_url="${OPENOBSERVE_OTLP_ENDPOINT}/prometheus/api/v1/query"
search_url="${OPENOBSERVE_OTLP_ENDPOINT}/_search"

wait_for_metric() {
  local query=$1
  local description=$2
  local response
  for _ in $(seq 1 60); do
    response=$(curl -fsS \
      -H "${authorization_header}" \
      -H 'Accept: application/json' \
      --get \
      --data-urlencode "query=${query}" \
      "${prometheus_query_url}" 2>/dev/null || true)
    if jq -e '.status == "success" and ((.data.result // []) | length > 0)' \
      <<<"${response:-{}}" >/dev/null 2>&1; then
      echo "Verified in OpenObserve: ${description}."
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for OpenObserve metric: ${description}." >&2
  return 1
}

log_event_count() {
  local marker=$1
  local start_time=$2
  local end_time
  local sql
  local payload
  local response
  end_time=$(( $(date +%s) * 1000000 ))
  sql="SELECT count(*) AS event_count FROM \"pm2_logs\" WHERE body = '${marker}' AND host_name = '${SERVER_NAME}'"
  payload=$(jq -cn \
    --arg sql "${sql}" \
    --argjson start_time "${start_time}" \
    --argjson end_time "${end_time}" \
    '{query:{sql:$sql,start_time:$start_time,end_time:$end_time,from:0,size:10},search_type:"ui",timeout:30}')
  response=$(curl -fsS \
    -H "${authorization_header}" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    --data-binary "${payload}" \
    "${search_url}" 2>/dev/null || true)
  jq -er '(.hits[0].event_count // 0) | tonumber' <<<"${response:-{}}" 2>/dev/null || printf '0\n'
}

wait_for_log_once() {
  local marker=$1
  local start_time=$2
  local count
  for _ in $(seq 1 60); do
    count=$(log_event_count "${marker}" "${start_time}")
    if [[ ${count} == "1" ]]; then
      echo "Verified exactly once in OpenObserve: ${marker}."
      return 0
    fi
    if [[ ${count} =~ ^[0-9]+$ ]] && (( count > 1 )); then
      echo "Acceptance marker was duplicated in OpenObserve: ${marker} (${count} records)." >&2
      return 1
    fi
    sleep 2
  done
  echo "Timed out waiting for the acceptance log marker: ${marker}." >&2
  return 1
}

"$(dirname -- "${BASH_SOURCE[0]}")/verify-monitoring-agent.sh"
wait_for_metric "system_uptime{host_name=\"${SERVER_NAME}\"}" "current host uptime for ${SERVER_NAME}"

if [[ ${MODE} == "pm2" ]]; then
  wait_for_metric "pm2_exporter_collect_success{host_name=\"${SERVER_NAME}\"}" \
    "current process-exporter telemetry for ${SERVER_NAME}"

  synthetic_log="${PM2_HOME}/logs/opspika-acceptance-out.log"
  resolved_log_dir=$(realpath -e -- "${PM2_HOME}/logs")
  [[ ${synthetic_log} == "${resolved_log_dir}/opspika-acceptance-out.log" ]] || {
    echo "Synthetic log target escaped the installed PM2 log directory." >&2
    exit 1
  }
  [[ ! -e ${synthetic_log} ]] || {
    echo "Refusing to overwrite existing synthetic target: ${synthetic_log}" >&2
    exit 1
  }
  cleanup_synthetic_log() {
    rm -f -- "${synthetic_log}"
  }
  trap cleanup_synthetic_log EXIT

  sudo -Hiu "${PM2_USER}" touch -- "${synthetic_log}"
  sleep 2
  start_time=$(( ($(date +%s) - 60) * 1000000 ))
  marker_one="opspika_acceptance_${SERVER_NAME}_$(date +%s)_one"
  printf '%s\n' "${marker_one}" \
    | sudo -Hiu "${PM2_USER}" tee -a -- "${synthetic_log}" >/dev/null
  wait_for_log_once "${marker_one}" "${start_time}"

  systemctl restart opspika-agent.service
  for _ in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:13134/ >/dev/null 2>&1 \
      || curl -fsS http://127.0.0.1:13134/status >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  systemctl is-active --quiet opspika-agent.service

  marker_two="opspika_acceptance_${SERVER_NAME}_$(date +%s)_two"
  printf '%s\n' "${marker_two}" \
    | sudo -Hiu "${PM2_USER}" tee -a -- "${synthetic_log}" >/dev/null
  wait_for_log_once "${marker_two}" "${start_time}"
  [[ $(log_event_count "${marker_one}" "${start_time}") == "1" ]] || {
    echo "The first marker count changed after Collector restart." >&2
    exit 1
  }

  cleanup_synthetic_log
  trap - EXIT
fi

unset authorization_header OPENOBSERVE_AUTHORIZATION_KEY
echo "OpsPika end-to-end acceptance checks passed for ${SERVER_NAME} (${MODE} mode)."
