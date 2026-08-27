#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
openobserve_binary=${OPENOBSERVE_BINARY:-}
test_port=${OPSPIKA_TEST_PORT:-15081}

[[ ${EUID} -eq 0 ]] || { echo "Run this disposable API test as root." >&2; exit 1; }
[[ -n ${openobserve_binary} && -x ${openobserve_binary} ]] || {
  echo "Set OPENOBSERVE_BINARY to an executable OpenObserve v0.90.3 binary." >&2
  exit 1
}
if [[ ! ${test_port} =~ ^[0-9]+$ ]]; then
  echo "OPSPIKA_TEST_PORT must be numeric." >&2
  exit 2
fi
test_port_number=$((10#${test_port}))
if (( test_port_number < 1024 || test_port_number > 65535 )); then
  echo "OPSPIKA_TEST_PORT must be an unprivileged port from 1024 to 65535." >&2
  exit 2
fi
command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }
if curl -fsS "http://127.0.0.1:${test_port}/healthz" >/dev/null 2>&1; then
  echo "Refusing to use occupied test port ${test_port}." >&2
  exit 1
fi

work_dir=$(mktemp -d /tmp/opspika-openobserve-api.XXXXXX)
server_pid=""
cleanup() {
  if [[ -n ${server_pid} ]] && kill -0 "${server_pid}" 2>/dev/null; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
  fi
  rm -r -- "${work_dir}"
}
trap cleanup EXIT

export ZO_LOCAL_MODE=true
export ZO_DATA_DIR="${work_dir}/data"
export ZO_HTTP_PORT=${test_port}
export ZO_ROOT_USER_EMAIL=opspika-validation@example.com
export ZO_ROOT_USER_PASSWORD='OpsPikaValidation1!local'
export ZO_TELEMETRY=false
mkdir -p "${ZO_DATA_DIR}"
"${openobserve_binary}" >"${work_dir}/openobserve.log" 2>&1 &
server_pid=$!

for _ in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:${test_port}/healthz" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "${server_pid}" 2>/dev/null; then
    cat "${work_dir}/openobserve.log" >&2
    exit 1
  fi
  sleep 1
done
curl -fsS "http://127.0.0.1:${test_port}/healthz" >/dev/null

env_file="${work_dir}/central.env"
cat >"${env_file}" <<EOF
OPENOBSERVE_IMAGE=validation-only
OPENOBSERVE_BIND_ADDRESS=127.0.0.1
OPENOBSERVE_HTTP_PORT=${test_port}
OPENOBSERVE_VOLUME_NAME=validation-only
ZO_ROOT_USER_EMAIL=${ZO_ROOT_USER_EMAIL}
ZO_ROOT_USER_PASSWORD=${ZO_ROOT_USER_PASSWORD}
ZO_COMPACT_DATA_RETENTION_DAYS=180
OPENOBSERVE_LOG_LEVEL=info
EOF
chmod 0600 "${env_file}"

auth=$(printf '%s' "${ZO_ROOT_USER_EMAIL}:${ZO_ROOT_USER_PASSWORD}" | base64 -w0)
auth_header="Authorization: Basic ${auth}"
api="http://127.0.0.1:${test_port}/api/default"

"${repo_dir}/central/scripts/provision-dashboards.sh" --env-file "${env_file}"

now_ms=$(( $(date +%s) * 1000 ))
previous_ms=$(( now_ms - 15000 ))
cat >"${work_dir}/metrics.json" <<EOF
[
 {"__name__":"system_cpu_time","__type__":"counter","host_name":"opspika-local","deployment_environment_name":"validation","state":"idle","cpu":"cpu0","_timestamp":${previous_ms},"value":10},
 {"__name__":"system_cpu_time","__type__":"counter","host_name":"opspika-local","deployment_environment_name":"validation","state":"idle","cpu":"cpu0","_timestamp":${now_ms},"value":20},
 {"__name__":"system_cpu_load_average_5m","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","_timestamp":${now_ms},"value":0.5},
 {"__name__":"system_memory_utilization","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","state":"used","_timestamp":${now_ms},"value":0.5},
 {"__name__":"system_paging_utilization","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","state":"used","_timestamp":${now_ms},"value":0.1},
 {"__name__":"system_filesystem_utilization","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","device":"/dev/sda1","mountpoint":"/","type":"ext4","_timestamp":${now_ms},"value":0.4},
 {"__name__":"system_disk_io","__type__":"counter","host_name":"opspika-local","deployment_environment_name":"validation","device":"sda","direction":"read","_timestamp":${previous_ms},"value":1000},
 {"__name__":"system_disk_io","__type__":"counter","host_name":"opspika-local","deployment_environment_name":"validation","device":"sda","direction":"read","_timestamp":${now_ms},"value":2000},
 {"__name__":"system_network_io","__type__":"counter","host_name":"opspika-local","deployment_environment_name":"validation","device":"eth0","direction":"receive","_timestamp":${previous_ms},"value":1000},
 {"__name__":"system_network_io","__type__":"counter","host_name":"opspika-local","deployment_environment_name":"validation","device":"eth0","direction":"receive","_timestamp":${now_ms},"value":2000},
 {"__name__":"system_uptime","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","_timestamp":${now_ms},"value":3600},
 {"__name__":"system_processes_count","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","status":"running","_timestamp":${now_ms},"value":20},
 {"__name__":"pm2_exporter_collect_success","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","_timestamp":${now_ms},"value":1},
 {"__name__":"pm2_process_up","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","app":"api","instance":"0","_timestamp":${now_ms},"value":1},
 {"__name__":"pm2_process_cpu_percent","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","app":"api","instance":"0","_timestamp":${now_ms},"value":5},
 {"__name__":"pm2_process_memory_bytes","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","app":"api","instance":"0","_timestamp":${now_ms},"value":67108864},
 {"__name__":"pm2_process_uptime_seconds","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","app":"api","instance":"0","_timestamp":${now_ms},"value":300},
 {"__name__":"pm2_process_restarts","__type__":"counter","host_name":"opspika-local","deployment_environment_name":"validation","app":"api","instance":"0","_timestamp":${previous_ms},"value":0},
 {"__name__":"pm2_process_restarts","__type__":"counter","host_name":"opspika-local","deployment_environment_name":"validation","app":"api","instance":"0","_timestamp":${now_ms},"value":1},
 {"__name__":"pm2_process_unstable_restarts","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","app":"api","instance":"0","_timestamp":${now_ms},"value":0},
 {"__name__":"pm2_app_instances_configured","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","app":"api","_timestamp":${now_ms},"value":1},
 {"__name__":"pm2_app_instances_running","__type__":"gauge","host_name":"opspika-local","deployment_environment_name":"validation","app":"api","_timestamp":${now_ms},"value":1}
]
EOF
curl -fsS -H "${auth_header}" -H 'Content-Type: application/json' \
  --data-binary "@${work_dir}/metrics.json" "${api}/ingest/metrics/_json" >/dev/null
curl -fsS -H "${auth_header}" -H 'Content-Type: application/json' \
  --data-binary '[{"body":"validation log","host_name":"opspika-local","deployment_environment_name":"validation","pm2_app":"api","pm2_stream":"error","log_file_name":"api-error.log"}]' \
  "${api}/pm2_logs/_json" >/dev/null

for _ in $(seq 1 30); do
  streams=$(curl -fsS -H "${auth_header}" "${api}/streams?fetchSchema=false&type=logs")
  if jq -e 'any(.list[]?; .name == "pm2_logs")' <<<"${streams}" >/dev/null; then
    break
  fi
  sleep 1
done
"${repo_dir}/central/scripts/configure-streams.sh" --env-file "${env_file}"

curl -fsS -H "${auth_header}" -H 'Content-Type: application/json' \
  --data-binary '{"name":"opspika_validation","url":"https://example.com/opspika-validation","method":"post","type":"http","template":"Default"}' \
  "${api}/alerts/destinations" >/dev/null
"${repo_dir}/central/scripts/provision-alerts.sh" \
  --env-file "${env_file}" \
  --destination opspika_validation

# A second pass must preserve every same-name resource without duplication.
"${repo_dir}/central/scripts/provision-dashboards.sh" --env-file "${env_file}"
"${repo_dir}/central/scripts/provision-alerts.sh" \
  --env-file "${env_file}" \
  --destination opspika_validation

dashboards=$(curl -fsS -H "${auth_header}" "${api}/dashboards")
jq -e '(.dashboards | length) == 3' <<<"${dashboards}" >/dev/null
alerts=$(curl -fsS -H "${auth_header}" "http://127.0.0.1:${test_port}/api/v2/default/alerts")
jq -e '((.list // .alerts // []) | length) >= 7' <<<"${alerts}" >/dev/null

start_us=$(( ($(date +%s) - 3600) * 1000000 ))
end_us=$(( ($(date +%s) + 60) * 1000000 ))
query_count=0
for dashboard in "${repo_dir}"/dashboards/*.dashboard.json; do
  while IFS=$'\t' read -r stream_type query; do
    query=${query//\$host_name/opspika-local}
    query=${query//\$environment/validation}
    query=${query//\$app/api}
    if [[ ${stream_type} == "metrics" ]]; then
      response=$(curl -fsS -H "${auth_header}" --get \
        --data-urlencode "query=${query}" "${api}/prometheus/api/v1/query")
      jq -e '.status == "success"' <<<"${response}" >/dev/null
    else
      payload=$(jq -cn --arg sql "${query}" \
        --argjson start "${start_us}" --argjson end "${end_us}" \
        '{query:{sql:$sql,start_time:$start,end_time:$end,from:0,size:100},search_type:"dashboards",timeout:30}')
      curl -fsS -H "${auth_header}" -H 'Content-Type: application/json' \
        --data-binary "${payload}" "${api}/_search" >/dev/null
    fi
    ((query_count += 1))
  done < <(jq -r '.tabs[].panels[].queries[] | [.fields.stream_type, .query] | @tsv' "${dashboard}")
done

echo "OpenObserve API validation passed: 3 dashboards, at least 7 alerts, ${query_count} panel queries."
