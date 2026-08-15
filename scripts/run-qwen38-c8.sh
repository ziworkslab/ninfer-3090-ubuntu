#!/usr/bin/env bash
# Qwen3.8-27B, up to eight concurrent requests, 8K context, MTP3 + ReplaySSM.
set -euo pipefail
source "$(dirname "$0")/common.sh"
ninfer_prepare qwen3_8_27b.ninfer "${1:-}"

echo "Starting Qwen3.8-27B at ${url}"
echo "API key: ${api_key:-(none)}"
echo "Profile: up to eight requests, 8K context, MTP3, ReplaySSM (GPU ${CUDA_VISIBLE_DEVICES})"
exec "${server}" "${model}" \
  "${endpoint[@]}" \
  --max-context 8192 --kv-capacity 16384 \
  --max-concurrency 8 --max-pending-requests 32 \
  --prefill-chunk 1024 --kv-dtype int8 \
  --spec mtp --draft-tokens 3 --lm-head-draft
