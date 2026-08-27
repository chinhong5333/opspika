#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pm2_binary=$(command -v pm2 || true)
node_binary=$(command -v node || true)
curl_binary=$(command -v curl || true)

[[ -x ${pm2_binary} ]] || { echo "Install a pinned PM2 version before this test." >&2; exit 1; }
[[ -x ${node_binary} ]] || { echo "Node.js is required." >&2; exit 1; }
[[ -x ${curl_binary} ]] || { echo "curl is required." >&2; exit 1; }

work_dir=$(mktemp -d)
export PM2_HOME="${work_dir}/.pm2"
export PM2_EXPORTER_HOST="127.0.0.1"
export PM2_EXPORTER_PORT="19988"
export PM2_EXPORTER_INTERVAL_MS="1000"
export PM2_EXPORTER_COMMAND_TIMEOUT_MS="5000"
export PM2_EXPORTER_PROCESS_NAME="opspika-process-exporter"
export PM2_BINARY="${pm2_binary}"
export OPSPIKA_INTEGRATION_SECRET="must-never-appear"

cleanup() {
  "${pm2_binary}" kill >/dev/null 2>&1 || true
  rm -rf -- "${work_dir}"
}
trap cleanup EXIT

"${pm2_binary}" start "${repo_dir}/agent/pm2-exporter/test/fixture-app.js" \
  --name opspika-fixture --no-autorestart >/dev/null
"${pm2_binary}" start "${repo_dir}/agent/pm2-exporter/server.js" \
  --name opspika-process-exporter --no-autorestart >/dev/null

metrics=""
for _ in $(seq 1 30); do
  if metrics=$("${curl_binary}" -fsS http://127.0.0.1:19988/metrics 2>/dev/null) \
    && grep -q '^pm2_exporter_collect_success 1$' <<<"${metrics}"; then
    break
  fi
  sleep 1
done

grep -q 'pm2_process_up{app="opspika-fixture",instance="0"} 1' <<<"${metrics}"
grep -q 'pm2_process_memory_bytes{app="opspika-fixture",instance="0"}' <<<"${metrics}"
if grep -Fq 'must-never-appear' <<<"${metrics}"; then
  echo "The exporter leaked a PM2 environment secret." >&2
  exit 1
fi
if grep -Fq 'opspika-process-exporter' <<<"${metrics}"; then
  echo "The exporter included itself in process metrics." >&2
  exit 1
fi

"${curl_binary}" -fsS http://127.0.0.1:19988/healthz >/dev/null
echo "PM2 integration test passed with $("${pm2_binary}" --version)."
