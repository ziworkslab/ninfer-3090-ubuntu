#!/usr/bin/env bash
# Qwen3.6-35B-A3B image understanding, one request, 32K context, MTP disabled.
set -euo pipefail
source "$(dirname "$0")/common.sh"
ninfer_prepare qwen3_6_35b_a3b.ninfer "${1:-}"

echo "Starting Qwen3.6-35B-A3B Vision at ${url}"
echo "Safe RTX 3090 profile: one request, 32K context, vision enabled, MTP disabled (GPU ${CUDA_VISIBLE_DEVICES})"
exec "${server}" "${model}" \
  "${endpoint[@]}" \
  --max-context 32768 --kv-capacity 32768 \
  --max-concurrency 1 --max-pending-requests 8 \
  --prefill-chunk 512 --kv-dtype int8 \
  --default-max-tokens 512 --vision --no-thinking --temperature 0.2
