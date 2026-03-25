# plugin.onnxruntime for Solar2D

Run any ONNX model in Solar2D. Single C source file, builds for macOS, iOS, Android, Windows.

## Quick Start

```lua
local ort = require("plugin.onnxruntime")

local session = ort.load(system.pathForFile("model.onnx", system.ResourceDirectory))

local outputs = session:run({
    input_name = { dims = {1, 3, 224, 224}, data = pixelTable }
})

local result = outputs.output_name.data   -- flat float array
local shape  = outputs.output_name.dims   -- e.g. {1, 1000}

session:close()
```

## API

### `ort.load(path) → session`

Load an ONNX model file. Returns a session userdata, or `nil, error_message` on failure.

### `session:info() → table`

Returns `{ inputs = {"name1", ...}, outputs = {"name1", ...} }`.

### `session:run(inputs) → outputs`

Run inference.

```lua
local inputs = {
    input_name = {
        dims  = {1, 3, 224, 224},   -- shape (required)
        data  = { ... },             -- flat number array (required)
        dtype = "float",             -- "float" (default) or "int64"
    }
}

local outputs = session:run(inputs)
-- outputs.output_name.dims = {1, 1000}
-- outputs.output_name.data = {0.1, 0.2, ...}
```

**Supported input dtypes:**
- `"float"` (default) — float32
- `"int64"` — for token IDs, indices, etc.

Returns `nil, error_message` on failure.

### `session:close()`

Release the session. Also called automatically on GC.

### `ort.version()` / `ort.VERSION`

Returns the plugin version string (e.g. `"v2"`).

## Build

### Prerequisites

| Platform | Requirements |
|----------|-------------|
| macOS | `brew install onnxruntime`, Solar2D installed |
| Android | Android NDK r27+, run `android/download_ort.sh` first |
| iOS | Xcode, run `ios/download_ort.sh` first |
| Windows | Visual Studio, run `win32/download_ort.ps1` first |

### macOS (Simulator)

```bash
make mac              # build only
make mac-install      # build + install to Simulator Plugins dir
```

Output: `build/mac/plugin_onnxruntime.dylib` (~51KB)

**Important:** The build script uses Solar2D's bundled Lua 5.1 headers (not Homebrew Lua). This is required to avoid ABI mismatch at runtime.

### Android

```bash
make android
```

### iOS

```bash
make ios
```

### Windows

```powershell
cd win32
powershell -File download_ort.ps1
build.bat
```

## Solar2D Project Setup

### build.settings

Prebuilt binaries are available from [GitHub Releases](https://github.com/labolado/solar2d-plugin-onnxruntime/releases). Add to your `build.settings`:

```lua
-- Change "v2" to the latest release tag
local ort_base = "https://github.com/labolado/solar2d-plugin-onnxruntime/releases/download/v2/"

settings = {
    plugins = {
        ["plugin.onnxruntime"] = {
            publisherId = "com.labolado",
            supportedPlatforms = {
                ["mac-sim"]     = { url = ort_base .. "plugin.onnxruntime-mac-sim.tgz" },
                android         = { url = ort_base .. "plugin.onnxruntime-android.tgz" },
                iphone          = { url = ort_base .. "plugin.onnxruntime-iphone.tgz" },
                ["iphone-sim"]  = { url = ort_base .. "plugin.onnxruntime-iphone-sim.tgz" },
                ["win32-sim"]   = { url = ort_base .. "plugin.onnxruntime-win32-sim.tgz" },
            },
        },
    },
}
```

Or build from source and install via `make mac-install` for Simulator testing.

## Example

The `example/` directory contains a combined demo with:
- **Style Transfer** — apply candy/mosaic artistic styles to an image
- **Text-to-Speech** — generate speech from "Hello world" using Kitten TTS Nano

To run: open `example/` as a Solar2D project in the Simulator.

## Architecture

```
plugin_onnxruntime.c          ← single cross-platform C source (~460 lines)
lua/plugin/onnxruntime.lua    ← Lua loader
        │
        ├── mac/build.sh      → .dylib
        ├── android/build.sh  → .so  (arm64 + armv7)
        ├── ios/build.sh      → .a   (device + simulator)
        └── win32/build.bat   → .dll
```

Plugin binary is ~51KB. ONNX Runtime (~8-18MB per platform) is the main size cost.

## Known Issues

- **macOS rpath**: The dylib links to Homebrew's `libonnxruntime.dylib`. For distribution, bundle ORT or fix the rpath with `install_name_tool`.
- **Output dtype**: All outputs are currently read as float32. Int64 outputs are cast to float.

## License

MIT
