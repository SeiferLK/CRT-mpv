-- CRT-mpv YouTube link window.
-- Opened from the YouTube button on the hover bar (ModernZ's screenshot button, patched by the installer) or
-- `script-message crt-youtube`. A panel in the remote's colours with a link field: paste or type a YouTube link and
-- press Play (or Enter), and it plays on the TV like any other video (mpv's ytdl_hook fetches it with yt-dlp, which
-- the installer puts in config/). Paste fills the field from the clipboard (Ctrl+V pastes too); Esc cancels.
-- If the link cannot be played, the video that was playing comes back and the panel opens again with the link.
local mp = require 'mp'
local utils = require 'mp.utils'

local WIN = package.config:sub(1, 1) == "\\"

-- yt-dlp needs a JavaScript runtime for YouTube and only looks for one on the PATH. On a computer that has none,
-- the installer puts Deno in the config folder: point yt-dlp at it.
local deno = mp.find_config_file(WIN and "deno.exe" or "deno")
if deno then
    local raw = mp.get_property_native("ytdl-raw-options") or {}
    raw["js-runtimes"] = "deno:" .. deno
    mp.set_property_native("ytdl-raw-options", raw)
end

local ov = mp.create_osd_overlay("ass-events")
ov.z = 1000                                             -- above the remote
local box = nil              -- the open panel: { text, error, hover, buttons, caret, was_paused }
local pending = nil          -- a link that is loading: { url, prev, pos }
local restore_pos = nil      -- where to put the previous video back to once it has loaded again
local blink = nil

local function hex(c)
    local r, g, b = c:match("#(%x%x)(%x%x)(%x%x)")
    return string.format("&H%s%s%s&", b, g, r)
end

local function rrect(x, y, w, h, r)
    local x2, y2 = x + w, y + h
    return string.format(
        "m %.1f %.1f l %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f l %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f "
        .. "l %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f l %.1f %.1f b %.1f %.1f %.1f %.1f %.1f %.1f",
        x + r, y, x2 - r, y, x2, y, x2, y, x2, y + r, x2, y2 - r, x2, y2, x2, y2, x2 - r, y2,
        x + r, y2, x, y2, x, y2, x, y2 - r, x, y + r, x, y, x, y, x + r, y)
end

-- typed text shown as-is: braces would start ASS tags, and a backslash could form \N
local function esc(s)
    return (s:gsub("\\", "\\\226\129\160"):gsub("{", "\\{"):gsub("}", "\\}"))
end

local function draw()
    if not box then ov:remove(); return end
    local dim = mp.get_property_native("osd-dimensions") or {}
    local W, H = dim.w or 0, dim.h or 0
    if W <= 0 or H <= 0 then return end
    local s = math.min(W / 1280, H / 720)
    local out = {}
    local function shape(path, fill, stroke, alpha, blur)
        out[#out + 1] = string.format("{\\an7\\pos(0,0)\\1c%s\\3c%s\\bord%.1f\\shad0\\1a&H%02X&\\blur%.1f\\p1}%s",
            hex(fill), hex(stroke or fill), stroke and 1.5 * s or 0, alpha or 0, blur or 0, path)
    end
    local function text(str, x, y, size, color, bold, an, clip)
        out[#out + 1] = string.format("{\\an%d\\pos(%.1f,%.1f)%s\\fs%.1f\\1c%s\\bord0\\shad0\\b%d}%s",
            an or 7, x, y, clip and string.format("\\clip(%.1f,%.1f,%.1f,%.1f)", table.unpack(clip)) or "",
            size * s, hex(color), bold and 1 or 0, str)
    end
    local function button(id, label, x, y, w, h, primary)
        local hov = box.hover == id
        local fill = primary and (hov and "#ff9a52" or "#ff8232") or (hov and "#464652" or "#2d2d35")
        shape(rrect(x, y + 3 * s, w, h, 12 * s), "#09090c")                            -- side wall
        shape(rrect(x, y, w, h, 12 * s), fill, "#08080b")                               -- cap
        text(label, x + w / 2, y + h / 2, 20, primary and "#140904" or "#e8e8ee", true, 5)
        box.buttons[#box.buttons + 1] = { id = id, x1 = x, y1 = y, x2 = x + w, y2 = y + h }
    end

    local pw, ph = 640 * s, 292 * s
    local px, py = (W - pw) / 2, (H - ph) / 2
    box.buttons = {}
    shape(rrect(0, 0, W, H, 0), "#000000", nil, 0x60)                                   -- dim the picture
    shape(rrect(px - 6 * s, py + 4 * s, pw + 12 * s, ph + 12 * s, 26 * s), "#000000", nil, 0x50, 10 * s)   -- shadow
    shape(rrect(px, py, pw, ph, 22 * s), "#151518", "#383840")                          -- the panel
    text("Play a YouTube video", px + 30 * s, py + 26 * s, 30, "#ff8232", true)
    text("Paste the link of a YouTube video. It plays on the TV like any other video.", px + 30 * s, py + 68 * s, 17, "#74747e")

    -- the link field: a recessed slot, with the Paste button beside it
    local fx, fy, fw, fh = px + 30 * s, py + 104 * s, pw - 194 * s, 46 * s
    shape(rrect(fx, fy, fw, fh, 10 * s), "#0a0a0d", "#383840")
    local caret = string.format("{\\1c%s\\1a&H%02X&}|", hex("#ff8232"), box.caret and 0 or 0xFF)
    local clip = { fx, fy, fx + fw - 10 * s, fy + fh }
    if box.text == "" then
        text(caret .. "{\\1c" .. hex("#4a4a55") .. "\\1a&H00&}https://www.youtube.com/watch?v=...",
            fx + 14 * s, fy + fh / 2, 20, "#e8e8ee", false, 4, clip)
    else
        -- the field cannot measure text, so a long link shows its end (about 0.52 em per character)
        local fit = math.max(8, math.floor((fw - 34 * s) / (20 * s * 0.52)))
        local shown = box.text
        if #shown > fit then shown = "\226\128\166" .. shown:sub(-(fit - 1)):gsub("^[\128-\191]+", "") end
        text(esc(shown) .. caret, fx + 14 * s, fy + fh / 2, 20, "#e8e8ee", false, 4, clip)
    end
    box.buttons[#box.buttons + 1] = { id = "field", x1 = fx, y1 = fy, x2 = fx + fw, y2 = fy + fh }
    button("paste", "Paste", fx + fw + 14 * s, fy, 120 * s, fh)

    if box.error then text(box.error, fx, py + 164 * s, 16, "#e0493b") end

    local by, bh = py + ph - 100 * s, 46 * s
    button("play", "Play", px + 30 * s, by, 150 * s, bh, true)
    button("cancel", "Cancel", px + 194 * s, by, 130 * s, bh)
    text("Enter: play     Ctrl+V: paste     Esc: cancel", px + pw - 26 * s, py + ph - 24 * s, 13, "#74747e", false, 3)

    ov.res_x, ov.res_y = W, H
    ov.data = table.concat(out, "\n")
    ov:update()
end

local function set_text(t)
    box.text, box.error, box.caret = t, nil, true
    draw()
end

local function insert(t)
    t = t:gsub("%c", "")                                -- no line breaks or other control characters
    if t ~= "" then set_text(box.text .. t) end
end

-- the clipboard as text: mpv's clipboard property (mpv 0.40+), else the system's own tool
local function read_clipboard(cb)
    local t = mp.get_property("clipboard/text")
    if t and t ~= "" then cb(t); return end
    local plat = mp.get_property("platform") or ""
    local args
    if WIN then args = { "powershell", "-NoProfile", "-Command", "Get-Clipboard -Raw" }
    elseif plat == "darwin" then args = { "pbpaste" }
    elseif os.getenv("WAYLAND_DISPLAY") then args = { "wl-paste", "--no-newline" }
    else args = { "xclip", "-o", "-selection", "clipboard" } end
    mp.command_native_async({ name = "subprocess", args = args, playback_only = false, capture_stdout = true, capture_stderr = true },
        function(ok, res) cb(ok and res and res.status == 0 and res.stdout or nil) end)
end

-- the Paste button replaces what is in the field; Ctrl+V adds to it, like typing
local function paste(replace)
    read_clipboard(function(t)
        if not box then return end
        t = ((t or ""):gsub("^%s+", ""):match("^[^\r\n]*") or ""):gsub("%s+$", "")
        if t == "" then box.error = "The clipboard has no text in it. Copy the video's link first."; draw(); return end
        if replace then box.text = "" end
        insert(t)
    end)
end

-- a link mpv can open, or nil and the reason
local function link(t)
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" then return nil, "Paste the link of a YouTube video first." end
    if t:match("^youtu%.be/") or t:match("^[%w.-]*youtube%.com/") then t = "https://" .. t end   -- copied without https://
    if not t:match("^https?://%S+$") then return nil, "That is not a link. Copy the address of a YouTube video." end
    return t
end

-- the file playing now, as an absolute path (URLs stay as they are)
local function current_file()
    local path = mp.get_property("path")
    if not path or path:find("://", 1, true) or path:match("^%a%a+:") then return path end
    return utils.join_path(mp.get_property("working-directory") or "", path)
end

local hide, show

local function submit()
    if not box then return end
    local url, err = link(box.text)
    if not url then box.error = err; draw(); return end
    pending = { url = url, prev = current_file(), pos = mp.get_property_number("time-pos") }
    hide(false)
    mp.set_property("idle", "yes")                      -- a link that fails to load must not close the player
    mp.osd_message("Loading the YouTube video...", 30)
    mp.commandv("loadfile", url, "replace")
    mp.set_property_bool("pause", false)
end

local function click()
    local m = mp.get_property_native("mouse-pos")
    if not box or not m then return end
    for _, b in ipairs(box.buttons or {}) do
        if m.x >= b.x1 and m.x <= b.x2 and m.y >= b.y1 and m.y <= b.y2 then
            if b.id == "play" then submit() elseif b.id == "paste" then paste(true) elseif b.id == "cancel" then hide(true) end
            return
        end
    end
end

local function nothing() end
local KEYS = {
    { "MBTN_LEFT", click }, { "MBTN_LEFT_DBL", nothing },          -- no fullscreen toggle under the panel
    { "ENTER", submit }, { "KP_ENTER", submit }, { "ESC", function() hide(true) end },
    { "Ctrl+v", function() paste(false) end }, { "Shift+INS", function() paste(false) end },
    { "BS", function() set_text((box.text:gsub("[\1-\127\194-\244][\128-\191]*$", ""))) end, { repeatable = true } },
    { "Ctrl+BS", function() set_text("") end },
    -- typed characters go into the field, not to the player's own keys
    { "any_unicode", function(e) if e.event ~= "up" and e.key_text then insert(e.key_text) end end,
      { complex = true, repeatable = true } },
    -- keys that would otherwise seek or skip behind the panel
    { "LEFT", nothing }, { "RIGHT", nothing }, { "UP", nothing }, { "DOWN", nothing },
    { "HOME", nothing }, { "END", nothing }, { "PGUP", nothing }, { "PGDWN", nothing }, { "DEL", nothing }, { "TAB", nothing },
}

hide = function(resume)
    if not box then return end
    if resume and not box.was_paused then mp.set_property_bool("pause", false) end
    box = nil
    if blink then blink:kill(); blink = nil end
    for i = 1, #KEYS do mp.remove_key_binding("crt-youtube-" .. i) end
    draw()
end

show = function(text, err)
    if box then return end
    box = { text = text or "", error = err, caret = true, was_paused = mp.get_property_bool("pause") }
    mp.set_property_bool("pause", true)
    for i, k in ipairs(KEYS) do mp.add_forced_key_binding(k[1], "crt-youtube-" .. i, k[2], k[3]) end
    blink = mp.add_periodic_timer(0.53, function() box.caret = not box.caret; draw() end)
    draw()
end

mp.observe_property("mouse-pos", "native", function(_, m)
    if not box or not m then return end
    local id
    for _, b in ipairs(box.buttons or {}) do
        if b.id ~= "field" and m.x >= b.x1 and m.x <= b.x2 and m.y >= b.y1 and m.y <= b.y2 then id = b.id end
    end
    if id ~= box.hover then box.hover = id; draw() end
end)
mp.observe_property("osd-dimensions", "native", function() if box then draw() end end)

mp.register_event("file-loaded", function()
    if restore_pos then mp.commandv("seek", restore_pos, "absolute"); restore_pos = nil end
    if pending then pending = nil; mp.osd_message("", 0) end
end)

-- the link did not play (yt-dlp missing or out of date, a private or removed video, no internet): put the previous
-- video back where it was and show the panel again with the link, so it can be fixed
mp.register_event("end-file", function(e)
    if not pending or e.reason ~= "error" then return end
    local p = pending
    pending = nil
    mp.osd_message("", 0)
    if p.prev then
        restore_pos = p.pos
        mp.commandv("loadfile", p.prev, "replace")
    end
    show(p.url, "That video could not be played. Check the link, or try again later.")
end)

mp.register_script_message("crt-youtube", function() show() end)
