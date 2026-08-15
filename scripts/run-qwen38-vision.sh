#!/usr/bin/env bash
# Qwen3.8-27B image understanding, one request, 32K context, MTP3 + ReplaySSM.
set -euo pipefail
source "$(dirname "$0")/common.sh"
ninfer_prepare qwen3_8_27b.ninfer "${1:-}"

echo "Starting Qwen3.8-27B Vision at http://127.0.0.1:8080/v1"
echo "Tested RTX 3090 profile: one request, 32K context, ReplaySSM and MTP3 (GPU ${CUDA_VISIBLE_DEVICES})"
exec "${server}" "${model}" \
  --host 127.0.0.1 --port 8080 \
  --max-context 32768 --kv-capacity 32768 \
  --max-concurrency 1 --max-pending-requests 8 \
  --prefill-chunk 512 --kv-dtype int8 \
  --default-max-tokens 1024 --vision \
  --spec mtp --draft-tokens 3 --lm-head-draft
