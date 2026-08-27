#!/usr/bin/env bash
set -Eeuo pipefail

on_error() {
  local exit_code=$?
  echo "Docker installation failed at line ${BASH_LINENO[0]} (exit ${exit_code})." >&2
  exit "${exit_code}"
}
trap on_error ERR

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this installer as root: sudo $0" >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify this operating system; /etc/os-release is missing." >&2
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
if [[ ${ID:-} != "ubuntu" ]]; then
  echo "This installer supports Ubuntu only; detected ID=${ID:-unknown}." >&2
  exit 1
fi
case "${VERSION_ID:-}" in
  22.04|24.04) ;;
  *)
    echo "Supported production releases are Ubuntu 22.04 and 24.04 LTS; detected VERSION_ID=${VERSION_ID:-unknown}." >&2
    exit 1
    ;;
esac

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  if ! command -v jq >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y jq
  fi
  echo "Docker Engine and Docker Compose are already installed."
  docker --version
  docker compose version
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg jq

install -m 0755 -d /etc/apt/keyrings
docker_key=$(mktemp)
trap 'rm -f -- "${docker_key}"' EXIT
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o "${docker_key}"
docker_key_fingerprint=$(gpg --show-keys --with-colons "${docker_key}" \
  | awk -F: '$1 == "fpr" { print $10; exit }')
if [[ ${docker_key_fingerprint} != "9DC858229FC7DD38854AE2D88D81803C0EBFCD88" ]]; then
  echo "Docker repository signing-key fingerprint verification failed." >&2
  exit 1
fi
install -m 0644 "${docker_key}" /etc/apt/keyrings/docker.asc
rm -f -- "${docker_key}"
trap - EXIT

ubuntu_codename=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
if [[ -z ${ubuntu_codename} ]]; then
  echo "Ubuntu codename is unavailable in /etc/os-release." >&2
  exit 1
fi

architecture=$(dpkg --print-architecture)
cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${ubuntu_codename}
Components: stable
Architectures: ${architecture}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable --now docker
docker --version
docker compose version
docker run --rm hello-world >/dev/null

echo "Docker Engine and Docker Compose are ready."
