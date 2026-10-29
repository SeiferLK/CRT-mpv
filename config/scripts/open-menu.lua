-- CRT-mpv library: one browser for saved locations, folders and videos.
local mp = require 'mp'
local utils = require 'mp.utils'
package.path = mp.command_native({"expand-path","~~/script-modules/"}) .. "/?.lua;" .. package.path
local library = require 'crt_library'
local view = require('crt_menu_view').new()
local session
local render, close, activate, browse, places
local modal = require('crt_modal').new("library",function() if session then close(false) end end)
local bindings = {}
local last_directory

local function selected_path(page)
    return page.rows[page.selected] and page.rows[page.selected].path
end
local function restore_selection(page,path,index)
    page.selected=math.max(1,math.min(index or page.selected or 1,#page.rows))
    if path then
        for i,row in ipairs(page.rows) do
            if library.key(row.path)==library.key(path) then page.selected=i; break end
        end
    end
end
local function library_page(filter)
    return {kind="library",filter=filter or "all",rows=library.locations(filter or "all"),selected=1,top=1}
end
local function ensure_visible()
    local page=session.page
    local visible=view.layout and view.layout.visible or 8
    page.top=math.max(1,math.min(page.top,math.max(1,#page.rows-visible+1)))
    if page.selected<page.top then page.top=page.selected end
    if page.selected>=page.top+visible then page.top=page.selected-visible+1 end
end
render=function()
    if not session then return end
    local p=session.page
    local titles={library="Your library",places="Locations"}
    local subtitles={library="Favourite folders and recent locations.",places="Choose a drive or your home folder."}
    local empty,detail
    if p.kind=="library" then
        empty=p.filter=="favourites" and "No favourite folders yet" or "No saved locations yet"
        detail="Browse to a folder and use the star to save it."
    elseif p.kind=="places" then empty="Finding your drives…"; detail="Your home folder is also available."
    else empty="No videos in this folder"; detail="Use Up or Locations to keep browsing." end
    local model={
        kind=p.kind,dir=p.dir,filter=p.filter,rows=p.rows,selected=p.selected,top=p.top,
        title=titles[p.kind] or library.name(p.dir),
        subtitle=subtitles[p.kind] or p.dir,
        saved=p.dir and library.favourite(p.dir),is_favourite=library.favourite,
        error=session.error,hover=session.hover,focus=session.focus,empty=empty,empty_detail=detail,
        suspended=mp.get_property_native("window-minimized")==true,
    }
    local layout=view:render(model)
    if layout then
        p.top=layout.top
        ensure_visible()
        if p.top~=layout.top then model.top=p.top; view:render(model) end
    end
end
local function switch(page,push)
    if push then session.history[#session.history+1]=session.page end
    session.page=page
    session.hover,session.focus,session.error=nil,nil,nil
    session.navigated=mp.get_time()
    render()
end
local function home(filter)
    session.history={}
    switch(library_page(filter),false)
end
browse=function(dir,push)
    dir=library.path(dir)
    local rows,err=library.list(dir)
    if not rows then
        session.error="Folder unavailable. Check the drive or try another location."
        mp.msg.warn("Cannot browse "..dir..": "..tostring(err))
        render()
        return false
    end
    last_directory=dir
    switch({kind="folder",dir=dir,rows=rows,selected=1,top=1},push~=false)
    return true
end
places=function()
    local page={kind="places",rows={},selected=1,top=1}
    switch(page,true)
    local owner=session
    library.places(function(rows)
        if session~=owner then return end
        page.rows=rows
        if session.page==page then render() end
    end)
end
local function back()
    if #session.history>0 then
        local previous=table.remove(session.history)
        if previous.kind=="library" then
            local path=selected_path(previous)
            previous.rows=library.locations(previous.filter)
            restore_selection(previous,path)
        end
        switch(previous,false)
    elseif session.page.kind~="library" then home()
    else close(true) end
end
local function refresh()
    local p=session.page
    local path=selected_path(p)
    if p.kind=="folder" then
        local rows=library.list(p.dir)
        if not rows then session.error="This folder is no longer available."; render(); return end
        p.rows=rows
    elseif p.kind=="library" then library.reload(); p.rows=library.locations(p.filter)
    else return end
    restore_selection(p,path)
    session.error=nil
    ensure_visible(); render()
end
local function favourite(path)
    if not path then return end
    local p=session.page
    local selected=selected_path(p)
    local ok,err=library.toggle(path)
    if not ok then session.error="Could not save favourites."; mp.msg.warn(tostring(err))
    elseif p.kind=="library" then
        p.rows=library.locations(p.filter)
        restore_selection(p,selected)
        ensure_visible()
    end
    render()
end
local function forget()
    local p=session.page
    local row=p.rows[p.selected]
    if p.kind~="library" or not row or row.source~="recent" or library.favourite(row.path) then return end
    local ok=library.forget(row.path)
    if ok then p.rows=library.locations(p.filter); restore_selection(p,nil); ensure_visible()
    else session.error="Could not update recent locations." end
    render()
end
activate=function(action)
    if not session or not action then return end
    local p=session.page
    session.error=nil
    if action.kind=="close" then close(true)
    elseif action.kind=="back" then back()
    elseif action.kind=="home" then home()
    elseif action.kind=="places" then places()
    elseif action.kind=="up" then
        local parent=p.dir and library.parent(p.dir)
        if parent then browse(parent) else places() end
    elseif action.kind=="filter" then
        local path=selected_path(p)
        local page=library_page(action.filter)
        restore_selection(page,path)
        switch(page,false)
    elseif action.kind=="browse" then
        local dir=last_directory or library.current() or library.data.recent[1] or library.home()
        if not browse(dir) then places() end
    elseif action.kind=="favourite" then favourite(action.path)
    elseif action.kind=="row" then
        local row=p.rows[action.index]
        if not row then return end
        p.selected=action.index
        if row.kind=="video" then
            local info=utils.file_info(row.path)
            if not info or not info.is_file then session.error="This video is no longer available."; render(); return end
            close(false)
            mp.commandv("loadfile",row.path,"replace")
            mp.set_property_bool("pause",false)
        else browse(row.path) end
    end
end
local function move(delta)
    if not session then return end
    local p=session.page
    p.selected=math.max(1,math.min(#p.rows,p.selected+delta))
    session.focus,session.hover=nil,nil
    ensure_visible(); render()
end
-- The wheel scrolls the list; it does not move the keyboard selection. The highlight follows whatever row ends up
-- under the pointer, so it does not jump back to the pointer when the mouse next twitches.
local function wheel(delta)
    if not session then return end
    local p=session.page
    local visible=view.layout and view.layout.visible or 8
    p.top=math.max(1,math.min(math.max(1,#p.rows-visible+1),p.top+delta))
    p.selected=math.max(p.top,math.min(p.top+visible-1,p.selected))
    session.focus=nil
    render()
    local m=mp.get_property_native("mouse-pos") or {}
    local h=m.x and m.y and m.hover~=false and view:hit(m.x,m.y) or nil
    local id=h and h.id
    local selected=h and h.action.kind=="row" and h.action.index or p.selected
    if id~=session.hover or selected~=p.selected then
        session.hover,p.selected=id,selected
        render()
    end
end
local function enter()
    if session.focus then
        for _,h in ipairs(view.hits) do if h.id==session.focus then activate(h.action); return end end
    elseif session.page.kind=="library" and #session.page.rows==0 then activate({kind="browse"})
    else activate({kind="row",index=session.page.selected}) end
end
local function tab(delta)
    local index=0
    for i,id in ipairs(view.controls) do if id==session.focus then index=i end end
    index=index+delta
    if index<1 or index>#view.controls then session.focus=nil
    else session.focus=view.controls[index] end
    render()
end
local function pointer()
    return mp.get_property_native("mouse-pos") or {}
end
local function drag(y)
    local track=view.layout and view.layout.track
    if not track or not y then return end
    local p=session.page
    local fraction=math.max(0,math.min(1,(y-track.y-track.thumb/2)/math.max(1,track.height-track.thumb)))
    p.top=1+math.floor(fraction*(#p.rows-view.layout.visible)+.5)
    p.selected=math.max(p.top,math.min(p.top+view.layout.visible-1,p.selected))
    render()
end
local function click(event)
    if not session then return end
    local m=pointer()
    if not m.x or not m.y then return end
    local hit=view:hit(m.x,m.y)
    if event.event=="down" then
        session.pressed=hit and hit.id or "outside"
        if hit and hit.id=="scrollbar" then session.dragging=true; drag(m.y) end
    elseif event.event=="up" or event.event=="press" then
        if session.dragging then session.dragging=nil; session.pressed=nil; return end
        local pressed=session.pressed
        session.pressed=nil
        if mp.get_time()-(session.navigated or 0)<.2 then return end
        if hit and (event.event=="press" or pressed==hit.id) then activate(hit.action)
        elseif not hit and (pressed=="outside" or event.event=="press") then
            local l=view.layout
            if l and (m.x<l.x or m.x>l.x+l.w or m.y<l.y or m.y>l.y+l.h) then close(true) end
        end
    end
end
local function nothing() end
local keys={
    {"MBTN_LEFT",click,{complex=true}},{"MBTN_LEFT_DBL",nothing},{"MBTN_RIGHT",nothing},
    {"UP",function() move(-1) end,{repeatable=true}},{"DOWN",function() move(1) end,{repeatable=true}},
    {"WHEEL_UP",function() wheel(-1) end},{"WHEEL_DOWN",function() wheel(1) end},
    {"PGUP",function() move(-(view.layout and view.layout.visible or 1)) end},
    {"PGDWN",function() move(view.layout and view.layout.visible or 1) end},
    {"HOME",function() move(-#session.page.rows) end},{"END",function() move(#session.page.rows) end},
    {"ENTER",enter},{"KP_ENTER",enter},{"RIGHT",enter},{"LEFT",back},{"BS",back},{"Alt+LEFT",back},
    {"Alt+UP",function() activate({kind="up"}) end},{"ESC",function() close(true) end},
    {"TAB",function() tab(1) end},{"Shift+TAB",function() tab(-1) end},
    {"f",function()
        local p=session.page
        local row=p.rows[p.selected]
        favourite(row and row.kind~="video" and row.path or p.dir)
    end},
    {"F5",refresh},{"DEL",forget},{"SPACE",nothing},{"any_unicode",nothing},
}
close=function(resume)
    if not session then return end
    session=nil
    view:close()
    for _,name in ipairs(bindings) do mp.remove_key_binding(name) end
    bindings={}
    modal:release(resume)
end
local function open()
    if session then close(true); return end
    library.reload()
    session={page=library_page(),history={}}
    modal:acquire()
    for i,key in ipairs(keys) do
        local name="crt-library-"..i
        mp.add_forced_key_binding(key[1],name,key[2],key[3])
        bindings[#bindings+1]=name
    end
    render()
end
mp.observe_property("mouse-pos","native",function(_,m)
    if not session or not m or not m.x or not m.y then return end
    if session.dragging then drag(m.y); return end
    if session.mouse_x==m.x and session.mouse_y==m.y then return end
    session.mouse_x,session.mouse_y=m.x,m.y
    local h=m.hover~=false and view:hit(m.x,m.y) or nil
    local id=h and h.id
    if id~=session.hover then
        session.hover,session.focus=id,nil
        if h and h.action.kind=="row" then session.page.selected=h.action.index end
        render()
    end
end)
mp.observe_property("osd-dimensions","native",render)
mp.observe_property("window-minimized","bool",render)
mp.register_script_message("crt-open",open)
mp.register_script_message("crt-open-recent",function()
    if not session then open() end
    home("recent")
end)
mp.register_script_message("crt-open-browse",function(dir)
    if not session then open() end
    if dir and dir~="" then browse(dir) end
end)
mp.add_key_binding("Ctrl+o","crt-open-menu",open)
mp.register_event("file-loaded",function()
    local ok,err=library.remember(library.current())
    if ok==nil and err then mp.msg.warn("Cannot save recent locations: "..tostring(err)) end
end)
mp.register_event("shutdown",function() close(false) end)
