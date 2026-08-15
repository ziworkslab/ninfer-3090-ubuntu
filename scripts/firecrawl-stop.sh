#!/usr/bin/env bash
#
# firecrawl-stop.sh — stop the Firecrawl services. Pass --down to remove the
# containers as well.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
firecrawl_dir=${FIRECRAWL_DIR:-${root}/firecrawl}

[[ -f ${firecrawl_dir}/docker-compose.yaml ]] || { echo "nothing to stop"; exit 0; }
cd "${firecrawl_dir}"
if [[ ${1:-} == --down ]]; then
  docker compose down
else
  docker compose stop
fi
