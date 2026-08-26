#!/usr/bin/env bash
# Build das_fuzz with AFL++ instrumentation.
set -euo pipefail
cd "$(dirname "$0")"

AFL="${AFL_DIR:-$HOME/work/AFLplusplus}"

# das_fuzz only links libDaScript + libDasModuleUnitTest. Disable the optional
# GUI/media/io modules (their submodule sources aren't checked out on the host,
# e.g. dasGlfw/src/aot_dasGLFW.h) plus tests/examples/tutorial for a fast build.
cmake -B build_afl -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$AFL/afl-clang-fast" \
    -DCMAKE_CXX_COMPILER="$AFL/afl-clang-fast++" \
    -DDAS_GLFW_DISABLED=ON \
    -DDAS_AUDIO_DISABLED=ON \
    -DDAS_STBIMAGE_DISABLED=ON \
    -DDAS_STDDLG_DISABLED=ON \
    -DDAS_HV_DISABLED=ON \
    -DDAS_PUGIXML_DISABLED=ON \
    -DDAS_TOOLS_DISABLED=ON \
    -DDAS_TESTS_DISABLED=ON \
    -DDAS_TUTORIAL_DISABLED=ON \
    -DDAS_AOT_EXAMPLES_DISABLED=ON \
    -DDAS_TREE_SITTER_DISABLED=ON

cmake --build build_afl --target das_fuzz -j"$(nproc)"

echo ">> built: $PWD/build_afl/das_fuzz"
