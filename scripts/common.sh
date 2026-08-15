# Shared helper for the Linux launcher scripts. Sourced, not executed.
#
# Resolves ninfer-serve and the model artifact, and pins the run to a single
# RTX 3090 (this repository's profiles assume one 24 GB device). Override with
# NINFER_SERVE, NINFER_MODEL_DIR, or CUDA_VISIBLE_DEVICES.

ninfer_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

ninfer_resolve_server() {
  if [[ -n ${NINFER_SERVE:-} ]]; then
    printf '%s' "${NINFER_SERVE}"
    return
  fi
  local candidate
  for candidate in \
    "${ninfer_root}/build/apps/ninfer-serve" \
    "${ninfer_root}/ninfer-serve" \
    "$(command -v ninfer-serve 2>/dev/null || true)"; do
    if [[ -n ${candidate} && -x ${candidate} ]]; then
      printf '%s' "${candidate}"
      return
    fi
  done
  return 1
}

ninfer_prepare() {
  local default_model=$1
  model=${2:-${NINFER_MODEL_DIR:-${ninfer_root}/models}/${default_model}}

  if ! server=$(ninfer_resolve_server); then
    echo "Missing ninfer-serve." >&2
    echo "Build it first:" >&2
    echo "  cmake -S ${ninfer_root} -B ${ninfer_root}/build -G Ninja -DCMAKE_BUILD_TYPE=Release" >&2
    echo "  cmake --build ${ninfer_root}/build --parallel" >&2
    echo "Or point NINFER_SERVE at an existing binary." >&2
    exit 1
  fi
  if [[ ! -f ${model} ]]; then
    echo "Missing model: ${model}" >&2
    echo "Run the matching scripts/download-*.sh first, or pass the artifact path" >&2
    echo "as the first argument to this launcher." >&2
    exit 1
  fi

  export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}
}
