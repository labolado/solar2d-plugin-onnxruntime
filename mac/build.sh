#!/bin/bash
# Build plugin.onnxruntime for macOS (Solar2D Simulator)
#
# IMPORTANT: Must use Solar2D's own Lua 5.1 headers, NOT Homebrew Lua.
# Using wrong headers causes ABI mismatch (dlopen fails with missing symbols).
#
# Prerequisites:
#   brew install onnxruntime
#   Solar2D installed at /Applications/Corona-b3/
#
# Usage:
#   bash mac/build.sh          # build only
#   bash mac/build.sh install  # build + install to Simulator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
OUT_DIR="$PLUGIN_DIR/build/mac"

# ── Solar2D Lua headers (MUST use these, not Homebrew) ──
SOLAR2D_LUA=""
for dir in \
    "/Applications/Corona-b3/Native/Corona/shared/include/lua" \
    "/Applications/Corona/Native/Corona/shared/include/lua" \
    "/Applications/Solar2D/Native/Corona/shared/include/lua"; do
    if [ -f "$dir/lua.h" ]; then
        SOLAR2D_LUA="$dir"
        break
    fi
done

if [ -z "$SOLAR2D_LUA" ]; then
    echo "ERROR: Solar2D Lua headers not found."
    echo "  Expected: /Applications/Corona-b3/Native/Corona/shared/include/lua/"
    echo "  Install Solar2D or set SOLAR2D_LUA_INCLUDE env var."
    exit 1
fi

# Allow override
SOLAR2D_LUA="${SOLAR2D_LUA_INCLUDE:-$SOLAR2D_LUA}"

# Verify it's actually Lua 5.1
LUA_VER=$(grep 'LUA_VERSION_NUM' "$SOLAR2D_LUA/lua.h" 2>/dev/null | head -1)
if [[ ! "$LUA_VER" =~ "501" ]]; then
    echo "WARNING: Lua headers at $SOLAR2D_LUA may not be Lua 5.1"
    echo "  Found: $LUA_VER"
    echo "  Solar2D requires Lua 5.1 ABI"
fi

# ── ONNX Runtime (Homebrew) ──
ORT_INCLUDE=""
ORT_LIB=""
for prefix in /opt/homebrew /usr/local; do
    if [ -f "$prefix/include/onnxruntime/onnxruntime_c_api.h" ]; then
        ORT_INCLUDE="$prefix/include/onnxruntime"
        ORT_LIB="$prefix/lib"
        break
    fi
done

if [ -z "$ORT_INCLUDE" ]; then
    echo "ERROR: onnxruntime not found. Run: brew install onnxruntime"
    exit 1
fi

# ── Build ──
mkdir -p "$OUT_DIR"

echo "Building plugin_onnxruntime.dylib ..."
echo "  Lua: $SOLAR2D_LUA (Lua 5.1)"
echo "  ORT: $ORT_INCLUDE"

clang -shared -o "$OUT_DIR/plugin_onnxruntime.dylib" \
    -I"$SOLAR2D_LUA" \
    -I"$ORT_INCLUDE" \
    -L"$ORT_LIB" \
    -lonnxruntime \
    -undefined dynamic_lookup \
    -O2 -Wall \
    "$PLUGIN_DIR/plugin_onnxruntime.c"

SIZE=$(ls -lh "$OUT_DIR/plugin_onnxruntime.dylib" | awk '{print $5}')
echo "Built: $OUT_DIR/plugin_onnxruntime.dylib ($SIZE)"

# ── Install ──
if [ "${1:-}" = "install" ]; then
    DEST="$HOME/Library/Application Support/Corona/Simulator/Plugins"
    mkdir -p "$DEST"
    cp "$OUT_DIR/plugin_onnxruntime.dylib" "$DEST/plugin_onnxruntime.dylib"
    echo "Installed to: $DEST/plugin_onnxruntime.dylib"
fi
