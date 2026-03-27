// HTML5 polyfill for plugin.onnxruntime
// Uses onnxruntime-web (CDN) to provide the same API as the native C plugin
// Solar2D JS Module Loader will load this as require("plugin.onnxruntime")

plugin_onnxruntime = {
    _ortLoaded: false,
    _ortLoadCallbacks: [],
    VERSION: "web-v6",

    // Internal: ensure onnxruntime-web is loaded from CDN
    _ensureORT: function(callback) {
        if (this._ortLoaded && typeof ort !== 'undefined') {
            callback();
            return;
        }
        this._ortLoadCallbacks.push(callback);
        if (this._ortLoadCallbacks.length === 1) {
            var self = this;
            var script = document.createElement('script');
            script.src = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.16.3/dist/ort.min.js';
            script.onload = function() {
                self._ortLoaded = true;
                var cbs = self._ortLoadCallbacks;
                self._ortLoadCallbacks = [];
                for (var i = 0; i < cbs.length; i++) cbs[i]();
            };
            script.onerror = function() {
                console.error('[ORT polyfill] Failed to load onnxruntime-web CDN');
            };
            document.head.appendChild(script);
        }
    },

    // load(modelPath) -> session object (async internally, blocks via busy-wait)
    // On HTML5, we store sessions and return a handle
    _sessions: {},
    _nextId: 0,

    load: function(modelPath) {
        // Read model from Emscripten FS
        var modelData = null;
        if (typeof Module !== 'undefined' && Module.FS) {
            var tryPaths = [
                '/' + modelPath,
                modelPath,
                '/coronaResources/' + modelPath
            ];
            for (var i = 0; i < tryPaths.length; i++) {
                try {
                    modelData = Module.FS.readFile(tryPaths[i]);
                    break;
                } catch(e) { continue; }
            }
        }
        if (!modelData) {
            console.error('[ORT polyfill] Model not found:', modelPath);
            return null;
        }

        var id = ++this._nextId;
        var self = this;

        // Start async session creation
        // Store a placeholder - session will be ready by the time run() is called
        this._sessions[id] = { ready: false, session: null, error: null };

        this._ensureORT(function() {
            ort.InferenceSession.create(modelData.buffer, {
                executionProviders: ['wasm']
            }).then(function(session) {
                self._sessions[id].session = session;
                self._sessions[id].ready = true;
                self._sessions[id].inputNames = session.inputNames;
                self._sessions[id].outputNames = session.outputNames;
                console.log('[ORT polyfill] Session ready:', modelPath);
            }).catch(function(err) {
                self._sessions[id].error = err.message;
                self._sessions[id].ready = true;
                console.error('[ORT polyfill] Session create failed:', err);
            });
        });

        // Return session handle
        var handle = {
            _id: id,
            _inputCount: 0,
            _outputCount: 0
        };
        return handle;
    },

    // run(sessionHandle, inputs) -> outputs table
    // inputs = { name = { dims = {}, data = {} } }
    run: function(handle, inputs) {
        var sess = this._sessions[handle._id];
        if (!sess) return null;

        // If session not ready yet, we can't block in JS without Asyncify
        // Return nil and let Lua retry, or return empty
        if (!sess.ready) {
            console.warn('[ORT polyfill] Session not ready yet, inference skipped');
            return null;
        }
        if (sess.error) {
            console.error('[ORT polyfill] Session had error:', sess.error);
            return null;
        }

        var session = sess.session;
        var feeds = {};
        var inputNames = session.inputNames;

        // Convert Lua table inputs to ORT tensors
        // inputs is passed as a JS object from Lua
        for (var i = 0; i < inputNames.length; i++) {
            var name = inputNames[i];
            var inp = inputs[name];
            if (inp) {
                var data = new Float32Array(inp.data);
                var dims = inp.dims;
                feeds[name] = new ort.Tensor('float32', data, dims);
            }
        }

        // Run inference asynchronously, store result
        var resultHolder = { done: false, outputs: null };
        session.run(feeds).then(function(results) {
            var outputs = {};
            for (var name in results) {
                var tensor = results[name];
                outputs[name] = {
                    dims: Array.from(tensor.dims),
                    data: Array.from(tensor.data)
                };
            }
            resultHolder.outputs = outputs;
            resultHolder.done = true;
        }).catch(function(err) {
            console.error('[ORT polyfill] run error:', err);
            resultHolder.done = true;
        });

        // NOTE: This returns null immediately since we can't block.
        // The Lua side needs to handle async results via timer polling.
        // For now, return null and log a message.
        console.warn('[ORT polyfill] run() is async on HTML5 - result not available synchronously');
        return null;
    },

    // close(sessionHandle) -> release session
    close: function(handle) {
        var sess = this._sessions[handle._id];
        if (sess && sess.session) {
            sess.session.release();
        }
        delete this._sessions[handle._id];
    }
};
