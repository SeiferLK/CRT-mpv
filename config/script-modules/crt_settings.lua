-- Tiny helper shared by the CRT-mpv scripts: reads/writes config/settings.json.
-- Disable all saving and loading with  script-opts-append=crt-settings=no
local utils = require 'mp.utils'
local M = {}

M.enabled = mp.get_opt("crt-settings") ~= "no"

local function path()
    return utils.join_path(mp.command_native({"expand-path", "~~/"}), "settings.json")
end

function M.load()
    if not M.enabled then return {} end
    local f = io.open(path(), "rb")
    if not f then return {} end
    local text = f:read("*a")
    f:close()
    local t = utils.parse_json(text)
    return type(t) == "table" and t or {}
end

function M.save(t)
    if not M.enabled then return end
    local text = utils.format_json(t)
    if not text then return end
    local f = io.open(path(), "wb")
    if not f then return end          -- read-only folder: just skip
    f:write(text)
    f:close()
end

return M
