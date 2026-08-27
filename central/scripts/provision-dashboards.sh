#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
central_dir=$(cd -- "${script_dir}/.." && pwd)
repo_dir=$(cd -- "${central_dir}/.." && pwd)
env_file="${central_dir}/.env"
organization="default"

usage() {
  cat <<'EOF'
Usage: sudo ./central/scripts/provision-dashboards.sh [options]

Options:
  --env-file ABSOLUTE_PATH  Central environment file (default central/.env).
  --organization NAME      OpenObserve organization (default default).
  --help                   Show this help.

Existing dashboards with the same exact title are preserved. Missing OpsPika
dashboards are created in OpenObserve's default folder.
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

[[ ${EUID} -eq 0 ]] || { echo "Run this provisioner as root with sudo." >&2; exit 1; }
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

# This file is root-owned mode 0600 and all values written by the installer
# have strict character contracts.
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
api_base="http://${api_host}:${OPENOBSERVE_HTTP_PORT}/api/${organization}"
authorization_key=$(printf '%s' "${ZO_ROOT_USER_EMAIL}:${ZO_ROOT_USER_PASSWORD}" | base64 -w0)
authorization_header="Authorization: Basic ${authorization_key}"
unset authorization_key

curl -fsS "http://${api_host}:${OPENOBSERVE_HTTP_PORT}/healthz" >/dev/null

dashboard_files=("${repo_dir}"/dashboards/*.dashboard.json)
[[ -e ${dashboard_files[0]} ]] || {
  echo "No dashboard assets exist in ${repo_dir}/dashboards." >&2
  exit 1
}

created=0
preserved=0
for dashboard_file in "${dashboard_files[@]}"; do
  title=$(jq -er '.title | select(type == "string" and length > 0)' "${dashboard_file}")
  list_response=$(curl -fsS \
    -H "${authorization_header}" \
    -H 'Accept: application/json' \
    --get \
    --data-urlencode "title=${title}" \
    "${api_base}/dashboards")

  if jq -e --arg title "${title}" 'any(.dashboards[]?; .title == $title)' \
    <<<"${list_response}" >/dev/null; then
    echo "Dashboard already exists; preserving it: ${title}"
    ((preserved += 1))
    continue
  fi

  curl -fsS \
    -H "${authorization_header}" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    --data-binary "@${dashboard_file}" \
    "${api_base}/dashboards?folder=default" >/dev/null
  echo "Created dashboard: ${title}"
  ((created += 1))
done

unset authorization_header ZO_ROOT_USER_PASSWORD
echo "Dashboard provisioning complete: ${created} created, ${preserved} preserved."
