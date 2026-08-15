# NInfer-3090 on Ubuntu

This fork builds and runs the `sm_86` NInfer runtime natively on Linux. It was brought up and
tested on Ubuntu 26.04 (glibc 2.43, GCC 15.2, CUDA 13.1, driver 595.84) with a GeForce RTX 3090.

## Requirements

- an NVIDIA GeForce RTX 3090 (or another `sm_86` card) and a driver new enough for the installed
  CUDA toolkit;
- CUDA Toolkit 12.8 or newer — the bring-up used 13.1 from `/usr/local/cuda`;
- GCC with C++20 support, CMake 3.28+, Ninja;
- FFmpeg (libavformat/libavcodec/libavutil/libswscale) and libcurl development packages;
- a supported `.ninfer` model artifact.

## One-time host setup

```bash
sudo ./scripts/setup-ubuntu.sh
```

The script installs the build and media dependencies and, when needed, patches the CUDA toolkit
headers for glibc (see below).

### The glibc rsqrt patch

glibc 2.41 added `rsqrt`/`rsqrtf` to `<math.h>` with `noexcept(true)`. CUDA's
`crt/math_functions.h` declares the same names without an exception specification, so on Ubuntu
25.10 and newer *every* `nvcc` translation unit fails with

```
error: exception specification is incompatible with that of previous function "rsqrt"
```

nvcc's device front end resolves that header through the toolkit's own include root, so it cannot
be shadowed with `-I` or `--pre-include`, and dropping `_GNU_SOURCE` (the other published
workaround) breaks libstdc++'s `pthread_*_clocklock` usage. `scripts/patch-cuda-glibc.sh` edits the
toolkit copy in place, keeps the original as `math_functions.h.ninfer-orig`, and does nothing on
systems whose glibc does not declare `rsqrt`. Restore the toolkit at any time with:

```bash
sudo cp /usr/local/cuda/targets/x86_64-linux/include/crt/math_functions.h.ninfer-orig \
        /usr/local/cuda/targets/x86_64-linux/include/crt/math_functions.h
```

## Build

```bash
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc
cmake --build build --parallel
```

`CMAKE_CUDA_COMPILER` matters when Ubuntu's `nvidia-cuda-toolkit` package is also installed: its
`/usr/bin/nvcc` is found first on `PATH` and its CUDA 12.4 default architecture (`sm_52`) is no
longer accepted by `ptxas`, so CMake's compiler detection fails. Pointing at
`/usr/local/cuda/bin/nvcc` avoids it. The architecture is fixed at `sm_86`.

The binaries land in `build/apps/ninfer` and `build/apps/ninfer-serve`.

### Tests

```bash
cmake -S . -B build-test -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DBUILD_TESTING=ON
cmake --build build-test --parallel
CUDA_VISIBLE_DEVICES=0 ctest --test-dir build-test -j4
```

All 83 tests pass on an RTX 3090. Six are skipped: five need a downloaded `.ninfer` artifact, and
`ninfer_linear_nvfp4_a4_test` needs the Blackwell-only NVFP4 W4A4 route.

## Run

```bash
./scripts/download-qwen38.sh          # 16.96 GiB, resumable
./scripts/run-qwen38-c1.sh            # one user, 64K context, MTP3
./scripts/run-qwen38-c8.sh            # eight users, 8K context, MTP3
./scripts/run-qwen38-vision.sh        # images, one user, 32K context
./scripts/run-qwen36-35b-vision.sh    # Qwen3.6-35B-A3B images, MTP off
```

The launchers are the Linux equivalents of the release `.bat` files and use the same tested RTX
3090 profiles. They find `ninfer-serve` in `build/apps`, beside the script, or on `PATH`
(`NINFER_SERVE` overrides), and read the artifact from `./models` (`NINFER_MODEL_DIR`, or pass a
path as the first argument). The OpenAI-compatible API is then at `http://127.0.0.1:8080/v1`.

On a multi-GPU host the launchers pin `CUDA_VISIBLE_DEVICES=0` unless it is already set; the
binaries also accept `--device N`. Prefer a card that is not driving a display — the 24 GB profiles
leave little headroom.

## Linux-specific runtime changes

The cooperative split-K schedules of the BF16 GDN control projection encode a device-wide CTA
budget. That budget was written for a 170-SM sm_120a card; an 82-SM RTX 3090 cannot co-schedule
those grids and the launch fails with `cudaErrorCooperativeLaunchTooLarge` (for the 27B geometry
this starts at roughly 768 tokens per gating call). The planner now queries the launched kernel's
occupancy and the device's SM count, and steps down the split-K ladder when the routed grid does
not fit. On an sm_120a card the queried limits reproduce the previous hard-coded values, so its
routing is unchanged.
