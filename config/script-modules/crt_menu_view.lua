-- Shared vector-only menu UI. Static chrome and moving text use separate ASS overlays.
-- Text bounds are measured once and cached; the animation timer exists only for overflow.
local mp = require 'mp'
local M = {}
local font = package.config:sub(1,1) == "\\" and "Segoe UI" or "sans-serif"
local C = {
    panel="17191e", border="363940", text="eceef2", muted="9a9fa9", dim="646b77",
    accent="ff9148", selected="302923", button="25282f", hover="343840", line="2b2e35", error="ff9b90",
}
local function color(hex) return "&H" .. hex:sub(5,6) .. hex:sub(3,4) .. hex:sub(1,2) .. "&" end
for k,v in pairs(C) do C[k] = color(v) end
local function esc(s)
    return (s:gsub("\\", "\\\226\129\160"):gsub("{", "\\{"):gsub("}", "\\}"):gsub("%c", " "))
end
local function rect(x,y,w,h,r)
    r = math.min(r or 0, w/2, h/2)
    return string.format("m %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f",
        x+r,y, x+w-r,y, x+w,y,x+w,y,x+w,y+r,
        x+w,y+h-r, x+w,y+h,x+w,y+h,x+w-r,y+h,
        x+r,y+h, x,y+h,x,y+h,x,y+h-r,
        x,y+r, x,y,x,y,x+r,y)
end
local function shape(path,col,alpha)
    return string.format("{\\an7\\pos(0,0)\\bord0\\shad0\\1c%s\\1a&H%02X&\\p1}%s", col,alpha or 0,path)
end
local function text_line(text,x,y,size,col,bold,clip,alignment)
    return string.format("{\\an%d\\q2\\fn%s\\pos(%.2f,%.2f)\\fs%.2f\\1c%s\\bord0\\shad0\\b%d%s}%s",
        alignment or 4,font,x,y,size,col,bold and 1 or 0,
        clip and string.format("\\clip(%.2f,%.2f,%.2f,%.2f)",clip[1],clip[2],clip[3],clip[4]) or "",esc(text))
end
local function polygon(points,x,y,size)
    local out = {}
    for i=1,#points,2 do
        out[#out+1] = string.format("%s %.2f %.2f",i==1 and "m" or "l", x+points[i]*size,y+points[i+1]*size)
    end
    return table.concat(out," ")
end
local icons = {
    folder={0,.2,.38,.2,.48,.32,1,.32,1,.86,0,.86},
    video={.18,.1,.88,.5,.18,.9},
    back={.72,.08,.84,.2,.42,.5,.84,.8,.72,.92,.16,.5},
    up={.08,.64,.2,.76,.5,.44,.8,.76,.92,.64,.5,.2},
    close={.2,.1,.5,.4,.8,.1,.9,.2,.6,.5,.9,.8,.8,.9,.5,.6,.2,.9,.1,.8,.4,.5,.1,.2},
    home={0,.45,.5,.05,1,.45,.86,.45,.86,.95,.58,.95,.58,.62,.42,.62,.42,.95,.14,.95,.14,.45},
    drive={.15,.12,.85,.12,1,.68,1,.9,0,.9,0,.68},
    chevron={.3,.12,.43,0,.93,.5,.43,1,.3,.88,.67,.5},
    check={.04,.52,.18,.38,.4,.62,.82,.12,.96,.26,.42,.9},
    audio={.08,.34,.3,.34,.65,.08,.65,.92,.3,.66,.08,.66},
    subtitles={.05,.12,.95,.12,.95,.75,.55,.75,.25,.96,.25,.75,.05,.75},
    chapter={.2,.08,.8,.08,.8,.96,.5,.74,.2,.96},
    speed={.5,.03,.18,.56,.47,.56,.38,.97,.87,.36,.56,.36},
    playlist={{.08,.16,.74,.16,.74,.28,.08,.28},{.08,.42,.74,.42,.74,.54,.08,.54},{.08,.68,.5,.68,.5,.8,.08,.8}},
}
icons.star = {}
for i=0,9 do
    local a = -math.pi/2+i*math.pi/5
    local r = i%2==0 and .48 or .22
    icons.star[#icons.star+1], icons.star[#icons.star+2] = .5+math.cos(a)*r, .5+math.sin(a)*r
end

function M.new()
    local self = {base=mp.create_osd_overlay("ass-events"), motion=mp.create_osd_overlay("ass-events"),
        measure=mp.create_osd_overlay("ass-events"), cache={}, cache_count=0, fields={}, hits={}}
    self.base.z, self.motion.z = 1001,1002
    self.measure.hidden, self.measure.compute_bounds = true,true
    return setmetatable(self,{__index=M})
end
function M:stop_timer()
    if self.timer then self.timer:kill(); self.timer=nil end
end
function M:close()
    self:stop_timer()
    self.base:remove(); self.motion:remove(); self.measure:remove()
    self.fields,self.hits,self.focus_key = {},{},nil
end
function M:width(text,size,bold)
    local key = string.format("%.2f:%s:%s",size,tostring(bold),text)
    if self.cache[key] then return self.cache[key] end
    if text=="" then return 0 end
    -- Measure UTF-8 chunks at their real scale; a sentinel retains trailing spaces.
    -- Chunking avoids clipping the hidden bounds measurement at the window edge.
    self.measure.res_x,self.measure.res_y = self.W,self.H
    local function measure(str)
        local rawkey="raw:"..string.format("%.2f:%s:%s",size,tostring(bold),str)
        if self.cache[rawkey] then return self.cache[rawkey] end
        self.measure.data=string.format("{\\an7\\q2\\fn%s\\pos(0,0)\\fs%.2f\\fscx100\\bord0\\shad0\\b%d}%s",
            font,size,bold and 1 or 0,esc(str))
        local bounds=self.measure:update()
        local width=bounds and bounds.x1 or #str*size*.6
        self.cache[rawkey],self.cache_count=width,self.cache_count+1
        return width
    end
    local sentinel=measure("|")
    local maximum=math.max(1,math.floor((self.W-32)/(size*1.5)))
    local chunks,count,width={},0,0
    for char in text:gmatch("[\1-\127\194-\244][\128-\191]*") do
        chunks[#chunks+1]=char
        count=count+1
        if count==maximum then
            width=width+math.max(0,measure(table.concat(chunks).."|")-sentinel)
            chunks,count={},0
        end
    end
    if count>0 then width=width+math.max(0,measure(table.concat(chunks).."|")-sentinel) end
    if self.cache_count >= 512 then self.cache,self.cache_count = {},0 end
    self.cache[key],self.cache_count = width,self.cache_count+1
    return width
end
-- long text scrolls after a pause, at this many pixels per second (before UI scaling)
local MARQUEE_SPEED, MARQUEE_PAUSE = 18, 1.6
function M:animate()
    self.timer=nil
    if #self.fields==0 then self.motion:remove(); return end
    local out, wait = {},1
    local elapsed = math.max(0,mp.get_time()-self.epoch)
    for _, f in ipairs(self.fields) do
        local distance = f.width+44*self.scale
        local duration = distance/(MARQUEE_SPEED*self.scale)
        local phase = elapsed%(MARQUEE_PAUSE+duration)
        local offset = phase<MARQUEE_PAUSE and 0 or (phase-MARQUEE_PAUSE)*MARQUEE_SPEED*self.scale
        wait = math.min(wait,phase<MARQUEE_PAUSE and math.max(.01,MARQUEE_PAUSE-phase) or 1/30)
        out[#out+1] = text_line(f.text,f.x-offset,f.y,f.size,f.col,f.bold,f.clip)
        if offset>0 then out[#out+1] = text_line(f.text,f.x-offset+distance,f.y,f.size,f.col,f.bold,f.clip) end
        -- A small mask softens partial letters at the moving text's edges.
        local step=2*self.scale
        for i=0,4 do
            out[#out+1]=shape(rect(f.clip[3]-(i+1)*step,f.clip[2],step,f.clip[4]-f.clip[2]),f.bg,i*48)
            if offset>0 then out[#out+1]=shape(rect(f.clip[1]+i*step,f.clip[2],step,f.clip[4]-f.clip[2]),f.bg,i*48) end
        end
    end
    local data = table.concat(out,"\n")
    if self.motion.data~=data or self.motion.res_x~=self.W or self.motion.res_y~=self.H then
        self.motion.res_x,self.motion.res_y,self.motion.data = self.W,self.H,data
        self.motion:update()
    end
    self.timer=mp.add_timeout(wait,function() self:animate() end)
end

function M:render(model)
    self:stop_timer()
    local d = mp.get_property_native("osd-dimensions") or {}
    local W,H = d.w or 0,d.h or 0
    if W<160 or H<160 then self.base:remove(); self.motion:remove(); return end
    if W~=self.W or H~=self.H then self.cache,self.cache_count={},0 end
    self.W,self.H = W,H
    local rh,head,foot = 60,142,48
    -- Reserve two rows even in a shallow window, including room for an empty state.
    local s = math.min(W/460,H/(head+2*rh+foot+32),math.max(.85,math.min(1.3,W/1280,H/720)))
    local pw = math.min(820,(W-32)/s)
    local capacity=math.max(1,math.min(8,math.floor((H/s-32-head-foot)/rh)))
    local visible=math.min(capacity,math.max(2,#model.rows))
    local ph=head+visible*rh+foot
    local px,py=(W-pw*s)/2,(H-ph*s)/2
    local top=math.max(1,math.min(model.top or 1,math.max(1,#model.rows-visible+1)))
    local out,fields,hits,controls={},{},{},{}
    local function X(x) return px+x*s end
    local function Y(y) return py+y*s end
    local function box(x,y,w,h,col,r,alpha)
        out[#out+1]=shape(rect(X(x),Y(y),w*s,h*s,(r or 0)*s),col,alpha)
    end
    local function icon(name,x,y,size,col)
        local points=icons[name] or icons.folder
        if type(points[1])=="table" then
            for _,part in ipairs(points) do out[#out+1]=shape(polygon(part,X(x),Y(y),size*s),col) end
        else out[#out+1]=shape(polygon(points,X(x),Y(y),size*s),col) end
    end
    local function hit(id,x,y,w,h,action,tooltip)
        hits[#hits+1]={id=id,x1=X(x),y1=Y(y),x2=X(x+w),y2=Y(y+h),action=action,tooltip=tooltip}
    end
    local function text(str,x,y,size,col,bold,width,moving,bg,centered)
        local clip = width and {X(x),Y(y-size),X(x+width),Y(y+size)}
        local measured = width and self:width(str,size*s,bold)
        if width and measured>width*s then
            if moving then
                fields[#fields+1]={text=str,x=X(x),y=Y(y),size=size*s,col=col,bold=bold,clip=clip,width=measured,bg=bg or C.panel}
            else
                clip[3]=X(x+width-15)
                out[#out+1]=text_line(str,X(x),Y(y),size*s,col,bold,clip)
                out[#out+1]=text_line("…",X(x+width-14),Y(y),size*s,col,bold)
            end
        else
            out[#out+1]=text_line(str,X(centered and x+width/2 or x),Y(y),size*s,col,bold,clip,centered and 5 or 4)
        end
    end
    local function button(id,label,kind,x,y,w,action,tip,primary,lit)
        local active=model.hover==id or model.focus==id
        box(x,y,w,32,primary and C.accent or active and C.hover or C.button,7)
        local col=primary and color("20150d") or lit and C.accent or C.text
        if kind then icon(kind,x+9,y+8,16,col) end
        if label then text(label,x+(kind and 33 or 12),y+16,15,col,false) end
        hit(id,x,y,w,32,action,tip or label)
        controls[#controls+1]=id
    end
    out[#out+1]=shape(rect(0,0,W,H),color("000000"),0x68)
    box(0,7,pw,ph,color("000000"),16,0x70)
    box(0,0,pw,ph,C.border,14)
    box(1,1,pw-2,ph-2,C.panel,13)
    box(24,23,3,34,C.accent,1)
    text(model.title,39,35,27,C.text,true,pw-110,true)
    text(model.subtitle,39,64,14,C.muted,false,pw-70,true)
    button("close",nil,"close",pw-54,22,32,{kind="close"},"Close  ·  Esc")
    if model.kind=="library" then
        local x=24
        for _, t in ipairs({{"all","All",48},{"favourites","Favourites",101},{"recent","Recent",75}}) do
            local active=model.filter==t[1]
            if model.focus=="filter:"..t[1] or model.hover=="filter:"..t[1] then
                box(x,98,t[3],30,C.hover,7)
            elseif active then box(x,98,t[3],30,C.button,7) end
            text(t[2],x,113,15,active and C.text or C.muted,active,t[3],false,nil,true)
            if active then box(x+10,129,t[3]-20,2,C.accent,1) end
            hit("filter:"..t[1],x,98,t[3],32,{kind="filter",filter=t[1]},t[2])
            controls[#controls+1]="filter:"..t[1]
            x=x+t[3]+3
        end
        local label=pw<600 and "Browse" or "Browse folders"
        local bw=pw<600 and 108 or 158
        button("browse",label,"folder",pw-24-bw,97,bw,{kind="browse"},"Browse folders",true)
    elseif model.kind=="folder" or model.kind=="places" then
        local wide=pw>=620
        local x=24
        for _, b in ipairs({{"back","Back","back"},{"home","Library","home"},{"up","Up","up"},{"places","Locations","drive"}}) do
            if b[1]~="up" or model.kind=="folder" then
                local w=wide and (b[1]=="places" and 111 or b[1]=="home" and 97 or 83) or 34
                button(b[1],wide and b[2] or nil,b[3],x,97,w,{kind=b[1]},b[2])
                x=x+w+6
            end
        end
        if model.kind=="folder" then
            local w=wide and 139 or 34
            button("favourite",wide and (model.saved and "Saved folder" or "Save folder") or nil,"star",pw-24-w,97,w,
                {kind="favourite",path=model.dir},"Favourite folder  ·  F",false,model.saved)
        end
    else
        if model.back then button("back","Back","back",24,97,83,{kind="back"},"Back")
        else text(model.caption or "Choose an item",25,113,15,C.muted,false,pw-50) end
    end
    box(24,139,pw-48,1,C.line)
    if #model.rows==0 then
        icon("folder",pw/2-15,head+22,30,C.dim)
        text(model.empty or "No videos in this folder",24,head+70,19,C.text,false,pw-48,true,C.panel,true)
        text(model.empty_detail or "Use Up to browse another folder.",24,head+99,14,C.muted,false,pw-48,true,C.panel,true)
    end
    for slot=1,visible do
        local i=top+slot-1
        local row=model.rows[i]
        if row then
            local y=head+(slot-1)*rh+4
            local active=i==model.selected
            if active then
                box(16,y,pw-32,rh-5,C.selected,9)
                box(17,y+12,3,rh-29,C.accent,1)
            end
            box(29,y+11,34,34,C.button,8)
            icon(row.icon or (row.kind=="video" and "video" or row.kind=="drive" and "drive" or "folder"),37,y+19,18,
                active and C.accent or C.muted)
            local title_width=pw-158
            local moving=active and not model.focus
            text(row.title,78,y+20,20,C.text,false,title_width,moving,C.selected)
            text(row.detail or "",78,y+42,13,C.muted,false,title_width,moving,C.selected)
            hit("row:"..i,22,y,pw-44,rh-5,{kind="row",index=i})
            if row.kind=="folder" or row.kind=="drive" then
                local saved=model.is_favourite and model.is_favourite(row.path)
                icon("star",pw-55,y+20,17,saved and C.accent or C.dim)
                hit("star:"..i,pw-65,y+6,38,rh-16,{kind="favourite",path=row.path},
                    saved and "Remove favourite" or "Save favourite")
            elseif row.current then icon("check",pw-55,y+20,17,C.accent)
            elseif active then icon("chevron",pw-52,y+21,12,C.accent) end
        end
    end
    local track
    if #model.rows>visible then
        local height=visible*rh-10
        local thumb=math.max(22,height*visible/#model.rows)
        local offset=(top-1)/(#model.rows-visible)*(height-thumb)
        box(pw-10,head+5,3,height,C.line,1)
        box(pw-10,head+5+offset,3,thumb,C.muted,1)
        hit("scrollbar",pw-19,head,19,visible*rh,{kind="scrollbar"})
        track={y=Y(head+5),height=height*s,thumb=thumb*s}
    end
    box(24,ph-foot+3,pw-48,1,C.line)
    local hint=model.hint or (model.kind=="library" and "Enter  Open    F  Favourite" or "Enter  Play / Open    Backspace  Back")
    if model.hover then
        for _, h in ipairs(hits) do if h.id==model.hover and h.tooltip then hint=h.tooltip; break end end
    end
    text(model.error or hint,25,ph-21,13,model.error and C.error or C.muted,false,pw-157)
    local count=#model.rows==0 and "No items" or string.format("%d / %d",model.selected,#model.rows)
    text(count,pw-108,ph-21,13,C.dim,false,86)
    local focused= model.rows[model.selected]
    local focus_key=(model.dir or model.filter or model.kind)..":"..(focused and focused.path or "")..":"..(model.focus or "")
    if self.focus_key~=focus_key then self.epoch=mp.get_time(); self.focus_key=focus_key end
    self.scale,self.fields,self.hits,self.controls=s,fields,hits,controls
    self.layout={x=px,y=py,w=pw*s,h=ph*s,visible=visible,top=top,track=track}
    local data=table.concat(out,"\n")
    if self.base.data~=data or self.base.res_x~=W or self.base.res_y~=H then
        self.base.res_x,self.base.res_y,self.base.data=W,H,data
        self.base:update()
    end
    if model.suspended then self.motion:remove() else self:animate() end
    return self.layout
end
function M:hit(x,y)
    -- Later hits (stars, scrollbar) take priority over the underlying row.
    for i=#self.hits,1,-1 do
        local h=self.hits[i]
        if x>=h.x1 and x<h.x2 and y>=h.y1 and y<h.y2 then return h end
    end
end

-- Input and confirmation dialogs use the same frame, typography, buttons and marquee.
-- Breaks a paragraph into lines that fit the dialog's text column. The panel's scale is not known until its height
-- is (which depends on the line count), so this uses the largest scale it could have: that column is never wider
-- than the real one.
function M:wrap(text,size,W,H)
    local s=math.max(.85,math.min(1.3,W/1280,H/720))
    s=math.min(W/460,s)
    local limit=(math.min(680,(W-32)/s)-52)*s
    local lines,line={},""
    for word in text:gmatch("%S+") do
        local try=line=="" and word or line.." "..word
        if line~="" and self:width(try,size*s,false)>limit then
            lines[#lines+1]=line
            line=word
        else line=try end
    end
    if line~="" then lines[#lines+1]=line end
    return lines
end
function M:render_dialog(model)
    self:stop_timer()
    local d=mp.get_property_native("osd-dimensions") or {}
    local W,H=d.w or 0,d.h or 0
    if W<160 or H<160 then self.base:remove(); self.motion:remove(); return end
    if W~=self.W or H~=self.H then self.cache,self.cache_count={},0 end
    self.W,self.H=W,H
    local body=model.body or {}
    if model.text then body=self:wrap(model.text,17,W,H) end
    local ph=model.input and 292 or 218+#body*30
    local s=math.min(W/460,H/(ph+32),math.max(.85,math.min(1.3,W/1280,H/720)))
    local pw=math.min(680,(W-32)/s)
    local px,py=(W-pw*s)/2,(H-ph*s)/2
    local out,fields,hits,controls={},{},{},{}
    local function X(x) return px+x*s end
    local function Y(y) return py+y*s end
    local function box(x,y,w,h,col,r,alpha)
        out[#out+1]=shape(rect(X(x),Y(y),w*s,h*s,(r or 0)*s),col,alpha)
    end
    local function hit(id,x,y,w,h)
        hits[#hits+1]={id=id,x1=X(x),y1=Y(y),x2=X(x+w),y2=Y(y+h)}
        controls[#controls+1]=id
    end
    local function text(str,x,y,size,col,bold,width)
        local clip=width and {X(x),Y(y-size),X(x+width),Y(y+size)}
        local measured=width and self:width(str,size*s,bold)
        if width and measured>width*s then
            fields[#fields+1]={text=str,x=X(x),y=Y(y),size=size*s,col=col,bold=bold,clip=clip,
                width=measured,bg=C.panel}
        else out[#out+1]=text_line(str,X(x),Y(y),size*s,col,bold,clip) end
    end
    local function button(id,label,x,y,w,primary)
        local hot=model.hover==id or model.focus==id
        box(x,y,w,36,primary and C.accent or hot and C.hover or C.button,7)
        text(label,x+14,y+18,16,primary and color("20150d") or C.text,false)
        hit(id,x,y,w,36)
    end
    out[#out+1]=shape(rect(0,0,W,H),color("000000"),0x68)
    box(0,7,pw,ph,color("000000"),14,0x70)
    box(0,0,pw,ph,C.border,14)
    box(1,1,pw-2,ph-2,C.panel,13)
    box(24,23,3,34,C.accent,1)
    text(model.title,39,35,27,C.text,true,pw-110)
    text(model.subtitle or "",39,64,14,C.muted,false,pw-70)
    box(pw-54,22,32,32,(model.hover=="close" or model.focus=="close") and C.hover or C.button,7)
    out[#out+1]=shape(polygon(icons.close,X(pw-46),Y(30),16*s),C.text)
    hit("close",pw-54,22,32,32)
    if model.input then
        local field=model.input
        text("Video link",26,103,14,C.muted)
        local fw=pw-148
        box(24,119,fw,44,model.focus=="field" and C.accent or C.border,8)
        box(25,120,fw-2,42,color("101216"),7)
        hit("field",24,119,fw,44)
        local x,y,width=36,141,fw-24
        local clip={X(x),Y(121),X(x+width),Y(161)}
        local prefix=field.text:sub(1,field.cursor or #field.text)
        local before=self:width(prefix,18*s,false)
        local offset=math.max(0,before-width*s+6*s)
        if field.all and field.text~="" then box(x,125,width,32,C.selected,2) end
        out[#out+1]=text_line(field.text~="" and field.text or "Paste a YouTube link",X(x)-offset,Y(y),18*s,
            field.text=="" and C.dim or C.text,false,clip)
        if field.caret and model.focus=="field" then
            out[#out+1]=shape(rect(math.min(X(x+width)-2,X(x)+before-offset),Y(130),s,22*s),C.accent)
        end
        button("paste","Paste",pw-112,123,88,false)
        if model.error then text(model.error,26,183,14,C.error,false,pw-52) end
    else
        for i,line in ipairs(body) do text(line,26,108+(i-1)*30,17,C.text,false,pw-52) end
    end
    local buttons=model.buttons or {}
    local total=0
    for _,b in ipairs(buttons) do total=total+(b.width or 110)+8 end
    local bx=pw-24-total+8
    for _,b in ipairs(buttons) do
        local w=b.width or 110
        button(b.id,b.label,bx,ph-88,w,b.primary)
        bx=bx+w+8
    end
    box(24,ph-41,pw-48,1,C.line)
    text(model.hint or "Enter  Confirm    Esc  Close",25,ph-21,13,C.muted,false,pw-50)
    local key="dialog:"..model.id..":"..(model.focus or "")..":"..(model.error or "")
    if key~=self.focus_key then self.epoch=mp.get_time(); self.focus_key=key end
    self.focus_key,self.scale,self.fields,self.hits,self.controls=key,s,fields,hits,controls
    self.layout={x=px,y=py,w=pw*s,h=ph*s}
    local data=table.concat(out,"\n")
    if self.base.data~=data or self.base.res_x~=W or self.base.res_y~=H then
        self.base.res_x,self.base.res_y,self.base.data=W,H,data
        self.base:update()
    end
    if model.suspended then self.motion:remove() else self:animate() end
end
return M
