-- Optional native pickers for custom bindings; the eject button uses open-menu.lua.
-- The file picker plays one or several videos; a single file queues the rest of its folder.
-- The folder picker sends the chosen location back to the eject menu for browsing.
-- Whenever there is nothing to play (CRT-mpv.exe started without a video, say), the TV shows no signal instead of
-- an empty window, so the remote and the hover bar are there to open something.
local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

local WIN = package.config:sub(1, 1) == "\\"
-- luma-only noise over mid grey, re-rolled every frame and stretched toward black and white: TV static
local NO_SIGNAL = "av://lavfi:color=c=gray:s=640x360:r=25,noise=c0s=100:c0f=t+u,eq=contrast=1.9,scale=1920:1080:flags=neighbor"
local EXTS = { "mkv", "mp4", "avi", "mov", "wmv", "webm", "m4v", "flv", "ts", "m2ts", "mpg", "mpeg", "ogv", "3gp", "divx", "vob" }

-- the folder of the video playing now, to open the picker in (nil for streams and the no-signal screen)
local function current_dir()
    local path = mp.get_property("path")
    if not path or path:find("://", 1, true) then return nil end
    return (utils.split_path(utils.join_path(mp.get_property("working-directory") or "", path)))
end

-- the picker for this system, as a list of commands to try in turn (the first one that exists is used)
local function pickers(dir, folder)
    if WIN then
        local function q(s) return "'" .. s:gsub("'", "''") .. "'" end
        if folder then return { { "powershell.exe", "-NoProfile", "-NonInteractive", "-STA", "-Command", table.concat({
            "[Console]::OutputEncoding = [Text.Encoding]::UTF8",
            "Add-Type -AssemblyName System.Windows.Forms",
            "$owner = New-Object Windows.Forms.Form -Property @{ TopMost = $true }",
            "$d = New-Object Windows.Forms.FolderBrowserDialog",
            "$d.Description = 'CRT-mpv: choose a folder'",
            dir and ("$d.SelectedPath = " .. q(dir)) or "$null",
            "if ($d.ShowDialog($owner) -eq 'OK') { $d.SelectedPath }",
        }, "; ") } } end
        return { { "powershell.exe", "-NoProfile", "-NonInteractive", "-STA", "-Command", table.concat({
            "[Console]::OutputEncoding = [Text.Encoding]::UTF8",
            "Add-Type -AssemblyName System.Windows.Forms",
            "$owner = New-Object Windows.Forms.Form -Property @{ TopMost = $true }",     -- in front of a fullscreen player
            "$d = New-Object Windows.Forms.OpenFileDialog",
            "$d.Title = 'CRT-mpv: choose a video'", "$d.Multiselect = $true",
            "$d.Filter = " .. q("Videos|*." .. table.concat(EXTS, ";*.") .. "|All files|*.*"),
            dir and ("$d.InitialDirectory = " .. q(dir)) or "$null",
            "if ($d.ShowDialog($owner) -eq 'OK') { $d.FileNames }",
        }, "; ") } }
    end
    if mp.get_property("platform") == "darwin" then
        local function q(s) return '"' .. s:gsub('[\\"]', "\\%0") .. '"' end
        if folder then return { { "osascript",
            "-e", 'tell application "System Events"', "-e", "activate",
            "-e", 'set f to choose folder with prompt "CRT-mpv: choose a folder"'
                .. (dir and (" default location POSIX file " .. q(dir)) or ""),
            "-e", "end tell", "-e", "return POSIX path of f" } } end
        return { { "osascript",
            "-e", 'tell application "System Events"', "-e", "activate",
            "-e", 'set fs to choose file with prompt "CRT-mpv: choose a video" with multiple selections allowed'
                .. (dir and (" default location POSIX file " .. q(dir)) or ""),
            "-e", "end tell", "-e", 'set out to ""',
            "-e", "repeat with f in fs", "-e", "set out to out & POSIX path of f & linefeed", "-e", "end repeat",
            "-e", "return out" } }
    end
    if folder then return {
        { "zenity", "--file-selection", "--directory", "--title=CRT-mpv: choose a folder",
          dir and ("--filename=" .. dir .. "/") or "--filename=" .. (os.getenv("HOME") or "") .. "/" },
        { "kdialog", "--getexistingdirectory", dir or os.getenv("HOME") or ".",
          "--title", "CRT-mpv: choose a folder" },
    } end
    return {
        { "zenity", "--file-selection", "--multiple", "--separator=\n", "--title=CRT-mpv: choose a video",
          dir and ("--filename=" .. dir .. "/") or "--filename=" .. (os.getenv("HOME") or "") .. "/" },
        { "kdialog", "--getopenfilename", dir or os.getenv("HOME") or ".", "--multiple", "--separator", "\n",
          "--title", "CRT-mpv: choose a video" },
    }
end

local function play(files)
    mp.commandv("loadfile", files[1], "replace")
    for i = 2, #files do mp.commandv("loadfile", files[i], "append") end
    mp.set_property_bool("pause", false)
end

local picking = false
local function open(folder, initial_dir)
    if picking then return end
    picking = true
    local list = pickers(initial_dir ~= "" and initial_dir or current_dir(), folder)
    local function try(i)
        if not list[i] then
            picking = false
            mp.osd_message("No file picker found: install zenity (or kdialog) to open videos from the player", 5)
            return
        end
        mp.command_native_async({ name = "subprocess", args = list[i], playback_only = false,
                                  capture_stdout = true, capture_stderr = true }, function(_, res)
            if res and res.error_string == "init" then try(i + 1); return end     -- this picker is not installed
            picking = false
            local files = {}
            for line in ((res and res.stdout) or ""):gmatch("[^\r\n]+") do files[#files + 1] = line end
            if #files > 0 then
                if folder then mp.commandv("script-message", "crt-open-browse", files[1])
                else play(files) end
            elseif res and res.status ~= 0 and res.status ~= 1 then              -- 1: the picker was cancelled
                msg.warn("file picker failed: " .. tostring(res.stderr))
            end
        end)
    end
    try(1)
end

mp.register_script_message("crt-open-picker", function(dir) open(false, dir) end)
mp.register_script_message("crt-open-folder-picker", function(dir) open(true, dir) end)

-- nothing to play: the TV comes on with no signal. Not again if that fails (it would only fail again).
local no_signal = nil            -- "loading" while the no-signal screen loads, "failed" if it could not
mp.observe_property("idle-active", "bool", function(_, idle)
    if not idle then return end
    -- a moment later, in case another script is already loading something (youtube.lua putting a video back)
    mp.add_timeout(0.3, function()
        if mp.get_property_native("idle-active") and no_signal ~= "failed" then
            no_signal = "loading"
            mp.commandv("loadfile", NO_SIGNAL, "replace")
        end
    end)
end)
mp.add_hook("on_load", 50, function()
    if mp.get_property("stream-open-filename") == NO_SIGNAL then
        mp.set_property("file-local-options/force-media-title", "No signal")
    end
end)
mp.register_event("file-loaded", function() if no_signal == "loading" then no_signal = nil end end)
mp.register_event("end-file", function(e)
    if no_signal == "loading" and e.reason == "error" then no_signal = "failed" end
end)
