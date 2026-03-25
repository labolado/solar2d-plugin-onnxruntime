# Cross-platform CMake build for plugin.onnxruntime
# Works for macOS native and Android NDK cross-compilation.
#
# macOS:
#   mkdir build-mac && cd build-mac
#   cmake .. && make
#
# Android (arm64):
#   mkdir build-android && cd build-android
#   cmake .. -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
#            -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 \
#            -DORT_ROOT=/path/to/onnxruntime-android \
#            -DLUA_INCLUDE_DIR=/path/to/lua/include
#   make

cmake_minimum_required(VERSION 3.14)
project(plugin_onnxruntime C)

set(CMAKE_C_STANDARD 99)

# ── Find dependencies ─────────────────────────────────────

# ONNX Runtime
if(ORT_ROOT)
    set(ORT_INCLUDE_DIR "${ORT_ROOT}/headers")
    if(ANDROID)
        set(ORT_LIB_DIR "${ORT_ROOT}/jni/${ANDROID_ABI}")
    else()
        set(ORT_LIB_DIR "${ORT_ROOT}/lib")
    endif()
else()
    # Try Homebrew (macOS)
    find_path(ORT_INCLUDE_DIR onnxruntime_c_api.h
        PATHS /opt/homebrew/include/onnxruntime /usr/local/include/onnxruntime)
    find_library(ORT_LIBRARY onnxruntime
        PATHS /opt/homebrew/lib /usr/local/lib)
    get_filename_component(ORT_LIB_DIR "${ORT_LIBRARY}" DIRECTORY)
endif()

# Lua headers (prefer Solar2D's Lua 5.1 headers over Homebrew)
if(NOT LUA_INCLUDE_DIR)
    find_path(LUA_INCLUDE_DIR lua.h
        PATHS "/Applications/Corona-b3/Native/Corona/shared/include/lua"
              "/Applications/Corona/Native/Corona/shared/include/lua"
              /opt/homebrew/include/lua /opt/homebrew/include/lua5.1
              /usr/local/include/lua /usr/local/include/lua5.1
              /usr/include/lua5.1)
endif()

message(STATUS "ORT include: ${ORT_INCLUDE_DIR}")
message(STATUS "ORT lib dir: ${ORT_LIB_DIR}")
message(STATUS "Lua include: ${LUA_INCLUDE_DIR}")

# ── Build shared library ─────────────────────────────────

add_library(plugin_onnxruntime SHARED
    plugin_onnxruntime.c
)

target_include_directories(plugin_onnxruntime PRIVATE
    ${ORT_INCLUDE_DIR}
    ${LUA_INCLUDE_DIR}
)

target_link_directories(plugin_onnxruntime PRIVATE
    ${ORT_LIB_DIR}
)

target_link_libraries(plugin_onnxruntime PRIVATE
    onnxruntime
)

# On macOS, don't require Lua symbols at link time (resolved at runtime by Solar2D)
if(APPLE)
    set_target_properties(plugin_onnxruntime PROPERTIES
        LINK_FLAGS "-undefined dynamic_lookup"
        SUFFIX ".dylib"
    )
endif()

# On Android, leave Lua symbols unresolved (resolved at runtime by Solar2D host)
if(ANDROID)
    set_target_properties(plugin_onnxruntime PROPERTIES
        OUTPUT_NAME "plugin_onnxruntime"
        PREFIX "lib"
        LINK_FLAGS "-Wl,--unresolved-symbols=ignore-all"
    )
endif()

target_compile_options(plugin_onnxruntime PRIVATE -O2 -Wall)
