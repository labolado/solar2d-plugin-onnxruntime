-- ONNX Runtime Plugin Demo — Style Transfer + TTS
local Bytemap = require("plugin.Bytemap")
local ort = require("plugin.onnxruntime")

display.setDefault("background", 0.07, 0.07, 0.09)

local CW = display.contentWidth   -- 390
local CH = display.contentHeight  -- 844
local CX = display.contentCenterX
local PAD = 18
local SIZE = 224
local sampleRate = 24000

-- ── Helpers ─────────────────────────────────────────────────

local function card(y, h)
    local r = display.newRoundedRect(CX, y, CW - PAD * 2, h, 14)
    r:setFillColor(0.12, 0.12, 0.14)
    r.strokeWidth = 1; r:setStrokeColor(0.2, 0.2, 0.24)
    return r
end

local function txt(text, x, y, size, bold, r, g, b)
    local t = display.newText({
        text = text, x = x, y = y,
        font = bold and native.systemFontBold or native.systemFont,
        fontSize = size or 14
    })
    t:setFillColor(r or 0.7, g or 0.7, b or 0.7)
    return t
end

local function btn(text, x, y, w, h, r, g, b, cb)
    local bg = display.newRoundedRect(x, y, w, h, h / 2)
    bg:setFillColor(r, g, b)
    txt(text, x, y, 16, true, 1, 1, 1)
    bg:addEventListener("tap", function() if cb then cb() end; return true end)
    return bg
end

-- ── Header ──────────────────────────────────────────────────

local headerH = 56
local headerBg = display.newRect(CX, headerH / 2, CW, headerH)
headerBg:setFillColor(0.1, 0.1, 0.13)
txt("ONNX Runtime", CX - 30, headerH / 2, 20, true, 0.85, 0.9, 1)
txt("for Solar2D", CX + 72, headerH / 2, 14, false, 0.45, 0.55, 0.7)
local ver = (ort.VERSION or "?"):gsub("^v", "")
txt("v" .. ver, CW - PAD - 14, headerH / 2, 11, false, 0.35, 0.35, 0.4)

-- ── Style Transfer Section ──────────────────────────────────

local stTop = headerH + PAD
local stH = 400
card(stTop + stH / 2, stH)

txt("Style Transfer", CX, stTop + 24, 18, true, 0.55, 0.78, 1)

local imgW = 150
local imgGap = 24
local imgY = stTop + 24 + imgW / 2 + 40

-- Original
txt("Original", CX - imgW / 2 - imgGap / 2, stTop + 50, 12, false, 0.4)
local originalImage = display.newImage("test_photo.png", system.ResourceDirectory)
if originalImage then
    originalImage.x = CX - imgW / 2 - imgGap / 2
    originalImage.y = imgY
    originalImage.width = imgW; originalImage.height = imgW
end

-- Arrow
txt("→", CX, imgY, 26, true, 0.3)

-- Styled placeholder
txt("Styled", CX + imgW / 2 + imgGap / 2, stTop + 50, 12, false, 0.4)
local styledSlot = display.newRoundedRect(CX + imgW / 2 + imgGap / 2, imgY, imgW, imgW, 8)
styledSlot:setFillColor(0.09, 0.09, 0.11)
styledSlot.strokeWidth = 1; styledSlot:setStrokeColor(0.18)
local slotQ = txt("?", CX + imgW / 2 + imgGap / 2, imgY, 36, false, 0.18)

local styleSession, styledImage

local sBtnY = imgY + imgW / 2 + 32
local styleStatus = txt("Choose a style", CX, sBtnY + 34, 13, false, 0.4)
local styleTime = txt("", CX, sBtnY + 52, 12, false, 0.3, 0.85, 0.4)

local function imageToTensor(path)
    local bm = Bytemap.loadTexture({ filename = path, baseDir = system.ResourceDirectory })
    if not bm then return nil end
    local w, h = bm.width, bm.height
    local bs = bm:GetBytes(); bm:releaseSelf()
    if type(bs) ~= "string" then return nil end
    local comp = #bs / (w * h)
    local data, idx = {}, 1
    for c = 0, 2 do
        for yy = 0, h - 1 do for xx = 0, w - 1 do
            data[idx] = string.byte(bs, (yy * w + xx) * comp + c + 1); idx = idx + 1
        end end
    end
    return data
end

local function tensorToImage(td, w, h)
    local bm = Bytemap.newTexture({ width = w, height = h, componentCount = 4 })
    local chars, chSize = {}, w * h
    for yy = 0, h - 1 do for xx = 0, w - 1 do
        local pi = yy * w + xx
        local r = math.max(0, math.min(255, math.floor(td[pi + 1] + 0.5)))
        local g = math.max(0, math.min(255, math.floor(td[chSize + pi + 1] + 0.5)))
        local b = math.max(0, math.min(255, math.floor(td[2 * chSize + pi + 1] + 0.5)))
        chars[#chars + 1] = string.char(r, g, b, 255)
    end end
    bm:SetBytes(table.concat(chars))
    return display.newImage(bm.filename, bm.baseDir), bm
end

local function runStyle(name)
    styleStatus.text = "Loading " .. name .. "..."
    styleStatus:setFillColor(0.7, 0.7, 0.3)
    timer.performWithDelay(50, function()
        local mp = system.pathForFile(name .. ".onnx", system.ResourceDirectory)
        if not mp then styleStatus.text = "Model not found"; return end
        if styleSession then styleSession:close(); styleSession = nil end
        styleSession = ort.load(mp)
        if not styleSession then styleStatus.text = "Load failed"; return end
        local inp = imageToTensor("test_photo.png")
        if not inp then styleStatus.text = "Image error"; return end
        styleStatus.text = "Running..."
        local t0 = system.getTimer()
        local out = styleSession:run({ input1 = { dims = {1, 3, SIZE, SIZE}, data = inp } })
        local ms = system.getTimer() - t0
        styleTime.text = string.format("%.0f ms", ms)
        if out and out.output1 then
            styleStatus.text = name:sub(1,1):upper() .. name:sub(2) .. " applied!"
            styleStatus:setFillColor(0.3, 0.9, 0.5)
            if styledImage then styledImage:removeSelf() end
            slotQ.isVisible = false
            local img = tensorToImage(out.output1.data, SIZE, SIZE)
            if img then
                img.x = CX + imgW / 2 + imgGap / 2; img.y = imgY
                img.width = imgW; img.height = imgW; styledImage = img
            end
        else
            styleStatus.text = "Failed"; styleStatus:setFillColor(0.9, 0.3, 0.3)
        end
    end)
end

-- Style buttons
local bw = (CW - PAD * 2 - 50) / 2
btn("Candy", CX - bw / 2 - 10, sBtnY, bw, 38, 0.82, 0.3, 0.5, function() runStyle("candy") end)
btn("Mosaic", CX + bw / 2 + 10, sBtnY, bw, 38, 0.3, 0.5, 0.82, function() runStyle("mosaic") end)

-- ── TTS Section ─────────────────────────────────────────────

local ttsTop = stTop + stH + PAD
local ttsH = CH - ttsTop - PAD
card(ttsTop + ttsH / 2, ttsH)

txt("Text-to-Speech", CX, ttsTop + 24, 18, true, 0.55, 0.78, 1)
txt("Kitten TTS Nano · 23MB ONNX model", CX, ttsTop + 46, 12, false, 0.35)

-- Input box
local ibY = ttsTop + 78
local ib = display.newRoundedRect(CX, ibY, CW - PAD * 4, 44, 10)
ib:setFillColor(0.08, 0.08, 0.1); ib.strokeWidth = 1; ib:setStrokeColor(0.18)
txt("\"Hello world\"", CX, ibY, 20, true, 0.85, 0.85, 0.9)
txt("həlˈoʊ wˈɜːld → 14 tokens", CX, ibY + 30, 11, false, 0.3)

-- Speak button
local spkY = ibY + 64
btn("Speak", CX, spkY, CW - PAD * 4, 44, 0.88, 0.38, 0.2, nil)
local spkTap = display.newRoundedRect(CX, spkY, CW - PAD * 4, 44, 22)
spkTap:setFillColor(0, 0, 0, 0.01)

local ttsStatus = txt("Tap to synthesize speech", CX, spkY + 36, 13, false, 0.4)
local ttsTime = txt("", CX, spkY + 54, 12, false, 0.3, 0.85, 0.4)

-- Waveform
local wvW = CW - PAD * 4
local wvH = ttsH - (spkY + 68 - ttsTop) - 16
local wvY = spkY + 68 + wvH / 2
local wvBg = display.newRoundedRect(CX, wvY, wvW, wvH, 8)
wvBg:setFillColor(0.06, 0.06, 0.08); wvBg.strokeWidth = 1; wvBg:setStrokeColor(0.15)
local wvLabel = txt("Waveform", CX, wvY, 14, false, 0.15)
local waveGroup = display.newGroup()
waveGroup.x = CX - wvW / 2; waveGroup.y = wvY - wvH / 2

-- "Hello world" phonemized
local ttsTokens = {50, 83, 54, 156, 57, 135, 16, 65, 156, 87, 158, 54, 46, 16}
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

-- WAV helpers
local function byte0(v) return v % 256 end
local function byte1(v) return math.floor(v / 256) % 256 end
local function byte2(v) return math.floor(v / 65536) % 256 end
local function byte3(v) return math.floor(v / 16777216) % 256 end
local function writeLE16(f, v) f:write(string.char(byte0(v), byte1(v))) end
local function writeLE32(f, v) f:write(string.char(byte0(v), byte1(v), byte2(v), byte3(v))) end

local function writeWav(fn, s, n)
    local f = io.open(fn, "wb"); if not f then return false end
    local p = {}
    for i = 1, n do
        local v = math.max(-1, math.min(1, s[i] or 0))
        local c = math.floor(v * 32767 + 0.5); if c < 0 then c = c + 65536 end
        p[i] = string.char(c % 256, math.floor(c / 256) % 256)
    end
    local ds = n * 2
    f:write("RIFF"); writeLE32(f, 36 + ds); f:write("WAVE")
    f:write("fmt "); writeLE32(f, 16); writeLE16(f, 1); writeLE16(f, 1)
    writeLE32(f, sampleRate); writeLE32(f, sampleRate * 2); writeLE16(f, 2); writeLE16(f, 16)
    f:write("data"); writeLE32(f, ds)
    for i = 1, n do f:write(p[i]) end
    f:close(); return true
end

local function drawWaveform(samples, n)
    for i = waveGroup.numChildren, 1, -1 do waveGroup[i]:removeSelf() end
    wvLabel.isVisible = false
    local step = math.max(1, math.floor(n / wvW))
    for i = 0, wvW - 1 do
        local si = i * step + 1; local mx = 0
        for j = si, math.min(si + step - 1, n) do
            local v = math.abs(samples[j] or 0); if v > mx then mx = v end
        end
        local bh = mx * wvH * 0.9; if bh < 1 then bh = 1 end
        local ln = display.newLine(waveGroup, i, wvH/2 - bh/2, i, wvH/2 + bh/2)
        ln:setStrokeColor(0.25, 0.75, 0.4, 0.85); ln.strokeWidth = 1
    end
end

local function runTTS()
    ttsStatus.text = "Loading model..."; ttsStatus:setFillColor(0.7, 0.7, 0.3)
    timer.performWithDelay(50, function()
        local mp = system.pathForFile("kitten_tts_nano_v0_1.onnx", system.ResourceDirectory)
        if not mp then ttsStatus.text = "Model not found"; return end
        local session = ort.load(mp)
        if not session then ttsStatus.text = "Load failed"; return end
        ttsStatus.text = "Running inference..."
        local t0 = system.getTimer()
        local out = session:run({
            input_ids = { dims = {1, #ttsTokens}, data = ttsTokens, dtype = "int64" },
            style = { dims = {1, 256}, data = voiceEmbedding },
            speed = { dims = {1}, data = {1.0} }
        })
        local ms = system.getTimer() - t0; session:close()
        if not out or not out.waveform then
            ttsStatus.text = "Failed"; ttsStatus:setFillColor(0.9, 0.3, 0.3); return
        end
        ttsTime.text = string.format("%.0f ms  ·  %d samples", ms, #out.waveform.data)
        local raw = out.waveform.data
        local ts, te = 5001, #raw - 10000; if te <= ts then te = #raw end
        local trimmed = {}; for i = ts, te do trimmed[#trimmed + 1] = raw[i] end
        drawWaveform(trimmed, #trimmed)
        local wp = system.pathForFile("tts_output.wav", system.TemporaryDirectory)
        if writeWav(wp, trimmed, #trimmed) then
            ttsStatus.text = "Playing..."; ttsStatus:setFillColor(0.3, 0.9, 0.5)
            local snd = audio.loadSound("tts_output.wav", system.TemporaryDirectory)
            if snd then
                audio.play(snd, { onComplete = function()
                    ttsStatus.text = "Done — \"Hello world\""
                    audio.dispose(snd)
                end })
            else ttsStatus.text = "Playback failed" end
        end
    end)
end

spkTap:addEventListener("tap", function() runTTS(); return true end)

print("[Demo] ONNX Runtime Demo loaded")
