-- CRT-mpv: composites the video into a TV picture inside mpv's video filter
-- pipeline (so on-screen controls and subtitles draw on top of the TV), and
-- drives the CRT shader in shaders/crt.glsl, which is limited to the TV screen.
--
-- The TV pictures in overlays/*.png are plain opaque backgrounds. At load time
-- an ffmpeg filter graph scales one to the canvas (the largest 16:9 area that fits the desktop) and cuts a
-- transparent hole at the screen rectangle given in overlays/tvs.json; the
-- video is scaled into that hole and the TV is laid over it.
local utils = require 'mp.utils'
package.path = mp.command_native({"expand-path", "~~/script-modules/"}) .. "/?.lua;" .. package.path   -- shared helper modules
local settings = require 'crt_settings'
local saved = settings.load()          -- what the remote left set last time (config/settings.json)

local dir = mp.command_native({"expand-path", "~~/overlays"})
local f = io.open(dir .. "/tvs.json", "rb")
local tvs = f and utils.parse_json(f:read("*a")) or {}
if f then f:close() end
-- leave out TVs whose picture is missing (a failed download, or a tvs.json entry without its .png)
for i = #tvs, 1, -1 do
    local png = io.open(dir .. "/" .. tvs[i].name .. ".png", "rb")
    if png then png:close() else mp.msg.warn("TV picture missing, skipped: " .. tvs[i].name); table.remove(tvs, i) end
end

local BASE_W, BASE_H = 1920, 1080   -- canvas size, set from the desktop resolution (canvas_size below)

-- The canvas is the largest 16:9 area that fits the display the player is on (the TV pictures are 16:9),
-- so the TV is composited at the user's own resolution instead of a fixed size. Override the height with
-- script-opts-append=crt-canvas-height=1080 to trade sharpness for less CPU on very large displays.
local function canvas_size()
    local dw, dh = mp.get_property_number("display-width"), mp.get_property_number("display-height")
    if not dw or not dh or dw <= 0 or dh <= 0 then return 1920, 1080 end      -- not known yet
    local h = dh
    local w = h * 16 / 9
    if w > dw then w = dw; h = w * 9 / 16 end
    local cap = tonumber(mp.get_opt("crt-canvas-height"))
    if cap and cap > 0 and h > cap then h = cap; w = h * 16 / 9 end
    local function even(v) return math.max(2, math.floor(v / 2 + 0.5) * 2) end
    return even(w), even(h)
end
local idx, overlay_on, crt_on = 1, saved.frame ~= false, saved.crt ~= false
local wanted = mp.get_opt("crt-tv") or saved.tv or "Generic_White_TV"
for i, t in ipairs(tvs) do
    if t.name == wanted then idx = i end
end

-- 16:9 mode: TV up/down only steps through the widescreen TVs (or, when off, only the 4:3 ones). A TV counts
-- as widescreen from the shape of its screen rectangle (the canvas is 16:9, so scale the fractions back to pixels).
local function is_wide(t) return t and (t.r - t.l) * 16 > (t.b - t.t) * 9 * 1.6 end
local wide = is_wide(tvs[idx]) or false
local last_tv = { [true] = saved.tv_wide, [false] = saved.tv_43 }   -- the TV last used in each mode
if tvs[idx] then last_tv[wide] = tvs[idx].name end

local P = { scan = 0.35, lines = 240, curve = 0.30, mask = 0.12, vig = 0.30, glow = 0.25, shine = tonumber(mp.get_opt("crt-shine")) or 0.30,
           bezel = tonumber(mp.get_opt("crt-bezel-glow")) or 0.65,
           noise = tonumber(mp.get_opt("crt-noise")) or 0.12,
           ntsc = tonumber(mp.get_opt("crt-ntsc")) or 0,
           contrast = 1.0, saturation = 1.0, track = 0 }
for k in pairs(P) do if type(saved[k]) == "number" then P[k] = saved[k] end end
local R = { rl = 0, rt = 0, rr = 1, rb = 1 }
-- Preset keys 1-6 are factory presets and can never be overwritten. Keys 7-9 are user slots: hold the key on the
-- remote (or press Ctrl+7..9) to save the current look into it, right-click it (or Alt+7..9) to empty it. A preset
-- is only the look: recalling it never changes the TV. Keyed by "7".."9" so they save cleanly as JSON.
local FIRST_USER = 7
local slots = {}
if type(saved.slots) == "table" then
    for k, v in pairs(saved.slots) do
        if (tonumber(k) or 0) >= FIRST_USER and type(v) == "table" then
            v.tv = nil                                  -- presets saved by 1.0 / 1.1 also stored the TV
            slots[k] = v
        end
    end
end
local SLOT_KEYS = { "scan", "lines", "curve", "mask", "vig", "glow", "shine", "bezel", "noise", "ntsc", "contrast", "saturation", "track" }
local muted = false
local night = saved.night == true    -- night mode: the room lights are off (the shader darkens the TV around the screen)
local episode_osd = 0       -- transient playlist episode number; 0 hides the on-screen digits
local episode_timer = nil
-- factory presets all have perfect VHS tracking (track = 0), so recalling one also re-tunes the picture
local presets = {
    { "Subtle",  { scan = 0.15, lines = 240, curve = 0.15, mask = 0.00, vig = 0.15, glow = 0.15, noise = 0.05, ntsc = 0, contrast = 1.00, saturation = 1.00, track = 0 } },
    { "Classic", { scan = 0.35, lines = 240, curve = 0.30, mask = 0.12, vig = 0.30, glow = 0.25, noise = 0.12, ntsc = 0, contrast = 1.00, saturation = 1.00, track = 0 } },
    { "Heavy",   { scan = 0.65, lines = 240, curve = 0.40, mask = 0.30, vig = 0.40, glow = 0.35, noise = 0.20, ntsc = 0, contrast = 1.08, saturation = 1.05, track = 0 } },
    { "Anime",   { scan = 0.25, lines = 240, curve = 0.25, mask = 0.06, vig = 0.25, glow = 0.45, noise = 0.08, ntsc = 1, contrast = 1.00, saturation = 1.15, track = 0 } },
    { "VHS",     { scan = 0.30, lines = 160, curve = 0.30, mask = 0.00, vig = 0.45, glow = 0.55, noise = 0.10, ntsc = 2, contrast = 0.90, saturation = 0.80, track = 0 } },
    { "Arcade",  { scan = 0.80, lines = 288, curve = 0.45, mask = 0.40, vig = 0.35, glow = 0.30, noise = 0.10, ntsc = 0, contrast = 1.10, saturation = 1.20, track = 0 } },
}

-- Short-lived effects driven from Lua: the power-on warm-up, the power-off collapse, the burst of static when the
-- channel changes, and the degauss wobble. fxt is their own clock, so they also animate while the video is paused.
local ANIMATE = mp.get_opt("crt-animations") ~= "no"
local FX = { warm = 1, off = 0, snow = 0, degauss = 0, t = 0, night = night and 1 or 0 }   -- night fades in and out
if ANIMATE and crt_on then FX.warm = 0 end           -- the screen stays dark until the first frame warms it up

local function push_opts()
    mp.set_property("glsl-shader-opts", string.format(
        "scan=%.3f,lines=%.1f,curve=%.3f,mask=%.3f,vig=%.3f,glow=%.3f,shine=%.3f,bezel=%.3f,night=%.3f,noise=%.3f,ntsc=%d,contrast=%.3f,saturation=%.3f,track=%.3f,mute=%d,episode=%d,"
        .. "warm=%.4f,poweroff=%.4f,snow=%.3f,degauss=%.3f,fxt=%.3f,rl=%.5f,rt=%.5f,rr=%.5f,rb=%.5f",
        P.scan, P.lines, P.curve, P.mask, P.vig, P.glow, P.shine, overlay_on and P.bezel or 0, FX.night, P.noise, math.floor(P.ntsc + 0.5), P.contrast, P.saturation, P.track,
        muted and 1 or 0, episode_osd, FX.warm, FX.off, FX.snow, FX.degauss, FX.t, R.rl, R.rt, R.rr, R.rb))
end

-- runs only while an animation is playing; each one gets its progress p (0..1) every frame
local anims, anim_timer = {}, nil
local function anim_tick()
    local now, finished = mp.get_time(), {}
    for name, a in pairs(anims) do
        local p = math.min(1, (now - a.t0) / a.dur)
        a.fn(p)
        if p >= 1 then anims[name] = nil; finished[#finished + 1] = a.done end
    end
    FX.t = now % 1000
    push_opts()
    if next(anims) == nil and anim_timer then anim_timer:kill(); anim_timer = nil end
    for _, done in ipairs(finished) do done() end
end
local function animate(name, dur, fn, done)
    anims[name] = { t0 = mp.get_time(), dur = dur, fn = fn, done = done or function() end }
    if not anim_timer then anim_timer = mp.add_periodic_timer(1 / 60, anim_tick) end
end

-- the degauss "thunk" and fading mains hum, synthesised by ffmpeg in a second, windowless mpv (no sound files)
local function play_sfx(expr, seconds)
    if mp.get_opt("crt-sfx") == "no" or mp.get_property_bool("mute") then return end
    local vol = mp.get_property_number("volume") or 100
    if vol <= 0.5 then return end
    local exe = os.getenv("CRT_MPV") or "mpv"
    if package.config:sub(1, 1) == "\\" then      -- Windows: the portable mpv next to the config folder, if it is there
        local root = utils.split_path((mp.command_native({"expand-path", "~~/"}):gsub("[/\\]+$", "")))
        local portable = utils.join_path(root, "mpv\\mpv.exe")
        if utils.file_info(portable) then exe = portable end
    end
    mp.command_native_async({ name = "subprocess", playback_only = false, capture_stdout = true, capture_stderr = true,
        -- cplayer mode, no window, no idle: launched without a console, mpv would otherwise open a window and wait
        args = { exe, "--player-operation-mode=cplayer", "--no-config", "--no-video", "--force-window=no", "--idle=no",
                 "--really-quiet", "--no-terminal", "--volume=" .. math.floor(vol + 0.5),
                 "av://lavfi:aevalsrc=" .. expr .. ":d=" .. seconds .. ":s=48000" } },
        function(_, res) if res and res.status ~= 0 then mp.msg.warn("sound effect failed: " .. (res.stderr or "")) end end)
end

local function say(msg) mp.osd_message(msg, 1.5) end

-- The no-signal static is stretched over the whole TV screen (4:3 or 16:9) instead of fitted inside it with black
-- bars, and with nearest-neighbour scaling so its blocks stay sharp. Set from the on_load hook below, before the
-- first frame is built.
local fill_screen = false
local STATIC_BLOCK = 3       -- static grain size in canvas pixels on a 1440 high canvas; scales with the canvas

local function graph_for(tv)
    local hw = math.floor((tv.r - tv.l) * BASE_W + 0.5)
    local hh = math.floor((tv.b - tv.t) * BASE_H + 0.5)
    local hx = math.floor(tv.l * BASE_W + 0.5)
    local hy = math.floor(tv.t * BASE_H + 0.5)
    -- ffmpeg filter-graph path escaping: forward slashes, escaped drive colon
    local path = (dir .. "/" .. tv.name .. ".png"):gsub("\\", "/"):gsub(":", "\\:")
    -- The canvas is composited in planar yuv420 (1.5 bytes per pixel) instead of RGBA (4 bytes per pixel): about
    -- twice as fast on the CPU and a third of the data to upload. Everything is pinned to BT.709 limited range so
    -- the TV picture (converted from RGB) and the video agree and no colour shift is introduced.
    local fit
    if fill_screen then
        -- static: a grid of whole-pixel blocks (square, STATIC_BLOCK canvas pixels), so no block is wider than the next
        local block = math.max(2, math.floor(STATIC_BLOCK * BASE_H / 1440 + 0.5))
        local cols, rows = math.max(1, math.floor(hw / block + 0.5)), math.max(1, math.floor(hh / block + 0.5))
        fit = string.format("scale=%d:%d:flags=neighbor,scale=%d:%d:flags=neighbor,scale=%d:%d:flags=neighbor",
            cols, rows, cols * block, rows * block, hw, hh)
    else
        fit = string.format("scale=%d:%d:force_original_aspect_ratio=decrease:flags=lanczos", hw, hh)
    end
    return string.format(
        "[in]scale=trunc(iw*sar/2)*2:ih,setsar=1,"
        .. fit .. ":out_color_matrix=bt709:out_range=tv,setsar=1,"
        .. "pad=%d:%d:%d+(%d-iw)/2:%d+(%d-ih)/2:black,format=yuv420p[v];"
        .. "movie='%s',scale=%d:%d:flags=lanczos:out_color_matrix=bt709:out_range=tv,format=yuva420p,"
        .. "drawbox=x=%d:y=%d:w=%d:h=%d:color=black@0:t=fill:replace=1[tv];"
        .. "[v][tv]overlay=format=yuv420:eof_action=repeat,"
        .. "setparams=colorspace=bt709:range=tv:color_primaries=bt709:color_trc=bt709[out]",
        BASE_W, BASE_H, hx, hw, hy, hh,
        path, BASE_W, BASE_H, hx, hy, hw, hh)
end

local applied = false
local function apply()
    if #tvs == 0 then return end
    applied = true
    BASE_W, BASE_H = canvas_size()
    if overlay_on then
        local tv = tvs[idx]
        R.rl, R.rt, R.rr, R.rb = tv.l, tv.t, tv.r, tv.b
        mp.set_property_native("vf", { { name = "lavfi", params = { graph = graph_for(tv) } } })
        -- keep subtitles inside the TV screen. Margins are in mpv's 1280x720 virtual units; forcing the
        -- override makes styled (ASS) subtitles obey them too, and a smaller font keeps lines inside the glass.
        -- "strip" turns styled (ASS) subtitles into plain text so they obey the margins below; set
        -- script-opts-append=crt-subs-keep-style=yes to keep ASS styling (then they may leave the screen).
        local keep = mp.get_opt("crt-subs-keep-style") == "yes"
        mp.set_property("sub-ass-override", keep and "scale" or "strip")
        mp.set_property_bool("sub-ass-force-margins", not keep)
        mp.set_property_number("sub-margin-y", tonumber(mp.get_opt("crt-sub-my")) or math.floor((1 - tv.b) * 720 + 14 + 0.5))   -- integer options; lands just above the glass bottom
        -- side margins sized so a subtitle line is as wide as the TV screen (with a little padding); 489.8 is
        -- the measured width of half the frame in sub-margin units when subtitles are blended into the video
        mp.set_property_number("sub-margin-x", tonumber(mp.get_opt("crt-sub-mx")) or math.floor((1 - (tv.r - tv.l) * 0.93) * 489.8 + 0.5))
        mp.set_property_number("sub-font-size", tonumber(mp.get_opt("crt-sub-fs")) or 34)
        -- blend subtitles into the video image so the CRT shader (curvature, scanlines, mask, glow) applies to them too
        mp.set_property("blend-subtitles", "video")
    else
        R.rl, R.rt, R.rr, R.rb = 0, 0, 1, 1
        mp.set_property_native("vf", {})
        mp.set_property("sub-ass-override", "scale")
        mp.set_property_bool("sub-ass-force-margins", false)
        mp.set_property_number("sub-margin-y", 22)
        mp.set_property_number("sub-margin-x", 25)
        mp.set_property_number("sub-font-size", 55)
        mp.set_property("blend-subtitles", "no")
    end
    push_opts()
end

-- the no-signal static (see NO_SIGNAL in open.lua) fills the screen; any real video is fitted inside it again
mp.add_hook("on_load", 40, function()
    local fill = (mp.get_property("stream-open-filename") or ""):find("^av://lavfi:color=c=gray") ~= nil
    if fill == fill_screen then return end
    fill_screen = fill
    if applied and overlay_on then apply() end
end)

-- what preset key n recalls: the user's saved slot if there is one, otherwise the factory preset
local NSLOTS = 9      -- keys 1-6 start as factory presets, keys 7-9 start empty (programmable only)
local function slot_values(n)
    local sl = slots[tostring(n)]
    if type(sl) == "table" then return sl, true end
    if presets[n] then return presets[n][2], false end
    return nil, false                                   -- an empty user slot
end

-- the preset key whose values match the current settings: returns its number and name (0, "" when customised)
local function current_preset()
    for n = 1, NSLOTS do
        local vals, custom = slot_values(n)
        if vals then
            local same = true
            for k, v in pairs(vals) do
                if math.abs((P[k] or 0) - v) > 0.001 then same = false; break end
            end
            if same then return n, custom and ("SLOT " .. n) or presets[n][1] end
        end
    end
    return 0, ""
end

local function publish()
    pcall(mp.set_property_native, "user-data/crt", {
        tv = tvs[idx] and tvs[idx].name or "", frame = overlay_on, crt = crt_on,
        wide = wide, tv_wide = last_tv[true], tv_43 = last_tv[false], night = night,
        scan = P.scan, curve = P.curve, lines = P.lines, mask = P.mask, vig = P.vig, glow = P.glow, shine = P.shine, bezel = P.bezel, noise = P.noise, ntsc = P.ntsc, contrast = P.contrast, saturation = P.saturation, track = P.track,
        preset = select(2, current_preset()), preset_n = (current_preset()),
        slots = slots,
    })
end

local function adj(key, delta, lo, hi, label)
    return function()
        P[key] = math.max(lo, math.min(hi, P[key] + delta)); push_opts()
        say(string.format("%s %.2f", label, P[key])); publish()
    end
end

-- a burst of static that clears, like changing channel. It holds for the first part, because switching TV
-- rebuilds the filter graph and the first new frames take a moment to arrive.
local function static_burst(dur)
    if not ANIMATE or not crt_on then return end
    animate("snow", dur, function(p) FX.snow = p < 0.4 and 0.95 or 0.95 * ((1 - p) / 0.6) ^ 1.6 end)
end

local function track_by(delta)
    P.track = math.max(-1, math.min(1, math.floor((P.track + delta) * 100 + 0.5) / 100)); push_opts()
    local v = math.floor(P.track * 100 + 0.5)
    say(v == 0 and "Tracking: centred" or string.format("Tracking %+d", v)); publish()
end

local power_going = false

-- show TV i, keeping 16:9 mode in step with it and remembering it as the last TV of its kind
local function show_tv(i, msg)
    idx = i; wide = is_wide(tvs[idx]) or false; last_tv[wide] = tvs[idx].name
    overlay_on = true; apply(); static_burst(0.6); say(msg or ("TV: " .. tvs[idx].name)); publish()
end

-- the next TV in direction dir (1 or -1) of the current mode; every TV if that mode has none
local function step_tv(dir)
    local any = false
    for _, t in ipairs(tvs) do if (is_wide(t) or false) == wide then any = true; break end end
    local i = idx
    for _ = 1, #tvs do
        i = (i - 1 + dir) % #tvs + 1
        if not any or (is_wide(tvs[i]) or false) == wide then return i end
    end
    return idx
end

-- 16:9 mode on or off: go back to the TV last used in that mode, else the one whose screen is closest to 16:9 / 4:3
local function set_wide(want)
    if want == wide then say(want and "Already on the 16:9 TVs" or "Already on the 4:3 TVs"); return end
    local first, best
    local target = want and 16 / 9 or 4 / 3
    for i, t in ipairs(tvs) do
        if (is_wide(t) or false) == want then
            if t.name == last_tv[want] then first = i; break end
            local off = math.abs((t.r - t.l) * 16 / ((t.b - t.t) * 9) - target)
            if not best or off < best then first, best = i, off end
        end
    end
    if not first then say(want and "No 16:9 TVs installed" or "No 4:3 TVs installed"); return end
    show_tv(first, (want and "16:9 TVs: " or "4:3 TVs: ") .. tvs[first].name)
end

-- every action is reachable from a key, from the on-screen remote (script-message crt-do <name>)
local actions = {
    tv_next = function()
        if #tvs == 0 then return end
        show_tv(step_tv(1))
    end,
    tv_prev = function()
        if #tvs == 0 then return end
        show_tv(step_tv(-1))
    end,
    -- the remote's 16:9 key and `w`: switch to the widescreen TVs (back to the last one used) or to the 4:3 TVs
    wide = function() set_wide(not wide) end,
    wide_on = function() set_wide(true) end,
    wide_off = function() set_wide(false) end,
    -- VHS tracking: 0 is a perfectly tuned tape; either way off adds a rolling noise band, torn lines and
    -- head-switching noise at the bottom, the way a mistuned VCR looks
    track_up   = function() track_by(0.05) end,
    track_down = function() track_by(-0.05) end,
    -- the degauss coil: a thunk, then the picture wobbles and swirls with colour while the field dies away
    degauss = function()
        if not crt_on then say("Degauss needs the CRT effect on"); return end
        play_sfx("0.42*exp(-28*t)*sin(2*PI*46*t)+0.22*exp(-260*t)*(2*random(0)-1)"
            .. "+0.26*exp(-2.2*t)*(sin(2*PI*60*t)+0.5*sin(2*PI*120*t)+0.3*sin(2*PI*180*t)+0.12*sin(2*PI*300*t))", 1.8)
        animate("degauss", 1.8, function(p) FX.degauss = math.min(1, p * 14) * (1 - p) ^ 1.7 end)
    end,
    -- PWR on the remote: the picture collapses to a line, then a dot, then the player quits
    power_off = function()
        if power_going or not ANIMATE or not crt_on then mp.commandv("quit"); return end   -- a second press quits at once
        power_going = true
        mp.set_property_bool("pause", true)                            -- the sound cuts out with the picture
        mp.commandv("script-message", "osc-visibility", "never", "no-osd")   -- and the hover bar stays away
        mp.osd_message("")
        animate("off", 0.6, function(p) FX.off = p end, function() mp.commandv("quit") end)   -- long enough to see it speed up
        mp.add_timeout(2, function() mp.commandv("quit") end)          -- in case the animation stalls
    end,
    -- night mode (the hover bar's moon button): the room lights go out, so the TV and the room around the screen
    -- fade dark and the screen's glow on the TV shows a little more. The picture itself is unchanged.
    night = function()
        if not night and not (crt_on and overlay_on) then say("Night mode needs the TV frame and the CRT effect on"); return end
        night = not night
        local from, to = FX.night, night and 1 or 0
        if ANIMATE then animate("night", 0.6, function(p) FX.night = from + (to - from) * p * p * (3 - 2 * p) end)
        else FX.night = to; push_opts() end
        say(night and "Night mode on" or "Night mode off"); publish()
    end,
    frame = function()
        overlay_on = not overlay_on; apply(); say("TV overlay " .. (overlay_on and "on" or "off")); publish()
    end,
    crt = function()
        crt_on = not crt_on
        mp.set_property("glsl-shaders", crt_on and mp.command_native({"expand-path", "~~/shaders/crt.glsl"}) or "")
        say("CRT shader " .. (crt_on and "on" or "off")); publish()
    end,
    -- the remote's single CRT key: TV frame and CRT effect together (on if either is off, else both off)
    screen = function()
        local on = not (overlay_on and crt_on)
        overlay_on, crt_on = on, on
        mp.set_property("glsl-shaders", on and mp.command_native({"expand-path", "~~/shaders/crt.glsl"}) or "")
        apply(); say("CRT " .. (on and "on" or "off")); publish()
    end,
    scan_up    = adj("scan",  0.05, 0, 1, "Scanlines"),
    scan_down  = adj("scan", -0.05, 0, 1, "Scanlines"),
    curve_up   = adj("curve", 0.05, 0, 1, "Curvature"),
    curve_down = adj("curve",-0.05, 0, 1, "Curvature"),
    contrast_up   = adj("contrast",   0.05, 0.5, 1.5, "Contrast"),
    contrast_down = adj("contrast",  -0.05, 0.5, 1.5, "Contrast"),
    sat_up        = adj("saturation", 0.05, 0.0, 2.0, "Colour"),
    sat_down      = adj("saturation",-0.05, 0.0, 2.0, "Colour"),
    shine_up   = adj("shine", 0.05, 0, 1, "Reflection"),
    shine_down = adj("shine",-0.05, 0, 1, "Reflection"),
    bezel_up   = adj("bezel", 0.05, 0, 1, "Bezel glow"),
    bezel_down = adj("bezel",-0.05, 0, 1, "Bezel glow"),
    noise_up   = adj("noise", 0.05, 0, 1, "Noise"),
    noise_down = adj("noise",-0.05, 0, 1, "Noise"),
    ntsc_up    = function() P.ntsc = math.min(3, math.floor(P.ntsc + 0.5) + 1); push_opts(); say("Signal: " .. ({[0] = "clean", "S-Video", "composite", "RF"})[P.ntsc]); publish() end,
    ntsc_down  = function() P.ntsc = math.max(0, math.floor(P.ntsc + 0.5) - 1); push_opts(); say("Signal: " .. ({[0] = "clean", "S-Video", "composite", "RF"})[P.ntsc]); publish() end,
    lines_up   = adj("lines", 12, 60, 720, "Lines"),
    lines_down = adj("lines",-12, 60, 720, "Lines"),
}
for n = 1, NSLOTS do
    local pr = presets[n]
    actions["preset_" .. n] = function()
        local vals, custom = slot_values(n)
        if not vals then say("Preset " .. n .. " is empty: hold its key to save the current look here"); return end
        for k, v in pairs(vals) do P[k] = v end
        push_opts(); say((custom and "Saved preset " .. n or "Preset: " .. pr[1])); publish()
    end
    -- programmable: store the look on screen now (not the TV) in this slot
    actions["slot_save_" .. n] = function()
        if n < FIRST_USER then say("Preset " .. n .. " is a factory preset and cannot be overwritten (keys 7-9 are programmable)"); return end
        local sl = {}
        for _, k in ipairs(SLOT_KEYS) do sl[k] = P[k] end
        slots[tostring(n)] = sl
        say("Saved to preset " .. n .. " (right-click or Alt+" .. n .. " to empty it)"); publish()
    end
    actions["slot_clear_" .. n] = function()
        if n < FIRST_USER then return end
        slots[tostring(n)] = nil
        say("Preset " .. n .. " emptied"); publish()
    end
end

mp.register_script_message("crt-do", function(name)
    local fn = actions[name]
    if fn then fn() else mp.msg.warn("unknown crt-do action: " .. tostring(name)) end
end)

mp.add_key_binding("t", "crt-next-tv", actions.tv_next)
mp.add_key_binding("T", "crt-prev-tv", actions.tv_prev)
mp.add_key_binding("w", "crt-toggle-wide", actions.wide)
mp.add_key_binding("o", "crt-toggle-tv", actions.frame)
mp.add_key_binding("c", "crt-toggle-crt", actions.crt)
mp.add_key_binding("]", "crt-scan-up",    actions.scan_up,    {repeatable = true})
mp.add_key_binding("[", "crt-scan-down",  actions.scan_down,  {repeatable = true})
mp.add_key_binding("v", "crt-signal-up",   actions.ntsc_up)
mp.add_key_binding("V", "crt-signal-down", actions.ntsc_down)
mp.add_key_binding("ctrl+UP",   "crt-contrast-up",   actions.contrast_up,   {repeatable = true})
mp.add_key_binding("ctrl+DOWN", "crt-contrast-down", actions.contrast_down, {repeatable = true})
mp.add_key_binding("alt+UP",    "crt-colour-up",     actions.sat_up,        {repeatable = true})
mp.add_key_binding("alt+DOWN",  "crt-colour-down",   actions.sat_down,      {repeatable = true})
mp.add_key_binding("n", "crt-noise-up",    actions.noise_up,   {repeatable = true})
mp.add_key_binding("N", "crt-noise-down",  actions.noise_down, {repeatable = true})
mp.add_key_binding("}", "crt-curve-up",   actions.curve_up,   {repeatable = true})
mp.add_key_binding("{", "crt-curve-down", actions.curve_down, {repeatable = true})
mp.add_key_binding(".", "crt-lines-up",   actions.lines_up,   {repeatable = true})
mp.add_key_binding(",", "crt-lines-down", actions.lines_down, {repeatable = true})
mp.add_key_binding(")", "crt-tracking-up",   actions.track_up,   {repeatable = true})
mp.add_key_binding("(", "crt-tracking-down", actions.track_down, {repeatable = true})
mp.add_key_binding("D", "crt-degauss", actions.degauss)
for n = 1, NSLOTS do
    mp.add_key_binding(tostring(n), "crt-preset-" .. n, actions["preset_" .. n])
    if n >= FIRST_USER then
        mp.add_key_binding("ctrl+" .. n, "crt-slot-save-" .. n, actions["slot_save_" .. n])
        mp.add_key_binding("alt+" .. n, "crt-slot-clear-" .. n, actions["slot_clear_" .. n])
    end
end

-- The green "MUTE" on-screen display is drawn by the shader (so it curves, glows and has scanlines
-- like the picture); here we only tell the shader whether audio is muted.
-- "muted" means the mute switch is on OR the volume has been turned all the way down
local mute_switch, volume_level = false, 100
local function update_mute()
    local now = mute_switch or volume_level <= 0.5
    if now ~= muted then muted = now; push_opts() end
end
mp.observe_property("mute", "bool", function(_, v) mute_switch = v and true or false; update_mute() end)
mp.observe_property("volume", "number", function(_, v) volume_level = v or 100; update_mute() end)

-- the display size is only known once the window exists, so wait for it (fall back to 1920x1080 after a second)
if not crt_on then mp.set_property("glsl-shaders", "") end      -- the CRT effect was left off last time
if mp.get_property_number("display-width") then apply() else push_opts(); publish() end

-- the real display size is only known once the window exists, and changes if the window moves to another
-- monitor: rebuild the canvas when it changes
local canvas_timer
local function on_display_change()
    if canvas_timer then canvas_timer:kill() end
    canvas_timer = mp.add_timeout(0.25, function()
        local w, h = canvas_size()
        if not applied or w ~= BASE_W or h ~= BASE_H then apply() end
    end)
end
mp.add_timeout(1.0, function() if not applied then apply() end end)
mp.observe_property("display-width", "number", on_display_change)
mp.observe_property("display-height", "number", on_display_change)

-- Power-on: the first picture warms up out of a thin bright line, starting as soon as the video output is up.
-- Later episodes arrive through a burst of static.
local first_picture, new_file = true, false
local last_loaded_episode_pos = nil
-- A new playlist entry is an episode regardless of whether it was selected with
-- the remote, a keyboard shortcut, the playlist UI or automatic advancement.
-- Hide the startup entry; only a genuine change displays the episode number.
local function show_episode_number(pos)
    episode_osd = math.min(pos + 1, 99999)
    if episode_timer then episode_timer:kill() end
    push_opts()
    episode_timer = mp.add_timeout(2.0, function()
        episode_osd = 0
        episode_timer = nil
        push_opts()     -- if muted, the persistent MUTE display returns
    end)
end
local function warm_up()
    if not first_picture then return end
    first_picture = false
    if FX.warm < 1 then animate("warm", 1.6, function(p) FX.warm = p end) end
end
-- start when the TV picture itself arrives (the canvas size), not the bare video shown for a moment before the
-- TV graph is built; with the TV frame off, start with the first picture
mp.observe_property("video-out-params", "native", function(_, v)
    if v and v.w and (not overlay_on or (applied and v.w == BASE_W and v.h == BASE_H)) then warm_up() end
end)
mp.register_event("file-loaded", function()
    local pos = mp.get_property_number("playlist-pos", -1)
    if pos >= 0 then
        if last_loaded_episode_pos ~= nil and pos ~= last_loaded_episode_pos then
            show_episode_number(pos)
        end
        last_loaded_episode_pos = pos
    end
    if not first_picture then new_file = true end
    mp.add_timeout(10, warm_up)            -- no video output at all (audio-only file, broken video): warm up anyway
end)
mp.register_event("playback-restart", function()
    if first_picture then warm_up()
    elseif new_file then new_file = false; static_burst(0.5) end
end)

-- Noise uses the shader's automatic PTS parameter. Updating glsl-shader-opts
-- on every time-pos change flushes gpu-next's renderer cache every frame.

-- Self-test hook (used to produce docs/preview.png):
--   mpv ... --script-opts=crt-shot=/path/out.png  -> screenshot the window, then quit
local shot = mp.get_opt("crt-shot")
if shot then
    mp.register_event("file-loaded", function()
        mp.add_timeout(4, function()
            mp.commandv("screenshot-to-file", shot, "window")
            mp.add_timeout(1, function() mp.commandv("quit") end)
        end)
    end)
end
