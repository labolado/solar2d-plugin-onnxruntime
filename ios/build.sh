#!/bin/bash
# Build plugin.onnxruntime for iOS (arm64, static library)
#
# Prerequisites:
#   1. Xcode command line tools
#   2. Download ONNX Runtime iOS:
#      bash download_ort.sh
#
# Usage:
#   cd ios && bash build.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
ORT_DIR="$SCRIPT_DIR/onnxruntime-ios"
OUT_DIR="$SCRIPT_DIR/build"

# Check ORT
if [ ! -d "$ORT_DIR" ]; then
    echo "ERROR: ONNX Runtime iOS not found at $ORT_DIR"
    echo "  Run: bash download_ort.sh"
    exit 1
fi

# Find Lua headers (prefer Solar2D's Lua 5.1 headers)
LUA_INCLUDE=""
for dir in \
    "/Applications/Corona-b3/Native/Corona/shared/include/lua" \
    "/Applications/Corona/Native/Corona/shared/include/lua" \
    "/opt/homebrew/include/lua5.1" \
    "/opt/homebrew/include/lua" \
    "/usr/local/include/lua5.1"; do
    if [ -f "$dir/lua.h" ]; then LUA_INCLUDE="$dir"; break; fi
done
if [ -z "$LUA_INCLUDE" ]; then echo "ERROR: lua.h not found"; exit 1; fi

ORT_INCLUDE="$ORT_DIR/Headers"
# Fallback to Homebrew headers
if [ ! -f "$ORT_INCLUDE/onnxruntime_c_api.h" ]; then
    ORT_INCLUDE="/opt/homebrew/include/onnxruntime"
fi

mkdir -p "$OUT_DIR"

# iOS device (arm64)
echo "=== Building for iOS arm64 ==="
xcrun -sdk iphoneos clang -c \
    -arch arm64 \
    -isysroot "$(xcrun -sdk iphoneos --show-sdk-path)" \
    -miphoneos-version-min=13.0 \
    -I"$ORT_INCLUDE" \
    -I"$LUA_INCLUDE" \
    -O2 -Wall \
    -o "$OUT_DIR/plugin_onnxruntime_arm64.o" \
    "$PLUGIN_DIR/plugin_onnxruntime.c"

ar rcs "$OUT_DIR/libplugin_onnxruntime.a" "$OUT_DIR/plugin_onnxruntime_arm64.o"
echo "Built: $OUT_DIR/libplugin_onnxruntime.a (arm64)"

# iOS simulator (arm64 + x86_64)
echo ""
echo "=== Building for iOS Simulator ==="
for ARCH in arm64 x86_64; do
    xcrun -sdk iphonesimulator clang -c \
        -arch "$ARCH" \
        -isysroot "$(xcrun -sdk iphonesimulator --show-sdk-path)" \
        -mios-simulator-version-min=13.0 \
        -I"$ORT_INCLUDE" \
        -I"$LUA_INCLUDE" \
        -O2 -Wall \
        -o "$OUT_DIR/plugin_onnxruntime_sim_${ARCH}.o" \
        "$PLUGIN_DIR/plugin_onnxruntime.c"
done

ar rcs "$OUT_DIR/libplugin_onnxruntime_sim.a" \
    "$OUT_DIR/plugin_onnxruntime_sim_arm64.o" \
    "$OUT_DIR/plugin_onnxruntime_sim_x86_64.o"
echo "Built: $OUT_DIR/libplugin_onnxruntime_sim.a (arm64 + x86_64)"

echo ""
echo "=== iOS build complete ==="
echo "Device:    $OUT_DIR/libplugin_onnxruntime.a"
echo "Simulator: $OUT_DIR/libplugin_onnxruntime_sim.a"
echo ""
echo "Note: Also need to link onnxruntime.xcframework from $ORT_DIR"
