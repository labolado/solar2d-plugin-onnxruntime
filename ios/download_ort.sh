#!/bin/bash
# Download ONNX Runtime iOS (xcframework from CocoaPods CDN)
#
# ORT does NOT publish iOS prebuilt binaries on GitHub releases.
# iOS distribution is via CocoaPods. The actual download URL is:
#   https://download.onnxruntime.ai/pod-archive-onnxruntime-c-{VERSION}.zip
#
# To find the URL for a specific version:
#   curl -sL "https://trunk.cocoapods.org/api/v1/pods/onnxruntime-c/specs/{VERSION}" | python3 -c "import json,sys; print(json.load(sys.stdin)['source']['http'])"
#
# The zip contains onnxruntime.xcframework with:
#   - ios-arm64 (device)
#   - ios-arm64_x86_64-simulator (simulator)
#   - Headers/onnxruntime_c_api.h
set -euo pipefail

ORT_VERSION="1.24.3"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/onnxruntime-ios"

if [ -d "$OUT_DIR" ]; then
    echo "ONNX Runtime iOS already at $OUT_DIR"
    exit 0
fi

DOWNLOAD_URL="https://download.onnxruntime.ai/pod-archive-onnxruntime-c-${ORT_VERSION}.zip"

echo "Downloading ONNX Runtime $ORT_VERSION for iOS..."
echo "  URL: $DOWNLOAD_URL"
TMP_DIR=$(mktemp -d)

if curl -fL --progress-bar -o "$TMP_DIR/ort-ios.zip" "$DOWNLOAD_URL"; then
    echo "Downloaded."
else
    echo "ERROR: Download failed."
    echo ""
    echo "To find the correct URL for another version:"
    echo "  curl -sL 'https://trunk.cocoapods.org/api/v1/pods/onnxruntime-c/specs/VERSION' | python3 -c \"import json,sys; print(json.load(sys.stdin)['source']['http'])\""
    rm -rf "$TMP_DIR"
    exit 1
fi

mkdir -p "$OUT_DIR"
unzip -q "$TMP_DIR/ort-ios.zip" -d "$OUT_DIR"
rm -rf "$TMP_DIR"

# Locate Headers — they may be inside the xcframework
HEADERS=$(find "$OUT_DIR" -name "onnxruntime_c_api.h" -print -quit 2>/dev/null)
if [ -n "$HEADERS" ]; then
    HDIR=$(dirname "$HEADERS")
    # Symlink Headers at top level for build.sh
    if [ ! -d "$OUT_DIR/Headers" ] && [ "$HDIR" != "$OUT_DIR/Headers" ]; then
        ln -sf "$HDIR" "$OUT_DIR/Headers"
    fi
fi

echo ""
echo "ONNX Runtime iOS extracted to: $OUT_DIR"
ls -la "$OUT_DIR/"
