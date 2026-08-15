#!/usr/bin/env bash
# Qwen3.8-27B, one interactive user, 64K context, MTP3 + ReplaySSM.
set -euo pipefail
source "$(dirname "$0")/common.sh"
ninfer_prepare qwen3_8_27b.ninfer "${1:-}"

echo "Starting Qwen3.8-27B at ${url}"
echo "Profile: one request, 64K context, MTP3, ReplaySSM (GPU ${CUDA_VISIBLE_DEVICES})"
exec "${server}" "${model}" \
  "${endpoint[@]}" \
  --max-context 65536 --kv-capacity 65536 \
  --max-concurrency 1 --max-pending-requests 16 \
  --prefill-chunk 1024 --kv-dtype int8 \
  --spec mtp --draft-tokens 3 --lm-head-draft
