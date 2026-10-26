-- Windows only: give the player window the CRT-mpv icon (taskbar button and title bar) and its taskbar
-- identity, so the button's right-click menu offers "CRT-mpv" (not plain mpv) and pinning pins CRT-mpv.
-- mpv has no icon option and its executable cannot be re-iconed, so a small hidden PowerShell helper
-- (tools/set-window-icon.ps1) sets both on the window and stays until the player exits.
-- Turn off with  script-opts-append=crt-window-icon=no
if package.config:sub(1, 1) ~= "\\" then return end
if mp.get_opt("crt-window-icon") == "no" then return end

local utils = require 'mp.utils'
local config = mp.command_native({"expand-path", "~~/"}):gsub("[/\\]+$", "")
local root = utils.split_path(config)
local script = utils.join_path(root, "tools/set-window-icon.ps1")
local icon = utils.join_path(root, "assets/crt-mpv.ico")
local launcher = utils.join_path(root, "CRT-mpv.exe")
local started = false

mp.observe_property("window-id", "number", function(_, hwnd)
    if started or not hwnd or hwnd <= 0 then return end
    local pid = mp.get_property_number("pid")
    if not pid then return end
    started = true
    local args = { "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script,
                   "-Hwnd", string.format("%d", hwnd), "-ProcessId", string.format("%d", pid), "-Icon", icon }
    if utils.file_info(launcher) then args[#args + 1] = "-Launcher"; args[#args + 1] = launcher end
    local dump = mp.get_opt("crt-icon-dump")          -- developer self-test: save the window's icon as a PNG
    if dump then args[#args + 1] = "-DumpTo"; args[#args + 1] = dump end
    mp.command_native_async({ name = "subprocess", args = args, playback_only = false, capture_stdout = true,
                              capture_stderr = true }, function(ok, res)
        if res and res.status ~= 0 then mp.msg.warn("window icon helper failed: " .. (res.stderr or "")) end
    end)
end)
