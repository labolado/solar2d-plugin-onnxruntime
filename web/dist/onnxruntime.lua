-- plugin/onnxruntime.lua — Solar2D HTML5 (Web) bridge for ONNX Runtime
-- Loads the WASM module and provides Lua API compatible with native plugin

local M = {}

-- Internal state
local js = nil
local ortModule = nil
local isReady = false
local pendingCalls = {}

-- Initialize the plugin
local function init()
    if isReady then return true end
    
    -- Check if we're in HTML5 environment
    if not system or system.getInfo("platform") ~= "html5" then
        print("[ORT] Warning: Not in HTML5 environment")
        return false
    end
    
    -- Load JavaScript bridge
    js = require("plugin_js")
    if not js then
        print("[ORT] Error: plugin_js not available")
        return false
    end
    
    -- Load the WASM module via JavaScript
    -- The WASM file should be in the same directory as this Lua file
    local wasmPath = "plugins/onnxruntime/onnxruntime_plugin.wasm"
    local jsPath = "plugins/onnxruntime/onnxruntime_plugin.js"
    
    -- Evaluate the JS wrapper
    local success = js.eval([
        (function() {
            // Load the Emscripten module
            var script = document.createElement('script');
            script.src = '" .. jsPath .. "';
            script.async = false;
            script.onload = function() {
                // Module is loaded, initialize it
                OrtPlugin().then(function(module) {
                    window.ortWasmModule = module;
                    // Notify Lua that we're ready
                    if (window.ortLuaCallbacks && window.ortLuaCallbacks.onReady) {
                        window.ortLuaCallbacks.onReady();
                    }
                }).catch(function(err) {
                    console.error('[ORT] Failed to load WASM:', err);
                    if (window.ortLuaCallbacks && window.ortLuaCallbacks.onError) {
                        window.ortLuaCallbacks.onError(err.toString());
                    }
                });
            };
            script.onerror = function(err) {
                console.error('[ORT] Failed to load script:', err);
                if (window.ortLuaCallbacks && window.ortLuaCallbacks.onError) {
                    window.ortLuaCallbacks.onError('Failed to load script');
                }
            };
            document.head.appendChild(script);
            return true;
        })();
    ])
    
    return success
end

-- Set up callbacks from JavaScript
local function setupCallbacks()
    if not js then return end
    
    js.setListener(function(event)
        if event.type == "ortReady" then
            isReady = true
            ortModule = window.ortWasmModule
            -- Process any pending calls
            for _, call in ipairs(pendingCalls) do
                call()
            end
            pendingCalls = {}
        elseif event.type == "ortError" then
            print("[ORT] Error: " .. tostring(event.message))
        end
    end)
end

-- Load a model (async)
function M.load(modelPath, opts)
    opts = opts or {}
    
    if not init() then
        return nil, "Failed to initialize ORT"
    end
    
    -- For HTML5, we need to fetch the model file first
    -- The model should be in the app's resource directory
    local function doLoad()
        -- This will be called once WASM is ready
        -- For now, return a placeholder session object
        return {
            path = modelPath,
            opts = opts,
            -- Session methods will be implemented via JS bridge
        }
    end
    
    if isReady then
        return doLoad()
    else
        -- Queue the call
        table.insert(pendingCalls, doLoad)
        return {
            _pending = true,
            path = modelPath,
            opts = opts,
        }
    end
end

-- Run inference (stub for now)
function M.run(session, inputs)
    if not isReady then
        return nil, "ORT not ready"
    end
    
    -- TODO: Implement via JS bridge
    -- This would call into the WASM module
    print("[ORT] run() called (not yet implemented for HTML5)")
    return {}
end

-- Close session (stub for now)
function M.close(session)
    -- TODO: Implement via JS bridge
    print("[ORT] close() called (not yet implemented for HTML5)")
end

-- Version
M._VERSION = "0.1.0-web"

-- Auto-init on load
setupCallbacks()

return M
