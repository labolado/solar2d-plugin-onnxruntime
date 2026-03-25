-- ONNX Runtime Plugin Demo — Style Transfer + TTS
-- Combined demo showcasing two ONNX models in Solar2D

local Bytemap = require("plugin.Bytemap")
local ort = require("plugin.onnxruntime")

display.setDefault("background", 0.1, 0.1, 0.12)

local SIZE = 224
local sampleRate = 24000

-- ============================================================
-- UI Setup
-- ============================================================

-- Title
display.newText({
    text = "ONNX Runtime Demo",
    x = display.contentCenterX, y = 22,
    font = native.systemFontBold, fontSize = 20
})

-- Divider
local divY = 215
local divLine = display.newLine(10, divY, display.contentWidth - 10, divY)
divLine:setStrokeColor(0.3)
divLine.strokeWidth = 1

-- Section labels
display.newText({
    text = "Style Transfer",
    x = display.contentCenterX, y = 42,
    font = native.systemFontBold, fontSize = 14
}):setFillColor(0.6, 0.8, 1)

display.newText({
    text = "Text-to-Speech (Kitten TTS Nano)",
    x = display.contentCenterX, y = divY + 16,
    font = native.systemFontBold, fontSize = 14
}):setFillColor(0.6, 0.8, 1)

-- ============================================================
-- Style Transfer Section (top half)
-- ============================================================
local styleSession
local styledImage
local styleStatus = display.newText({
    text = "Tap a style button",
    x = display.contentCenterX, y = 190,
    font = native.systemFont, fontSize = 12
})
local styleTime = display.newText({
    text = "",
    x = display.contentCenterX, y = 203,
    font = native.systemFont, fontSize = 11
})
styleTime:setFillColor(0.3, 1, 0.3)

-- Original image
local originalImage = display.newImage("test_photo.png", system.ResourceDirectory)
if originalImage then
    originalImage.x = display.contentCenterX - 110
    originalImage.y = 120
    originalImage.width = 150
    originalImage.height = 150
end

display.newText("Original", display.contentCenterX - 110, 58, native.systemFont, 10)
display.newText("Styled", display.contentCenterX + 110, 58, native.systemFont, 10)

-- Arrow
display.newText({
    text = "->",
    x = display.contentCenterX,
    y = 120,
    font = native.systemFontBold, fontSize = 24
})

local function imageToTensor(path)
    local bm = Bytemap.loadTexture({ filename = path, baseDir = system.ResourceDirectory })
    if not bm then return nil end
    local w, h = bm.width, bm.height
    local byteStr = bm:GetBytes()
    bm:releaseSelf()
    if type(byteStr) ~= "string" then return nil end
    local comp = #byteStr / (w * h)
    local data = {}
    local idx = 1
    for c = 0, 2 do
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                data[idx] = string.byte(byteStr, (y * w + x) * comp + c + 1)
                idx = idx + 1
            end
        end
    end
    return data
end

local function tensorToImage(tensorData, w, h)
    local bm = Bytemap.newTexture({ width = w, height = h, componentCount = 4 })
    local chars = {}
    local chSize = w * h
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local pi = y * w + x
            local r = math.max(0, math.min(255, math.floor(tensorData[pi + 1] + 0.5)))
            local g = math.max(0, math.min(255, math.floor(tensorData[chSize + pi + 1] + 0.5)))
            local b = math.max(0, math.min(255, math.floor(tensorData[2 * chSize + pi + 1] + 0.5)))
            chars[#chars + 1] = string.char(r, g, b, 255)
        end
    end
    bm:SetBytes(table.concat(chars))
    return display.newImage(bm.filename, bm.baseDir), bm
end

local function runStyleTransfer(styleName)
    styleStatus.text = "Loading " .. styleName .. "..."
    timer.performWithDelay(50, function()
        local modelPath = system.pathForFile(styleName .. ".onnx", system.ResourceDirectory)
        if not modelPath then styleStatus.text = "Model not found"; return end

        if styleSession then styleSession:close(); styleSession = nil end
        styleSession = ort.load(modelPath)
        if not styleSession then styleStatus.text = "Load failed"; return end

        local inputData = imageToTensor("test_photo.png")
        if not inputData then styleStatus.text = "Image error"; return end

        styleStatus.text = "Running inference..."
        local t0 = system.getTimer()
        local outputs = styleSession:run({
            input1 = { dims = {1, 3, SIZE, SIZE}, data = inputData }
        })
        local elapsed = system.getTimer() - t0
        styleTime.text = string.format("%.0f ms", elapsed)

        if outputs and outputs.output1 then
            styleStatus.text = styleName .. " applied!"
            if styledImage then styledImage:removeSelf() end
            local img = tensorToImage(outputs.output1.data, SIZE, SIZE)
            if img then
                img.x = display.contentCenterX + 110
                img.y = 120
                img.width = 150
                img.height = 150
                styledImage = img
            end
        else
            styleStatus.text = "Inference failed"
        end
    end)
end

-- Style buttons
local styles = { "candy", "mosaic" }
for i, style in ipairs(styles) do
    local bx = display.contentCenterX - 140 + (i - 1) * 120
    local by = 120
    local btn = display.newRoundedRect(bx, by, 50, 24, 4)
    btn:setFillColor(0.2, 0.5, 0.9)
    display.newText({ text = style, x = bx, y = by, font = native.systemFontBold, fontSize = 11 })
    btn:addEventListener("tap", function() runStyleTransfer(style); return true end)
end

-- ============================================================
-- TTS Section (bottom half)
-- ============================================================

-- "Hello world" phonemized: həlˈoʊ wˈɜːld
local ttsTokens = {50, 83, 54, 156, 57, 135, 16, 65, 156, 87, 158, 54, 46, 16}

-- Full voice embedding for "expr-voice-5-m" (256 floats)
local voiceEmbedding = {
    0.0643, -0.0792, -0.2220, -0.1497, -0.3155, 0.2467, -0.1455, 0.2083,
    0.0414, 0.1680, -0.0345, -0.0507, -0.1308, 0.2285, -0.0593, 0.2741,
    0.3588, 0.0572, -0.1070, -0.3027, 0.0465, -0.0847, -0.1208, 0.0042,
    -0.0829, -0.0756, 0.1118, -0.1105, 0.2805, -0.0467, 0.0278, -0.1963,
    0.0695, -0.0298, -0.2324, 0.3554, 0.1181, 0.1462, -0.1455, 0.1023,
    -0.0833, -0.2597, -0.0726, -0.1688, -0.0563, -0.5985, -0.0676, 0.0615,
    0.0905, 0.0056, 0.0929, 0.0585, 0.0201, -0.0952, -0.1835, -0.1454,
    -0.0486, -0.1923, 0.2859, 0.1279, 0.1921, -0.1331, -0.4356, -0.0936,
    0.1249, 0.1274, -0.0133, 0.1086, -0.0842, 0.0075, 0.0719, 0.0484,
    -0.0975, 0.1561, 0.1113, -0.1754, 0.1355, 0.2520, -0.1904, 0.2064,
    -0.0576, -0.0231, 0.0557, 0.3383, -0.0921, 0.1088, -0.2608, -0.3474,
    0.0933, 0.1999, -0.2839, -0.1822, -0.1179, -0.1342, 0.0464, -0.2794,
    -0.1080, -0.0662, -0.2493, -0.1445, 0.1313, -0.2196, 0.2302, -0.1921,
    -0.3196, 0.2378, 0.2966, 0.1031, -0.2060, -0.0511, 0.0156, -0.0656,
    0.3345, 0.2629, 0.1129, -0.0885, 0.1783, -0.1098, -0.0855, 0.0275,
    -0.2990, -0.1368, -0.1838, -0.1299, 0.1139, 0.2291, -0.1169, -0.0255,
    -0.0755, -0.1760, 0.1828, 0.3520, -0.0453, 0.3366, 0.0102, 0.0100,
    0.1291, 0.1388, -0.1507, 0.0183, -0.0566, 0.0218, 0.0022, 0.1979,
    -0.1695, 0.1028, 0.0725, 0.0306, 0.1928, -0.0847, 0.1697, 0.3454,
    -0.0881, 0.0499, 0.0659, 0.0143, -0.0155, 0.0097, 0.0487, -0.1845,
    0.0458, -0.2232, -0.3231, 0.0702, -0.1057, -0.1611, 0.0677, 0.2812,
    -0.2465, -0.4122, -0.3338, -0.1887, -0.1504, -0.4796, -0.2739, -0.1521,
    -0.6470, 0.0193, 0.1745, 0.1714, 0.1440, -0.1489, -0.1848, -0.0802,
    0.5966, -0.2108, 0.2619, 0.0274, 0.1689, -0.2530, -0.2073, -0.1157,
    0.1559, -0.0569, 0.0778, 0.0323, 0.0173, 0.1412, 0.1590, 0.1099,
    0.1847, -0.0813, -0.1710, -0.0294, -0.0719, 0.2866, -0.1210, 0.0081,
    0.2542, -0.0647, -0.0305, 0.2158, -0.0022, 0.2196, -0.1007, 0.1645,
    0.1361, 0.0662, -0.0101, -0.0130, 0.3553, -0.2462, 0.1478, 0.0108,
    -0.3128, -0.1486, -0.2269, -0.1461, 0.1666, 0.3575, 0.1631, -0.2062,
    0.1954, 0.1268, 0.1655, 0.0667, -0.1810, -0.1781, 0.1197, -0.1398,
    0.4355, 0.1143, -0.0430, -0.1950, -0.3901, -0.0969, 0.0001, 0.0549,
    0.0720, 0.1461, 0.2053, 0.0024, -0.0197, 0.2478, -0.1094, -0.2614
}

local ttsStatus = display.newText({
    text = "Tap to speak",
    x = display.contentCenterX, y = divY + 50,
    font = native.systemFont, fontSize = 12
})
local ttsTime = display.newText({
    text = "",
    x = display.contentCenterX, y = divY + 65,
    font = native.systemFont, fontSize = 11
})
ttsTime:setFillColor(0.3, 1, 0.3)

-- Waveform display
local waveGroup = display.newGroup()
waveGroup.x = display.contentCenterX - 200
waveGroup.y = divY + 110

-- WAV writing helpers (Lua 5.1 compatible)
local function byte0(v) return v % 256 end
local function byte1(v) return math.floor(v / 256) % 256 end
local function byte2(v) return math.floor(v / 65536) % 256 end
local function byte3(v) return math.floor(v / 16777216) % 256 end

local function writeLE16(f, value) f:write(string.char(byte0(value), byte1(value))) end
local function writeLE32(f, value) f:write(string.char(byte0(value), byte1(value), byte2(value), byte3(value))) end

local function writeWav(filename, samples, numSamples)
    local f = io.open(filename, "wb")
    if not f then return false end
    local pcmData = {}
    for i = 1, numSamples do
        local sample = math.max(-1.0, math.min(1.0, samples[i] or 0))
        local pcm = math.floor(sample * 32767 + 0.5)
        if pcm < 0 then pcm = pcm + 65536 end
        pcmData[i] = string.char(pcm % 256, math.floor(pcm / 256) % 256)
    end
    local dataSize = numSamples * 2
    f:write("RIFF"); writeLE32(f, 36 + dataSize); f:write("WAVE")
    f:write("fmt "); writeLE32(f, 16); writeLE16(f, 1); writeLE16(f, 1)
    writeLE32(f, sampleRate); writeLE32(f, sampleRate * 2); writeLE16(f, 2); writeLE16(f, 16)
    f:write("data"); writeLE32(f, dataSize)
    for i = 1, numSamples do f:write(pcmData[i]) end
    f:close()
    return true
end

local function drawWaveform(samples, numSamples)
    for i = waveGroup.numChildren, 1, -1 do waveGroup[i]:removeSelf() end
    local w, h = 400, 60
    local bg = display.newRect(waveGroup, w/2, h/2, w, h)
    bg:setFillColor(0.15, 0.15, 0.18)
    bg.strokeWidth = 1; bg:setStrokeColor(0.3)
    local step = math.max(1, math.floor(numSamples / w))
    local points = {}
    for i = 0, w - 1 do
        local si = i * step + 1
        local maxVal = 0
        for j = si, math.min(si + step - 1, numSamples) do
            local v = math.abs(samples[j] or 0)
            if v > maxVal then maxVal = v end
        end
        points[#points + 1] = { x = i, y = h/2 - maxVal * h/2 }
        points[#points + 1] = { x = i, y = h/2 + maxVal * h/2 }
    end
    for i = 1, #points - 1, 2 do
        local line = display.newLine(waveGroup, points[i].x, points[i].y, points[i].x, points[i+1].y)
        line:setStrokeColor(0.3, 0.8, 0.4, 0.8)
        line.strokeWidth = 1
    end
end

local function runTTS()
    ttsStatus.text = "Loading model..."
    timer.performWithDelay(50, function()
        local modelPath = system.pathForFile("kitten_tts_nano_v0_1.onnx", system.ResourceDirectory)
        if not modelPath then ttsStatus.text = "Model not found"; return end

        local session = ort.load(modelPath)
        if not session then ttsStatus.text = "Load failed"; return end

        ttsStatus.text = "Running inference..."
        local t0 = system.getTimer()
        local outputs = session:run({
            input_ids = { dims = {1, #ttsTokens}, data = ttsTokens, dtype = "int64" },
            style = { dims = {1, 256}, data = voiceEmbedding },
            speed = { dims = {1}, data = {1.0} }
        })
        local elapsed = system.getTimer() - t0
        session:close()

        if not outputs or not outputs.waveform then
            ttsStatus.text = "Inference failed"
            return
        end

        ttsTime.text = string.format("%.0f ms | %d samples", elapsed, #outputs.waveform.data)

        -- Trim startup/trailing noise (same as Python KittenTTS API)
        local raw = outputs.waveform.data
        local trimStart = 5001
        local trimEnd = #raw - 10000
        if trimEnd <= trimStart then trimEnd = #raw end
        local trimmed = {}
        for i = trimStart, trimEnd do trimmed[#trimmed + 1] = raw[i] end

        drawWaveform(trimmed, #trimmed)

        local wavPath = system.pathForFile("tts_output.wav", system.TemporaryDirectory)
        if writeWav(wavPath, trimmed, #trimmed) then
            ttsStatus.text = "\"Hello world\" — playing..."
            local sound = audio.loadSound("tts_output.wav", system.TemporaryDirectory)
            if sound then
                audio.play(sound, { onComplete = function()
                    ttsStatus.text = "\"Hello world\" — done"
                    audio.dispose(sound)
                end })
            else
                ttsStatus.text = "Audio playback failed"
            end
        end
    end)
end

-- TTS button
local ttsBtn = display.newRoundedRect(display.contentCenterX, divY + 50, 160, 30, 6)
ttsBtn:setFillColor(0.9, 0.4, 0.2)
display.newText({
    text = "Speak: Hello World",
    x = ttsBtn.x, y = ttsBtn.y,
    font = native.systemFontBold, fontSize = 12
})
ttsBtn:addEventListener("tap", function() runTTS(); return true end)

-- Status
ttsStatus.y = divY + 80
ttsTime.y = divY + 93

print("[Demo] ONNX Runtime Demo loaded")
