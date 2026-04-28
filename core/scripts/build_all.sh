#!/bin/bash
#############################################
# PMET - Unified Build Script (monorepo)
#
# Modules:
#   core/indexing/c          -> index_c          (C)
#   core/indexing/cpp        -> index_cpp        (C++11)
#   core/indexing/fused_fimo -> index_fimo_fused (C, links libxml2/libxslt)
#   core/pairing/parallel    -> pair_parallel    (C++17, threaded)
#   core/pairing/original    -> pair_original    (C++11)
#
# All binaries are copied to <repo>/build/.
# Intermediate build artifacts are removed after each module.
#############################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_ROOT="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$CORE_ROOT")"
BUILD_OUTPUT_DIR="$REPO_ROOT/build"
NPROC=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

print_separator() { echo -e "${BLUE}================================================================${NC}"; }
print_step()      { echo -e "${YELLOW}>>> $1${NC}"; }
print_success()   { echo -e "${GREEN}✓ $1${NC}"; }
print_error()     { echo -e "${RED}✗ $1${NC}"; }

# cmake_build <source_dir> <binary_name> [extra_cmake_args...]
cmake_build() {
    local src_dir="$1"
    local binary="$2"
    shift 2
    local cmake_args=("$@")

    print_step "Building: $binary  ($src_dir)"
    cd "$src_dir"

    rm -rf _build
    mkdir _build && cd _build

    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$(pwd)" \
          "${cmake_args[@]}" ..
    make -j"$NPROC"

    if [ -f "$binary" ]; then
        cp "$binary" "$BUILD_OUTPUT_DIR/$binary"
        print_success "$binary built and copied to build/"
    else
        print_error "$binary not found after build"
        cd "$src_dir" && rm -rf _build
        return 1
    fi

    cd "$src_dir" && rm -rf _build
}

#############################################
# Module build functions
#############################################
build_index_c()          { cmake_build "$CORE_ROOT/indexing/c"          "index_c"; }
build_index_cpp()        { cmake_build "$CORE_ROOT/indexing/cpp"        "index_cpp"; }
build_index_fimo_fused() { cmake_build "$CORE_ROOT/indexing/fused_fimo" "index_fimo_fused"; }
build_pair_parallel()    { cmake_build "$CORE_ROOT/pairing/parallel"    "pair_parallel"; }
build_pair_original()    { cmake_build "$CORE_ROOT/pairing/original"    "pair_original"; }

#############################################
# Main
#############################################
BUILD_TARGET="${1:-all}"

print_separator
echo -e "${GREEN}PMET - Build System${NC}"
echo -e "Target: ${YELLOW}$BUILD_TARGET${NC}"
print_separator

mkdir -p "$BUILD_OUTPUT_DIR"

case "$BUILD_TARGET" in
    all)
        build_index_c
        build_index_cpp
        build_index_fimo_fused
        build_pair_parallel
        build_pair_original
        ;;
    indexing)
        build_index_c
        build_index_cpp
        build_index_fimo_fused
        ;;
    pairing)
        build_pair_parallel
        build_pair_original
        ;;
    index-c)          build_index_c ;;
    index-cpp)        build_index_cpp ;;
    index-fimo-fused) build_index_fimo_fused ;;
    pair-parallel)    build_pair_parallel ;;
    pair-original)    build_pair_original ;;
    *)
        echo "Usage: $0 [target]"
        echo ""
        echo "Targets:"
        echo "  all              - Build everything (default)"
        echo "  indexing         - index_c + index_cpp + index_fimo_fused"
        echo "  pairing          - pair_parallel + pair_original"
        echo "  index-c          - core/indexing/c only"
        echo "  index-cpp        - core/indexing/cpp only"
        echo "  index-fimo-fused - core/indexing/fused_fimo only"
        echo "  pair-parallel    - core/pairing/parallel only"
        echo "  pair-original    - core/pairing/original only"
        exit 1
        ;;
esac

print_separator
print_success "Build completed successfully!"
echo ""
echo -e "Binaries available in: ${YELLOW}$BUILD_OUTPUT_DIR${NC}"
ls -la "$BUILD_OUTPUT_DIR" 2>/dev/null | grep -v "^d" | grep -v "^total" || true
print_separator
