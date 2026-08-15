#!/usr/bin/env bash
# Make the CUDA toolkit headers compatible with glibc >= 2.41.
#
# glibc 2.41 added rsqrt/rsqrtf to <math.h> with noexcept(true). CUDA's
# crt/math_functions.h declares the same names without an exception
# specification, so every nvcc translation unit that reaches <math.h> fails with
#
#   error: exception specification is incompatible with that of previous
#          function "rsqrt"
#
# nvcc's device front end resolves that header through the toolkit's own include
# root, so it cannot be shadowed with -I or --pre-include; the toolkit copy has
# to be edited in place. The original is kept next to it as
# math_functions.h.ninfer-orig and the script is idempotent.
set -euo pipefail

cuda_root=${CUDA_HOME:-${CUDA_PATH:-/usr/local/cuda}}
header=${cuda_root}/targets/x86_64-linux/include/crt/math_functions.h
hpp=${cuda_root}/targets/x86_64-linux/include/crt/math_functions.hpp

if [[ ! -f ${header} ]]; then
  echo "error: ${header} not found; set CUDA_HOME to the toolkit root" >&2
  exit 1
fi

# Does this glibc actually declare rsqrt? Older systems need no patch.
if ! printf '#include <math.h>\n#if !__GLIBC_USE (IEC_60559_FUNCS_EXT_C23)\n#error no_conflict\n#endif\nint main(){}\n' \
  | cc -x c - -o /dev/null 2>/dev/null; then
  echo "glibc does not declare rsqrt/rsqrtf; no CUDA header patch needed"
  exit 0
fi

if grep -q 'rsqrt(double x) noexcept(true);' "${header}"; then
  echo "already patched: ${header}"
  exit 0
fi

for f in "${header}" "${hpp}"; do
  [[ -f ${f} ]] || continue
  [[ -f ${f}.ninfer-orig ]] || cp -p "${f}" "${f}.ninfer-orig"
done

sed -i \
  -e 's/\(double  *\)rsqrt(double x);/\1rsqrt(double x) noexcept(true);/' \
  -e 's/\(float  *\)rsqrtf(float x);/\1rsqrtf(float x) noexcept(true);/' \
  "${header}"

if [[ -f ${hpp} ]]; then
  sed -i \
    -e 's/^__func__(double rsqrt(const double a))$/__func__(double rsqrt(const double a) noexcept(true))/' \
    -e 's/^__func__(float rsqrtf(const float a))$/__func__(float rsqrtf(const float a) noexcept(true))/' \
    "${hpp}"
fi

grep -q 'rsqrt(double x) noexcept(true);' "${header}" \
  || { echo "error: patch did not apply to ${header}" >&2; exit 1; }

echo "patched ${header} (original saved as ${header}.ninfer-orig)"
