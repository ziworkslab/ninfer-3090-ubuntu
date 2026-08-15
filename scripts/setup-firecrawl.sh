#!/usr/bin/env bash
#
# setup-firecrawl.sh — prepare the self-hosted Firecrawl that backs the
# web-search proxy.
#
#   1. clone Firecrawl into ./firecrawl (skipped if it is already there);
#   2. write firecrawl/.env from scripts/firecrawl.env with random secrets;
#   3. build the container images.
#
# Nothing here touches the GPU, so it can run while a model is served.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
firecrawl_dir=${FIRECRAWL_DIR:-${root}/firecrawl}
firecrawl_repo=${FIRECRAWL_REPO:-https://github.com/firecrawl/firecrawl.git}

command -v docker >/dev/null || { echo "error: docker is required" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || {
  echo "error: docker compose v2 is required" >&2; exit 1; }
docker ps >/dev/null 2>&1 || {
  echo "error: cannot talk to the docker daemon. Add yourself to the docker group" >&2
  echo "       (sudo usermod -aG docker \"\$USER\", then log in again)." >&2
  exit 1; }

if [[ ! -f ${firecrawl_dir}/docker-compose.yaml ]]; then
  echo "==> cloning Firecrawl into ${firecrawl_dir}"
  git clone --depth 1 "${firecrawl_repo}" "${firecrawl_dir}"
else
  echo "==> Firecrawl already present at ${firecrawl_dir}"
fi

gen() { openssl rand -hex 16 2>/dev/null || head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
if [[ ! -f ${firecrawl_dir}/.env ]]; then
  echo "==> writing ${firecrawl_dir}/.env with random secrets"
  sed -e "s/__POSTGRES_PASSWORD__/$(gen)/" -e "s/__BULL_AUTH_KEY__/$(gen)/" \
    "${root}/scripts/firecrawl.env" > "${firecrawl_dir}/.env"
else
  echo "==> ${firecrawl_dir}/.env already exists, keeping it"
fi

echo "==> building images (several minutes on a first run)"
(cd "${firecrawl_dir}" && docker compose build)

echo
echo "Firecrawl is ready. Start it with scripts/firecrawl-start.sh"
