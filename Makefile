# plugin.onnxruntime — Build & install for Solar2D
#
# Usage:
#   make mac              # build macOS dylib
#   make mac-install      # build + install to Simulator
#   make android          # build Android .so (arm64 + armv7)
#   make ios              # build iOS .a (device + simulator)
#   make clean            # remove all build artifacts
#   make tgz              # package for Solar2D plugin server

.PHONY: mac mac-install android ios clean tgz

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
	rm -rf android/build/cmake-*
	rm -f android/build/*/plugin_onnxruntime.o
	rm -rf ios/build/
	rm -rf win32/build/

# Package for local Solar2D plugin server
# Output: build/2024.0001-mac-sim.tgz (for mac-sim platform)
tgz: mac
	@mkdir -p build/tgz-staging
	@cp build/mac/plugin_onnxruntime.dylib build/tgz-staging/
	@cp lua/plugin/onnxruntime.lua build/tgz-staging/
	@cd build/tgz-staging && tar czf ../2024.0001-mac-sim.tgz *
	@rm -rf build/tgz-staging
	@echo "Package: build/2024.0001-mac-sim.tgz"
