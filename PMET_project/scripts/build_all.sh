#!/bin/bash
#############################################
# PMET Project - Unified Build Script
#
# Modules:
#   indexing/standlone   -> index_c          (C)
#   indexing/fused_fimo  -> index_fimo_fused (C, links libxml2/libxslt)
#   pairing              -> pair_parallel    (C++17, threaded)
#   legency/indexing     -> index_cpp        (C++11, legacy)
#   legency/pairing      -> pair_original    (C++11, legacy)
#
# All binaries are copied to $PROJECT_ROOT/build/.
# Intermediate build artifacts are removed after each module.
#############################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_OUTPUT_DIR="$PROJECT_ROOT/build"
NPROC=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

print_separator() { echo -e "${BLUE}================================================================${NC}"; }
print_step()      { echo -e "${YELLOW}>>> $1${NC}"; }
print_success()   { echo -e "${GREEN}✓ $1${NC}"; }
print_error()     { echo -e "${RED}✗ $1${NC}"; }

# cmake_build <source_dir> <binary_name> [extra_cmake_args...]
#   1. Creates a temporary build dir inside <source_dir>.
#   2. Runs cmake + make.
#   3. Copies the resulting binary to BUILD_OUTPUT_DIR.
#   4. Removes the temporary build dir (no intermediate files left).
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
build_index_c() {
    cmake_build "$PROJECT_ROOT/src/indexing/standlone" "index_c"
}

build_index_fimo_fused() {
    cmake_build "$PROJECT_ROOT/src/indexing/fused_fimo" "index_fimo_fused"
}

build_pair_parallel() {
    cmake_build "$PROJECT_ROOT/src/pairing" "pair_parallel"
}

build_index_cpp() {
    cmake_build "$PROJECT_ROOT/src/legency/indexing" "index_cpp"
}

build_pair_original() {
    cmake_build "$PROJECT_ROOT/src/legency/pairing" "pair_original"
}

#############################################
# Main
#############################################
BUILD_TARGET="${1:-all}"

print_separator
echo -e "${GREEN}PMET Project - Build System${NC}"
echo -e "Target: ${YELLOW}$BUILD_TARGET${NC}"
print_separator

mkdir -p "$BUILD_OUTPUT_DIR"

case "$BUILD_TARGET" in
    all)
        build_index_c
        build_index_fimo_fused
        build_pair_parallel
        build_index_cpp
        build_pair_original
        ;;
    indexing)
        build_index_c
        build_index_fimo_fused
        ;;
    pairing)
        build_pair_parallel
        ;;
    legency)
        build_index_cpp
        build_pair_original
        ;;
    index-c)          build_index_c ;;
    index-fimo-fused) build_index_fimo_fused ;;
    pair-parallel)    build_pair_parallel ;;
    index-cpp)        build_index_cpp ;;
    pair-original)    build_pair_original ;;
    *)
        echo "Usage: $0 [target]"
        echo ""
        echo "Targets:"
        echo "  all              - Build everything (default)"
        echo "  indexing         - index_c + index_fimo_fused"
        echo "  pairing          - pair_parallel"
        echo "  legency          - index_cpp + pair_original"
        echo "  index-c          - indexing/standlone only"
        echo "  index-fimo-fused - indexing/fused_fimo only"
        echo "  pair-parallel    - pairing only"
        echo "  index-cpp        - legency/indexing only"
        echo "  pair-original    - legency/pairing only"
        exit 1
        ;;
esac

print_separator
print_success "Build completed successfully!"
echo ""
echo -e "Binaries available in: ${YELLOW}$BUILD_OUTPUT_DIR${NC}"
ls -la "$BUILD_OUTPUT_DIR" 2>/dev/null | grep -v "^d" | grep -v "^total" || true
print_separator
