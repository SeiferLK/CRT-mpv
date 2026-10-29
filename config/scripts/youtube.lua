-- CRT-mpv YouTube link window.
-- Opened from the YouTube button on the hover bar (ModernZ's screenshot button, patched by the installer) or
-- `script-message crt-youtube`. A shared CRT panel with a link field: paste or type a YouTube link and
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

package.path = mp.command_native({"expand-path","~~/script-modules/"}) .. "/?.lua;" .. package.path
local view = require('crt_menu_view').new()
local box, pending, restore_pos, blink
local hide, show
local modal = require('crt_modal').new("youtube",function() if box then hide(false) end end)

local function draw()
    if not box then view:close(); return end
    view:render_dialog({
        id="youtube",title="Watch on YouTube",subtitle="Paste a video link to play it on your TV.",
        input={text=box.text,cursor=box.cursor,all=box.all,caret=box.caret},
        error=box.error,hover=box.hover,focus=box.focus,
        buttons={{id="cancel",label="Cancel",width=94},{id="play",label="Play video",width=126,primary=true}},
        hint="Enter  Play    Ctrl+V  Paste    Esc  Cancel",
        suspended=mp.get_property_native("window-minimized")==true,
    })
end
local function focus(id)
    if not box then return end
    box.focus,box.caret=id,true
    if blink then blink:kill(); blink=nil end
    if id=="field" then
        blink=mp.add_periodic_timer(.53,function()
            if box and not mp.get_property_native("window-minimized") then box.caret=not box.caret; draw() end
        end)
    end
    draw()
end
local function previous(text,pos)
    if pos<=0 then return 0 end
    local before=text:sub(1,pos):gsub("[\1-\127\194-\244][\128-\191]*$","")
    return #before
end
local function following(text,pos)
    if pos>=#text then return #text end
    local char=text:sub(pos+1):match("^[\1-\127\194-\244][\128-\191]*")
    return pos+#(char or "")
end

local function set_text(t,cursor)
    box.text, box.error, box.caret, box.all = t, nil, true, false
    box.cursor=cursor or #t
    focus("field")
end

local function insert(t)
    t = t:gsub("%c", "")                                -- no line breaks or other control characters
    if t ~= "" then
        if box.all then box.text,box.cursor="",0 end
        if #box.text+#t>4096 then box.error="This link is too long."; draw(); return end
        set_text(box.text:sub(1,box.cursor)..t..box.text:sub(box.cursor+1),box.cursor+#t)
    end
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
    local target=box
    read_clipboard(function(t)
        if not box or box~=target then return end
        t = ((t or ""):gsub("^%s+", ""):match("^[^\r\n]*") or ""):gsub("%s+$", "")
        if t == "" then box.error = "The clipboard has no text in it. Copy the video's link first."; draw(); return end
        if replace then box.text,box.cursor = "",0 end
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

local function action(id)
    if id=="play" then submit()
    elseif id=="paste" then paste(true)
    elseif id=="cancel" or id=="close" then hide(true)
    elseif id=="field" then focus("field") end
end
local function click()
    local m = mp.get_property_native("mouse-pos")
    if not box or not m then return end
    for _, b in ipairs(view.hits) do
        if m.x >= b.x1 and m.x <= b.x2 and m.y >= b.y1 and m.y <= b.y2 then
            action(b.id)
            return
        end
    end
end

local function nothing() end
local function tab(delta)
    local order={"field","paste","cancel","play","close"}
    local at=1
    for i,id in ipairs(order) do if id==box.focus then at=i end end
    focus(order[(at-1+delta)%#order+1])
end
local function erase(forward)
    if box.all then set_text(""); return end
    local pos=box.cursor
    if forward then set_text(box.text:sub(1,pos)..box.text:sub(following(box.text,pos)+1),pos)
    else
        local prior=previous(box.text,pos)
        set_text(box.text:sub(1,prior)..box.text:sub(pos+1),prior)
    end
end
local function enter() if box.focus=="field" then submit() else action(box.focus) end end
local KEYS = {
    { "MBTN_LEFT", click }, { "MBTN_LEFT_DBL", nothing },          -- no fullscreen toggle under the panel
    { "ENTER", enter }, { "KP_ENTER", enter }, { "ESC", function() hide(true) end },
    { "Ctrl+v", function() paste(false) end }, { "Shift+INS", function() paste(false) end },
    { "BS", function() erase(false) end, { repeatable = true } },
    { "DEL", function() erase(true) end, { repeatable = true } },
    { "Ctrl+a", function() box.all=true; focus("field") end },
    { "Ctrl+BS", function() set_text("") end },
    -- typed characters go into the field, not to the player's own keys
    { "any_unicode", function(e) if e.event ~= "up" and e.key_text then insert(e.key_text) end end,
      { complex = true, repeatable = true } },
    -- keys that would otherwise seek or skip behind the panel
    { "LEFT", function() box.cursor=box.all and 0 or previous(box.text,box.cursor); box.all=false; focus("field") end, {repeatable=true} },
    { "RIGHT", function() box.cursor=box.all and #box.text or following(box.text,box.cursor); box.all=false; focus("field") end, {repeatable=true} },
    { "HOME", function() box.cursor=0; box.all=false; focus("field") end },
    { "END", function() box.cursor=#box.text; box.all=false; focus("field") end },
    { "UP", nothing }, { "DOWN", nothing }, { "PGUP", nothing }, { "PGDWN", nothing },
    { "WHEEL_UP", nothing }, { "WHEEL_DOWN", nothing }, { "MBTN_RIGHT", nothing },
    { "TAB", function() tab(1) end }, { "Shift+TAB", function() tab(-1) end },
}

hide = function(resume)
    if not box then return end
    box = nil
    if blink then blink:kill(); blink = nil end
    for i = 1, #KEYS do mp.remove_key_binding("crt-youtube-" .. i) end
    modal:release(resume)
    draw()
end

show = function(text, err)
    if box then return end
    box = { text = text or "", cursor=#(text or ""), error = err, caret = true, focus="field" }
    modal:acquire()
    for i, k in ipairs(KEYS) do mp.add_forced_key_binding(k[1], "crt-youtube-" .. i, k[2], k[3]) end
    focus("field")
end

mp.observe_property("mouse-pos", "native", function(_, m)
    if not box or not m then return end
    local id
    for _, b in ipairs(view.hits) do
        if b.id ~= "field" and m.x >= b.x1 and m.x <= b.x2 and m.y >= b.y1 and m.y <= b.y2 then id = b.id end
    end
    if id ~= box.hover then box.hover = id; draw() end
end)
mp.observe_property("osd-dimensions", "native", function() if box then draw() end end)
mp.observe_property("window-minimized","bool",function() if box then draw() end end)
mp.register_event("shutdown",function() if box then hide(false) end end)

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

mp.register_script_message("crt-youtube", function(url) show(url) end)
