// HTML5 polyfill for plugin.Bytemap
// Implements loadTexture and newTexture using Canvas API
// Only loaded on HTML5 builds (Solar2D JS Module Loader)

plugin_Bytemap = {
    _nextId: 0,
    _textures: {},

    // loadTexture({ filename, baseDir }) -> texture object
    // Reads PNG from Emscripten virtual filesystem, decodes via Canvas
    loadTexture: function(opts) {
        try {
            var filename = opts.filename || opts[1];
            var baseDir = opts.baseDir;

            // Read file from Emscripten FS
            var path = filename;
            if (typeof Module !== 'undefined' && Module.FS) {
                // Try common resource paths
                var tryPaths = [
                    '/' + filename,
                    '/coronaResources/' + filename,
                    filename
                ];
                var data = null;
                for (var i = 0; i < tryPaths.length; i++) {
                    try {
                        data = Module.FS.readFile(tryPaths[i]);
                        break;
                    } catch(e) { continue; }
                }
                if (!data) return null;

                // Decode PNG using Canvas
                var blob = new Blob([data], {type: 'image/png'});
                var url = URL.createObjectURL(blob);
                var img = new Image();
                img.src = url;

                // Synchronous decode trick: draw to canvas immediately
                // This works because the image data is already in memory (from blob URL)
                var canvas = document.createElement('canvas');
                var ctx = canvas.getContext('2d');

                // We need synchronous decode - use a hidden canvas with known dimensions
                // For PNG, we can parse dimensions from header
                var w = (data[16] << 24) | (data[17] << 16) | (data[18] << 8) | data[19];
                var h = (data[20] << 24) | (data[21] << 16) | (data[22] << 8) | data[23];

                canvas.width = w;
                canvas.height = h;

                // Use createImageBitmap for sync-ish decode if available
                // Fallback: store raw data and decode on GetBytes
                var id = ++this._nextId;
                this._textures[id] = {
                    width: w,
                    height: h,
                    pngData: data,
                    canvas: canvas,
                    ctx: ctx,
                    decoded: false,
                    blobUrl: url
                };

                // Start async decode (will be ready by the time GetBytes is called)
                var self = this;
                img.onload = function() {
                    var tex = self._textures[id];
                    if (tex) {
                        tex.ctx.drawImage(img, 0, 0);
                        tex.decoded = true;
                        URL.revokeObjectURL(url);
                    }
                };

                return {
                    _id: id,
                    width: w,
                    height: h
                };
            }
            return null;
        } catch(e) {
            console.error('[Bytemap polyfill] loadTexture error:', e);
            return null;
        }
    },

    // GetBytes(textureRef) -> pixel data as string (RGBA)
    GetBytes: function(ref) {
        var tex = this._textures[ref._id];
        if (!tex) return null;

        // If not decoded yet, do sync decode via drawing
        if (!tex.decoded) {
            // Fallback: use a synchronous XMLHttpRequest to decode
            // Or try to decode PNG manually for the pixel data
            // Simple approach: create temp image and draw
            var img = new Image();
            img.src = tex.blobUrl;
            try {
                tex.ctx.drawImage(img, 0, 0);
                tex.decoded = true;
            } catch(e) {
                // Image not loaded yet, try raw pixel extraction
                console.warn('[Bytemap polyfill] sync decode failed, using blank');
                return null;
            }
        }

        var imageData = tex.ctx.getImageData(0, 0, tex.width, tex.height);
        var pixels = imageData.data; // Uint8ClampedArray RGBA

        // Convert to string (Lua expects binary string)
        var result = '';
        for (var i = 0; i < pixels.length; i++) {
            result += String.fromCharCode(pixels[i]);
        }
        return result;
    },

    // releaseSelf(textureRef) -> free memory
    releaseSelf: function(ref) {
        var tex = this._textures[ref._id];
        if (tex) {
            if (tex.blobUrl) URL.revokeObjectURL(tex.blobUrl);
            delete this._textures[ref._id];
        }
    },

    // newTexture({ width, height, componentCount }) -> texture object
    newTexture: function(opts) {
        var w = opts.width || opts[1];
        var h = opts.height || opts[2];
        var comp = opts.componentCount || 4;

        var canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h;
        var ctx = canvas.getContext('2d');

        var id = ++this._nextId;
        this._textures[id] = {
            width: w,
            height: h,
            componentCount: comp,
            canvas: canvas,
            ctx: ctx
        };

        // Generate a unique filename for Solar2D display system
        var filename = '_bytemap_tex_' + id + '.png';

        return {
            _id: id,
            width: w,
            height: h,
            filename: filename,
            baseDir: null // Will be handled specially
        };
    },

    // SetBytes(textureRef, data) -> write pixel data
    SetBytes: function(ref, data) {
        var tex = this._textures[ref._id];
        if (!tex) return;

        var w = tex.width;
        var h = tex.height;
        var imageData = tex.ctx.createImageData(w, h);
        var pixels = imageData.data;

        // data is a Lua string of RGBA bytes
        for (var i = 0; i < Math.min(data.length, pixels.length); i++) {
            pixels[i] = data.charCodeAt(i);
        }

        tex.ctx.putImageData(imageData, 0, 0);

        // Save as data URL for Solar2D display.newImage
        var dataUrl = tex.canvas.toDataURL('image/png');

        // Write to Emscripten FS so display.newImage can find it
        if (typeof Module !== 'undefined' && Module.FS) {
            try {
                var binary = atob(dataUrl.split(',')[1]);
                var array = new Uint8Array(binary.length);
                for (var j = 0; j < binary.length; j++) {
                    array[j] = binary.charCodeAt(j);
                }
                Module.FS.writeFile('/' + ref.filename, array);
            } catch(e) {
                console.error('[Bytemap polyfill] SetBytes FS write error:', e);
            }
        }
    }
};
