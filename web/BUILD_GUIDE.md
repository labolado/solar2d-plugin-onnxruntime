# Solar2D ONNX Runtime WebAssembly Build Guide

> **Goal**: Compile plugin_onnxruntime.c + ONNX Runtime C API into a single WebAssembly module for Solar2D HTML5 builds.

## Overview

This guide documents the process of building the ONNX Runtime plugin for Solar2D's HTML5 platform using Emscripten. Unlike the previous JS bridge approach, this new approach compiles the native C plugin code directly to WebAssembly, maintaining API compatibility with other platforms.

```
┌─────────────────────────────────────────────────────────────┐
│  Solar2D HTML5 App                                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Lua Code                                           │   │
│  │  local ort = require("plugin.onnxruntime")          │   │
│  │  local session = ort.load("model.onnx")             │   │
│  │  local out = session:run({input = tensor})          │   │
│  └─────────────────────────────────────────────────────┘   │
│                         │                                   │
│  ┌──────────────────────▼──────────────────────────────┐   │
│  │  Solar2D Runtime (WASM)                             │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │  plugin_onnxruntime.wasm                    │   │   │
│  │  │  ┌─────────────────────────────────────┐   │   │   │
│  │  │  │  plugin_onnxruntime.c               │   │   │   │
│  │  │  │  (compiled to WASM)                 │   │   │   │
│  │  │  ├─────────────────────────────────────┤   │   │   │
│  │  │  │  ONNX Runtime C API                 │   │   │   │
│  │  │  │  (OrtCreateSession, OrtRun, ...)   │   │   │   │
│  │  │  └─────────────────────────────────────┘   │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Technical Foundation

### Why This Approach Works

1. **ONNX Runtime C API is synchronous**: The C functions `OrtCreateSession()`, `OrtRun()`, etc. are synchronous blocking calls.

2. **Solar2D HTML5 uses Emscripten**: Solar2D's HTML5 build process compiles C/C++ code to WebAssembly using Emscripten.

3. **ONNX Runtime supports WASM static library**: Microsoft provides `--build_wasm_static_lib` flag to build ORT as a static library (`libonnxruntime_webassembly.a`).

### Key Insight from Research

> "When you build ONNX Runtime Web using `--build_wasm_static_lib` instead of `--build_wasm`, a build script generates a static library of ONNX Runtime Web named `libonnxruntime_webassembly.a`" — [ONNX Runtime Docs](https://onnxruntime.ai/docs/build/web.html)

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Emscripten SDK | 3.1.45+ | Compile C/C++ to WebAssembly |
| CMake | 3.26+ | Build ONNX Runtime |
| Python | 3.9+ | ONNX Runtime build scripts |
| Ninja | latest | Fast build system |
| Node.js | 18.0+ | ONNX Runtime JS dependencies |

### Install Emscripten

```bash
# Clone and setup emsdk
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh

# Verify installation
emcc --version
```

## Build Steps

### Step 1: Clone ONNX Runtime

```bash
git clone --recursive https://github.com/Microsoft/onnxruntime
cd onnxruntime

# Initialize submodules (includes emsdk)
git submodule sync --recursive
git submodule update --init --recursive
```

### Step 2: Build ONNX Runtime WebAssembly Static Library

```bash
cd onnxruntime

# Set up emsdk environment (if not already done)
source cmake/external/emsdk/emsdk_env.sh

# Build static library for Release
./build.sh \
    --config Release \
    --build_wasm_static_lib \
    --enable_wasm_simd \
    --skip_tests \
    --disable_rtti \
    --disable_wasm_exception_catching

# Build outputs:
#   build/Linux/Release/libonnxruntime_webassembly.a
#   include/onnxruntime/core/session/onnxruntime_c_api.h
#   include/onnxruntime/core/session/onnxruntime_cxx_api.h
```

**Build Flags Explained:**

| Flag | Purpose |
|------|---------|
| `--build_wasm_static_lib` | Build as static library (.a) instead of JS/WASM bundle |
| `--enable_wasm_simd` | Enable SIMD instructions for better performance |
| `--skip_tests` | Skip tests (required for Release builds) |
| `--disable_rtti` | Disable Run-Time Type Information (smaller binary) |
| `--disable_wasm_exception_catching` | Disable exception catching (performance) |

**Build Time:** 30-60 minutes depending on hardware.

**Expected Output Size:**
- `libonnxruntime_webassembly.a`: ~50-100 MB (unstripped)
- Final WASM binary: ~5-15 MB (after linking and optimization)

### Step 3: Build the Plugin

```bash
cd /path/to/solar2d-plugin-onnxruntime/web

# Set ORT_ROOT environment variable
export ORT_ROOT=/path/to/onnxruntime

# Run build script
./build.sh Release
```

**Build Output:**
```
web/build/release/
├── plugin_onnxruntime.js      # JavaScript loader
├── plugin_onnxruntime.wasm    # WebAssembly binary
└── plugin_onnxruntime/
    ├── metadata.lua           # Solar2D plugin metadata
    ├── plugin_onnxruntime.js
    └── plugin_onnxruntime.wasm
```

## Integration with Solar2D

### Understanding Solar2D HTML5 Plugin Loading

Solar2D HTML5 builds use a specific mechanism for loading plugins:

1. **Plugin Discovery**: Solar2D looks for `metadata.lua` in the plugin directory
2. **WASM Loading**: The runtime loads `.wasm` files using Emscripten's `loadWebAssemblyModule`
3. **Symbol Resolution**: Plugin's `luaopen_*` function is called to register Lua bindings

### Solar2D Emscripten Build System

From the [submodule-platform-emscripten](https://github.com/coronalabs/submodule-platform-emscripten) repository:

```bash
# Solar2D HTML5 build process (simplified)
emcc \
    obj/Release/libratatouille.a \
    obj/Release/librtt.a \
    [PLUGIN_STATIC_LIBS...] \
    -s LEGACY_VM_SUPPORT=1 \
    -s EXTRA_EXPORTED_RUNTIME_METHODS='["ccall", "cwrap"]' \
    -s USE_SDL=2 \
    -s ALLOW_MEMORY_GROWTH=1 \
    --preload-file "assets@/" \
    -o "index.html"
```

**Key Observations:**
- Solar2D does NOT use `-s ASYNCIFY=1` (confirmed by research)
- Plugins are linked as static libraries (`.a` files)
- The final output is a combined WASM module

### Plugin Directory Structure

For HTML5 platform, Solar2D expects:

```
plugins/
└── plugin.onnxruntime/
    └── html5/
        ├── metadata.lua
        ├── libplugin_onnxruntime.a    # Static library (alternative)
        └── plugin_onnxruntime.wasm    # WebAssembly module (preferred)
```

### metadata.lua Format

```lua
local metadata = 
{
    plugin =
    {
        format = 'wasm',
        
        -- For static library linking
        staticLibs = { "plugin_onnxruntime" },
        
        -- For WebAssembly module
        wasmFiles = { "plugin_onnxruntime.wasm" },
        
        -- Dependencies (if any)
        dependencies = {
            -- List of other required libraries
        },
    },
}

return metadata
```

## Current Status & Known Issues

### ✅ What Works

1. **Build script framework**: `web/build.sh` is ready
2. **ONNX Runtime WASM static library**: Confirmed supported by Microsoft
3. **Plugin C code**: Uses standard ORT C API

### ⚠️ Unknown / Needs Testing

1. **Solar2D plugin loading mechanism**: How exactly does Solar2D load WASM-based plugins?
   - Does it support standalone `.wasm` files?
   - Or must plugins be linked as `.a` static libraries during the main build?

2. **Lua runtime integration**: How does the plugin access Solar2D's Lua state?
   - Standard `lua.h` headers should work
   - Need to verify `luaopen_plugin_onnxruntime` symbol export

3. **Memory management**: ORT's WASM memory needs vs Solar2D's WASM memory
   - Both use Emscripten's memory model
   - May need `-s ALLOW_MEMORY_GROWTH=1`

4. **Build system integration**: How to integrate with Solar2D's build process?
   - Local HTML5 builds?
   - Solar2D Build service?

### 🔴 Blockers

1. **No test environment**: Need a working Solar2D HTML5 build setup to test
2. **Documentation gaps**: Solar2D's WASM plugin documentation is limited
3. **ORT binary size**: Full ORT WASM is ~10MB+ (may need minimal build)

## Alternative: Minimal ORT Build

For smaller binary size, consider using ONNX Runtime's minimal build:

```bash
./build.sh \
    --config Release \
    --build_wasm_static_lib \
    --minimal_build \
    --enable_wasm_simd \
    --skip_tests
```

**Requirements:**
- Models must be in ORT format (not ONNX)
- Convert ONNX to ORT format using `onnxruntime.tools.convert_onnx_models_to_ort`

## Next Steps

### Immediate (This Branch)

1. ✅ Create build script framework (`web/build.sh`)
2. ✅ Document build process (`web/BUILD_GUIDE.md`)
3. ⬜ Set up ONNX Runtime build environment
4. ⬜ Attempt full ORT WASM compilation
5. ⬜ Test with Solar2D HTML5 simulator

### Research Needed

1. **Solar2D WASM plugin loading**: Study `submodule-platform-emscripten` source
2. **Plugin API compatibility**: Verify our C plugin works with Emscripten
3. **Memory model**: Test ORT WASM memory usage within Solar2D

### Long Term

1. **Optimize binary size**: Use minimal build or custom ORT configuration
2. **Performance testing**: Benchmark vs native platforms
3. **WebGPU support**: Add WebGPU execution provider for better performance

## References

1. [ONNX Runtime Web Build Documentation](https://onnxruntime.ai/docs/build/web.html)
2. [ONNX Runtime C API](https://onnxruntime.ai/docs/api/c/)
3. [Solar2D Platform Emscripten](https://github.com/coronalabs/submodule-platform-emscripten)
4. [Emscripten Documentation](https://emscripten.org/docs/)

## Build Troubleshooting

### Issue: "libonnxruntime_webassembly.a not found"

**Solution**: Build ONNX Runtime first with `--build_wasm_static_lib` flag.

### Issue: "emcc: command not found"

**Solution**: Activate Emscripten environment:
```bash
source /path/to/emsdk/emsdk_env.sh
```

### Issue: "undefined reference to OrtCreateSession"

**Solution**: Ensure ORT static library is properly linked. Check library path:
```bash
nm libonnxruntime_webassembly.a | grep OrtCreateSession
```

### Issue: Large binary size

**Solutions**:
1. Use minimal build (`--minimal_build`)
2. Strip debug symbols
3. Enable Link Time Optimization (LTO)
4. Use ORT format models

## Appendix: Complete Build Example

```bash
#!/bin/bash

# 1. Setup paths
export EMSDK_ROOT=$HOME/emsdk
export ORT_ROOT=$HOME/onnxruntime
export PLUGIN_ROOT=$HOME/solar2d-plugin-onnxruntime

# 2. Activate Emscripten
source $EMSDK_ROOT/emsdk_env.sh

# 3. Build ONNX Runtime (if not already built)
cd $ORT_ROOT
./build.sh \
    --config Release \
    --build_wasm_static_lib \
    --enable_wasm_simd \
    --skip_tests

# 4. Build plugin
cd $PLUGIN_ROOT/web
export ORT_ROOT
./build.sh Release

# 5. Check output
ls -la build/release/
```

---

*Last updated: 2026-03-26*
*Branch: feature/html5-web-bridge*
