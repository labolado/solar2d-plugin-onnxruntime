#!/bin/bash
# Build + install ONNX Runtime demo to connected Android device
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DST="/tmp/onnx-android-build-$(date +%s)"
PLUGIN_TGZ="/tmp/plugin.onnxruntime-android.tgz"
BUNDLE_ID="com.labolado.onnxruntime.demo"

# Check plugin tgz exists
if [ ! -f "$PLUGIN_TGZ" ]; then
    echo "ERROR: Plugin tgz not found at $PLUGIN_TGZ"
    echo "  Run: cd $(dirname "$SCRIPT_DIR") && make android"
    echo "  Then package the tgz (see android/build.sh)"
    exit 1
fi

# Check adb
if ! adb devices | grep -q "device$"; then
    echo "ERROR: No Android device connected"
    exit 1
fi

# Swap build.settings to use local plugin tgz
cp "$SCRIPT_DIR/build.settings" "$SCRIPT_DIR/build.settings.bak"
sed 's|https://github.com/labolado/solar2d-plugin-onnxruntime/releases/download/v[0-9]*/plugin.onnxruntime-android.tgz|file://'"$PLUGIN_TGZ"'|' \
    "$SCRIPT_DIR/build.settings" > "$SCRIPT_DIR/build.settings.tmp"
mv "$SCRIPT_DIR/build.settings.tmp" "$SCRIPT_DIR/build.settings"

# Build
mkdir -p "$DST"
cat > /tmp/android-build-args-deploy.lua << LUAEOF
local params = {
    platform = 'android',
    appName = 'OnnxDemo',
    appVersion = '1.0',
    dstPath = '$DST',
    projectPath = '$SCRIPT_DIR',
    androidAppPackage = '$BUNDLE_ID',
    keystorePath = '/Users/yee/.android/debug.keystore',
    keystorePassword = 'android',
    keystoreAlias = 'androiddebugkey',
    keystoreAliasPassword = 'android',
}
return params
LUAEOF

echo "Building for Android..."
/Applications/Corona-b3/Native/Corona/mac/bin/CoronaBuilder.app/Contents/MacOS/CoronaBuilder \
    build --lua /tmp/android-build-args-deploy.lua 2>&1

# Restore build.settings
mv "$SCRIPT_DIR/build.settings.bak" "$SCRIPT_DIR/build.settings"

# Wait for APK to appear (dev builds may take a moment)
for i in 1 2 3 4 5; do
    if [ -f "$DST/OnnxDemo.apk" ]; then break; fi
    sleep 2
done

if [ -f "$DST/OnnxDemo.apk" ]; then
    echo "Installing..."
    adb install -r "$DST/OnnxDemo.apk"
    echo "Launching..."
    adb shell am force-stop "$BUNDLE_ID"
    adb shell am start -n "$BUNDLE_ID/com.ansca.corona.CoronaActivity"
    echo "Done. Monitor logs with: adb logcat -s Corona:V"
else
    echo "WARNING: APK not found at $DST/OnnxDemo.apk"
    echo "  Developer builds may have been installed directly."
    echo "  Try launching: adb shell am start -n $BUNDLE_ID/com.ansca.corona.CoronaActivity"
fi
