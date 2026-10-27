-- CRT-mpv's own buttons on the hover bar. ModernZ has no slot for extra buttons, so three of its own that CRT-mpv
-- does not use are re-dressed each time it builds its elements (the installer appends the call to modernz.lua):
-- the screenshot button becomes the YouTube button, the pin (always on top) button the night-mode switch, and the
-- shuffle button the eject (open a video) button. What the first two do when clicked is set in
-- script-opts/modernz.conf; shuffle has no such option, so its click is replaced here. The icons are ASS shapes:
-- ModernZ's icon font has none of them.
local M = {}

local YOUTUBE = "{\\p1}m 4.5 0 l 17.5 0 b 20 0 22 2 22 4.5 l 22 11.5 b 22 14 20 16 17.5 16 l 4.5 16 b 2 16 0 14 0 11.5 "
    .. "l 0 4.5 b 0 2 2 0 4.5 0 m 8.5 4.5 l 8.5 11.5 l 15 8{\\p0}"
local MOON = "{\\p1}m 8.4 0.0 l 6.8 0.3 l 5.2 0.8 l 3.8 1.7 l 2.5 2.7 l 1.5 4.0 l 0.7 5.5 l 0.2 7.1 l 0.0 8.7 l 0.1 10.4 "
    .. "l 0.5 12.0 l 1.2 13.5 l 2.1 14.8 l 3.3 16.0 l 4.7 16.9 l 6.2 17.6 l 7.8 17.9 l 9.5 18.0 l 11.1 17.8 l 12.7 17.2 "
    .. "l 14.1 16.4 l 15.4 15.4 l 16.4 14.1 l 17.2 12.7 l 17.8 11.1 l 16.4 11.7 l 15.0 12.0 l 13.6 12.0 l 12.1 11.7 "
    .. "l 10.8 11.2 l 9.6 10.4 l 8.6 9.4 l 7.7 8.2 l 7.2 6.9 l 6.8 5.5 l 6.8 4.0 l 7.1 2.6 l 7.6 1.2{\\p0}"
local EJECT = "{\\p1}m 9 0 l 18 10 l 0 10 m 0 13 l 18 13 l 18 16 l 0 16{\\p0}"
local LIT = "{\\1c&H3282FF&}"            -- the remote's orange (#ff8232): the moon while night mode is on

local function night() return mp.get_property_native("user-data/crt/night") == true end   -- published by crt.lua

function M.attach(elements)
    for _, e in pairs(elements) do
        if e.name == "screenshot" then
            e.content, e.tooltipF = YOUTUBE, "YouTube"
        elseif e.name == "ontop" then
            e.content = function() return night() and LIT .. MOON or MOON end
            e.tooltipF = function() return night() and "Night mode off" or "Night mode" end
        elseif e.name == "shuffle" then
            e.content, e.tooltipF = EJECT, "Open a video"
            e.eventresponder["mbtn_left_up"] = function() mp.commandv("script-message", "crt-open") end
        end
    end
end

return M
