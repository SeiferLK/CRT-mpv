-- CRT-mpv's own buttons on the hover bar. ModernZ has no slot for extra buttons, so some of its own that CRT-mpv
-- does not use are re-dressed each time it builds its elements (the installer appends the call to modernz.lua):
-- the screenshot button becomes the YouTube button, the pin (always on top) button the night-mode switch, and the
-- shuffle button the library (open a video) button, the "i" (info) button the CRT remote button, and the file loop
-- button the About button. What the first two do when clicked is set in
-- script-opts/modernz.conf; shuffle has no such option, so its click is replaced here. The icons are ASS shapes:
-- ModernZ's icon font has none of them.
local M = {}

local YOUTUBE = "{\\p1}m 4.5 0 l 17.5 0 b 20 0 22 2 22 4.5 l 22 11.5 b 22 14 20 16 17.5 16 l 4.5 16 b 2 16 0 14 0 11.5 "
    .. "l 0 4.5 b 0 2 2 0 4.5 0 m 8.5 4.5 l 8.5 11.5 l 15 8{\\p0}"
local MOON = "{\\p1}m 8.4 0.0 l 6.8 0.3 l 5.2 0.8 l 3.8 1.7 l 2.5 2.7 l 1.5 4.0 l 0.7 5.5 l 0.2 7.1 l 0.0 8.7 l 0.1 10.4 "
    .. "l 0.5 12.0 l 1.2 13.5 l 2.1 14.8 l 3.3 16.0 l 4.7 16.9 l 6.2 17.6 l 7.8 17.9 l 9.5 18.0 l 11.1 17.8 l 12.7 17.2 "
    .. "l 14.1 16.4 l 15.4 15.4 l 16.4 14.1 l 17.2 12.7 l 17.8 11.1 l 16.4 11.7 l 15.0 12.0 l 13.6 12.0 l 12.1 11.7 "
    .. "l 10.8 11.2 l 9.6 10.4 l 8.6 9.4 l 7.7 8.2 l 7.2 6.9 l 6.8 5.5 l 6.8 4.0 l 7.1 2.6 l 7.6 1.2{\\p0}"
local FOLDER = "{\\p1}m 0 1 l 6.5 1 l 8.5 3 l 18 3 l 18 5 l 0 5 m 0 6.5 l 18 6.5 l 18 15 l 0 15{\\p0}"
-- a handheld remote: rounded body with a power dot and a grid of buttons punched out of it
local REMOTE = "{\\p1}m 2.5 0 l 7.5 0 b 8.9 0 10 1.1 10 2.5 l 10 13.5 b 10 14.9 8.9 16 7.5 16 l 2.5 16 "
    .. "b 1.1 16 0 14.9 0 13.5 l 0 2.5 b 0 1.1 1.1 0 2.5 0 "
    .. "m 3.8 2 l 3.8 4.4 l 6.2 4.4 l 6.2 2 "
    .. "m 1.8 6.4 l 1.8 8.6 l 4.2 8.6 l 4.2 6.4 m 5.8 6.4 l 5.8 8.6 l 8.2 8.6 l 8.2 6.4 "
    .. "m 1.8 9.8 l 1.8 12 l 4.2 12 l 4.2 9.8 m 5.8 9.8 l 5.8 12 l 8.2 12 l 8.2 9.8 "
    .. "m 1.8 13.2 l 1.8 14.4 l 4.2 14.4 l 4.2 13.2 m 5.8 13.2 l 5.8 14.4 l 8.2 14.4 l 8.2 13.2{\\p0}"
-- an "i" in a filled circle: the circle clockwise, the dot and the stem punched out of it counter-clockwise
local ABOUT = "{\\p1}m 8 0 b 12.4 0 16 3.6 16 8 b 16 12.4 12.4 16 8 16 b 3.6 16 0 12.4 0 8 b 0 3.6 3.6 0 8 0 "
    .. "m 7 3.2 l 7 5.2 l 9 5.2 l 9 3.2 m 7 7 l 7 12.8 l 9 12.8 l 9 7{\\p0}"
local LIT = "{\\1c&H3282FF&}"            -- the remote's orange (#ff8232): the moon while night mode is on

local function night() return mp.get_property_native("user-data/crt/night") == true end   -- published by crt.lua

function M.attach(elements)
    for _, e in pairs(elements) do
        if e.name == "screenshot" then
            e.content, e.tooltipF = YOUTUBE, "YouTube"
        elseif e.name == "ontop" then
            e.content = function() return night() and LIT .. MOON or MOON end
            e.tooltipF = function() return night() and "Night mode off" or "Night mode" end
        elseif e.name == "file_loop" then
            e.content, e.tooltipF = ABOUT, "About"
        elseif e.name == "info" then
            e.content = REMOTE
        elseif e.name == "shuffle" then
            e.content, e.tooltipF = FOLDER, "Library"
            e.eventresponder["mbtn_left_up"] = function() mp.commandv("script-message", "crt-open") end
        end
    end
end

return M
