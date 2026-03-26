/**
 * plugin_onnxruntime_js.js — Solar2D HTML5 plugin for ONNX Runtime Web
 * 
 * This plugin bridges Lua to onnxruntime-web for HTML5 builds.
 * Due to the async nature of Web APIs, the interface uses callbacks
 * unlike the synchronous native plugin.
 * 
 * JS API (called from Lua):
 *   load(modelPath, callback) - Load model, callback(sessionHandle)
 *   run(sessionHandle, inputs, callback) - Run inference, callback(outputs)
 *   close(sessionHandle) - Release session
 *   version() - Return version string
 * 
 * Requires: onnxruntime-web loaded via script tag:
 *   <script src="https://cdn.jsdelivr.net/npm/onnxruntime-web/dist/ort.min.js"></script>
 */

plugin_onnxruntime_js = {
    // Internal session storage
    _sessions: {},
    _sessionCounter: 0,
    _ort: null,

    /**
     * Initialize and check for onnxruntime-web
     */
    _init: function() {
        if (typeof ort !== 'undefined') {
            this._ort = ort;
            return true;
        }
        console.error('[ort] onnxruntime-web not found. Please include:');
        console.error('[ort] <script src="https://cdn.jsdelivr.net/npm/onnxruntime-web/dist/ort.min.js"></script>');
        return false;
    },

    /**
     * Convert Lua input format to onnxruntime-web Tensor
     * Lua format: { dims = {...}, data = {...}, type = "float32" }
     * or binary: { dims = {...}, data_binary = "...", type = "float32" }
     */
    _createTensor: function(inputSpec) {
        if (!this._ort) {
            throw new Error('onnxruntime-web not initialized');
        }

        var dims = inputSpec.dims;
        var data = inputSpec.data;
        var dataBinary = inputSpec.data_binary;
        var type = inputSpec.type || 'float32';

        // Convert dims to regular array if it's a Lua table
        var shape = [];
        if (typeof dims === 'object' && dims !== null) {
            for (var i = 1; dims[i] !== undefined; i++) {
                shape.push(dims[i]);
            }
        }

        // Calculate total size
        var totalSize = 1;
        for (var i = 0; i < shape.length; i++) {
            totalSize *= shape[i];
        }

        // Create typed array based on data or data_binary
        var typedArray;
        if (dataBinary !== undefined && typeof dataBinary === 'string') {
            // Binary string format - convert to Float32Array
            var buffer = new ArrayBuffer(dataBinary.length);
            var view = new Uint8Array(buffer);
            for (var i = 0; i < dataBinary.length; i++) {
                view[i] = dataBinary.charCodeAt(i) & 0xFF;
            }
            typedArray = new Float32Array(buffer);
        } else if (typeof data === 'object' && data !== null) {
            // Table format - convert to typed array
            var arr = [];
            for (var i = 1; data[i] !== undefined; i++) {
                arr.push(data[i]);
            }
            
            // Create appropriate typed array based on type
            switch(type) {
                case 'float64':
                    typedArray = new Float64Array(arr);
                    break;
                case 'int32':
                    typedArray = new Int32Array(arr);
                    break;
                case 'int64':
                    // JavaScript doesn't have native int64, use BigInt64Array if available
                    if (typeof BigInt64Array !== 'undefined') {
                        typedArray = new BigInt64Array(arr.map(function(x) { return BigInt(x); }));
                    } else {
                        // Fallback to regular array with numbers
                        typedArray = arr;
                    }
                    break;
                case 'uint8':
                    typedArray = new Uint8Array(arr);
                    break;
                case 'float32':
                default:
                    typedArray = new Float32Array(arr);
                    break;
            }
        } else {
            throw new Error('Invalid input data format');
        }

        return new this._ort.Tensor(type, typedArray, shape);
    },

    /**
     * Convert onnxruntime-web output Tensor to Lua format
     * Returns: { dims = {...}, data = {...}, data_binary = "..." }
     */
    _tensorToLua: function(tensor) {
        var result = {
            dims: {},
            data: {},
            data_binary: ""
        };

        // Convert dims to Lua 1-indexed table
        for (var i = 0; i < tensor.dims.length; i++) {
            result.dims[i + 1] = tensor.dims[i];
        }

        // Convert data to Lua 1-indexed table
        var dataArray = Array.from(tensor.data);
        for (var i = 0; i < dataArray.length; i++) {
            // Convert BigInt to Number if needed
            result.data[i + 1] = typeof dataArray[i] === 'bigint' ? Number(dataArray[i]) : dataArray[i];
        }

        // Create binary string (for large tensors, more efficient)
        if (tensor.data instanceof Float32Array) {
            var bytes = new Uint8Array(tensor.data.buffer);
            var binary = '';
            for (var i = 0; i < bytes.length; i++) {
                binary += String.fromCharCode(bytes[i]);
            }
            result.data_binary = binary;
        }

        return result;
    },

    /**
     * Load an ONNX model and create a session
     * 
     * @param {string} modelPath - Path to .onnx model file (relative to index.html)
     * @param {function} callbackRef - Lua callback function reference (optional)
     * @param {table} opts - Options table with executionProviders, etc. (optional)
     * 
     * Lua usage:
     *   ort.load("model.onnx", function(session, error)
     *       if session then ... end
     *   end)
     */
    load: function(modelPath, callbackRef, opts) {
        var self = this;

        if (!this._ort && !this._init()) {
            if (LuaIsFunction(callbackRef)) {
                var cb = LuaCreateFunction(callbackRef);
                cb(null, "onnxruntime-web not available");
                LuaReleaseFunction(cb);
            }
            return;
        }

        // Parse options
        var sessionOptions = {};
        if (typeof opts === 'object' && opts !== null) {
            // Map execution provider
            if (opts.ep) {
                switch(opts.ep) {
                    case 'webgpu':
                        sessionOptions.executionProviders = ['webgpu', 'wasm'];
                        break;
                    case 'webgl':
                        sessionOptions.executionProviders = ['webgl', 'wasm'];
                        break;
                    default:
                        sessionOptions.executionProviders = ['wasm'];
                }
            }
            // Thread count
            if (opts.intraOpNumThreads) {
                sessionOptions.intraOpNumThreads = opts.intraOpNumThreads;
            }
        }

        // Default to wasm if not specified
        if (!sessionOptions.executionProviders) {
            sessionOptions.executionProviders = ['wasm'];
        }

        // Create callback function if provided
        var callback = null;
        if (LuaIsFunction(callbackRef)) {
            callback = LuaCreateFunction(callbackRef);
        }

        // Load the model
        this._ort.InferenceSession.create(modelPath, sessionOptions)
            .then(function(session) {
                var handle = ++self._sessionCounter;
                self._sessions[handle] = {
                    session: session,
                    inputNames: session.inputNames,
                    outputNames: session.outputNames
                };

                if (callback) {
                    callback(handle, null);
                    LuaReleaseFunction(callback);
                }
            })
            .catch(function(error) {
                console.error('[ort] Failed to load model:', error);
                if (callback) {
                    callback(null, error.toString());
                    LuaReleaseFunction(callback);
                }
            });
    },

    /**
     * Run inference on a session
     * 
     * @param {number} sessionHandle - Session handle from load()
     * @param {table} inputs - Input tensors as {inputName = {dims={}, data={}}}
     * @param {function} callbackRef - Lua callback function reference
     * 
     * Lua usage:
     *   session:run({input = {dims={1,3,224,224}, data={...}}}, function(outputs, error)
     *       -- outputs = {outputName = {dims={}, data={}, data_binary=""}}
     *   end)
     */
    run: function(sessionHandle, inputs, callbackRef) {
        var self = this;

        var sessionData = this._sessions[sessionHandle];
        if (!sessionData) {
            if (LuaIsFunction(callbackRef)) {
                var cb = LuaCreateFunction(callbackRef);
                cb(null, "Invalid session handle");
                LuaReleaseFunction(cb);
            }
            return;
        }

        // Convert Lua inputs to ort Tensors
        var feeds = {};
        try {
            for (var inputName in inputs) {
                if (inputs.hasOwnProperty(inputName)) {
                    feeds[inputName] = this._createTensor(inputs[inputName]);
                }
            }
        } catch (error) {
            console.error('[ort] Failed to create input tensor:', error);
            if (LuaIsFunction(callbackRef)) {
                var cb = LuaCreateFunction(callbackRef);
                cb(null, error.toString());
                LuaReleaseFunction(cb);
            }
            return;
        }

        // Create callback
        var callback = null;
        if (LuaIsFunction(callbackRef)) {
            callback = LuaCreateFunction(callbackRef);
        }

        // Run inference
        sessionData.session.run(feeds)
            .then(function(results) {
                // Convert outputs to Lua format
                var outputs = {};
                for (var outputName in results) {
                    if (results.hasOwnProperty(outputName)) {
                        outputs[outputName] = self._tensorToLua(results[outputName]);
                    }
                }

                if (callback) {
                    callback(outputs, null);
                    LuaReleaseFunction(callback);
                }
            })
            .catch(function(error) {
                console.error('[ort] Inference failed:', error);
                if (callback) {
                    callback(null, error.toString());
                    LuaReleaseFunction(callback);
                }
            });
    },

    /**
     * Get session info (input/output names)
     * 
     * @param {number} sessionHandle - Session handle from load()
     * @returns {table} - {inputs = {...}, outputs = {...}}
     */
    info: function(sessionHandle) {
        var sessionData = this._sessions[sessionHandle];
        if (!sessionData) {
            return null;
        }

        var result = {
            inputs: {},
            outputs: {}
        };

        for (var i = 0; i < sessionData.inputNames.length; i++) {
            result.inputs[i + 1] = sessionData.inputNames[i];
        }

        for (var i = 0; i < sessionData.outputNames.length; i++) {
            result.outputs[i + 1] = sessionData.outputNames[i];
        }

        return result;
    },

    /**
     * Close a session and free resources
     * 
     * @param {number} sessionHandle - Session handle from load()
     */
    close: function(sessionHandle) {
        var sessionData = this._sessions[sessionHandle];
        if (sessionData) {
            // Session will be garbage collected
            delete this._sessions[sessionHandle];
        }
    },

    /**
     * Get plugin version
     * @returns {string}
     */
    version: function() {
        return "0.1.0-web";
    },

    /**
     * Check if onnxruntime-web is available
     * @returns {boolean}
     */
    isAvailable: function() {
        return this._init();
    }
};
