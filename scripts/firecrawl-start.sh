#!/usr/bin/env bash
#
# firecrawl-start.sh — start the self-hosted Firecrawl services the web-search
# proxy calls. Only the services the proxy needs are started.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
firecrawl_dir=${FIRECRAWL_DIR:-${root}/firecrawl}
port=${FIRECRAWL_PORT:-3002}

[[ -f ${firecrawl_dir}/docker-compose.yaml ]] || {
  echo "error: no Firecrawl at ${firecrawl_dir}; run scripts/setup-firecrawl.sh first" >&2
  exit 1; }

cd "${firecrawl_dir}"
echo "==> starting Firecrawl"
docker compose up -d api playwright-service redis rabbitmq nuq-postgres \
  2>&1 | grep -vE "^time=|variable is not set" || true

echo "==> waiting for the API on :${port}"
for _ in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${port}/" 2>/dev/null || true)
  if [[ ${code} =~ ^[1-5][0-9][0-9]$ ]]; then
    echo "OK: Firecrawl is serving http://127.0.0.1:${port} (HTTP ${code})"
    exit 0
  fi
  sleep 2
done
echo "error: :${port} did not answer. Logs: (cd ${firecrawl_dir} && docker compose logs api)" >&2
exit 1
