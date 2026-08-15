#!/usr/bin/env bash
# Qwen3.8-27B, one interactive user, 64K context, MTP3 + ReplaySSM.
set -euo pipefail
source "$(dirname "$0")/common.sh"
ninfer_prepare qwen3_8_27b.ninfer "${1:-}"

echo "Starting Qwen3.8-27B at http://127.0.0.1:8080/v1"
echo "Profile: one request, 64K context, MTP3, ReplaySSM (GPU ${CUDA_VISIBLE_DEVICES})"
exec "${server}" "${model}" \
  --host 127.0.0.1 --port 8080 \
  --max-context 65536 --kv-capacity 65536 \
  --max-concurrency 1 --max-pending-requests 16 \
  --prefill-chunk 1024 --kv-dtype int8 \
  --spec mtp --draft-tokens 3 --lm-head-draft
