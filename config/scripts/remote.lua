-- CRT-mpv on-screen remote control.
-- Opened from the "i" button of the hover bar (ModernZ, patched by the installer), the `r` key,
-- or `script-message crt-remote-toggle`. Drawn as vector graphics (no image files), clickable, with
-- hover and press feedback. CRT/TV actions are sent to scripts/crt.lua with `script-message crt-do`.
local mp = require 'mp'
local msg = require 'mp.msg'

local DW, DH = 330, 966          -- design size of the remote (scaled to the window)
package.path = mp.command_native({"expand-path", "~~/script-modules/"}) .. "/?.lua;" .. package.path   -- shared helper modules
local open = false
local hover, pressed = nil, nil
local sel = 1                                -- which setting the adjustment panel is showing
local ir, ir_timer = false, nil          -- the red IR window flashes while a button is pressed
local IR_HOLD = mp.get_opt("crt-remote-test") and 2.0 or 0.18
local st = {}                    -- state published by crt.lua (user-data/crt)
local pl = { pause = false, mute = false, volume = 100, sub = false, audio = true, speed = 1, fs = false, loop = false,
            has_sub = false, audio_n = 0 }
local overlay = mp.create_osd_overlay("ass-events")
local close                 -- defined below
local render                -- defined below

-- layout of the last render
local L = { ox = 0, oy = 0, sc = 1, rw = 0, rh = 0 }
local buttons, byid = {}, {}

local C = {
    body = "#151518", bevel = "#383840", shade = "#08080a",
    key = "#26262c", keyhi = "#303037", keyhover = "#464652", keydown = "#0f0f12",
    text = "#c4c4cc", dim = "#74747e",
    red = "#b9352a", redhover = "#e0493b", accent = "#ff8232",
    lcd = "#0e1a10", lcdtext = "#7dff9a",
}

local function hex(c)
    local r, g, b = c:match("#(%x%x)(%x%x)(%x%x)")
    return string.format("&H%s%s%s&", b, g, r)
end

local lines
local function add(s) lines[#lines + 1] = s end

local function X(x) return L.ox + x * L.sc end
local function Y(y) return L.oy + y * L.sc end
local function S(v) return v * L.sc end

local function p_rrect(x, y, w, h, r)
    local x2, y2 = x + w, y + h
    return string.format(
        "m %.1f %.1f l %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f l %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f "
        .. "l %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f l %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f",
        x + r, y, x2 - r, y, x2, y, x2, y, x2, y + r, x2, y2 - r, x2, y2, x2, y2, x2 - r, y2,
        x + r, y2, x, y2, x, y2, x, y2 - r, x, y + r, x, y, x, y, x + r, y)
end

local function p_circle(cx, cy, r)
    local k = 0.5523 * r
    return string.format(
        "m %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f "
        .. "b %.1f %.1f %.1f %.1f %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f",
        cx + r, cy, cx + r, cy + k, cx + k, cy + r, cx, cy + r,
        cx - k, cy + r, cx - r, cy + k, cx - r, cy,
        cx - r, cy - k, cx - k, cy - r, cx, cy - r,
        cx + k, cy - r, cx + r, cy - k, cx + r, cy)
end

local function shape(path, fill, stroke, sw, alpha)
    add(string.format("{\\an7\\pos(0,0)\\1c%s\\3c%s\\bord%.1f\\shad0\\1a&H%02X&\\p1}%s",
        hex(fill), hex(stroke or fill), stroke and sw or 0, alpha or 0, path))
end

local function text(str, x, y, size, color, bold)
    add(string.format("{\\an5\\pos(%.1f,%.1f)\\fs%.1f\\1c%s\\bord0\\shad0\\b%d}%s",
        x, y, size, hex(color), bold and 1 or 0, str))
end

local function poly(pts, fill)
    local t = { string.format("m %.1f %.1f", pts[1], pts[2]) }
    for i = 3, #pts, 2 do t[#t + 1] = string.format("l %.1f %.1f", pts[i], pts[i + 1]) end
    shape(table.concat(t, " "), fill)
end

local function rect(x, y, w, h, fill) poly({ x, y, x + w, y, x + w, y + h, x, y + h }, fill) end

local function icon(kind, cx, cy, s, col)
    local h = s * 0.5
    if kind == "play" then poly({ cx - .42 * s, cy - h, cx + .55 * s, cy, cx - .42 * s, cy + h }, col)
    elseif kind == "pause" then
        rect(cx - .36 * s, cy - h, .26 * s, s, col); rect(cx + .10 * s, cy - h, .26 * s, s, col)
    elseif kind == "next" then
        poly({ cx - .5 * s, cy - h, cx + .25 * s, cy, cx - .5 * s, cy + h }, col); rect(cx + .3 * s, cy - h, .2 * s, s, col)
    elseif kind == "prev" then
        poly({ cx + .5 * s, cy - h, cx - .25 * s, cy, cx + .5 * s, cy + h }, col); rect(cx - .5 * s, cy - h, .2 * s, s, col)
    elseif kind == "fwd" then
        poly({ cx - .55 * s, cy - h, cx, cy, cx - .55 * s, cy + h }, col)
        poly({ cx, cy - h, cx + .55 * s, cy, cx, cy + h }, col)
    elseif kind == "rew" then
        poly({ cx + .55 * s, cy - h, cx, cy, cx + .55 * s, cy + h }, col)
        poly({ cx, cy - h, cx - .55 * s, cy, cx, cy + h }, col)
    elseif kind == "up" then poly({ cx - .5 * s, cy + .3 * s, cx, cy - .4 * s, cx + .5 * s, cy + .3 * s }, col)
    elseif kind == "down" then poly({ cx - .5 * s, cy - .3 * s, cx, cy + .4 * s, cx + .5 * s, cy - .3 * s }, col)
    elseif kind == "plus" then
        rect(cx - .5 * s, cy - .1 * s, s, .2 * s, col); rect(cx - .1 * s, cy - .5 * s, .2 * s, s, col)
    elseif kind == "minus" then rect(cx - .5 * s, cy - .1 * s, s, .2 * s, col)
    elseif kind == "left" then poly({ cx + .32 * s, cy - h, cx - .36 * s, cy, cx + .32 * s, cy + h }, col)
    elseif kind == "right" then poly({ cx - .32 * s, cy - h, cx + .36 * s, cy, cx - .32 * s, cy + h }, col)
    elseif kind == "x" then
        local d = .42 * s
        poly({ cx - d, cy - d + .16 * s, cx - d + .16 * s, cy - d, cx + d, cy + d - .16 * s, cx + d - .16 * s, cy + d }, col)
        poly({ cx + d - .16 * s, cy - d, cx + d, cy - d + .16 * s, cx - d + .16 * s, cy + d, cx - d, cy + d - .16 * s }, col)
    end
end

local function cmd(...)
    local a = { ... }
    return function() mp.commandv(table.unpack(a)) end
end
local function crt(a) return function() mp.commandv("script-message", "crt-do", a) end end

-- switch to the next audio track (language / dub). Unlike `cycle audio` this never lands on "no audio".
local function next_audio()
    local ids, cur = {}, mp.get_property_native("aid")
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == "audio" then ids[#ids + 1] = t end
    end
    if #ids < 2 then mp.osd_message("Only one audio track", 2.5); return end
    local at = 0
    for i, t in ipairs(ids) do if t.id == cur then at = i end end
    local nxt = ids[at % #ids + 1]
    mp.set_property_number("aid", nxt.id)
    local label = nxt.title or nxt.lang or ""
    mp.osd_message(string.format("Audio track %d/%d%s", at % #ids + 1, #ids, label ~= "" and (": " .. label) or ""), 2.5)
end

-- open the Retrogrounds website in the default browser
local SITE = "https://retrogrounds.com"
local function open_site()
    local plat = mp.get_property("platform") or (package.config:sub(1, 1) == "\\" and "windows" or "linux")
    local args
    if plat == "windows" then args = { "cmd", "/c", "start", "", SITE }
    elseif plat == "darwin" then args = { "open", SITE }
    else args = { "xdg-open", SITE } end
    mp.command_native_async({ name = "subprocess", args = args, playback_only = false, capture_stdout = true, capture_stderr = true },
        function() end)
end

-- soft (blurred) shape, used for shadows and light
local function glow(path, color, alpha, blur, clip)
    add(string.format("{\\an7\\pos(0,0)%s\\1c%s\\1a&H%02X&\\bord0\\shad0\\blur%.1f\\p1}%s",
        clip and ("\\clip(" .. clip .. ")") or "", hex(color), alpha, blur, path))
end

-- an outline only (no fill), clipped to a rectangle: lights one edge of a key like a bevel
local function rim(path, color, alpha, width, x1, y1, x2, y2)
    add(string.format("{\\an7\\pos(0,0)\\clip(%.1f,%.1f,%.1f,%.1f)\\1a&HFF&\\3c%s\\3a&H%02X&\\bord%.1f\\shad0\\blur0.4\\p1}%s",
        x1, y1, x2, y2, hex(color), alpha, width, path))
end

-- Add a clickable button, drawn as a moulded key: a soft drop shadow, a visible side wall, a lit cap
-- (sheen on top, shade underneath), a bevel (light top edge, dark bottom edge) and raised lettering.
-- A pressed key sinks into its socket and the lighting flattens.
-- spec: {id,x,y,w,h, circle=, r=, icon=, label=, sub=, action=, rep=, red=, led=, disabled=}
local function key(sp)
    local x, y, w, h = X(sp.x), Y(sp.y), S(sp.w), S(sp.h)
    local down, hov, dis = pressed == sp.id, hover == sp.id, sp.disabled
    local dy = down and S(2.4) or 0                         -- how far the cap has sunk
    local depth = down and S(0.8) or S(3.4)                 -- height of the side wall
    local rad = math.min(S(sp.r or 9), w / 2, h / 2)
    local cx, cy = x + w / 2, y + h / 2

    local base
    if dis then base = "#1b1b1f"
    elseif sp.red then base = down and "#78201b" or hov and "#d8493d" or "#b4302a"
    else base = down and "#1e1e24" or hov and "#3c3c47" or "#2d2d35" end
    local wall = sp.red and "#3f0f0c" or "#09090c"

    -- the key's outline at a vertical offset, grown (or shrunk, if negative) by `grow` pixels
    local function outline(oy, grow)
        if sp.circle then return p_circle(cx, cy + oy, w / 2 + grow) end
        return p_rrect(x - grow, y + oy - grow, w + 2 * grow, h + 2 * grow, math.max(0.5, rad + grow))
    end

    -- drop shadow and side wall
    if not dis then glow(outline(depth + S(2.6), S(0.4)), "#000000", down and 0xB0 or 0x70, S(3.2)) end
    shape(outline(depth, 0), wall, "#040405", S(1))
    -- cap
    shape(outline(dy, 0), base, "#08080b", S(1.1))

    if not dis then
        local face = outline(dy, -S(0.5))
        local fy = y + dy
        if sp.circle then
            local r = w / 2
            if down then
                glow(p_circle(cx, fy + h * 0.15, r * 0.95), "#000000", 0x98, S(4), face)                     -- inner shadow, top
            else
                glow(p_circle(cx, fy + h * 0.10, r * 0.85), "#ffffff", sp.red and 0xE4 or 0xEE, S(8), face)  -- sheen (matte)
                glow(p_circle(cx, fy + h * 1.00, r * 1.05), "#000000", 0xC4, S(8), face)                     -- shade
            end
        else
            if down then
                glow(p_rrect(x, fy - h * 0.2, w, h * 0.5, rad), "#000000", 0x98, S(4), face)                 -- inner shadow, top
            else
                glow(p_rrect(x, fy - h * 0.15, w, h * 0.62, rad), "#ffffff", sp.red and 0xE4 or 0xEE, S(8), face)  -- sheen (matte)
                glow(p_rrect(x, fy + h * 0.55, w, h * 0.7, rad), "#000000", 0xC4, S(8), face)                -- shade
            end
        end
        -- bevel: light along the top edge, dark along the bottom edge
        local lit, shade = outline(dy, -S(0.9)), outline(dy, -S(0.9))
        rim(lit, "#ffffff", down and 0xF2 or (hov and 0xB4 or 0xD0), S(1.2), x - S(2), fy - S(2), x + w + S(2), fy + h * 0.2)
        rim(shade, "#000000", 0xA0, S(1.3), x - S(2), fy + h * 0.8, x + w + S(2), fy + h + S(2))
    end

    -- indicator LED in the cap's corner
    if sp.led ~= nil then
        local lx = sp.circle and x + w * 0.80 or x + w - S(9)
        local ly = (sp.circle and y + h * 0.20 or y + S(9)) + dy
        shape(p_circle(lx, ly, S(4.6)), "#050506", "#2c2c33", S(0.8))                                   -- bezel
        if sp.led and not dis then
            glow(p_circle(lx, ly, S(7.5)), "#00ff55", 0xA8, S(3.5))
            shape(p_circle(lx, ly, S(3.4)), "#8bffab", "#00b33c", S(0.7))
        else
            shape(p_circle(lx, ly, S(3.0)), "#0f2a17", "#050a06", S(0.6))
        end
    end

    -- raised lettering / icon: a dark shadow just below and to the right, then the face
    local ix, iy = cx, cy + dy
    if sp.icon then
        local sz = S(sp.is or 15)
        if not dis then icon(sp.icon, ix + S(0.9), iy + S(1.4), sz, "#06060a") end
        icon(sp.icon, ix, iy, sz, dis and "#43434a" or (sp.iconcol or C.text))
    end
    if sp.label then
        local ly = (sp.sub and cy - S(5) or cy) + dy
        local fs = S(sp.fs or 15)
        local col = dis and "#43434a" or (sp.labelcol or C.text)
        if not dis then text(sp.label, ix + S(0.8), ly + S(1.3), fs, "#06060a", true) end
        text(sp.label, ix, ly, fs, col, true)
        if sp.sub then
            if not dis then text(sp.sub, ix + S(0.5), cy + S(11) + dy + S(1), S(9.5), "#06060a", false) end
            text(sp.sub, ix, cy + S(11) + dy, S(9.5), C.dim, false)
        end
    end

    if sp.id and sp.action and not dis then
        buttons[#buttons + 1] = { id = sp.id, x1 = x, y1 = y, x2 = x + w, y2 = y + h, action = sp.action, rep = sp.rep }
        byid[sp.id] = buttons[#buttons]
    end
end

-- ---- 5x7 pixel font for the dot-matrix display (each row is a 5-bit pattern, top row first) ----
local FONT = {
    A = {14,17,17,31,17,17,17}, B = {30,17,17,30,17,17,30}, C = {14,17,16,16,16,17,14},
    D = {30,17,17,17,17,17,30}, E = {31,16,16,30,16,16,31}, F = {31,16,16,30,16,16,16},
    G = {14,17,16,23,17,17,15}, H = {17,17,17,31,17,17,17}, I = {14,4,4,4,4,4,14},
    J = {7,2,2,2,2,18,12},      K = {17,18,20,24,20,18,17}, L = {16,16,16,16,16,16,31},
    M = {17,27,21,21,17,17,17}, N = {17,25,21,19,17,17,17}, O = {14,17,17,17,17,17,14},
    P = {30,17,17,30,16,16,16}, Q = {14,17,17,17,21,18,13}, R = {30,17,17,30,20,18,17},
    S = {15,16,16,14,1,1,30},   T = {31,4,4,4,4,4,4},       U = {17,17,17,17,17,17,14},
    V = {17,17,17,17,17,10,4},  W = {17,17,17,21,21,27,17}, X = {17,17,10,4,10,17,17},
    Y = {17,17,10,4,4,4,4},     Z = {31,1,2,4,8,16,31},
    ["0"] = {14,17,19,21,25,17,14}, ["1"] = {4,12,4,4,4,4,14},   ["2"] = {14,17,1,2,4,8,31},
    ["3"] = {31,2,4,2,1,17,14},     ["4"] = {2,6,10,18,31,2,2},  ["5"] = {31,16,30,1,1,17,14},
    ["6"] = {6,8,16,30,17,17,14},   ["7"] = {31,1,2,4,8,8,8},    ["8"] = {14,17,17,14,17,17,14},
    ["9"] = {14,17,17,15,1,2,12},   ["-"] = {0,0,0,31,0,0,0},
}

-- short names that fit the 13-character display
local TV_NAMES = {
    Generic_White_TV = "WHITE TV", Generic_Gray_TV = "GRAY TV", Generic_Flat_TV = "FLAT TV",
    Generic_CRT_Monitor = "CRT MONITOR", G02_Generic_TV = "G02 TV",
    Nintendo_NES = "NES", Nintendo_SNES = "SNES", Nintendo_N64 = "N64", Nintendo_Famicom = "FAMICOM",
    Sega_Genesis = "GENESIS", Sega_MasterSystem = "MASTER SYSTEM", Sega_Dreamcast = "DREAMCAST",
    SNK_NeoGeo = "NEO GEO", Sony_PlayStation = "PLAYSTATION", Sony_PS2 = "PS2",
}

local COLS = 13                      -- characters per display row

-- squares for one line of text, centred on the display: returns a "lit" path and an "unlit" path (the dim dot grid).
-- The grid is COLS*6-1 cells wide; a line of n characters is n*6-1 cells wide, so the left offset
-- (COLS-n)*3 is always a whole number of cells and the text is centred exactly.
local function pixel_line(str, x0, y0, p)
    str = str:upper():sub(1, COLS)
    local n = #str
    local shift = (COLS - n) * 3
    local lit, dim = {}, {}
    local inset, sz = p * 0.08, p * 0.84
    local function sq(t, x, y)
        t[#t + 1] = string.format("m %.1f %.1f l %.1f %.1f l %.1f %.1f l %.1f %.1f",
            x, y, x + sz, y, x + sz, y + sz, x, y + sz)
    end
    for cell = 0, COLS * 6 - 2 do
        local k, c = math.floor((cell - shift) / 6), (cell - shift) % 6     -- char index, column in glyph (0..5)
        local rows = (k >= 0 and k < n and c < 5) and FONT[str:sub(k + 1, k + 1)] or nil
        for r = 1, 7 do
            local x = x0 + cell * p + inset
            local y = y0 + (r - 1) * p + inset
            if rows and ((rows[r] >> (4 - c)) & 1) == 1 then sq(lit, x, y) else sq(dim, x, y) end
        end
    end
    return table.concat(lit, " "), table.concat(dim, " ")
end

local function layer(path, color, alpha, blur)
    add(string.format("{\\an7\\pos(0,0)\\1c%s\\1a&H%02X&\\bord0\\shad0\\blur%.1f\\p1}%s",
        hex(color), alpha, blur, path))
end

local function build()
    local w, h = mp.get_osd_size()
    if not w or w <= 0 or h <= 0 then return false end
    buttons, byid, lines = {}, {}, {}
    L.sc = math.max(0.4, math.min(1.15, (h * 0.74) / DH))
    L.rw, L.rh = DW * L.sc, DH * L.sc
    L.ox = w - L.rw - 36 * L.sc
    L.oy = math.max(8, (h - L.rh) / 2 - h * 0.03)

    -- body
    shape(p_rrect(X(-4), Y(2), S(DW + 8), S(DH + 8), S(52)), "#000000", nil, 0, 0x90)
    shape(p_rrect(X(0), Y(0), S(DW), S(DH), S(48)), C.body, C.bevel, S(2.5))
    shape(p_rrect(X(8), Y(6), S(DW - 16), S(DH * 0.16), S(40)), "#1f1f24", nil, 0, 0xB8)
    -- IR window
    do   -- IR window: a small dark red lens; when a button is pressed it lights up with a soft glow
        local lx, ly, lw, lh = X(DW / 2 - 34), Y(15), S(68), S(10)
        if ir then
            layer(p_rrect(lx - S(12), ly - S(9), lw + S(24), lh + S(18), S(14)), "#ff1a00", 0xD8, S(12))   -- faint wide halo
            layer(p_rrect(lx - S(4), ly - S(3), lw + S(8), lh + S(6), S(8)), "#ff2a10", 0xA8, S(5))        -- nearer glow
        end
        shape(p_rrect(lx, ly, lw, lh, S(5)), ir and "#c4170a" or "#1c0606", "#050505", S(1))               -- the lens
        if ir then
            layer(p_rrect(lx + lw * 0.12, ly + lh * 0.18, lw * 0.76, lh * 0.64, S(3)), "#ff5a3c", 0x20, S(2))   -- bright face
            layer(p_rrect(lx + lw * 0.30, ly + lh * 0.34, lw * 0.40, lh * 0.32, S(2)), "#ffc0b0", 0x50, S(1.5)) -- hot centre
        else
            layer(p_rrect(lx + S(6), ly + S(1.5), lw - S(12), S(2), S(1)), "#6a2424", 0x90, S(0.8))        -- glassy reflection
        end
    end
    key { id = "close", x = DW - 40, y = 10, w = 26, h = 26, circle = true, icon = "x", is = 13, red = true, action = function() close() end }

    local silent = pl.mute or pl.volume <= 0.5     -- mute switch on, or volume turned to zero
    -- power (switches the TV off, then quits) / CRT effect and TV frame / degauss / mute
    key { id = "pwr", x = 22, y = 52, w = 52, h = 52, circle = true, label = "PWR", fs = 13, red = true, action = crt("power_off") }
    text("EXIT", X(48), Y(118), S(10), C.dim, false)
    local screen_on = st.crt ~= false and st.frame ~= false
    key { id = "screen", x = 99, y = 52, w = 52, h = 52, circle = true, label = "CRT", fs = 14, led = screen_on, action = crt("screen") }
    text(screen_on and "CRT ON" or "CRT OFF", X(125), Y(118), S(10), C.dim, false)
    key { id = "degauss", x = 176, y = 52, w = 52, h = 52, circle = true, label = "DEG", fs = 13, action = crt("degauss") }
    text("DEGAUSS", X(202), Y(118), S(10), C.dim, false)
    key { id = "mute", x = 253, y = 52, w = 52, h = 52, circle = true, label = "MUTE", fs = 12,
          labelcol = silent and C.accent or C.text, led = silent, action = cmd("cycle", "mute") }
    text(silent and "MUTED" or "SOUND", X(279), Y(118), S(10), C.dim, false)

    -- dot-matrix display: black panel, square orange pixels, faint glow, dim unlit pixels
    shape(p_rrect(X(20), Y(134), S(290), S(62), S(8)), "#040302", "#000000", S(2))
    rim(p_rrect(X(20), Y(134), S(290), S(62), S(8)), "#ffffff", 0xB8, S(1.4), X(16), Y(134) + S(50), X(314), Y(134) + S(68))   -- lit lower lip
    local tvname = TV_NAMES[st.tv or ""] or (st.tv or "?"):gsub("_", " ")
    local info = string.format("S%d C%d L%d", math.floor((st.scan or 0) * 100 + 0.5),
        math.floor((st.curve or 0) * 100 + 0.5), math.floor((st.lines or 0) + 0.5))
    local pp = S(3.2)                                   -- pixel pitch
    local gx = X(165) - (COLS * 6 - 1) * pp / 2
    local gap = S(5)
    local top = Y(134) + (S(62) - (14 * pp + gap)) / 2                  -- centre the two rows vertically
    local lit1, dim1 = pixel_line(tvname, gx, top, pp)
    local lit2, dim2 = pixel_line(info, gx, top + 7 * pp + gap, pp)
    layer(dim1 .. " " .. dim2, "#2a1405", 0x00, 0)                    -- unlit pixels
    layer(lit1 .. " " .. lit2, "#ff6a00", 0x70, S(2.6))              -- glow
    layer(lit1 .. " " .. lit2, "#ff9a2e", 0x00, 0)                   -- lit pixels

    -- presets 1..6
    local names = { "SUBTLE", "CLASSIC", "HEAVY", "ANIME", "VHS", "ARCADE", "EMPTY", "EMPTY", "EMPTY" }
    for i = 1, 9 do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local custom = type(st.slots) == "table" and st.slots[tostring(i)] ~= nil
        key { id = "p" .. i, x = 20 + col * 100, y = 208 + row * 66, w = 90, h = 56, label = tostring(i),
              sub = custom and "SAVED" or names[i], fs = 22, led = st.preset_n == i, action = crt("preset_" .. i) }
    end
    text("KEYS 7-9: HOLD TO SAVE   -   RIGHT-CLICK TO EMPTY", X(165), Y(404), S(8), C.dim, false)

    -- rockers: VOL, TV, EP
    local rockers = {
        { x = 24,  name = "VOL", up = cmd("add", "volume", 5), dn = cmd("add", "volume", -5), rep = true },
        { x = 123, name = "TV",  up = crt("tv_next"), dn = crt("tv_prev") },
        { x = 222, name = "EP",  up = cmd("playlist-next"), dn = cmd("playlist-prev") },
    }
    for _, r in ipairs(rockers) do
        key { id = r.name .. "u", x = r.x, y = 412, w = 84, h = 70, icon = "up", is = 22, action = r.up, rep = r.rep, r = 14 }
        key { id = r.name .. "d", x = r.x, y = 490, w = 84, h = 70, icon = "down", is = 22, action = r.dn, rep = r.rep, r = 14 }
        local label = r.name == "VOL" and string.format("VOL %d", math.floor(pl.volume + 0.5)) or r.name
        shape(p_rrect(X(r.x + 8), Y(477), S(68), S(18), S(8)), "#0b0b0e", "#030304", S(1))                  -- recessed plate
        rim(p_rrect(X(r.x + 8), Y(477), S(68), S(18), S(8)), "#ffffff", 0xC8, S(1), X(r.x + 4), Y(477) + S(12), X(r.x + 80), Y(477) + S(20))
        text(label, X(r.x + 42), Y(486), S(11), C.accent, true)
    end

    -- transport
    local tx = 21
    local function tkey(i, id, ic, act, rep)
        key { id = id, x = tx + (i - 1) * 59, y = 580, w = 52, h = 52, icon = ic, is = 16, action = act, rep = rep }
    end
    tkey(1, "prev", "prev", cmd("playlist-prev"))
    tkey(2, "rew", "rew", cmd("seek", -10), true)
    tkey(3, "play", pl.pause and "play" or "pause", cmd("cycle", "pause"))
    tkey(4, "fwd", "fwd", cmd("seek", 10), true)
    tkey(5, "next", "next", cmd("playlist-next"))
    text("PREV   -10s   PLAY/PAUSE   +10s   NEXT", X(165), Y(646), S(9), C.dim, false)

    -- adjustment panel: pick a setting with the arrows, read it on the meter, change it with - / +
    local pct = function(v) return string.format("%d", math.floor(v * 100 + 0.5)) end
    local adjustable = {
        { "SCANLINES",  "scan",       0, 1,     "scan_down",     "scan_up",     function(v) return pct(v) end },
        { "CURVATURE",  "curve",      0, 1,     "curve_down",    "curve_up",    function(v) return pct(v) end },
        { "LINE COUNT", "lines",      60, 720,  "lines_down",    "lines_up",    function(v) return string.format("%d", math.floor(v + 0.5)) end },
        { "NOISE",      "noise",      0, 1,     "noise_down",    "noise_up",    function(v) return pct(v) end },
        { "SIGNAL",     "ntsc",       0, 3,     "ntsc_down",     "ntsc_up",     function(v) return ({ [0] = "CLEAN", "S-VIDEO", "COMPOSITE", "RF" })[math.floor(v + 0.5)] or "CLEAN" end, 4 },
        { "CONTRAST",   "contrast",   0.5, 1.5, "contrast_down", "contrast_up", function(v) return pct(v) end },
        { "COLOUR",     "saturation", 0, 2,     "sat_down",      "sat_up",      function(v) return pct(v) end },
        { "GLASS SHINE", "shine",     0, 1,     "shine_down",    "shine_up",    function(v) return pct(v) end },
        { "BEZEL GLOW", "bezel",      0, 1,     "bezel_down",    "bezel_up",    function(v) return pct(v) end },
        { "TRACKING",   "track",     -1, 1,     "track_down",    "track_up",
          function(v) local n = math.floor(v * 100 + 0.5); return n == 0 and "CENTRED" or string.format("%+d", n) end, 21, true },
    }
    local cur = adjustable[sel]
    local val = st[cur[2]] or cur[3]
    local py = 666
    shape(p_rrect(X(20), Y(py), S(290), S(96), S(8)), "#0a0a0d", "#030304", S(1.6))                      -- recessed panel
    rim(p_rrect(X(20), Y(py), S(290), S(96), S(8)), "#ffffff", 0xCC, S(1.2), X(16), Y(py) + S(84), X(314), Y(py) + S(102))
    key { id = "sel_prev", x = 27, y = py + 8, w = 38, h = 34, icon = "left", is = 13, r = 7,
          action = function() sel = (sel - 2) % #adjustable + 1; render() end }
    key { id = "sel_next", x = 265, y = py + 8, w = 38, h = 34, icon = "right", is = 13, r = 7,
          action = function() sel = sel % #adjustable + 1; render() end }
    text(cur[1], X(165), Y(py + 16), S(11), C.accent, true)
    text(cur[7](val), X(165), Y(py + 36), S(21), "#e8e8ee", true)
    -- segmented level meter
    local segs = cur[8] or 20
    local lit = math.floor((val - cur[3]) / (cur[4] - cur[3]) * (segs - 1) + 0.5) + 1
    if (cur[3] == 0 and val <= 0.0001 and segs == 20) then lit = 0 end
    local lo, hi = 1, lit                                     -- lit segments; a centred meter lights from the middle out
    if cur[9] then local mid = (segs + 1) / 2; lo, hi = math.min(mid, lit), math.max(mid, lit) end
    local mx, mw = 34, 262
    local gap = S(2)
    local sw = (S(mw) - gap * (segs - 1)) / segs
    local litp, dimp = {}, {}
    for i = 1, segs do
        local x0 = X(mx) + (i - 1) * (sw + gap)
        local p = string.format("m %.1f %.1f l %.1f %.1f l %.1f %.1f l %.1f %.1f", x0, Y(py + 62), x0 + sw, Y(py + 62), x0 + sw, Y(py + 80), x0, Y(py + 80))
        if i >= lo and i <= hi then litp[#litp + 1] = p else dimp[#dimp + 1] = p end
    end
    if #dimp > 0 then layer(table.concat(dimp, " "), "#2a1405", 0x00, 0) end
    if #litp > 0 then
        layer(table.concat(litp, " "), "#ff6a00", 0x70, S(2.4))
        layer(table.concat(litp, " "), "#ffa23a", 0x00, 0)
    end
    key { id = "adj_dn", x = 20, y = py + 106, w = 135, h = 48, icon = "minus", is = 18, rep = true,
          action = function() mp.commandv("script-message", "crt-do", cur[5]) end }
    key { id = "adj_up", x = 175, y = py + 106, w = 135, h = 48, icon = "plus", is = 18, rep = true,
          action = function() mp.commandv("script-message", "crt-do", cur[6]) end }

    local function small(i, y, id, label, act, rep, led, disabled)
        key { id = id, x = 20 + (i - 1) * 75, y = y, w = 65, h = 42, label = label, fs = 12, action = act, rep = rep, led = led, disabled = disabled }
    end
    small(1, 836, "sub", "SUBS", cmd("cycle", "sub"), nil, pl.sub, not pl.has_sub)
    key { id = "aud", x = 95, y = 836, w = 65, h = 42, label = "LANG", fs = 12,
          disabled = pl.audio_n < 2, action = next_audio }
    small(3, 836, "slow", "SLOW", cmd("add", "speed", -0.25), true)
    small(4, 836, "fast", "FAST", cmd("add", "speed", 0.25), true)
    small(1, 886, "full", "FULL", cmd("cycle", "fullscreen"), nil, pl.fs)
    small(2, 886, "loop", "LOOP", cmd("cycle-values", "loop-file", "inf", "no"), nil, pl.loop)
    small(3, 886, "shot", "SHOT", cmd("screenshot"))
    small(4, 886, "list", "LIST", cmd("script-binding", "select/select-playlist"))

    -- maker's mark engraved into the body under the last row; clicking it opens the website
    do
        local bx, by, bw, bh = 62, 936, 206, 22
        local cx, cy = X(bx + bw / 2), Y(by + bh / 2)
        local fs = S(13)
        local hov = hover == "brand"
        -- engraved into the plastic: a lit lip on the lower wall, a shadowed top wall, a dark recessed floor
        text("RETROGROUNDS", cx + S(0.6), cy + S(0.8), fs, "#4a4a55", true)                       -- lit lower edge
        text("RETROGROUNDS", cx - S(0.4), cy - S(0.5), fs, "#000000", true)                       -- shadowed upper edge
        text("RETROGROUNDS", cx, cy, fs, hov and C.accent or "#0b0b0d", true)                     -- the recessed floor
        buttons[#buttons + 1] = { id = "brand", x1 = X(bx), y1 = Y(by), x2 = X(bx + bw), y2 = Y(by + bh), action = open_site }
        byid.brand = buttons[#buttons]
    end
    return true, w, h
end

render = function()
    if not open then return end
    local ok, w, h = build()
    if not ok then return end
    overlay.res_x, overlay.res_y = w, h
    overlay.data = table.concat(lines, "\n")
    overlay:update()
end

local function hit(mx, my)
    for i = #buttons, 1, -1 do
        local b = buttons[i]
        if mx >= b.x1 and mx <= b.x2 and my >= b.y1 and my <= b.y2 then return b.id end
    end
end

local function inside(mx, my)
    return mx >= L.ox and mx <= L.ox + L.rw and my >= L.oy and my <= L.oy + L.rh
end

-- while the pointer is over the remote, own the left mouse button so clicks (and rapid
-- double clicks, which would otherwise toggle fullscreen) go to the remote only
local capturing = false
local function flash_ir()
    ir = true
    if ir_timer then ir_timer:kill() end
    ir_timer = mp.add_timeout(IR_HOLD, function() ir = false; render() end)
end

-- preset keys are programmable: a short click recalls the preset, holding the key for HOLD_SAVE seconds
-- saves the current look into it, and a right-click resets it to the factory preset.
local HOLD_SAVE = tonumber(mp.get_opt("crt-hold-seconds")) or 0.8
local hold = nil
-- is the pointer still on this key? (the developer self-test drives keys without a pointer)
local function pointer_on(id)
    if (mp.get_opt("crt-remote-test") or ""):match("^%a+sim:") then return true end
    local m = mp.get_property_native("mouse-pos")
    return m ~= nil and hit(m.x, m.y) == id
end
local function preset_number(id) return tonumber(id and id:match("^p(%d)$")) end

-- a key goes down (mouse press): preset keys start the hold-to-save timer, other keys act at once
local function key_down(id)
    local b = byid[id]
    if not b then return end
    pressed = id
    flash_ir()
    local n = preset_number(id)
    if n and n >= 7 then
        if hold then return end                        -- second half of a double click
        hold = { id = id, saved = false }
        hold.timer = mp.add_timeout(HOLD_SAVE, function()
            if not pointer_on(id) then return end      -- the pointer slid off the key: no save
            hold.saved = true
            mp.commandv("script-message", "crt-do", "slot_save_" .. n)
            flash_ir(); render()
        end)
        render()
        return
    end
    local ok, err = pcall(b.action)
    if not ok then msg.error("remote action failed: " .. tostring(err)) end
    render()
    mp.add_timeout(0.12, function() if pressed == id then pressed = nil; render() end end)
end

-- the button is released: a short press on a preset key recalls it (released somewhere else, it does nothing)
local function key_up()
    if not hold then return end
    local h = hold; hold = nil
    h.timer:kill()
    if not h.saved and pointer_on(h.id) then
        local ok, err = pcall(byid[h.id] and byid[h.id].action or function() end)
        if not ok then msg.error("remote action failed: " .. tostring(err)) end
    end
    mp.add_timeout(0.12, function() if pressed == h.id then pressed = nil; render() end end)
    render()
end

local function key_right(id)
    local n = preset_number(id)
    if not n or n < 7 then return end                  -- factory presets 1-6 are locked
    pressed = id
    flash_ir()
    mp.commandv("script-message", "crt-do", "slot_clear_" .. n)
    render()
    mp.add_timeout(0.12, function() if pressed == id then pressed = nil; render() end end)
end

local function on_click(e)
    if not open then return end
    if e.event == "up" then key_up(); return end
    if e.event ~= "down" and e.event ~= "repeat" and e.event ~= "press" then return end
    local m = mp.get_property_native("mouse-pos")
    if not m then return end
    local id = hit(m.x, m.y)
    if not id then return end
    if e.event == "repeat" and not byid[id].rep then return end
    key_down(id)
end

local function on_right_click(e)
    if not open or e.event ~= "down" then return end
    local m = mp.get_property_native("mouse-pos")
    if m then key_right(hit(m.x, m.y)) end
end

local function set_capture(on)
    if on == capturing then return end
    capturing = on
    if on then
        mp.add_forced_key_binding("MBTN_LEFT", "crt-remote-click", on_click, { complex = true, repeatable = true })
        -- a double click already arrives as two clicks; the extra double-click event is swallowed (it would
        -- otherwise toggle fullscreen, or press the key a third time)
        mp.add_forced_key_binding("MBTN_LEFT_DBL", "crt-remote-dbl", function() end)
        mp.add_forced_key_binding("MBTN_RIGHT", "crt-remote-rclick", on_right_click, { complex = true })
    else
        -- the pointer left the remote with a preset key held: its release will not reach us, so cancel the hold
        if hold then hold.timer:kill(); hold = nil; pressed = nil; render() end
        mp.remove_key_binding("crt-remote-click")
        mp.remove_key_binding("crt-remote-dbl")
        mp.remove_key_binding("crt-remote-rclick")
    end
end

close = function()
    open = false
    if hold then hold.timer:kill(); hold = nil end
    pcall(mp.set_property_native, "user-data/crt-remote", { remote = false })
    hover, pressed = nil, nil
    set_capture(false)
    mp.remove_key_binding("crt-remote-esc")
    overlay:remove()
end

local function show()
    open = true
    pcall(mp.set_property_native, "user-data/crt-remote", { remote = true })
    mp.add_forced_key_binding("ESC", "crt-remote-esc", close)
    render()
end

local function toggle()
    if open then close() else show() end
end

mp.observe_property("mouse-pos", "native", function(_, m)
    if not open or not m then return end
    local id = nil
    local over = (m.hover ~= false or mp.get_opt("crt-remote-test") ~= nil) and inside(m.x, m.y)
    if over then id = hit(m.x, m.y) end
    set_capture(over)
    if id ~= hover then hover = id; render() end
end)

mp.observe_property("user-data/crt", "native", function(_, v) st = v or {}; render() end)
mp.observe_property("pause", "bool", function(_, v) pl.pause = v and true or false; render() end)
mp.observe_property("mute", "bool", function(_, v) pl.mute = v and true or false; render() end)
mp.observe_property("volume", "number", function(_, v) pl.volume = v or 100; render() end)
local function off(v) return v == nil or v == false or v == "no" end
mp.observe_property("sid", "native", function(_, v) pl.sub = not off(v) and mp.get_property_bool("sub-visibility", true); render() end)
mp.observe_property("sub-visibility", "bool", function(_, v) pl.sub = (v ~= false) and not off(mp.get_property_native("sid")); render() end)
mp.observe_property("aid", "native", function(_, v) pl.audio = not off(v); render() end)
mp.observe_property("speed", "number", function(_, v) pl.speed = v or 1; render() end)
mp.observe_property("fullscreen", "bool", function(_, v) pl.fs = v and true or false; render() end)
mp.observe_property("loop-file", "native", function(_, v) pl.loop = not off(v); render() end)
mp.observe_property("track-list", "native", function(_, tl)
    local subs, auds = 0, 0
    for _, t in ipairs(tl or {}) do
        if t.type == "sub" then subs = subs + 1 elseif t.type == "audio" then auds = auds + 1 end
    end
    pl.has_sub, pl.audio_n = subs > 0, auds
    render()
end)
mp.observe_property("osd-dimensions", "native", function() render() end)

-- the hover bar sends script-message crt-remote-toggle; the bar also stays usable
-- (a patched click on its "i" button opens this remote)
mp.register_script_message("crt-remote-toggle", toggle)
mp.add_key_binding("r", "crt-remote", toggle)

-- always shown at start. Closing it only lasts for that session; script-opts-append=crt-remote-start=no
-- in config/mpv.conf is the only way to start hidden.
if mp.get_opt("crt-remote-start") ~= "no" then show() end

-- when the file ends / player idles, make sure the capture binding does not linger
mp.register_event("shutdown", function() if open then close() end end)

-- Developer self-test: --script-opts=crt-remote-test=open | hover:XxY | click:XxY | barclick:XxY | press:ID
-- (barclick presses the real left button at XxY, e.g. on the hover bar's remote button)
local test = mp.get_opt("crt-remote-test")
if test then
    mp.register_event("file-loaded", function()
        mp.add_timeout(1.5, function()
            local mode = test:match("^(%a+)")
            if mode ~= "barclick" and not open then show() end
            local sim, sid = test:match("^(%a+sim):([%w_]+)$")      -- holdsim:p3 / clicksim:p3 / rclicksim:p3 drive the key code directly
            if sim == "holdsim" then
                mp.add_timeout(1, function() key_down(sid) end)
                mp.add_timeout(2.5, function() key_up() end)
            elseif sim == "clicksim" then
                mp.add_timeout(1, function() key_down(sid) end)
                mp.add_timeout(1.2, function() key_up() end)
            elseif sim == "rclicksim" then
                mp.add_timeout(1, function() key_right(sid) end)
            end
            local pid = test:match("^press:([%w_]+)$")
            if pid then
                mp.add_timeout(1, function()
                    local b = byid[pid]
                    if b then pressed = pid; ir = true; if ir_timer then ir_timer:kill() end; ir_timer = mp.add_timeout(IR_HOLD, function() ir = false; render() end); b.action(); render() else msg.error("no such button: " .. pid) end
                end)
            end
            local x, y = test:match("^%a+:(%d+)x(%d+)$")
            local kid = test:match("^%a+:([%a][%w_]*)$")          -- e.g. hold:p3 targets that key's centre
            if kid and kid ~= pid and byid[kid] then
                local b = byid[kid]
                x, y = tostring(math.floor((b.x1 + b.x2) / 2)), tostring(math.floor((b.y1 + b.y2) / 2))
            end
            if x then
                mp.add_timeout(1, function() mp.commandv("mouse", x, y) end)
                if mode == "click" then
                    mp.add_timeout(2, function() mp.commandv("mouse", x, y, "0", "single") end)
                elseif mode == "hold" then
                    mp.add_timeout(1.6, function() mp.commandv("keydown", "MBTN_LEFT") end)
                    mp.add_timeout(3.0, function() mp.commandv("keyup", "MBTN_LEFT") end)
                elseif mode == "rclick" then
                    mp.add_timeout(1.6, function() mp.commandv("keydown", "MBTN_RIGHT") end)
                    mp.add_timeout(1.7, function() mp.commandv("keyup", "MBTN_RIGHT") end)
                elseif mode == "barclick" then
                    mp.add_timeout(1.6, function() mp.commandv("keydown", "MBTN_LEFT") end)
                    mp.add_timeout(1.7, function() mp.commandv("keyup", "MBTN_LEFT") end)
                end
            end
        end)
    end)
end
