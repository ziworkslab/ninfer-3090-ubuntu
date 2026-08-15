#!/usr/bin/env bash
#
# run-websearch-proxy.sh — start the OpenAI-compatible web-search proxy in front
# of a running ninfer-serve.
#
#   scripts/run-qwen38-c1.sh        # or any other launcher   :8080
#   scripts/firecrawl-start.sh                                :3002
#   scripts/run-websearch-proxy.sh                            :8899
#
# Clients then use http://<host>:8899/v1 instead of :8080/v1.
# Honours the same NINFER_HOST / NINFER_PORT / NINFER_API_KEY defaults as the
# model launchers, plus PROXY_PORT, FIRECRAWL_URL, and MODEL.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

export PROXY_HOST=${NINFER_HOST:-0.0.0.0}
export PROXY_PORT=${PROXY_PORT:-8899}
export PROXY_API_KEY=${NINFER_API_KEY-welcome}
export UPSTREAM=${UPSTREAM:-http://127.0.0.1:${NINFER_PORT:-8080}/v1}
export UPSTREAM_API_KEY=${UPSTREAM_API_KEY-${NINFER_API_KEY-welcome}}
export FIRECRAWL_URL=${FIRECRAWL_URL:-http://127.0.0.1:${FIRECRAWL_PORT:-3002}}
export MODEL=${MODEL:-qwen3.8-27b}

# Both dependencies take time to come up — Firecrawl's API needs about 15 s
# after its container starts, and a model load is slower still — so wait for
# them rather than failing a launcher that was started one command too early.
wait_seconds=${WAIT_SECONDS:-90}

wait_for() {
  local url=$1 name=$2 hint=$3 waited=0
  while ! curl -s --max-time 5 -o /dev/null "${url}"; do
    if (( waited >= wait_seconds )); then
      echo "error: no ${name} at ${url} after ${wait_seconds}s. ${hint}" >&2
      return 1
    fi
    [[ ${waited} -eq 0 ]] && echo "waiting for ${name} at ${url} ..."
    sleep 2
    waited=$((waited + 2))
  done
}

fail=0
wait_for "${UPSTREAM%/v1}/health" "ninfer-serve" \
  "Start a scripts/run-*.sh launcher first." || fail=1
wait_for "${FIRECRAWL_URL}/" "Firecrawl" \
  "Run scripts/firecrawl-start.sh, then check: docker compose -f firecrawl/docker-compose.yaml logs api" || fail=1
[[ ${fail} -eq 0 ]] || exit 1

advertised=${PROXY_HOST}
if [[ ${advertised} == 0.0.0.0 || ${advertised} == "::" ]]; then
  advertised=$(hostname -I 2>/dev/null | awk '{print $1}')
  advertised=${advertised:-127.0.0.1}
fi
echo "Web search enabled at http://${advertised}:${PROXY_PORT}/v1"
echo "API key: ${PROXY_API_KEY:-(none)}"
exec python3 "${root}/scripts/websearch-proxy.py"
