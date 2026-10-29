-- CRT-mpv update check.
-- A few seconds after the player starts it asks GitHub for the newest CRT-mpv release (at most once an hour; the
-- answer is kept in config/update.json). When that release is newer than this copy (the VERSION file) and has not
-- been skipped, a prompt offers to update. "Update now" saves the resume position, starts the updater
-- (tools/update.ps1 on Windows, mac-linux/update.sh on macOS / Linux) and quits. The updater downloads the release
-- from GitHub, installs it over this folder (settings, presets, resume positions and TVs you added are kept, and
-- every file it replaces is copied to backup/ first) and starts CRT-mpv again on the same video.
--   script-opts-append=crt-update=no      never check
--   script-message crt-update-check       check now (ignores the hourly limit and a skipped version)
local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

local REPO = "SeiferLK/CRT-mpv"
local API = mp.get_opt("crt-update-api") or ("https://api.github.com/repos/" .. REPO .. "/releases/latest")
local CHECK_EVERY = 3600                 -- seconds between checks (GitHub allows 60 unauthenticated requests an hour)
local WIN = package.config:sub(1, 1) == "\\"

local config_dir = mp.command_native({"expand-path", "~~/"}):gsub("[/\\]+$", "")
local root = config_dir:gsub("[/\\][^/\\]+$", "")       -- the CRT-mpv folder (config's parent)
if WIN then config_dir, root = config_dir:gsub("/", "\\"), root:gsub("/", "\\") end
local STATE = utils.join_path(config_dir, "update.json")

-- the updater restarts the player with one of these, so the result shows on screen
local done, failed = mp.get_opt("crt-update-done"), mp.get_opt("crt-update-failed")
if done or failed then
    local shown = false
    mp.register_event("file-loaded", function()
        if shown then return end
        shown = true
        mp.add_timeout(1.5, function()
            mp.osd_message(done and ("Updated to CRT-mpv " .. done:gsub("^v", "") .. ". Your settings and TVs were kept.")
                or "The update did not work. CRT-mpv was left as it was.", 6)
        end)
    end)
end

if mp.get_opt("crt-update") == "no" or mp.get_opt("crt-shot") then return end   -- off, or a scripted screenshot

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function load_state()
    local t = utils.parse_json(read_file(STATE) or "")
    return type(t) == "table" and t or {}
end

local function save_state(t)
    local f = io.open(STATE, "wb")
    if not f then return end
    f:write(utils.format_json(t) or "{}")
    f:close()
end

local function current_version()
    return ((read_file(utils.join_path(root, "VERSION")) or "0"):gsub("%s+", ""))
end

-- "v1.10.2" -> {1, 10, 2}; a > b when the first differing number is bigger
local function parts(v)
    local t = {}
    for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end
local function newer(a, b)
    a, b = parts(a), parts(b)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

-- the parts of a GitHub release this script needs: the CRT-mpv-*.zip asset (and its SHA-256, when GitHub has
-- one), falling back to the source zip
local function from_release(j)
    local r = { tag = j.tag_name, name = j.name, page = j.html_url, notes = j.body or "" }
    for _, a in ipairs(j.assets or {}) do
        if type(a.name) == "string" and a.name:match("^CRT%-mpv.*%.zip$") then
            r.url = a.browser_download_url
            r.sha256 = type(a.digest) == "string" and a.digest:match("^sha256:(%x+)$") or nil
            break
        end
    end
    r.url = r.url or j.zipball_url
    return r
end

-- release notes for the prompt: plain text, at most a few short lines
local function note_lines(body, max)
    local out = {}
    for line in (body .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        line = line:gsub("%[([^%]]*)%]%b()", "%1"):gsub("[`*_#>]", ""):gsub("^%s*[-+]%s+", "- ")
        line = line:gsub("[{}\\]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            out[#out + 1] = line
            if #out == max then break end
        end
    end
    return out
end

---------------------------------------------------------------------------------------------------------------------
-- The prompt shares the library's panel style, with mouse and keyboard navigation.

package.path = mp.command_native({"expand-path","~~/script-modules/"}) .. "/?.lua;" .. package.path
local view = require('crt_menu_view').new()
local prompt, hide
local modal = require('crt_modal').new("update",function() if prompt then hide(false) end end)
local BINDINGS = {}

local function draw()
    if not prompt then view:close(); return end
    local body={"Your library, settings, presets, playback position and TVs are kept."}
    for _,line in ipairs(prompt.notes) do body[#body+1]=line end
    view:render_dialog({
        id="update",title="CRT-mpv "..prompt.rel.tag:gsub("^v","").." is ready",
        subtitle="Installed version: "..prompt.cur,body=body,hover=prompt.hover,focus=prompt.focus,
        buttons={{id="later",label="Later",width=82},{id="skip",label="Skip version",width=125},
            {id="update",label="Update now",width=140,primary=true}},
        hint="Enter  Choose    Esc  Later    S  Skip version",
        suspended=mp.get_property_native("window-minimized")==true,
    })
end

hide = function(resume)
    if not prompt then return end
    prompt=nil
    for _,name in ipairs(BINDINGS) do mp.remove_key_binding(name) end
    BINDINGS={}
    modal:release(resume)
    view:close()
end

local function later() hide(true) end

local function skip()
    if not prompt then return end
    local st = load_state()
    st.skip = prompt.rel.tag
    save_state(st)
    mp.osd_message("Skipped CRT-mpv " .. prompt.rel.tag .. ". You will be asked again when a newer version comes out.", 4)
    hide(true)
end

-- the file to reopen after the update, as an absolute path (URLs and other stream names stay as they are)
local function current_file()
    local path = mp.get_property("path")
    if not path or path:find("://", 1, true) or path:match("^%a%a+:") then return path end
    return utils.join_path(mp.get_property("working-directory") or "", path)
end

local function accept()
    if not prompt then return end
    local rel = prompt.rel
    if not rel.url then mp.osd_message("This release has no download. Get it from " .. tostring(rel.page), 6); return end
    local relaunch = {}
    if not mp.get_property_bool("fullscreen") then relaunch[#relaunch + 1] = WIN and "--windowed" or "--no-fullscreen" end
    local extra = mp.get_opt("crt-update-relaunch-opts")                   -- used by the self-test
    if extra then relaunch[#relaunch + 1] = extra end
    local file = current_file()
    if file then relaunch[#relaunch + 1] = file end

    local pid = utils.getpid()
    if WIN then
        local job = utils.join_path(os.getenv("TEMP") or config_dir, "crt-mpv-update-" .. pid .. ".json")
        local f = io.open(job, "wb")
        if not f then mp.osd_message("Could not start the update (no temp folder)", 5); return end
        f:write(utils.format_json({ url = rel.url, sha256 = rel.sha256 or "", tag = rel.tag, pid = pid, relaunch = relaunch }))
        f:close()
        hide(false)                                     -- stays paused until the player quits
        mp.commandv("run", "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
            "-File", root .. "\\tools\\update.ps1", "-Job", job)
    else
        hide(false)
        local args = { "run", root .. "/mac-linux/update.sh", rel.url, rel.sha256 or "", rel.tag, tostring(pid) }
        for _, a in ipairs(relaunch) do args[#args + 1] = a end
        mp.commandv(table.unpack(args))
    end
    mp.osd_message("Updating CRT-mpv to " .. rel.tag .. ". The player will start again by itself.", 5)
    mp.add_timeout(0.8, function() mp.command("quit-watch-later") end)         -- resume here after the restart
end

local function action(id)
    if id=="update" then accept() elseif id=="skip" then skip() else later() end
end
local function click()
    local m = mp.get_property_native("mouse-pos")
    if not prompt or not m then return end
    for _, b in ipairs(view.hits) do
        if m.x >= b.x1 and m.x <= b.x2 and m.y >= b.y1 and m.y <= b.y2 then
            action(b.id)
            return
        end
    end
end
local function tab(delta)
    local order={"later","skip","update","close"}
    local at=1
    for i,id in ipairs(order) do if id==prompt.focus then at=i end end
    prompt.focus=order[(at-1+delta)%#order+1]
    draw()
end
local function nothing() end

local function show(rel, cur)
    mp.osd_message("", 0)                               -- clears "Checking for a newer CRT-mpv..."
    prompt = { rel = rel, cur = cur, notes = note_lines(rel.notes or "", 5), focus="update" }
    modal:acquire()
    local keys={
        {"MBTN_LEFT",click},{"MBTN_LEFT_DBL",nothing},{"MBTN_RIGHT",nothing},
        {"ENTER",function() action(prompt.focus) end},{"KP_ENTER",function() action(prompt.focus) end},
        {"ESC",later},{"s",skip},{"TAB",function() tab(1) end},{"Shift+TAB",function() tab(-1) end},
        {"LEFT",function() tab(-1) end},{"RIGHT",function() tab(1) end},
        {"UP",nothing},{"DOWN",nothing},{"WHEEL_UP",nothing},{"WHEEL_DOWN",nothing},
        {"SPACE",nothing},{"any_unicode",nothing},
    }
    for i,key in ipairs(keys) do
        local name="crt-update-dialog-"..i
        BINDINGS[#BINDINGS+1]=name
        mp.add_forced_key_binding(key[1],name,key[2])
    end
    draw()
end

mp.observe_property("mouse-pos", "native", function(_, m)
    if not prompt or not m then return end
    local id
    for _, b in ipairs(view.hits) do
        if m.x >= b.x1 and m.x <= b.x2 and m.y >= b.y1 and m.y <= b.y2 then id = b.id end
    end
    if id ~= prompt.hover then prompt.hover = id; draw() end
end)
mp.observe_property("osd-dimensions", "native", function() if prompt then draw() end end)
mp.observe_property("window-minimized","bool",function() if prompt then draw() end end)
mp.register_event("shutdown",function() if prompt then hide(false) end end)

---------------------------------------------------------------------------------------------------------------------

local function consider(rel, st, forced)
    local cur = current_version()
    local avail = rel and rel.tag and newer(rel.tag, cur)
    pcall(mp.set_property_native, "user-data/crt-update", { available = avail and rel.tag or nil, current = cur })
    if not avail then
        if forced then mp.osd_message("CRT-mpv " .. cur .. " is the newest version.", 3) end
        return
    end
    if st.skip == rel.tag and not forced then return end
    show(rel, cur)
end

local function check(forced)
    if prompt then return end
    if forced then mp.osd_message("Checking for a newer CRT-mpv...", 10) end
    local st = load_state()
    if not forced and st.latest and st.checked and os.time() - st.checked < CHECK_EVERY then
        consider(st.latest, st, false)
        return
    end
    mp.command_native_async({
        name = "subprocess", playback_only = false, capture_stdout = true, capture_stderr = true,
        args = { "curl", "-fsSL", "--max-time", "10", "-H", "Accept: application/vnd.github+json",
                 "-H", "User-Agent: CRT-mpv", API },
    }, function(ok, res)
        local j = ok and res and res.status == 0 and utils.parse_json(res.stdout or "") or nil
        if type(j) ~= "table" or not j.tag_name then
            msg.verbose("update check failed: " .. tostring(res and (res.error_string ~= "" and res.error_string or res.stderr)))
            if forced then mp.osd_message("Could not reach GitHub to check for updates.", 3) end
            return
        end
        st.checked, st.latest = os.time(), from_release(j)
        save_state(st)
        consider(st.latest, st, forced)
    end)
end

local started = false
mp.register_event("file-loaded", function()
    if started then return end
    started = true
    mp.add_timeout(3, function() check(false) end)      -- once the TV has warmed up
end)
mp.register_script_message("crt-update-check", function() check(true) end)
mp.register_script_message("crt-update-accept", accept)                  -- the prompt's buttons, for scripts
mp.register_script_message("crt-update-later", later)
mp.register_script_message("crt-update-skip", skip)
