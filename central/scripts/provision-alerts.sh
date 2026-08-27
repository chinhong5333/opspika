#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
central_dir=$(cd -- "${script_dir}/.." && pwd)
repo_dir=$(cd -- "${central_dir}/.." && pwd)
env_file="${central_dir}/.env"
organization="default"
destination=""
enable_alerts=false

usage() {
  cat <<'EOF'
Usage:
  sudo ./central/scripts/provision-alerts.sh \
    --destination OPENOBSERVE_DESTINATION [--enable]

Options:
  --destination NAME         Existing, tested OpenObserve alert destination.
  --enable                   Create alerts enabled; default is disabled.
  --env-file ABSOLUTE_PATH   Central environment file (default central/.env).
  --organization NAME        OpenObserve organization (default default).
  --help                     Show this help.

Run this after agents have sent data and after creating/testing a notification
destination in OpenObserve. Existing alerts with the same name are preserved.
Templates whose metric or log stream does not exist are skipped safely; rerun
the command after that integration begins sending data.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination)
      [[ $# -ge 2 ]] || { echo "--destination requires a value." >&2; exit 2; }
      destination=$2
      shift 2
      ;;
    --enable)
      enable_alerts=true
      shift
      ;;
    --env-file)
      [[ $# -ge 2 ]] || { echo "--env-file requires a value." >&2; exit 2; }
      env_file=$2
      shift 2
      ;;
    --organization)
      [[ $# -ge 2 ]] || { echo "--organization requires a value." >&2; exit 2; }
      organization=$2
      shift 2
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

[[ ${EUID} -eq 0 ]] || { echo "Run this provisioner as root with sudo." >&2; exit 1; }
[[ ${env_file} == /* && -r ${env_file} ]] || {
  echo "--env-file must be a readable absolute path." >&2
  exit 2
}
[[ ${organization} =~ ^[A-Za-z0-9_-]+$ ]] || {
  echo "--organization may contain only letters, digits, underscore, and hyphen." >&2
  exit 2
}
[[ ${destination} =~ ^[A-Za-z0-9_.-]+$ ]] || {
  echo "--destination may contain only letters, digits, dot, underscore, and hyphen." >&2
  exit 2
}
command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

# shellcheck disable=SC1090
source "${env_file}"
[[ ${ZO_ROOT_USER_EMAIL:-} =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || {
  echo "ZO_ROOT_USER_EMAIL is missing or invalid in ${env_file}." >&2
  exit 1
}
[[ ${ZO_ROOT_USER_PASSWORD:-} =~ ^[A-Za-z0-9._!@%+=:/-]{12,128}$ ]] || {
  echo "ZO_ROOT_USER_PASSWORD is missing or invalid in ${env_file}." >&2
  exit 1
}
[[ ${OPENOBSERVE_BIND_ADDRESS:-} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || {
  echo "OPENOBSERVE_BIND_ADDRESS is missing or invalid in ${env_file}." >&2
  exit 1
}
if [[ ! ${OPENOBSERVE_HTTP_PORT:-} =~ ^[0-9]+$ ]]; then
  echo "OPENOBSERVE_HTTP_PORT is missing or invalid in ${env_file}." >&2
  exit 1
fi
port_number=$((10#${OPENOBSERVE_HTTP_PORT}))
if (( port_number < 1 || port_number > 65535 )); then
  echo "OPENOBSERVE_HTTP_PORT is outside the valid port range in ${env_file}." >&2
  exit 1
fi

api_host=${OPENOBSERVE_BIND_ADDRESS}
if [[ ${api_host} == "0.0.0.0" ]]; then
  api_host="127.0.0.1"
fi
server_base="http://${api_host}:${OPENOBSERVE_HTTP_PORT}"
organization_api="${server_base}/api/${organization}"
alerts_api="${server_base}/api/v2/${organization}/alerts"
authorization_key=$(printf '%s' "${ZO_ROOT_USER_EMAIL}:${ZO_ROOT_USER_PASSWORD}" | base64 -w0)
authorization_header="Authorization: Basic ${authorization_key}"
unset authorization_key

curl -fsS "${server_base}/healthz" >/dev/null
curl -fsS \
  -H "${authorization_header}" \
  -H 'Accept: application/json' \
  "${organization_api}/alerts/destinations/${destination}" >/dev/null || {
    echo "Alert destination does not exist or is inaccessible: ${destination}" >&2
    exit 1
  }

"${script_dir}/configure-streams.sh" \
  --env-file "${env_file}" \
  --organization "${organization}"

metrics_streams=$(curl -fsS \
  -H "${authorization_header}" \
  -H 'Accept: application/json' \
  "${organization_api}/streams?fetchSchema=false&type=metrics")
log_streams=$(curl -fsS \
  -H "${authorization_header}" \
  -H 'Accept: application/json' \
  "${organization_api}/streams?fetchSchema=false&type=logs")
alerts_response=$(curl -fsS \
  -H "${authorization_header}" \
  -H 'Accept: application/json' \
  "${alerts_api}")

alert_exists() {
  local alert_name=$1
  jq -e --arg name "${alert_name}" \
    'any((.list // .alerts // [])[]?; .name == $name)' \
    <<<"${alerts_response}" >/dev/null
}

existing_alert() {
  local alert_name=$1
  jq -c --arg name "${alert_name}" \
    'first((.list // .alerts // [])[]? | select(.name == $name)) // empty' \
    <<<"${alerts_response}"
}

stream_exists() {
  local stream_type=$1
  local stream_name=$2
  local response
  if [[ ${stream_type} == "metrics" ]]; then
    response=${metrics_streams}
  else
    response=${log_streams}
  fi
  jq -e --arg name "${stream_name}" 'any(.list[]?; .name == $name)' \
    <<<"${response}" >/dev/null
}

post_alert() {
  local payload_file=$1
  local alert_name
  local existing
  local alert_id
  alert_name=$(jq -er '.name' "${payload_file}")
  if alert_exists "${alert_name}"; then
    existing=$(existing_alert "${alert_name}")
    if [[ ${enable_alerts} == true ]] \
      && ! jq -e '.enabled == true' <<<"${existing}" >/dev/null; then
      alert_id=$(jq -er '.alert_id' <<<"${existing}")
      curl -fsS \
        -X PATCH \
        -H "${authorization_header}" \
        -H 'Accept: application/json' \
        "${alerts_api}/${alert_id}/enable?value=true" >/dev/null
      echo "Enabled existing alert: ${alert_name}"
      ((enabled_existing += 1))
      return 0
    fi
    echo "Alert already exists; preserving it: ${alert_name}"
    ((preserved += 1))
    return 0
  fi
  curl -fsS \
    -H "${authorization_header}" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    --data-binary "@${payload_file}" \
    "${alerts_api}?folder=default" >/dev/null
  echo "Created alert: ${alert_name} (enabled=${enable_alerts})"
  alerts_response=$(jq --arg name "${alert_name}" \
    '.list = ((.list // []) + [{"name": $name}])' <<<"${alerts_response}")
  ((created += 1))
}

work_dir=$(mktemp -d)
trap 'rm -rf "${work_dir}"' EXIT
created=0
preserved=0
enabled_existing=0
skipped=0

for template in "${repo_dir}"/alerts/*.alert.json; do
  [[ -e ${template} ]] || { echo "No alert assets exist in ${repo_dir}/alerts." >&2; exit 1; }
  if [[ $(basename -- "${template}") == "opspika-host-telemetry-missing.alert.json" ]]; then
    continue
  fi
  stream_type=$(jq -er '.stream_type' "${template}")
  stream_name=$(jq -er '.stream_name' "${template}")
  if ! stream_exists "${stream_type}" "${stream_name}"; then
    echo "Skipping alert until stream exists: $(jq -r '.name' "${template}") (${stream_type}/${stream_name})"
    ((skipped += 1))
    continue
  fi
  payload_file="${work_dir}/$(basename -- "${template}")"
  jq --arg destination "${destination}" --argjson enabled "${enable_alerts}" \
    '.destinations = [$destination] | .enabled = $enabled' \
    "${template}" >"${payload_file}"
  post_alert "${payload_file}"
done

if stream_exists metrics system_uptime; then
  host_response=$(curl -fsS \
    -H "${authorization_header}" \
    -H 'Accept: application/json' \
    --get \
    --data-urlencode 'query=group by(host_name) (system_uptime)' \
    "${organization_api}/prometheus/api/v1/query")
  mapfile -t host_names < <(jq -er '.data.result[]?.metric.host_name' <<<"${host_response}" | sort -u)
  for host_name in "${host_names[@]}"; do
    [[ ${host_name} =~ ^[A-Za-z0-9._-]+$ ]] || {
      echo "Skipping unsafe host label returned by OpenObserve: ${host_name}" >&2
      ((skipped += 1))
      continue
    }
    safe_host=$(tr '[:upper:].-' '[:lower:]__' <<<"${host_name}" | tr -cd 'a-z0-9_')
    alert_name="opspika_host_telemetry_missing_${safe_host}"
    payload_file="${work_dir}/${alert_name}.json"
    jq \
      --arg destination "${destination}" \
      --arg host "${host_name}" \
      --arg name "${alert_name}" \
      --argjson enabled "${enable_alerts}" \
      '.name = $name
       | .destinations = [$destination]
       | .enabled = $enabled
       | .query_condition.promql |= gsub("__HOST_NAME__"; $host)
       | .description |= gsub("__HOST_NAME__"; $host)' \
      "${repo_dir}/alerts/opspika-host-telemetry-missing.alert.json" >"${payload_file}"
    post_alert "${payload_file}"
  done
else
  echo "Skipping per-host telemetry alerts until system_uptime exists."
  ((skipped += 1))
fi

unset authorization_header ZO_ROOT_USER_PASSWORD
echo "Alert provisioning complete: ${created} created, ${enabled_existing} enabled, ${preserved} preserved, ${skipped} skipped."
if [[ ${enable_alerts} != true ]]; then
  echo "Alerts were created disabled. Re-run with --enable after testing the destination."
fi
