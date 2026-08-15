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

fail=0
if ! curl -s --max-time 5 "${UPSTREAM%/v1}/health" >/dev/null; then
  echo "error: no ninfer-serve at ${UPSTREAM}. Start a scripts/run-*.sh launcher first." >&2
  fail=1
fi
if ! curl -s --max-time 5 -o /dev/null "${FIRECRAWL_URL}/"; then
  echo "error: no Firecrawl at ${FIRECRAWL_URL}. Run scripts/firecrawl-start.sh first." >&2
  fail=1
fi
[[ ${fail} -eq 0 ]] || exit 1

advertised=${PROXY_HOST}
if [[ ${advertised} == 0.0.0.0 || ${advertised} == "::" ]]; then
  advertised=$(hostname -I 2>/dev/null | awk '{print $1}')
  advertised=${advertised:-127.0.0.1}
fi
echo "Web search enabled at http://${advertised}:${PROXY_PORT}/v1"
echo "API key: ${PROXY_API_KEY:-(none)}"
exec python3 "${root}/scripts/websearch-proxy.py"
