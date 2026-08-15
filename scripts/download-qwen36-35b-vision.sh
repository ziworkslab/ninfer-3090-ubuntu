#!/usr/bin/env bash
# Download the RTX 3090-compatible (pinned container-v1) Qwen3.6-35B-A3B
# artifact into ./models. Resumes if interrupted.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
model_dir=${NINFER_MODEL_DIR:-${root}/models}
model=${model_dir}/qwen3_6_35b_a3b.ninfer
rev=c8b8c1c0df4c74df3c190c6aa3a7f24dc614721c
url=https://huggingface.co/neroued/Qwen3.6-35B-A3B-NInfer/resolve/${rev}/qwen3_6_35b_a3b.ninfer

mkdir -p "${model_dir}"
echo "Downloading Qwen3.6-35B-A3B (pinned 20.84 GiB v1 artifact) to ${model}"
curl -L -C - --fail --progress-bar --output "${model}" "${url}" \
  || { echo "Download failed. Run this script again to resume." >&2; exit 1; }

echo "Model ready: ${model}"
echo "Expected SHA-256: 9e8378398d2b789a77224b5110c7590adbbc6fd4accd139b918157b2b9da7163"
echo "Verify with: sha256sum ${model}"
