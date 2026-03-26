#!/bin/bash
# Build plugin.onnxruntime for Android (arm64-v8a + armeabi-v7a)
#
# Prerequisites:
#   1. Android NDK r27+ (set ANDROID_NDK_HOME or uses latest in SDK)
#   2. Download ONNX Runtime Android:
#      ./download_ort.sh
#
# Usage:
#   cd android && bash build.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
ORT_DIR="$SCRIPT_DIR/onnxruntime-android"
OUT_DIR="$SCRIPT_DIR/build"

# Find NDK
NDK="${ANDROID_NDK_HOME:-${NDK_HOME:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk/$(ls -1 ${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk/ 2>/dev/null | sort -V | tail -1)}}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
if [ ! -d "$TOOLCHAIN" ]; then
    # Linux
    TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
fi
if [ ! -d "$TOOLCHAIN" ]; then
    echo "ERROR: Android NDK toolchain not found. Set ANDROID_NDK_HOME."
    exit 1
fi
echo "NDK: $NDK"

# Check ORT
if [ ! -d "$ORT_DIR/jni" ]; then
    echo "ERROR: ONNX Runtime Android not found at $ORT_DIR"
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
    "/usr/local/include/lua5.1" \
    "/usr/local/include"; do
    if [ -f "$dir/lua.h" ]; then LUA_INCLUDE="$dir"; break; fi
done
if [ -z "$LUA_INCLUDE" ]; then echo "ERROR: lua.h not found"; exit 1; fi

# Build for each ABI using direct clang (Lua symbols resolved at runtime by Solar2D)
for ABI in arm64-v8a armeabi-v7a; do
    echo ""
    echo "=== Building for $ABI ==="
    case "$ABI" in
        arm64-v8a)   CC="$TOOLCHAIN/bin/aarch64-linux-android24-clang" ;;
        armeabi-v7a) CC="$TOOLCHAIN/bin/armv7a-linux-androideabi24-clang" ;;
    esac
    ABI_OUT="$OUT_DIR/$ABI"
    mkdir -p "$ABI_OUT"

    # Compile
    $CC -c -fPIC -O2 -Wall \
        -I"$ORT_DIR/headers" \
        -I"$LUA_INCLUDE" \
        -o "$ABI_OUT/plugin_onnxruntime.o" \
        "$PLUGIN_DIR/plugin_onnxruntime.c"

    # Link against liblua.so (from Corona APK) so dlopen can resolve Lua symbols.
    # NOTE: filename uses dots (libplugin.onnxruntime.so) so Corona's Android
    # loader finds it for require("plugin.onnxruntime"). The exported symbol
    # luaopen_plugin_onnxruntime uses underscores per Lua convention.
    LUA_LIB_DIR="${LUA_SO_DIR:-/tmp/corona-android-libs/$ABI}"
    if [ ! -f "$LUA_LIB_DIR/liblua.so" ]; then
        echo "WARNING: liblua.so not found at $LUA_LIB_DIR, Lua symbols will be unresolved"
        LUA_LINK_FLAGS="-Wl,--warn-unresolved-symbols"
    else
        LUA_LINK_FLAGS="-L$LUA_LIB_DIR -llua"
    fi
    $CC -shared \
        -o "$ABI_OUT/libplugin.onnxruntime.so" \
        "$ABI_OUT/plugin_onnxruntime.o" \
        -L"$ORT_DIR/jni/$ABI" -lonnxruntime $LUA_LINK_FLAGS

    rm -f "$ABI_OUT/plugin_onnxruntime.o"

    # Copy ORT runtime .so
    cp "$ORT_DIR/jni/$ABI/libonnxruntime.so" "$ABI_OUT/"

    echo "Built: $ABI_OUT/libplugin.onnxruntime.so ($(ls -lh "$ABI_OUT/libplugin.onnxruntime.so" | awk '{print $5}'))"
done

echo ""
echo "=== Android build complete ==="
echo "Output: $OUT_DIR/{arm64-v8a,armeabi-v7a}/"
