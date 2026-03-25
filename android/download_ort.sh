#!/bin/bash
# Download ONNX Runtime Android prebuilt libraries
# Output: android/onnxruntime-android/

set -euo pipefail

ORT_VERSION="1.24.3"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/onnxruntime-android"

if [ -d "$OUT_DIR/jni" ]; then
    echo "ONNX Runtime Android already downloaded at $OUT_DIR"
    exit 0
fi

echo "Downloading ONNX Runtime $ORT_VERSION for Android..."

TMP_DIR=$(mktemp -d)
AAR_URL="https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/${ORT_VERSION}/onnxruntime-android-${ORT_VERSION}.aar"

curl -L -o "$TMP_DIR/ort.aar" "$AAR_URL"
echo "Extracting..."

mkdir -p "$OUT_DIR"
cd "$TMP_DIR"
unzip -q ort.aar

# Copy JNI libs (the .so files)
cp -r jni "$OUT_DIR/"

# Copy headers
mkdir -p "$OUT_DIR/headers"
cp -r headers/* "$OUT_DIR/headers/" 2>/dev/null || true

# If headers not in AAR, download from GitHub release
if [ ! -f "$OUT_DIR/headers/onnxruntime_c_api.h" ]; then
    echo "Downloading headers from GitHub..."
    HEADER_URL="https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/onnxruntime-android-${ORT_VERSION}.aar"
    # Headers are typically in the include/ folder of the release package
    # For Android, we can use the same C headers as desktop
    curl -L -o "$TMP_DIR/ort-headers.tgz" \
        "https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/onnxruntime-linux-x64-${ORT_VERSION}.tgz" 2>/dev/null || true
    if [ -f "$TMP_DIR/ort-headers.tgz" ]; then
        tar xzf "$TMP_DIR/ort-headers.tgz" -C "$TMP_DIR" --wildcards "*/include/*" 2>/dev/null || true
        cp "$TMP_DIR"/onnxruntime-*/include/*.h "$OUT_DIR/headers/" 2>/dev/null || true
    fi
    # Fallback: copy from Homebrew if available
    if [ ! -f "$OUT_DIR/headers/onnxruntime_c_api.h" ]; then
        for hdir in /opt/homebrew/include/onnxruntime /usr/local/include/onnxruntime; do
            if [ -f "$hdir/onnxruntime_c_api.h" ]; then
                cp "$hdir"/*.h "$OUT_DIR/headers/"
                break
            fi
        done
    fi
fi

rm -rf "$TMP_DIR"

echo ""
echo "ONNX Runtime Android extracted to: $OUT_DIR"
ls -la "$OUT_DIR/jni/"
echo ""
echo "Headers:"
ls "$OUT_DIR/headers/" 2>/dev/null || echo "(using system headers)"
