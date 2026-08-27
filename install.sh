#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<'EOF'
OpsPika quick installer

Usage:
  sudo ./install.sh central   Install Docker and central OpenObserve.
  sudo ./install.sh agent     Install host-only or PM2 monitoring agent.
  sudo ./install.sh help      Show this help.

The installer is interactive so secrets do not need to appear in shell history.
EOF
}

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "Run this command with sudo." >&2
    exit 1
  fi
}

prompt_required() {
  local prompt=$1
  local value=""
  while [[ -z ${value} ]]; do
    read -r -p "${prompt}: " value
  done
  printf '%s' "${value}"
}

prompt_default() {
  local prompt=$1
  local default_value=$2
  local value=""
  read -r -p "${prompt} [${default_value}]: " value
  printf '%s' "${value:-${default_value}}"
}

detect_pm2_users() {
  local process_dir
  local command_line
  local process_owner
  for process_dir in /proc/[0-9]*; do
    [[ -r ${process_dir}/cmdline ]] || continue
    command_line=$(tr '\0' ' ' <"${process_dir}/cmdline" 2>/dev/null || true)
    if [[ ${command_line} == *PM2* && ${command_line} == *"God Daemon"* ]]; then
      process_owner=$(stat -c '%U' "${process_dir}" 2>/dev/null || true)
      [[ -n ${process_owner} ]] && printf '%s\n' "${process_owner}"
    fi
  done | sort -u
}

install_central() {
  require_root
  echo "Central OpenObserve installation"
  echo

  if [[ -f ${repo_dir}/central/.env ]]; then
    echo "Existing central configuration found; reusing it."
    "${repo_dir}/central/scripts/install-docker-ubuntu.sh"
    docker compose \
      --env-file "${repo_dir}/central/.env" \
      -f "${repo_dir}/central/compose.yaml" \
      pull
    docker compose \
      --env-file "${repo_dir}/central/.env" \
      -f "${repo_dir}/central/compose.yaml" \
      up -d
    "${repo_dir}/central/scripts/verify-central.sh"
    echo "Central installation is already configured and healthy."
    return
  fi

  local root_email
  local http_port
  root_email=$(prompt_required "OpenObserve root email")
  http_port=$(prompt_default "OpenObserve port" "5080")

  "${repo_dir}/central/scripts/install-docker-ubuntu.sh"
  "${repo_dir}/central/scripts/install-central.sh" \
    --root-email "${root_email}" \
    --bind-address "127.0.0.1" \
    --http-port "${http_port}" \
    --retention-days "180"
  "${repo_dir}/central/scripts/verify-central.sh"

  echo
  echo "Central installation finished."
  echo "OpenObserve is bound to http://127.0.0.1:${http_port} with 180-day retention."
  echo "Configure your reverse proxy to http://127.0.0.1:${http_port}."
  echo "Then log in, open Data Sources > Linux, and copy the base64 authorization key."
}

install_agent() {
  require_root
  echo "Ubuntu monitoring-agent installation"
  echo

  local mode="host"
  local server_name
  local environment_name="production"
  local base_url
  local organization="default"
  local authorization_key
  local pm2_user=""
  local key_file
  local allow_insecure=false
  local -a detected_pm2_users=()

  mapfile -t detected_pm2_users < <(detect_pm2_users)
  if [[ ${#detected_pm2_users[@]} -eq 1 ]]; then
    mode="pm2"
    pm2_user=${detected_pm2_users[0]}
  elif [[ ${#detected_pm2_users[@]} -gt 1 ]]; then
    echo "Multiple active PM2 daemon owners were detected:"
    printf '  - %s\n' "${detected_pm2_users[@]}"
    pm2_user=$(prompt_required "Unix user to monitor")
    if [[ ! " ${detected_pm2_users[*]} " == *" ${pm2_user} "* ]]; then
      echo "Selected user is not one of the detected PM2 daemon owners." >&2
      exit 2
    fi
    mode="pm2"
  fi

  server_name=$(hostname -s)
  echo "Detected server name: ${server_name}"
  echo "Detected agent mode: ${mode}"
  if [[ ${mode} == "pm2" ]]; then
    echo "Detected PM2 Unix user: ${pm2_user}"
  else
    echo "No active PM2 daemon detected; installing host monitoring only."
  fi
  echo "Environment label: ${environment_name}"
  echo "OpenObserve organization: ${organization}"
  echo

  base_url=$(prompt_required "OpenObserve base URL, for example https://monitor.example.com")
  base_url=${base_url%/}

  read -r -s -p "Paste the base64 authorization key (without the word Basic): " authorization_key
  echo
  if [[ -z ${authorization_key} ]]; then
    echo "Authorization key cannot be empty." >&2
    exit 2
  fi

  if [[ ${base_url} == http://* ]] \
    && [[ ${base_url} != http://127.0.0.1:* ]] \
    && [[ ${base_url} != http://localhost:* ]]; then
    local insecure_confirmation
    read -r -p "This is non-loopback HTTP. Type ALLOW for a private-network proof of concept: " insecure_confirmation
    if [[ ${insecure_confirmation} != "ALLOW" ]]; then
      echo "Cancelled. Configure HTTPS or explicitly confirm private HTTP." >&2
      exit 2
    fi
    allow_insecure=true
  fi

  key_file=$(mktemp)
  chmod 0600 "${key_file}"
  trap 'rm -f -- "${key_file:-}"' EXIT
  printf '%s\n' "${authorization_key}" >"${key_file}"
  unset authorization_key

  local installer_args=(
    --mode "${mode}"
    --server-name "${server_name}"
    --environment "${environment_name}"
    --openobserve-url "${base_url}/api/${organization}"
    --authorization-key-file "${key_file}"
  )
  if [[ ${mode} == "pm2" ]]; then
    installer_args+=(--pm2-user "${pm2_user}")
  fi
  if [[ ${allow_insecure} == true ]]; then
    installer_args+=(--allow-insecure-http)
  fi

  "${repo_dir}/agent/install-monitoring-agent.sh" "${installer_args[@]}"
  "${repo_dir}/agent/verify-monitoring-agent.sh"

  rm -f -- "${key_file}"
  key_file=""
  trap - EXIT

  echo
  echo "Agent installation finished. Check the server in OpenObserve."
}

case "${1:-help}" in
  central)
    [[ $# -eq 1 ]] || { usage >&2; exit 2; }
    install_central
    ;;
  agent)
    [[ $# -eq 1 ]] || { usage >&2; exit 2; }
    install_agent
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    echo "Unknown command: ${1}" >&2
    usage >&2
    exit 2
    ;;
esac
