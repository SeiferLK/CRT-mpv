-- Local locations and folder listings. No filesystem work happens in a drawing callback.
local mp = require 'mp'
local utils = require 'mp.utils'
local M = {}
local windows = package.config:sub(1, 1) == "\\"
local state_path = mp.command_native({"expand-path", "~~/open-locations.json"})
local video = {}
for ext in ("mkv mp4 avi mov wmv webm m4v flv ts m2ts mpg mpeg ogv 3gp divx vob"):gmatch("%S+") do video[ext] = true end

function M.path(path)
    if windows then path = path:gsub("/", "\\") end
    if path == "/" or path:match("^%a:[/\\]$") then return path end
    return (path:gsub(windows and "[/\\]+$" or "/+$", ""))
end
function M.key(path) return windows and M.path(path):lower() or M.path(path) end
function M.name(path)
    local clean = M.path(path)
    return clean:match(windows and "([^/\\]+)$" or "([^/]+)$") or clean
end
function M.parent(path)
    path = M.path(path)
    if path == "/" or path:match("^%a:[/\\]$") or path:match("^\\\\[^\\]+\\[^\\]+$") then return nil end
    local parent = utils.split_path(path)
    return parent ~= "" and M.path(parent) or nil
end
function M.join(dir, name) return M.path(utils.join_path(dir, name)) end
function M.current()
    local path = mp.get_property("path")
    if not path or path:find("://", 1, true) then return nil end
    path = utils.join_path(mp.get_property("working-directory") or "", path)
    local dir = utils.split_path(path)
    return dir ~= "" and M.path(dir) or nil
end
function M.home()
    return M.path(os.getenv(windows and "USERPROFILE" or "HOME") or (windows and "C:\\" or "/"))
end
local function find(list, path)
    for i, item in ipairs(list) do if M.key(item) == M.key(path) then return i end end
end

M.data = {favourites={}, recent={}}
function M.reload()
    local file = io.open(state_path, "rb")
    if not file then return end
    local raw = file:read("*a")
    file:close()
    local parsed = utils.parse_json(raw)
    if type(parsed) ~= "table" then return end
    for _, kind in ipairs({"favourites", "recent"}) do
        local list = {}
        if type(parsed[kind]) == "table" then
            for _, path in ipairs(parsed[kind]) do
                if type(path) == "string" and path ~= "" and not find(list, path) then
                    list[#list+1] = M.path(path)
                    if kind == "recent" and #list == 12 then break end
                end
            end
        end
        M.data[kind] = list
    end
end
local function save()
    local file, err = io.open(state_path, "wb")
    if not file then return nil, err end
    local ok, write_error = file:write(utils.format_json(M.data))
    local closed, close_error = file:close()
    return ok and closed, write_error or close_error
end
function M.favourite(path) return find(M.data.favourites, path) ~= nil end
function M.toggle(path)
    local old = M.favourite(path)
    local i = find(M.data.favourites, path)
    if i then table.remove(M.data.favourites, i) else table.insert(M.data.favourites, 1, M.path(path)) end
    local ok, err = save()
    if not ok then
        if old then table.insert(M.data.favourites, i, path) else table.remove(M.data.favourites, 1) end
    end
    return ok, err
end
function M.remember(path)
    if not path then return end
    local i = find(M.data.recent, path)
    if i == 1 then return end
    if i then table.remove(M.data.recent, i) end
    table.insert(M.data.recent, 1, M.path(path))
    while #M.data.recent > 12 do table.remove(M.data.recent) end
    return save()
end
function M.forget(path)
    local i = find(M.data.recent, path)
    if i then table.remove(M.data.recent, i); return save() end
    return true
end
function M.locations(filter)
    local rows, seen = {}, {}
    local current = M.current()
    local function add(path, kind)
        if seen[M.key(path)] then return end
        seen[M.key(path)] = true
        rows[#rows+1] = {path=path, title=M.name(path), detail=path, kind="folder", source=kind}
    end
    if filter ~= "recent" then for _, path in ipairs(M.data.favourites) do add(path, "favourite") end end
    if filter ~= "favourites" then
        if current then add(current, "current") end
        for _, path in ipairs(M.data.recent) do add(path, "recent") end
    end
    return rows
end
local function sort_key(name)
    return name:lower():gsub("%d+", function(d)
        local n = d:gsub("^0+", "")
        return string.format("%04d", #n) .. n .. string.format("%04d", #d)
    end)
end
function M.list(dir)
    local dirs, err = utils.readdir(dir, "dirs")
    if not dirs then return nil, err end
    local files, file_error = utils.readdir(dir, "files")
    if not files then return nil, file_error end
    local rows = {}
    for _, name in ipairs(dirs) do
        if name ~= "." and name ~= ".." then
            rows[#rows+1] = {path=M.join(dir,name), title=name, detail="Folder", kind="folder", sort=sort_key(name)}
        end
    end
    for _, name in ipairs(files) do
        local ext = (name:match("%.([^.]*)$") or ""):lower()
        if video[ext] then
            rows[#rows+1] = {path=M.join(dir,name), title=name, detail=ext:upper() .. " video", kind="video", sort=sort_key(name)}
        end
    end
    table.sort(rows, function(a,b)
        if a.kind ~= b.kind then return a.kind == "folder" end
        if a.sort == b.sort then return a.title < b.title end
        return a.sort < b.sort
    end)
    return rows
end
local drives
function M.places(done)
    local rows = {{title="Home", detail=M.home(), path=M.home(), kind="folder"}}
    local function add_drives(paths)
        for _, path in ipairs(paths) do
            rows[#rows+1] = {title=windows and ("Drive " .. path:sub(1,2)) or "Filesystem",
                detail=path, path=path, kind="drive"}
        end
        done(rows)
    end
    if not windows then add_drives({"/"}); return end
    if drives then add_drives(drives); return end
    mp.command_native_async({name="subprocess", playback_only=false, capture_stdout=true, capture_stderr=true,
        args={"powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "[Environment]::GetLogicalDrives()"}},
        function(ok, result)
            local paths = {}
            if ok and result and result.status == 0 then
                for path in result.stdout:gmatch("[^\r\n]+") do
                    if path:match("^%a:[/\\]$") then paths[#paths+1] = M.path(path) end
                end
            end
            if #paths > 0 then drives = paths end
            add_drives(paths)
        end)
end
M.reload()
return M
