#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
central_dir=$(cd -- "${script_dir}/.." && pwd)
env_file="${central_dir}/.env"
organization="default"

usage() {
  cat <<'EOF'
Usage: sudo ./central/scripts/configure-streams.sh [options]

Options:
  --env-file ABSOLUTE_PATH  Central environment file (default central/.env).
  --organization NAME      OpenObserve organization (default default).
  --help                   Show this help.

The command is idempotent. It configures indexed filter fields and full-text
search for the pm2_logs stream after that stream first appears.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

[[ ${EUID} -eq 0 ]] || { echo "Run this command as root with sudo." >&2; exit 1; }
[[ ${env_file} == /* && -r ${env_file} ]] || {
  echo "--env-file must be a readable absolute path." >&2
  exit 2
}
[[ ${organization} =~ ^[A-Za-z0-9_-]+$ ]] || {
  echo "--organization may contain only letters, digits, underscore, and hyphen." >&2
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

api_host=${OPENOBSERVE_BIND_ADDRESS:-127.0.0.1}
if [[ ${api_host} == "0.0.0.0" ]]; then
  api_host="127.0.0.1"
fi
organization_api="http://${api_host}:${OPENOBSERVE_HTTP_PORT}/api/${organization}"
authorization_key=$(printf '%s' "${ZO_ROOT_USER_EMAIL}:${ZO_ROOT_USER_PASSWORD}" | base64 -w0)
authorization_header="Authorization: Basic ${authorization_key}"
unset authorization_key

streams=$(curl -fsS \
  -H "${authorization_header}" \
  -H 'Accept: application/json' \
  "${organization_api}/streams?fetchSchema=false&type=logs")
if ! jq -e 'any(.list[]?; .name == "pm2_logs")' <<<"${streams}" >/dev/null; then
  echo "pm2_logs does not exist yet; stream indexing was not changed."
  exit 0
fi

settings='{
  "full_text_search_keys": {"add": ["body"]},
  "index_fields": {"add": ["host_name", "deployment_environment_name", "pm2_app", "pm2_stream", "log_file_name"]}
}'
curl -fsS \
  -X PUT \
  -H "${authorization_header}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data-binary "${settings}" \
  "${organization_api}/streams/pm2_logs/settings" >/dev/null

unset authorization_header ZO_ROOT_USER_PASSWORD
echo "Configured pm2_logs full-text and exact-match indexes."
