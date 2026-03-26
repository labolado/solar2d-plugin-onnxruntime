# Solar2D HTML5 ONNX Runtime JS Bridge — Research Report

## Executive Summary

**JS Interop Feasibility: ✅ FEASIBLE with limitations**

Solar2D HTML5 builds support JavaScript interop through the JS Module Loader mechanism. However, **full API compatibility with the native plugin is impossible** due to fundamental architectural differences:
- Native plugin uses **synchronous** C API calls
- HTML5/JS bridge is **asynchronous** by design (Promises)

## 1. Solar2D HTML5 JS Interop Research

### 1.1 Mechanism

Solar2D HTML5 builds use Emscripten and provide a JS Module Loader for Lua-JS bridging:

```lua
-- Lua side
local js = require("my_plugin_js")  -- loads my_plugin_js.js
js.someFunction(args)
```

```javascript
// JS side (my_plugin_js.js)
my_plugin_js = {
    someFunction: function(args) {
        // JavaScript code here
    }
}
```

### 1.2 Key Capabilities

| Feature | Support | Notes |
|---------|---------|-------|
| Call JS from Lua | ✅ | Direct method calls |
| Pass numbers/strings | ✅ | Copied by value |
| Pass Lua tables | ✅ | Converted to JS objects |
| Pass Lua functions | ✅ | Via `LuaCreateFunction` |
| Async callbacks | ✅ | JS can call Lua callbacks |
| Return values | ✅ | Sync only (no async await) |

### 1.3 Function Passing API

```javascript
// Check if parameter is a function reference
LuaIsFunction(ref) → boolean

// Convert reference to callable JS function
LuaCreateFunction(ref) → function

// Release to prevent memory leak
LuaReleaseFunction(func)
```

### 1.4 Limitations

1. **No synchronous return from async JS**: Cannot `return await fetch()` to Lua
2. **Function references expire**: Must call `LuaCreateFunction` immediately in the JS function
3. **No Promise/await in Lua**: Lua coroutines cannot await JS Promises

## 2. ONNX Runtime Web Research

### 2.1 Package Overview

- **npm package**: `onnxruntime-web`
- **CDN**: `https://cdn.jsdelivr.net/npm/onnxruntime-web/dist/ort.min.js`
- **Global object**: `ort`

### 2.2 Core API

```javascript
// Session creation (async)
const session = await ort.InferenceSession.create('model.onnx', {
    executionProviders: ['wasm'],  // or 'webgpu', 'webgl'
    intraOpNumThreads: 4
});

// Run inference (async)
const feeds = {
    inputName: new ort.Tensor('float32', float32Array, [1, 3, 224, 224])
};
const results = await session.run(feeds);

// Results format
// results.outputName = { data: TypedArray, dims: [...], type: 'float32' }
```

### 2.3 Execution Providers

| Provider | Description | Availability |
|----------|-------------|--------------|
| `wasm` | WebAssembly CPU (default) | All browsers |
| `webgpu` | WebGPU acceleration | Modern Chrome/Edge |
| `webgl` | WebGL acceleration | Most browsers (deprecated) |
| `webnn` | WebNN API | Experimental |

### 2.4 Data Types Supported

- `float32` (default)
- `float64`
- `int32`
- `int64` (BigInt64Array or number array)
- `uint8`

## 3. API Compatibility Analysis

### 3.1 Native Plugin API (Synchronous)

```lua
local ort = require("plugin.onnxruntime")

-- Load model (sync)
local session = ort.load(modelPath [, opts])

-- Run inference (sync)
local outputs = session:run({
    inputName = { dims = {...}, data = {...} }
})
-- Returns: { outputName = { dims = {...}, data = {...}, data_binary = "..." } }

-- Get info (sync)
local info = session:info()  -- {inputs = {...}, outputs = {...}}

-- Close (sync)
session:close()
```

### 3.2 HTML5 Plugin API (Asynchronous)

```lua
local ort = require("plugin.onnxruntime")

-- Load model (async with callback)
ort.load(modelPath, function(session, error)
    if error then return end
    
    -- Run inference (async with callback)
    session:run({
        inputName = { dims = {...}, data = {...} }
    }, function(outputs, error)
        if error then return end
        -- Use outputs
        
        session:close()
    end)
end)
```

### 3.3 Compatibility Matrix

| Feature | Native | HTML5 | Compatible? |
|---------|--------|-------|-------------|
| `ort.load()` | sync | async+callback | ❌ No |
| `session:run()` | sync | async+callback | ❌ No |
| `session:close()` | sync | sync | ✅ Yes |
| `session:info()` | sync | sync | ✅ Yes |
| Input format | `{dims, data}` | `{dims, data}` | ✅ Yes |
| Output format | `{dims, data, data_binary}` | `{dims, data, data_binary}` | ✅ Yes |
| `opts.ep` | "coreml"/"directml"/"cpu" | "webgpu"/"webgl"/"wasm" | ⚠️ Different |

## 4. Implementation

### 4.1 Files Created

```
web/
├── metadata.lua              # Plugin metadata for Solar2D
├── plugin_onnxruntime_js.js  # JS implementation
├── plugin_onnxruntime.lua    # Lua wrapper with platform detection
└── RESEARCH.md              # This document
```

### 4.2 Usage Example

```lua
local ort = require("plugin.onnxruntime")

-- Platform-agnostic check
if not ort.isAvailable() then
    print("ONNX Runtime not available on this platform")
    return
end

-- Load model (async)
ort.load("model.onnx", function(session, error)
    if error then
        print("Failed to load model:", error)
        return
    end
    
    print("Model loaded:", session:info())
    
    -- Prepare input
    local inputs = {
        input = {
            dims = {1, 3, 224, 224},
            data = {0.5, 0.3, ...}  -- 1*3*224*224 numbers
        }
    }
    
    -- Run inference (async)
    session:run(inputs, function(outputs, error)
        if error then
            print("Inference failed:", error)
            session:close()
            return
        end
        
        -- Process results
        for name, tensor in pairs(outputs) do
            print(name, "shape:", table.concat(tensor.dims, ","))
            -- tensor.data is 1-indexed Lua table
            -- tensor.data_binary is binary string for large tensors
        end
        
        session:close()
    end)
end)
```

### 4.3 HTML5 Setup

Add to your `index.html` (before Solar2D script):

```html
<script src="https://cdn.jsdelivr.net/npm/onnxruntime-web/dist/ort.min.js"></script>
```

## 5. Limitations and Workarounds

### 5.1 Async-Only API

**Problem**: Native plugin is synchronous, HTML5 is async.

**Workaround**: Use callback pattern exclusively, or create a wrapper:

```lua
-- Async wrapper that works on both platforms
local function loadModelAsync(modelPath, callback)
    if system.getInfo("platform") == "html5" then
        ort.load(modelPath, callback)
    else
        -- Native: wrap sync in async callback
        timer.performWithDelay(1, function()
            local ok, session = pcall(ort.load, modelPath)
            callback(session, ok and nil or session)
        end)
    end
end
```

### 5.2 Execution Provider Names

**Problem**: Different EP names across platforms.

| Native | HTML5 |
|--------|-------|
| "cpu" | "wasm" |
| "coreml" | "webgpu" |
| "directml" | "webgl" |

**Workaround**: Map common names in your app:

```lua
local epMap = {
    cpu = system.getInfo("platform") == "html5" and "wasm" or "cpu",
    gpu = system.getInfo("platform") == "html5" and "webgpu" or "coreml",
}
```

### 5.3 Model Path Resolution

**Problem**: HTML5 uses relative paths from `index.html`.

**Solution**: Place models in the same directory or use absolute URLs.

### 5.4 Large Model Loading

**Problem**: WebAssembly compilation can be slow.

**Solution**: Use WebGPU if available; preload models during splash screen.

## 6. Future Improvements

1. **Web Worker Support**: Run inference in worker to avoid blocking main thread
2. **Streaming API**: Support for chunked model loading
3. **Model Caching**: Use IndexedDB to cache compiled models
4. **SharedArrayBuffer**: For zero-copy tensor transfer (requires COOP/COEP headers)

## 7. Conclusion

✅ **JS Interop is technically feasible**

The Solar2D HTML5 JS bridge provides all necessary mechanisms to call onnxruntime-web from Lua. However, the **asynchronous nature of web APIs creates an irreconcilable API difference** with the synchronous native plugin.

**Recommendation**: 
- Use the provided HTML5 plugin for web deployments
- Create a thin abstraction layer in your app to handle platform differences
- Consider using coroutines in Lua to make async code more readable

**Migration path for existing apps**:
1. Wrap `ort.load()` calls in async helper functions
2. Use callbacks for `session:run()` results
3. Test on both native and HTML5 platforms
