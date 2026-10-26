-- Remembers the remote-control settings between runs: saved to config/settings.json shortly after every
-- change and again when the player exits, restored the next time it starts.
--   TV, TV frame, CRT effect, scanlines / curvature / line count / mask / vignette / glow (so the preset),
--   volume, mute, loop. (The remote itself is always shown at start.)
-- (crt.lua and remote.lua read their own part of the file when they start.)
package.path = mp.command_native({"expand-path", "~~/script-modules/"}) .. "/?.lua;" .. package.path   -- shared helper modules
local cs = require 'crt_settings'
if not cs.enabled then return end

local saved = cs.load()
local current = {}
for k, v in pairs(saved) do current[k] = v end

local timer
local function save_now()
    if timer then timer:kill(); timer = nil end
    cs.save(current)
end
local function save_soon()
    if timer then timer:kill() end
    timer = mp.add_timeout(1.5, save_now)
end

local function take(prefix, keys)
    return function(_, v)
        if type(v) ~= "table" then return end
        for _, k in ipairs(keys) do
            if v[k] ~= nil then current[prefix and (prefix .. k) or k] = v[k] end
        end
        save_soon()
    end
end

-- published by crt.lua and remote.lua
mp.observe_property("user-data/crt", "native", take(nil, { "tv", "frame", "crt", "scan", "curve", "lines", "mask", "vig", "glow", "shine", "bezel", "noise", "ntsc", "contrast", "saturation", "track", "slots" }))

-- plain player properties
local function observe(prop, key, kind)
    mp.observe_property(prop, kind, function(_, v)
        if v == nil then return end
        current[key] = v
        save_soon()
    end)
end

-- restore volume / mute / loop from the last run
if saved.volume ~= nil then mp.set_property_number("volume", saved.volume) end
if saved.mute ~= nil then mp.set_property_bool("mute", saved.mute) end
if saved.loop ~= nil then mp.set_property("loop-file", saved.loop and "inf" or "no") end

observe("volume", "volume", "number")
observe("mute", "mute", "bool")
mp.observe_property("loop-file", "native", function(_, v)
    if v == nil then return end
    current.loop = not (v == false or v == "no")
    save_soon()
end)

mp.register_event("shutdown", save_now)
