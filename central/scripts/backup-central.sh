#!/usr/bin/env bash
set -Eeuo pipefail

readonly volume_name="opspika-openobserve-data"
readonly backup_image="busybox:1.37.0"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
central_dir=$(cd -- "${script_dir}/.." && pwd)
env_file="${central_dir}/.env"
output_dir="${central_dir}/backups"

usage() {
  echo "Usage: sudo $0 [--output-dir ABSOLUTE_PATH]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || { echo "--output-dir requires a value." >&2; exit 2; }
      output_dir=$2
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

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this backup as root with sudo." >&2
  exit 1
fi
if [[ ! -f ${env_file} ]]; then
  echo "Missing ${env_file}; central OpenObserve is not configured." >&2
  exit 1
fi
if [[ ${output_dir} != /* ]]; then
  echo "--output-dir must be an absolute path." >&2
  exit 2
fi

install -d -m 0700 "${output_dir}"
docker volume inspect "${volume_name}" >/dev/null
docker pull "${backup_image}" >/dev/null
compose=(docker compose --env-file "${env_file}" -f "${central_dir}/compose.yaml")
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
archive_name="openobserve-${timestamp}.tar.gz"

echo "Stopping OpenObserve briefly to create a consistent backup."
"${compose[@]}" stop openobserve
restart_required=true
cleanup() {
  if [[ ${restart_required:-false} == true ]]; then
    "${compose[@]}" start openobserve >/dev/null || true
  fi
}
trap cleanup EXIT

docker run --rm \
  -v "${volume_name}:/source:ro" \
  -v "${output_dir}:/backup" \
  "${backup_image}" \
  tar -C /source -czf "/backup/${archive_name}" .

sha256sum "${output_dir}/${archive_name}" >"${output_dir}/${archive_name}.sha256"
"${compose[@]}" start openobserve
restart_required=false
trap - EXIT

echo "Backup created: ${output_dir}/${archive_name}"
echo "Checksum: ${output_dir}/${archive_name}.sha256"
