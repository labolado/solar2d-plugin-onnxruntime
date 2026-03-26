-- plugin/onnxruntime.lua — Solar2D ONNX Runtime plugin (HTML5 version)
-- 
-- This is the HTML5/JS bridge version of the plugin that uses onnxruntime-web.
-- Due to the async nature of web APIs, this version uses callbacks unlike
-- the synchronous native plugin.
--
-- Usage:
--   local ort = require("plugin.onnxruntime")
--   
--   -- Load model (async)
--   ort.load("model.onnx", function(session, error)
--       if error then
--           print("Failed to load:", error)
--           return
--       end
--       
--       -- Run inference (async)
--       local inputs = {
--           input = {
--               dims = {1, 3, 224, 224},
--               data = {...}  -- flat array of numbers
--           }
--       }
--       session:run(inputs, function(outputs, error)
--           if error then
--               print("Inference failed:", error)
--               return
--       end
--           
--           -- Process outputs
--           print(outputs.output.dims[1])
--           for i, v in ipairs(outputs.output.data) do
--               print(i, v)
--           end
--           
--           session:close()
--       end)
--   end)

local lib = {}

-- Platform detection
local isHTML5 = (system.getInfo("platform") == 'html5')

-- For HTML5, we load the JS plugin; otherwise return dummy implementation
if isHTML5 then
    -- Load the JS implementation
    local js = require("plugin_onnxruntime_js")
    
    -- Session metatable for method-style calls
    local SessionMT = {
        __index = {
            run = function(self, inputs, callback)
                if type(inputs) ~= "table" then
                    error("inputs must be a table")
                end
                if type(callback) ~= "function" then
                    error("callback must be a function")
                end
                js.run(self._handle, inputs, callback)
            end,
            
            close = function(self)
                js.close(self._handle)
                self._handle = nil
            end,
            
            info = function(self)
                return js.info(self._handle)
            end,
            
            -- For debugging
            __tostring = function(self)
                local info = js.info(self._handle)
                if info then
                    return string.format("OrtSession(%d inputs, %d outputs)",
                        #info.inputs, #info.outputs)
                else
                    return "OrtSession(closed)"
                end
            end
        }
    }
    
    -- Create a session object from handle
    local function createSession(handle)
        local session = {
            _handle = handle
        }
        setmetatable(session, SessionMT)
        return session
    end
    
    -- Module functions
    lib.load = function(modelPath, optsOrCallback, maybeCallback)
        -- Handle optional opts parameter
        local opts = nil
        local callback = nil
        
        if type(optsOrCallback) == "function" then
            -- load(modelPath, callback)
            callback = optsOrCallback
        elseif type(optsOrCallback) == "table" then
            -- load(modelPath, opts, callback)
            opts = optsOrCallback
            callback = maybeCallback
        elseif type(maybeCallback) == "function" then
            -- load(modelPath, nil, callback)
            callback = maybeCallback
        end
        
        if type(callback) ~= "function" then
            error("load() requires a callback function")
        end
        
        -- Wrap the callback to convert handle to session object
        local wrappedCallback = function(handle, error)
            if error then
                callback(nil, error)
            else
                local session = createSession(handle)
                callback(session, nil)
            end
        end
        
        js.load(modelPath, wrappedCallback, opts)
    end
    
    lib.version = function()
        return js.version()
    end
    
    -- Check if onnxruntime-web is available
    lib.isAvailable = function()
        return js.isAvailable()
    end
    
else
    -- Dummy implementation for simulator/non-HTML5 platforms
    -- Returns placeholder functions that print warnings
    
    local dummySession = {
        run = function(self, inputs, callback)
            print("WARNING: onnxruntime plugin is not available on this platform")
            if type(callback) == "function" then
                callback(nil, "Plugin not available on this platform")
            end
        end,
        close = function(self)
            -- no-op
        end,
        info = function(self)
            return {inputs = {}, outputs = {}}
        end
    }
    
    setmetatable(dummySession, {
        __tostring = function() return "OrtSession(dummy)" end
    })
    
    lib.load = function(modelPath, optsOrCallback, maybeCallback)
        print("WARNING: onnxruntime plugin is not available on this platform")
        print("         (requires HTML5 build with onnxruntime-web)")
        
        -- Extract callback
        local callback = nil
        if type(optsOrCallback) == "function" then
            callback = optsOrCallback
        elseif type(maybeCallback) == "function" then
            callback = maybeCallback
        end
        
        if callback then
            -- Schedule callback on next frame to mimic async behavior
            timer.performWithDelay(1, function()
                callback(dummySession, nil)
            end)
        end
        
        return dummySession
    end
    
    lib.version = function()
        return "0.0.0-dummy"
    end
    
    lib.isAvailable = function()
        return false
    end
end

-- Version constant
lib.VERSION = lib.version()

return lib
