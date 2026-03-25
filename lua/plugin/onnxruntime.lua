-- plugin/onnxruntime.lua — Lua wrapper for the ONNX Runtime native plugin.
-- Falls back to native C implementation; this file just re-exports it.

local lib = require("plugin_onnxruntime")  -- loads the native .dylib/.so

return lib
