#!/usr/bin/env bash
# One-time host setup for building NInfer-3090 on Ubuntu.
#
#   sudo ./scripts/setup-ubuntu.sh
#
# 1. installs the build and media dependencies;
# 2. patches the CUDA toolkit's crt/math_functions.h when the installed glibc
#    declares rsqrt/rsqrtf (glibc >= 2.41), which otherwise breaks every nvcc
#    compilation with "exception specification is incompatible".
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "error: run as root (sudo $0)" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install --yes --no-install-recommends \
  build-essential \
  cmake \
  ninja-build \
  pkg-config \
  libavcodec-dev \
  libavformat-dev \
  libavutil-dev \
  libswscale-dev \
  libcurl4-openssl-dev

"$(dirname "$0")/patch-cuda-glibc.sh"

echo
echo "Setup complete. Build with:"
echo "  cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release"
echo "  cmake --build build --parallel"
