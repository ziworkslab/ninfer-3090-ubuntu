#!/usr/bin/env bash
# Download the Qwen3.8-27B NInfer artifact into ./models. Resumes if interrupted.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
model_dir=${NINFER_MODEL_DIR:-${root}/models}
model=${model_dir}/qwen3_8_27b.ninfer
url=https://huggingface.co/neroued/Qwen3.8-27B-NInfer/resolve/main/qwen3_8_27b.ninfer

mkdir -p "${model_dir}"
echo "Downloading Qwen3.8-27B NInfer model (16.96 GiB) to ${model}"
curl -L -C - --fail --progress-bar --output "${model}" "${url}" \
  || { echo "Download failed. Run this script again to resume." >&2; exit 1; }

echo "Model ready: ${model}"
echo "Expected SHA-256: eec39564993d6e9c7d5e383382a760f093465c9d163ec9a1bd6b80199514bf3e"
echo "Verify with: sha256sum ${model}"
