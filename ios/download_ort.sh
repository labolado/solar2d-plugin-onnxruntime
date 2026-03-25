#!/bin/bash
# Download ONNX Runtime iOS (xcframework with CoreML EP)
set -euo pipefail

ORT_VERSION="1.24.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/onnxruntime-ios"

if [ -d "$OUT_DIR" ]; then
    echo "ONNX Runtime iOS already at $OUT_DIR"
    exit 0
fi

echo "Downloading ONNX Runtime $ORT_VERSION for iOS..."
TMP_DIR=$(mktemp -d)

# Download the iOS C/C++ package (includes xcframework)
PKG_URL="https://github.com/nicklausw/onnxruntime-swift-package/releases/download/${ORT_VERSION}/onnxruntime-ios-${ORT_VERSION}.zip"
# Fallback: use CocoaPods pod or direct GitHub release
POD_URL="https://github.com/nicklausw/onnxruntime-swift-package/releases/download/v${ORT_VERSION}/onnxruntime-ios-${ORT_VERSION}.zip"
RELEASE_URL="https://github.com/nicklausw/onnxruntime-objc/releases/download/v${ORT_VERSION}/ort-objc-xcframework-${ORT_VERSION}.zip"

# Try the official C release package
C_URL="https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/onnxruntime-ios-xcframework-${ORT_VERSION}.zip"

echo "Trying: $C_URL"
if curl -fL -o "$TMP_DIR/ort-ios.zip" "$C_URL" 2>/dev/null; then
    echo "Downloaded official xcframework package"
else
    # Fallback: build from CocoaPods
    echo "Direct download failed. Try installing via CocoaPods:"
    echo "  pod 'onnxruntime-c', '~> $ORT_VERSION'"
    echo ""
    echo "Or download manually from:"
    echo "  https://github.com/microsoft/onnxruntime/releases/tag/v${ORT_VERSION}"
    rm -rf "$TMP_DIR"
    exit 1
fi

mkdir -p "$OUT_DIR"
unzip -q "$TMP_DIR/ort-ios.zip" -d "$OUT_DIR"
rm -rf "$TMP_DIR"

echo ""
echo "ONNX Runtime iOS extracted to: $OUT_DIR"
ls -la "$OUT_DIR/"
