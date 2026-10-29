-- Playlist, tracks, chapters, speed and audio output share the library's UI.
local mp = require 'mp'
package.path=mp.command_native({"expand-path","~~/script-modules/"}).."/?.lua;"..package.path
local view=require('crt_menu_view').new()
local menu,close,show
local modal=require('crt_modal').new("selector",function() if menu then close(false) end end)
local bound={}
local function filename(path) return path:match("([^/\\]+)$") or path end
local function time_label(t)
    t=math.floor(t or 0)
    return t>=3600 and string.format("%d:%02d:%02d",math.floor(t/3600),math.floor(t/60)%60,t%60)
        or string.format("%d:%02d",math.floor(t/60),t%60)
end
local definitions={
    playlist={"Playlist","Choose a video from the queue.","No videos queued"},
    audio={"Audio tracks","Choose the language or audio track.","No audio tracks"},
    subtitles={"Subtitles","Choose a subtitle track.","No subtitle tracks"},
    video={"Video tracks","Choose the video track.","No video tracks"},
    tracks={"Media tracks","Choose a video, audio or subtitle track.","No media tracks"},
    editions={"Editions","Choose an edition of this video.","No editions in this video"},
    chapters={"Chapters","Jump to a chapter in this video.","No chapters in this video"},
    speed={"Playback speed","Choose a comfortable pace."},
    device={"Audio output","Choose where the sound plays.","No audio outputs available"},
    controls={"Player menu","Playback, media and player options."},
}
local function rows_for(kind)
    local rows={}
    local function add(id,title,detail,current,choose,icon)
        rows[#rows+1]={path=tostring(id),title=title,detail=detail or "",current=current,choose=choose,kind="option",icon=icon or "video"}
    end
    if kind=="playlist" then
        for i,e in ipairs(mp.get_property_native("playlist") or {}) do
            if not e.filename:match("^av://lavfi:") then
                local position=i-1
                add(e.id or i,e.title or filename(e.filename),string.format("Video %d",i),e.current,
                    function() mp.set_property_number("playlist-pos",position) end)
            end
        end
    elseif kind=="audio" or kind=="subtitles" or kind=="video" or kind=="tracks" then
        local prop=kind=="audio" and "aid" or kind=="video" and "vid" or "sid"
        local selected=mp.get_property_native(prop)
        local subtitles_visible=mp.get_property_bool("sub-visibility",true)
        if kind=="subtitles" then
            add("off","Subtitles off","",selected==false or selected=="no" or not subtitles_visible,
                function() mp.set_property(prop,"no") end,"subtitles")
        end
        for _,track in ipairs(mp.get_property_native("track-list") or {}) do
            if kind=="tracks" or track.type==(kind=="audio" and "audio" or kind=="video" and "video" or "sub") then
                local id=track.id
                local property=kind=="tracks" and ({audio="aid",sub="sid",video="vid"})[track.type] or prop
                local label=track.title or track.lang or ("Track "..id)
                local detail={}
                if kind=="tracks" then detail[#detail+1]=track.type=="sub" and "Subtitles" or track.type=="video" and "Video" or "Audio" end
                if track.lang then detail[#detail+1]=track.lang end
                if track.codec then detail[#detail+1]=track.codec:upper() end
                if track["audio-channels"] then
                    detail[#detail+1]=track["audio-channels"]..(track["audio-channels"]==1 and " channel" or " channels")
                end
                if track.external then detail[#detail+1]="External" end
                local current=tostring(mp.get_property_native(property))==tostring(id)
                if property=="sid" then current=current and subtitles_visible end
                add(track.type..id,label,table.concat(detail,"  ·  "),current,
                    function()
                        mp.set_property_number(property,id)
                        if property=="sid" then mp.set_property_bool("sub-visibility",true) end
                    end,track.type=="audio" and "audio" or track.type=="video" and "video" or "subtitles")
            end
        end
    elseif kind=="editions" then
        for i,edition in ipairs(mp.get_property_native("edition-list") or {}) do
            local index=i-1
            add(i,edition.title or ("Edition "..i),"",mp.get_property_number("edition")==index,
                function() mp.set_property_number("edition",index) end,"video")
        end
    elseif kind=="chapters" then
        for i,chapter in ipairs(mp.get_property_native("chapter-list") or {}) do
            local index=i-1
            add(i,chapter.title or ("Chapter "..i),time_label(chapter.time),mp.get_property_number("chapter")==index,
                function() mp.set_property_number("chapter",index) end,"chapter")
        end
    elseif kind=="speed" then
        local current=mp.get_property_number("speed",1)
        local speeds={.5,.75,1,1.25,1.5,1.75,2}
        local found=false
        for _,speed in ipairs(speeds) do if math.abs(speed-current)<.001 then found=true end end
        if not found then speeds[#speeds+1]=current; table.sort(speeds) end
        for _,speed in ipairs(speeds) do
            local value=speed
            add(speed,string.format("%g×",speed),speed==1 and "Normal speed" or "",math.abs(speed-current)<.001,
                function() mp.set_property_number("speed",value) end,"speed")
        end
    elseif kind=="device" then
        for _,device in ipairs(mp.get_property_native("audio-device-list") or {}) do
            local name=device.name
            add(name,device.description or name,name,mp.get_property("audio-device")==name,
                function() mp.set_property("audio-device",name) end,"audio")
        end
    elseif kind=="controls" then
        for _,item in ipairs({
            {"library","Library","Favourite folders and recent locations","folder"},
            {"playlist","Playlist","Videos in your queue","playlist"},{"audio","Audio tracks","Languages and audio tracks","audio"},
            {"subtitles","Subtitles","Subtitle tracks and visibility","subtitles"},{"chapters","Chapters","Jump within this video","chapter"},
            {"speed","Playback speed","Slow down or speed up","speed"},{"device","Audio output","Speakers and headphones","audio"},
            {"youtube","YouTube","Play a video link"},{"update","Updates","Check for a newer version","up"},
        }) do
            local id=item[1]
            add(id,item[2],item[3],false,function()
                if id=="library" then mp.commandv("script-message","crt-open")
                elseif id=="youtube" then mp.commandv("script-message","crt-youtube")
                elseif id=="update" then mp.commandv("script-message","crt-update-check")
                else show(id,true) end
            end,item[4])
        end
    end
    return rows
end
local function render()
    if not menu then return end
    local def=definitions[menu.kind]
    local model={
        kind="select",title=def[1],subtitle=def[2],rows=menu.rows,selected=menu.selected,top=menu.top,
        caption=menu.kind=="controls" and "Choose a menu" or "Select to apply",
        hint="Enter  Choose    Esc  Close",back=menu.back,focus=menu.focus,hover=menu.hover,
        empty=def[3] or "No items",empty_detail="Open a video to see the available choices.",
        suspended=mp.get_property_native("window-minimized")==true,
    }
    local layout=view:render(model)
    if layout then
        menu.top=layout.top
        if menu.selected<menu.top then menu.top=menu.selected
        elseif menu.selected>=menu.top+layout.visible then menu.top=menu.selected-layout.visible+1 end
        if menu.top~=layout.top then model.top=menu.top; view:render(model) end
    end
end
local function move(delta)
    menu.selected=math.max(1,math.min(#menu.rows,menu.selected+delta))
    menu.focus,menu.hover=nil,nil
    render()
end
-- The wheel scrolls the list; it does not move the keyboard selection. The highlight follows whatever row ends up
-- under the pointer, so it does not jump back to the pointer when the mouse next twitches.
local function wheel(delta)
    if not menu then return end
    local visible=view.layout and view.layout.visible or 8
    menu.top=math.max(1,math.min(math.max(1,#menu.rows-visible+1),menu.top+delta))
    menu.selected=math.max(menu.top,math.min(menu.top+visible-1,menu.selected))
    menu.focus=nil
    render()
    local m=mp.get_property_native("mouse-pos") or {}
    local h=m.x and m.y and m.hover~=false and view:hit(m.x,m.y) or nil
    local id=h and h.id
    local selected=h and h.action and h.action.kind=="row" and h.action.index or menu.selected
    if id~=menu.hover or selected~=menu.selected then
        menu.hover,menu.selected=id,selected
        render()
    end
end
local function choose(index)
    local row=menu.rows[index]
    if not row then return end
    local action=row.choose
    close(true)
    action()
end
local function activate(hit)
    if not hit then return end
    if hit.id=="close" then close(true)
    elseif hit.id=="back" then show("controls")
    elseif hit.action and hit.action.kind=="row" then choose(hit.action.index) end
end
local function enter()
    if menu.focus then
        for _,h in ipairs(view.hits) do if h.id==menu.focus then activate(h); return end end
    else choose(menu.selected) end
end
local function tab(delta)
    local index=0
    for i,id in ipairs(view.controls) do if id==menu.focus then index=i end end
    index=index+delta
    menu.focus=view.controls[index]
    render()
end
local function drag(y)
    local t=view.layout.track
    if not t then return end
    local ratio=math.max(0,math.min(1,(y-t.y-t.thumb/2)/math.max(1,t.height-t.thumb)))
    menu.top=1+math.floor(ratio*(#menu.rows-view.layout.visible)+.5)
    menu.selected=math.max(menu.top,math.min(menu.top+view.layout.visible-1,menu.selected))
    render()
end
local function click(e)
    if not menu then return end
    local m=mp.get_property_native("mouse-pos")
    if not m then return end
    local h=view:hit(m.x,m.y)
    if e.event=="down" then
        menu.pressed=h and h.id
        if h and h.id=="scrollbar" then menu.dragging=true; drag(m.y) end
    elseif e.event=="up" or e.event=="press" then
        if menu.dragging then menu.dragging=nil; return end
        if h and (e.event=="press" or menu.pressed==h.id) then activate(h) end
    end
end
local function nothing() end
local keys={
    {"MBTN_LEFT",click,{complex=true}},{"MBTN_LEFT_DBL",nothing},{"MBTN_RIGHT",nothing},
    {"UP",function() move(-1) end,{repeatable=true}},{"DOWN",function() move(1) end,{repeatable=true}},
    {"WHEEL_UP",function() wheel(-1) end},{"WHEEL_DOWN",function() wheel(1) end},
    {"PGUP",function() move(-(view.layout.visible or 1)) end},{"PGDWN",function() move(view.layout.visible or 1) end},
    {"HOME",function() move(-#menu.rows) end},{"END",function() move(#menu.rows) end},
    {"ENTER",enter},{"KP_ENTER",enter},{"ESC",function() close(true) end},
    {"BS",function() if menu.back then show("controls") else close(true) end end},
    {"TAB",function() tab(1) end},{"Shift+TAB",function() tab(-1) end},
    {"LEFT",nothing},{"RIGHT",nothing},{"SPACE",nothing},{"any_unicode",nothing},
}
close=function(resume)
    if not menu then return end
    menu=nil
    for _,name in ipairs(bound) do mp.remove_key_binding(name) end
    bound={}
    view:close()
    modal:release(resume)
end
show=function(kind,back)
    kind=definitions[kind] and kind or "controls"
    if menu then close(true) end
    menu={kind=kind,back=back,rows=rows_for(kind),selected=1,top=1}
    for i,row in ipairs(menu.rows) do if row.current then menu.selected=i; break end end
    modal:acquire()
    for i,key in ipairs(keys) do
        local name="crt-selector-"..i
        bound[#bound+1]=name
        mp.add_forced_key_binding(key[1],name,key[2],key[3])
    end
    render()
end
mp.observe_property("mouse-pos","native",function(_,m)
    if not menu or not m then return end
    if menu.dragging then drag(m.y); return end
    if m.x==menu.x and m.y==menu.y then return end
    menu.x,menu.y=m.x,m.y
    local h=m.hover~=false and view:hit(m.x,m.y) or nil
    if (h and h.id)~=menu.hover then
        menu.hover,menu.focus=h and h.id,nil
        if h and h.action and h.action.kind=="row" then menu.selected=h.action.index end
        render()
    end
end)
mp.observe_property("osd-dimensions","native",render)
mp.observe_property("window-minimized","bool",render)
mp.register_script_message("crt-menu",show)
-- Match mpv's familiar shortcuts and context-menu entry points. Normal bindings allow
-- the hover bar and remote to retain their own right-click actions.
for _,binding in ipairs({
    {"MBTN_RIGHT","controls"},{"MENU","controls"},{"Shift+F10","controls"},{"Ctrl+p","controls"},{"g-m","controls"},
    {"g-p","playlist"},{"g-a","audio"},{"g-s","subtitles"},{"g-c","chapters"},{"g-d","device"},
    {"g-v","video"},{"g-t","tracks"},{"g-e","editions"},
}) do
    local kind= binding[2]
    mp.add_key_binding(binding[1],"crt-menu-"..binding[1],function() show(kind) end)
end
mp.register_event("shutdown",function() close(false) end)
