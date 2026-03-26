# plugin.onnxruntime — Build & install for Solar2D
#
# Usage:
#   make mac              # build macOS dylib
#   make mac-install      # build + install to Simulator
#   make android          # build Android .so (arm64 + armv7)
#   make ios              # build iOS .a (device + simulator)
#   make clean            # remove all build artifacts
#   make tgz-mac          # package mac-sim tgz
#   make tgz-android      # package android tgz
#   make tgz              # package all platforms

.PHONY: mac mac-install android ios clean tgz tgz-mac tgz-android

mac:
	bash mac/build.sh

mac-install:
	bash mac/build.sh install

android:
	cd android && bash download_ort.sh && bash build.sh

ios:
	cd ios && bash download_ort.sh && bash build.sh

clean:
	rm -rf build/
	rm -rf mac/build/
	rm -rf android/build/
	rm -rf ios/build/
	rm -rf win32/build/

# ── Packaging ─────────────────────────────────────────

TGZ_OUT = build/tgz

tgz-mac: mac
	@mkdir -p $(TGZ_OUT)/mac-staging
	@cp build/mac/plugin_onnxruntime.dylib $(TGZ_OUT)/mac-staging/
	@cp lua/plugin/onnxruntime.lua $(TGZ_OUT)/mac-staging/
	@cd $(TGZ_OUT)/mac-staging && tar czf ../plugin.onnxruntime-mac-sim.tgz *
	@rm -rf $(TGZ_OUT)/mac-staging
	@echo "Package: $(TGZ_OUT)/plugin.onnxruntime-mac-sim.tgz"

tgz-android: android
	@mkdir -p $(TGZ_OUT)/android-staging/jniLibs/arm64-v8a $(TGZ_OUT)/android-staging/jniLibs/armeabi-v7a
	@cp android/build/arm64-v8a/libplugin.onnxruntime.so $(TGZ_OUT)/android-staging/jniLibs/arm64-v8a/
	@cp android/build/arm64-v8a/libonnxruntime.so $(TGZ_OUT)/android-staging/jniLibs/arm64-v8a/
	@cp android/build/armeabi-v7a/libplugin.onnxruntime.so $(TGZ_OUT)/android-staging/jniLibs/armeabi-v7a/
	@cp android/build/armeabi-v7a/libonnxruntime.so $(TGZ_OUT)/android-staging/jniLibs/armeabi-v7a/
	@cp android/build/arm64-v8a/libplugin.onnxruntime.so $(TGZ_OUT)/android-staging/
	@printf 'local metadata =\n{\n\tplugin =\n\t{\n\t\tformat = "sharedLibrary",\n\t\tstaticLibs = { "plugin.onnxruntime", },\n\t\tframeworks = {},\n\t\tframeworksOptional = {},\n\t},\n}\nreturn metadata\n' > $(TGZ_OUT)/android-staging/metadata.lua
	@cd $(TGZ_OUT)/android-staging && tar czf ../plugin.onnxruntime-android.tgz *
	@rm -rf $(TGZ_OUT)/android-staging
	@echo "Package: $(TGZ_OUT)/plugin.onnxruntime-android.tgz"

tgz: tgz-mac tgz-android
	@echo "All packages in $(TGZ_OUT)/"
	@ls -lh $(TGZ_OUT)/*.tgz
