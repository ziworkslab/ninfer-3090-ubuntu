#!/usr/bin/env bash
# Qwen3.8-27B for coding agents (OpenCode, Cline, Aider, ...): up to four
# concurrent requests of 32K context each out of a shared 96K-token KV pool,
# MTP3 + ReplaySSM.
#
# Agents interleave a foreground conversation with background tool calls, so
# concurrency helps — but on a 24 GB card the KV pool, not --max-concurrency, is
# the real limit: four simultaneous 24K-token prompts already fill this pool.
# Requests beyond it queue instead of failing, so the admission wait is raised
# from its 30 s default to 10 minutes.
set -euo pipefail
source "$(dirname "$0")/common.sh"
ninfer_prepare qwen3_8_27b.ninfer "${1:-}"

echo "Starting Qwen3.8-27B at ${url}"
echo "Profile: up to 4 requests, 32K context each, 96K shared KV, MTP3, ReplaySSM (GPU ${CUDA_VISIBLE_DEVICES})"
exec "${server}" "${model}" \
  "${endpoint[@]}" \
  --max-context 32768 --kv-capacity 98304 \
  --max-concurrency 4 --max-pending-requests 32 --pending-timeout-ms 600000 \
  --prefill-chunk 1024 --kv-dtype int8 \
  --spec mtp --draft-tokens 3 --lm-head-draft
