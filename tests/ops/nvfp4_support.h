#pragma once

// NVFP4 W4A4 execution is a Blackwell (sm_120a) route: this build links stubs
// that reject it on sm_86. Suites that also cover portable routes skip only
// their A4 cases; suites that are entirely A4 exit with the CTest skip code.

#include <cuda_runtime.h>

namespace ninfer::test {

inline bool nvfp4_a4_available() {
    int device = 0;
    if (cudaGetDevice(&device) != cudaSuccess) { return false; }
    int major = 0;
    if (cudaDeviceGetAttribute(&major, cudaDevAttrComputeCapabilityMajor, device) != cudaSuccess) {
        return false;
    }
    return major >= 12;
}

} // namespace ninfer::test
