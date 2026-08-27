#!/usr/bin/env bash
set -Eeuo pipefail

readonly DEFAULT_IMAGE="public.ecr.aws/zinclabs/openobserve:v0.90.3"
readonly DEFAULT_BIND_ADDRESS="127.0.0.1"
readonly DEFAULT_HTTP_PORT="5080"
readonly DEFAULT_RETENTION_DAYS="180"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
central_dir=$(cd -- "${script_dir}/.." && pwd)
env_file="${central_dir}/.env"

root_email=""
root_password_file=""
image=${DEFAULT_IMAGE}
bind_address=${DEFAULT_BIND_ADDRESS}
http_port=${DEFAULT_HTTP_PORT}
retention_days=${DEFAULT_RETENTION_DAYS}
force_reconfigure=false

usage() {
  cat <<'EOF'
Usage:
  sudo ./central/scripts/install-central.sh --root-email EMAIL [options]

Required:
  --root-email EMAIL             OpenObserve root login email.

Options:
  --root-password-file PATH      File containing one password line. If omitted,
                                 a strong password is generated and printed once.
  --image IMAGE                  Pinned OpenObserve OSS image.
  --bind-address IPV4            Host address for port 5080 (default 127.0.0.1).
  --http-port PORT               Host HTTP port (default 5080).
  --retention-days DAYS          Global retention in days (default 180, minimum 3).
  --force-reconfigure            Replace an existing central/.env file.
  --help                         Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root-email)
      [[ $# -ge 2 ]] || { echo "--root-email requires a value." >&2; exit 2; }
      root_email=$2
      shift 2
      ;;
    --root-password-file)
      [[ $# -ge 2 ]] || { echo "--root-password-file requires a value." >&2; exit 2; }
      root_password_file=$2
      shift 2
      ;;
    --image)
      [[ $# -ge 2 ]] || { echo "--image requires a value." >&2; exit 2; }
      image=$2
      shift 2
      ;;
    --bind-address)
      [[ $# -ge 2 ]] || { echo "--bind-address requires a value." >&2; exit 2; }
      bind_address=$2
      shift 2
      ;;
    --http-port)
      [[ $# -ge 2 ]] || { echo "--http-port requires a value." >&2; exit 2; }
      http_port=$2
      shift 2
      ;;
    --retention-days)
      [[ $# -ge 2 ]] || { echo "--retention-days requires a value." >&2; exit 2; }
      retention_days=$2
      shift 2
      ;;
    --force-reconfigure)
      force_reconfigure=true
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
  echo "Run this installer as root with sudo." >&2
  exit 1
fi
if [[ ! ${root_email} =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  echo "--root-email must be a valid email address." >&2
  exit 2
fi
if [[ ! ${bind_address} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "--bind-address must be an IPv4 address such as 127.0.0.1." >&2
  exit 2
fi
if [[ ! ${http_port} =~ ^[0-9]+$ ]] || (( http_port < 1 || http_port > 65535 )); then
  echo "--http-port must be between 1 and 65535." >&2
  exit 2
fi
if [[ ! ${retention_days} =~ ^[0-9]+$ ]] || (( retention_days < 3 )); then
  echo "--retention-days must be an integer of at least 3." >&2
  exit 2
fi
if [[ ! ${image} =~ ^[A-Za-z0-9./:_@-]+$ ]] || [[ ${image} == *":latest" ]]; then
  echo "--image must be a pinned container image and must not use the latest tag." >&2
  exit 2
fi
if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "Docker Engine and Docker Compose are required. Run install-docker-ubuntu.sh first." >&2
  exit 1
fi

generated_password=false
if [[ -n ${root_password_file} ]]; then
  if [[ ! -f ${root_password_file} || ! -r ${root_password_file} ]]; then
    echo "Cannot read --root-password-file: ${root_password_file}" >&2
    exit 2
  fi
  mapfile -t password_lines <"${root_password_file}"
  if [[ ${#password_lines[@]} -ne 1 || -z ${password_lines[0]} ]]; then
    echo "The root password file must contain exactly one non-empty line." >&2
    exit 2
  fi
  root_password=${password_lines[0]}
else
  if ! command -v openssl >/dev/null 2>&1; then
    apt-get update
    apt-get install -y openssl
  fi
  root_password="Oo1!$(openssl rand -hex 24)"
  generated_password=true
fi

if [[ ${root_password} == *$'\n'* || ${root_password} == *$'\r'* ]]; then
  echo "The root password must be a single line." >&2
  exit 2
fi
if [[ ! ${root_password} =~ ^[A-Za-z0-9._!@%+=:/-]{12,128}$ ]]; then
  echo "The root password must be 12-128 characters and use shell-safe letters, digits, or ._!@%+=:/-." >&2
  exit 2
fi

if [[ -e ${env_file} && ${force_reconfigure} != true ]]; then
  echo "${env_file} already exists. Re-run without configuration options, or use --force-reconfigure explicitly." >&2
  exit 1
fi
if [[ -e ${env_file} && ${force_reconfigure} == true ]]; then
  env_backup="${env_file}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -a "${env_file}" "${env_backup}"
  echo "Backed up the previous central configuration to ${env_backup}."
fi

umask 077
cat >"${env_file}" <<EOF
OPENOBSERVE_IMAGE=${image}
OPENOBSERVE_BIND_ADDRESS=${bind_address}
OPENOBSERVE_HTTP_PORT=${http_port}
ZO_ROOT_USER_EMAIL=${root_email}
ZO_ROOT_USER_PASSWORD=${root_password}
ZO_COMPACT_DATA_RETENTION_DAYS=${retention_days}
OPENOBSERVE_LOG_LEVEL=info
EOF
chmod 0600 "${env_file}"

compose=(docker compose --env-file "${env_file}" -f "${central_dir}/compose.yaml")
"${compose[@]}" config >/dev/null
"${compose[@]}" pull
"${compose[@]}" up -d

health_host=${bind_address}
if [[ ${health_host} == "0.0.0.0" ]]; then
  health_host="127.0.0.1"
fi
health_url="http://${health_host}:${http_port}/healthz"
for _ in $(seq 1 60); do
  if curl -fsS "${health_url}" >/dev/null 2>&1; then
    echo "OpenObserve is healthy at ${health_url}."
    if [[ ${generated_password} == true ]]; then
      echo
      echo "OpenObserve root email: ${root_email}"
      echo "OpenObserve generated root password: ${root_password}"
      echo "Save this password in your password manager now."
    fi
    if [[ ${bind_address} == "127.0.0.1" ]]; then
      echo "The service is bound to localhost. Use an SSH tunnel or configure HTTPS before remote agents connect."
    else
      echo "The service is listening on ${bind_address}:${http_port}. Restrict it with a firewall and add HTTPS before production use."
    fi
    exit 0
  fi
  sleep 2
done

echo "OpenObserve did not become healthy within 120 seconds." >&2
"${compose[@]}" ps >&2 || true
"${compose[@]}" logs --tail 100 openobserve >&2 || true
exit 1
