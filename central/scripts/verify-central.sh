#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
central_dir=$(cd -- "${script_dir}/.." && pwd)
env_file="${central_dir}/.env"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this verifier as root with sudo." >&2
  exit 1
fi
if [[ ! -f ${env_file} ]]; then
  echo "Missing ${env_file}; run install-central.sh first." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${env_file}"
compose=(docker compose --env-file "${env_file}" -f "${central_dir}/compose.yaml")
health_host=${OPENOBSERVE_BIND_ADDRESS}
if [[ ${health_host} == "0.0.0.0" ]]; then
  health_host="127.0.0.1"
fi

"${compose[@]}" ps
curl -fsS "http://${health_host}:${OPENOBSERVE_HTTP_PORT}/healthz"
echo
docker volume inspect opspika-openobserve-data >/dev/null
echo "OpenObserve container, HTTP health endpoint, and persistent volume are available."
