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
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
```

The build defaults to `/usr/local/cuda/bin/nvcc` on Linux. That matters when Ubuntu's
`nvidia-cuda-toolkit` package is also installed: its `/usr/bin/nvcc` comes first on `PATH`, and its
CUDA 12.4 default architecture (`sm_52`) is no longer accepted by `ptxas`, so CMake's compiler
detection fails with a confusing `ptxas fatal` message. Set `-DCMAKE_CUDA_COMPILER=...` or `CUDACXX`
to use a toolkit installed elsewhere. The architecture is fixed at `sm_86`.

The binaries land in `build/apps/ninfer` and `build/apps/ninfer-serve`.

### Tests

```bash
cmake -S . -B build-test -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
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
./scripts/run-qwen38-agent.sh         # coding agents: 4 x 32K context, 96K KV pool
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

## Serving other machines on the LAN

The server binds `127.0.0.1` by default and has no access control beyond `--api-key`. To reach it
from another PC:

```bash
NINFER_HOST=0.0.0.0 NINFER_API_KEY=$(openssl rand -hex 16) ./scripts/run-qwen38-agent.sh
sudo ufw allow from 192.168.0.0/16 to any port 8080 proto tcp   # if ufw is active
```

`NINFER_HOST`, `NINFER_PORT`, and `NINFER_API_KEY` are honoured by every launcher; the key is
required as an OpenAI `Authorization: Bearer` or Anthropic `x-api-key` header, and a non-loopback
host without a key prints a warning. `GET /health` stays unauthenticated. Add `--cors` only if a
browser page calls the API directly. Do not expose the port to the internet — there is no rate
limiting, and a single long request occupies the GPU.

## Coding agents (OpenCode, Cline, Aider, ...)

Point the agent at `http://<host>:8080/v1` as an OpenAI-compatible provider, with the model id
`qwen3.8-27b` and the API key if one is set.

`scripts/run-qwen38-agent.sh` is the profile for this: four concurrent requests of up to 32K
context each from a 96K-token shared pool, with the admission wait raised to 10 minutes so bursts
queue instead of returning `503`. It peaked at 22.2 GiB in testing.

Three measured properties decide the right settings:

- **The KV pool, not `--max-concurrency`, is the real concurrency limit.** Four simultaneous
  25K-token prompts need ~100K pooled tokens. With the C1 profile's 64K pool only two of four such
  requests were admitted, and with the 30 s default `--pending-timeout-ms` the other two returned
  `503 Service Unavailable` while waiting.
- **Prefills do not overlap.** Prefill runs at ~850 tok/s and one request at a time, so four cold
  25K-token prompts finished at 46 s, 75 s, 105 s and 123 s. Concurrency multiplies decode
  throughput, not prefill throughput.
- **Continuing a conversation is nearly free.** A follow-up turn on a 25K-token history reused
  25,443 tokens and dropped TTFT from 28.9 s to 0.19 s. Prefix reuse restores the previous turn's
  KV, so it applies when the agent appends to the same conversation — not when two different
  requests merely share a long blob of text.

So a single agent session is best served by `run-qwen38-c1.sh` (64K context, one slot, everything
after the first turn is fast). Choose `run-qwen38-agent.sh` when several sessions, subagents, or
background tasks run at once and 32K per request is enough. Raise `--kv-capacity` past 98304 only
carefully: a 128K pool left just 854 MiB free on this card.

## Measured on this port

Qwen3.8-27B (`qwen3_8_27b.ninfer`, SHA-256 verified) on one RTX 3090, Ubuntu 26.04, CUDA 13.1,
greedy decoding, INT8 KV, CUDA Graphs, MTP3 with ReplaySSM:

| Profile | Prompt | Result | Peak VRAM |
|---|---|---|---:|
| `run-qwen38-c1.sh` (64K context) | 4,870 tokens | 931 tok/s prefill, 85.3 tok/s decode, 81.1% MTP acceptance, 5.2 s TTFT | 20,097 MiB |
| `run-qwen38-c8.sh` (8 concurrent) | 67 tokens each | 1,100 generated tokens in 8.8 s — 125 aggregate tok/s, decode batch 6.9 | 20,591 MiB |

These are single spot checks, not the published benchmark campaign; the C8 run used short
128-256 token replies, so its ramp-up weighs more heavily than in the 1,024-token release test.

## Linux-specific runtime changes

The cooperative split-K schedules of the BF16 GDN control projection encode a device-wide CTA
budget. That budget was written for a 170-SM sm_120a card; an 82-SM RTX 3090 cannot co-schedule
those grids and the launch fails with `cudaErrorCooperativeLaunchTooLarge` (for the 27B geometry
this starts at roughly 768 tokens per gating call). The planner now queries the launched kernel's
occupancy and the device's SM count, and steps down the split-K ladder when the routed grid does
not fit. On an sm_120a card the queried limits reproduce the previous hard-coded values, so its
routing is unchanged.
