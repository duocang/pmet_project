#!/bin/bash
#############################################
# fimo (fused version) - Build Script
#############################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(cd "$PROJECT_DIR/../../.." && pwd)"

# Binary names
BINARY_NAME="index_fimo_fused"
UNIFIED_NAME="index_fimo_fused"

echo "==> Building index_fimo_fused (fused FIMO + pmetindex)..."

cd "$PROJECT_DIR"
rm -rf build
mkdir -p build
cd build

cmake -S .. -B .
cmake --build . -- -j$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

if [ -f "$BINARY_NAME" ]; then
    echo "✓ Build successful: build/$BINARY_NAME"

    # Copy to project root build directory
    if [ -d "$PROJECT_ROOT/build" ] || mkdir -p "$PROJECT_ROOT/build"; then
        cp "$BINARY_NAME" "$PROJECT_ROOT/build/$UNIFIED_NAME"
        echo "✓ Copied to: $PROJECT_ROOT/build/$UNIFIED_NAME"
    fi
else
    echo "✗ Build failed"
    exit 1
fi
