# Solar2D ONNX Runtime HTML5 Plugin — Research & Build Documentation

> **Note**: This document has been updated to reflect the new Emscripten-based approach. The previous JS bridge approach has been deprecated.

## Executive Summary

**New Approach**: Use Emscripten to compile the native C plugin + ONNX Runtime C API directly to WebAssembly.

**Key Principle**: **One codebase, same API.** Developer-written Lua code is identical across all platforms (iOS/Android/macOS/Windows/HTML5):

```lua
local ort = require('plugin.onnxruntime')
local session = ort.load(path)
local out = session:run(inputs)
session:close()
```

## Technical Foundation

### Why This Works

1. **ONNX Runtime C API is synchronous**: Functions like `OrtCreateSession()`, `OrtRun()` are blocking calls.

2. **Solar2D HTML5 uses Emscripten**: Solar2D's HTML5 build process compiles C code to WebAssembly.

3. **ONNX Runtime supports WASM static libraries**: Microsoft's official build system supports `--build_wasm_static_lib` flag.

### Research Evidence

From the [ONNX Runtime Web Build Documentation](https://onnxruntime.ai/docs/build/web.html):

> "When you build ONNX Runtime Web using `--build_wasm_static_lib` instead of `--build_wasm`, a build script generates a static library of ONNX Runtime Web named `libonnxruntime_webassembly.a`"

This static library can be linked with our `plugin_onnxruntime.c` using Emscripten to produce a single WebAssembly module.

## Previous Approach (Deprecated)

The original approach used a JavaScript bridge:
- `plugin_onnxruntime_js.js` - JavaScript implementation using onnxruntime-web
- `plugin_onnxruntime.lua` - Lua wrapper with platform detection

**Why it was deprecated**:
- onnxruntime-web's `session.run()` is asynchronous (returns Promise)
- Solar2D does not enable Emscripten's Asyncify feature
- Could not achieve API compatibility with native platforms

## Current Approach (Emscripten + ORT C API)

### Architecture

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
│  │  Combined WebAssembly Module                        │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │  plugin_onnxruntime.c (compiled)            │   │   │
│  │  │  - luaopen_plugin_onnxruntime               │   │   │
│  │  │  - session_load, session_run, session_close │   │   │
│  │  ├─────────────────────────────────────────────┤   │   │
│  │  │  ONNX Runtime C API (linked)                │   │   │
│  │  │  - OrtCreateSession                         │   │   │
│  │  │  - OrtRun                                   │   │   │
│  │  │  - OrtReleaseSession                        │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Build Files

| File | Purpose |
|------|---------|
| `web/build.sh` | Build script for WASM compilation |
| `web/BUILD_GUIDE.md` | Detailed build instructions |

## Build Instructions

### Prerequisites

- Emscripten SDK (emsdk)
- ONNX Runtime source code
- CMake 3.26+, Python 3.9+, Ninja

### Quick Build

```bash
# 1. Build ONNX Runtime WASM static library (one-time)
cd onnxruntime
./build.sh --config Release --build_wasm_static_lib --enable_wasm_simd --skip_tests

# 2. Build the plugin
export ORT_ROOT=/path/to/onnxruntime
cd solar2d-plugin-onnxruntime/web
./build.sh Release
```

See `BUILD_GUIDE.md` for complete instructions.

## Solar2D HTML5 Plugin System

### How Solar2D Loads WASM Plugins

From analysis of [submodule-platform-emscripten](https://github.com/coronalabs/submodule-platform-emscripten):

1. Solar2D HTML5 builds use Emscripten to compile the main engine
2. Plugins can be provided as:
   - Static libraries (`.a` files) linked at build time
   - WebAssembly modules (`.wasm` files) loaded at runtime
3. The plugin's `luaopen_*` function is called to register Lua bindings

### Emscripten Flags Used by Solar2D

```bash
emcc ... \
    -s LEGACY_VM_SUPPORT=1 \
    -s EXTRA_EXPORTED_RUNTIME_METHODS='["ccall", "cwrap"]' \
    -s USE_SDL=2 \
    -s ALLOW_MEMORY_GROWTH=1
```

**Important**: Solar2D does NOT use `-s ASYNCIFY=1`, which is why the JS bridge approach couldn't support synchronous APIs.

## API Compatibility Matrix

| Feature | iOS/Android/macOS/Win | HTML5 (New) | Compatible? |
|---------|----------------------|-------------|-------------|
| `ort.load()` | sync | sync | ✅ Yes |
| `session:run()` | sync | sync | ✅ Yes |
| `session:close()` | sync | sync | ✅ Yes |
| `session:info()` | sync | sync | ✅ Yes |
| Input format | `{dims, data}` | `{dims, data}` | ✅ Yes |
| Output format | `{dims, data}` | `{dims, data}` | ✅ Yes |

## Current Status

### ✅ Completed

1. Build script framework (`web/build.sh`)
2. Build documentation (`web/BUILD_GUIDE.md`)
3. Removed deprecated JS bridge files
4. Restored example/main.lua to master version

### ⬜ Pending

1. Full ONNX Runtime WASM build (requires build environment)
2. Integration testing with Solar2D HTML5
3. Plugin loading mechanism verification
4. Binary size optimization

### Known Issues

1. **Build complexity**: Full ORT WASM build takes 30-60 minutes
2. **Binary size**: Full ORT WASM is ~10MB+ (may need minimal build)
3. **Solar2D integration**: Need to verify plugin loading mechanism

## References

1. [ONNX Runtime Web Build](https://onnxruntime.ai/docs/build/web.html)
2. [ONNX Runtime C API](https://onnxruntime.ai/docs/api/c/)
3. [Solar2D Emscripten Platform](https://github.com/coronalabs/submodule-platform-emscripten)
4. [Emscripten Documentation](https://emscripten.org/docs/)

---

*Last updated: 2026-03-26*  
*Branch: feature/html5-web-bridge*
