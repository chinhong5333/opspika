#!/usr/bin/env bash
set -Eeuo pipefail

readonly default_volume_name="opspika-openobserve-data"
readonly restore_image="busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
central_dir=$(cd -- "${script_dir}/.." && pwd)
env_file="${central_dir}/.env"
backup_file=""
confirmed=false
allow_missing_checksum=false

usage() {
  cat <<'EOF'
Usage:
  sudo ./central/scripts/restore-central.sh \
    --backup /absolute/path/openobserve-TIMESTAMP.tar.gz \
    --confirm-restoration

This replaces all current OpenObserve volume data. A pre-restore backup is
created automatically before replacement. A matching .sha256 file is required
unless --allow-missing-checksum is supplied explicitly.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup)
      [[ $# -ge 2 ]] || { echo "--backup requires a value." >&2; exit 2; }
      backup_file=$2
      shift 2
      ;;
    --confirm-restoration)
      confirmed=true
      shift
      ;;
    --allow-missing-checksum)
      allow_missing_checksum=true
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
  echo "Run this restore as root with sudo." >&2
  exit 1
fi
if [[ ${confirmed} != true ]]; then
  echo "Restoration requires the explicit --confirm-restoration flag." >&2
  exit 2
fi
if [[ ${backup_file} != /* || ! -f ${backup_file} ]]; then
  echo "--backup must be an existing absolute .tar.gz path." >&2
  exit 2
fi
if [[ ${backup_file} != *.tar.gz ]]; then
  echo "--backup must end in .tar.gz." >&2
  exit 2
fi
backup_file=$(realpath -e -- "${backup_file}")
if [[ ! -f ${env_file} ]]; then
  echo "Missing ${env_file}; central OpenObserve is not configured." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${env_file}"
volume_name=${OPENOBSERVE_VOLUME_NAME:-${default_volume_name}}

backup_dir=$(dirname -- "${backup_file}")
backup_name=$(basename -- "${backup_file}")
case "${backup_dir}" in
  /|/bin|/boot|/dev|/etc|/home|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var)
    echo "Refusing to mount a broad system directory as the backup source: ${backup_dir}" >&2
    exit 2
    ;;
esac
if [[ -f ${backup_file}.sha256 ]]; then
  (cd "${backup_dir}" && sha256sum --check "${backup_name}.sha256")
elif [[ ${allow_missing_checksum} == true ]]; then
  echo "WARNING: Restoring without a checksum because --allow-missing-checksum was supplied." >&2
else
  echo "Missing required checksum file: ${backup_file}.sha256" >&2
  exit 1
fi

while IFS= read -r archive_path; do
  case "${archive_path}" in
    /*|../*|*/../*|*/..)
      echo "Unsafe archive path detected: ${archive_path}" >&2
      exit 1
      ;;
  esac
done < <(tar -tzf "${backup_file}")
archive_listing=$(tar -tvzf "${backup_file}")
if grep -Eq '^[^d-]' <<<"${archive_listing}"; then
  echo "Archive contains a link, device, or another unsupported entry type." >&2
  exit 1
fi

echo "Creating a pre-restore backup of current data."
"${script_dir}/backup-central.sh" --output-dir "${central_dir}/backups"

compose=(docker compose --env-file "${env_file}" -f "${central_dir}/compose.yaml")
"${compose[@]}" stop openobserve
restart_required=true
# shellcheck disable=SC2317 # Invoked indirectly by the EXIT trap.
cleanup() {
  if [[ ${restart_required:-false} == true ]]; then
    "${compose[@]}" start openobserve >/dev/null || true
  fi
}
trap cleanup EXIT

docker run --rm \
  -e "BACKUP_NAME=${backup_name}" \
  -v "${volume_name}:/target" \
  -v "${backup_dir}:/backup:ro" \
  "${restore_image}" \
  sh -ceu 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; tar -xzf "/backup/${BACKUP_NAME}" -C /target'

"${compose[@]}" start openobserve
restart_required=false
trap - EXIT

health_host=${OPENOBSERVE_BIND_ADDRESS}
if [[ ${health_host} == "0.0.0.0" ]]; then
  health_host="127.0.0.1"
fi
for _ in $(seq 1 60); do
  if curl -fsS "http://${health_host}:${OPENOBSERVE_HTTP_PORT}/healthz" >/dev/null 2>&1; then
    echo "Restore completed and OpenObserve is healthy."
    exit 0
  fi
  sleep 2
done

echo "Data was restored, but OpenObserve did not become healthy within 120 seconds." >&2
"${compose[@]}" logs --tail 100 openobserve >&2 || true
exit 1
