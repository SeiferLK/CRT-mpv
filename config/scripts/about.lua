-- CRT-mpv About window.
-- Opened from the "i" button on the hover bar (ModernZ's file loop button, redrawn by script-modules/crt_bar.lua) or
-- `script-message crt-about`. Shows the installed version (the VERSION file) and links to Ko-fi and Retrogrounds.
local mp = require 'mp'
local utils = require 'mp.utils'

local KOFI = "https://ko-fi.com/retrogrounds"
local SITE = "https://retrogrounds.com/?utm_source=crt_mpv&utm_medium=app&utm_campaign=about&utm_content=retrogrounds_button"

local config_dir = mp.command_native({"expand-path", "~~/"}):gsub("[/\\]+$", "")
local root = config_dir:gsub("[/\\][^/\\]+$", "")       -- the CRT-mpv folder (config's parent)

local function version()
    local f = io.open(utils.join_path(root, "VERSION"), "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return (s:gsub("%s+", ""))
end

local function open_link(url)
    local plat = mp.get_property("platform") or (package.config:sub(1, 1) == "\\" and "windows" or "linux")
    local args
    if plat == "windows" then args = { "cmd", "/c", "start", "", (url:gsub("&", "^&")) }   -- ^& stops cmd.exe cutting the link at each &
    elseif plat == "darwin" then args = { "open", url }
    else args = { "xdg-open", url } end
    mp.command_native_async({ name = "subprocess", args = args, playback_only = false, capture_stdout = true, capture_stderr = true },
        function() end)
end

package.path = mp.command_native({"expand-path","~~/script-modules/"}) .. "/?.lua;" .. package.path
local view = require('crt_menu_view').new()
local about, hide
local modal = require('crt_modal').new("about", function() if about then hide(false) end end)
local BINDINGS = {}
local ORDER = {"done", "site", "coffee", "close"}

local TEXT = "Thank you for using CRT-mpv. If you like this software, consider buying me a coffee or joining Retrogrounds"
    .. "\194\160-my growing retro gaming community project."

local function draw()
    if not about then view:close(); return end
    view:render_dialog({
        id="about", title="About CRT-mpv", subtitle="Version "..(version() or "unknown"),
        text=TEXT, hover=about.hover, focus=about.focus,
        buttons={{id="done",label="Close",width=82},{id="site",label="Retrogrounds",width=140},
            {id="coffee",label="Buy me a coffee",width=160,primary=true}},
        hint="Enter  Choose    Tab  Next    Esc  Close",
        suspended=mp.get_property_native("window-minimized")==true,
    })
end

hide = function(resume)
    if not about then return end
    about = nil
    for _, name in ipairs(BINDINGS) do mp.remove_key_binding(name) end
    BINDINGS = {}
    modal:release(resume)
    view:close()
end

local function action(id)
    if id == "coffee" then open_link(KOFI)
    elseif id == "site" then open_link(SITE)
    else hide(true) end
end

local function hit_at(m)
    for _, b in ipairs(view.hits) do
        if m.x >= b.x1 and m.x <= b.x2 and m.y >= b.y1 and m.y <= b.y2 then return b.id end
    end
end
local function click()
    local m = mp.get_property_native("mouse-pos")
    if not about or not m then return end
    local id = hit_at(m)
    if id then action(id) end
end
local function tab(delta)
    local at = 0
    for i, id in ipairs(ORDER) do if id == about.focus then at = i end end
    about.focus = ORDER[(at - 1 + delta) % #ORDER + 1]
    draw()
end
local function nothing() end

local function show()
    if about then hide(true); return end
    about = { focus = "coffee" }
    modal:acquire()
    local keys = {
        {"MBTN_LEFT",click},{"MBTN_LEFT_DBL",nothing},{"MBTN_RIGHT",nothing},
        {"ENTER",function() action(about.focus) end},{"KP_ENTER",function() action(about.focus) end},
        {"ESC",function() hide(true) end},{"TAB",function() tab(1) end},{"Shift+TAB",function() tab(-1) end},
        {"LEFT",function() tab(-1) end},{"RIGHT",function() tab(1) end},
        {"UP",nothing},{"DOWN",nothing},{"WHEEL_UP",nothing},{"WHEEL_DOWN",nothing},
        {"SPACE",nothing},{"any_unicode",nothing},
    }
    for i, key in ipairs(keys) do
        local name = "crt-about-dialog-"..i
        BINDINGS[#BINDINGS+1] = name
        mp.add_forced_key_binding(key[1], name, key[2])
    end
    draw()
end

mp.observe_property("mouse-pos", "native", function(_, m)
    if not about or not m then return end
    local id = hit_at(m)
    if id ~= about.hover then about.hover = id; draw() end
end)
mp.observe_property("osd-dimensions", "native", function() if about then draw() end end)
mp.observe_property("window-minimized", "bool", function() if about then draw() end end)
mp.register_event("shutdown", function() if about then hide(false) end end)
mp.register_script_message("crt-about", show)
