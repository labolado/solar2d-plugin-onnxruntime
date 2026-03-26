# Solar2D ONNX Runtime Plugin - HTML5/Web Build

This directory contains the HTML5/WebAssembly build of the Solar2D ONNX Runtime plugin.

## Files

- `onnxruntime_plugin.wasm` - WebAssembly binary (14MB)
- `onnxruntime_plugin.js` - Emscripten JavaScript loader (54KB)
- `onnxruntime.lua` - Lua bridge for Solar2D HTML5 platform

## Installation

1. Copy all files to your Solar2D project's `plugins/onnxruntime/` directory
2. Add to your `build.settings`:

```lua
plugins = {
    ["plugin.onnxruntime"] = {
        publisherId = "com.yourcompany",
        supportedPlatforms = { html5 = true }
    }
}
```

3. In your `config.lua` or main Lua file:

```lua
local ort = require("plugin.onnxruntime")

-- Load a model
local session = ort.load("model.onnx")

-- Run inference
local outputs = ort.run(session, {
    input = { dims = {1, 3, 224, 224}, data = {...} }
})
```

## Building from Source

See `web/build.sh` in the project root. Requires:
- Emscripten SDK
- ONNX Runtime WASM static library (v1.21.1)
- LuaJIT headers

## Technical Details

- **ONNX Runtime Version**: v1.21.1
- **Build Flags**: `--build_wasm_static_lib --disable_wasm_exception_catching --disable_rtti --enable_reduced_operator_type_support`
- **Execution Provider**: CPU only (CoreML/DirectML not available in WASM)
- **Memory**: Initial 64MB, max 256MB, grows dynamically

## Notes

- Model files must be included in the app resources
- First load may take a moment as the WASM module initializes
- The Lua API is designed to be compatible with the native plugin version
