-- One active player dialog. A replacement inherits the original playback state.
local mp = require 'mp'
local M = {}
function M.new(owner,replaced)
    local self={owner=owner}
    mp.observe_property("user-data/crt-modal","native",function()
        -- Observations are delivered later; a queued notification may describe an older owner.
        local active=mp.get_property_native("user-data/crt-modal")
        if self.lease and (type(active)~="table" or active.owner~=owner) then
            self.lease=nil
            replaced()
        end
    end)
    function self:acquire()
        local active=mp.get_property_native("user-data/crt-modal")
        local dragging=mp.get_property_native("window-dragging")
        if type(active)=="table" and active.dragging~=nil then dragging=active.dragging end   -- false is a real value
        self.lease={
            owner=owner,
            paused=type(active)=="table" and active.paused or mp.get_property_bool("pause"),
            osc=type(active)=="table" and active.osc or mp.get_property_native("user-data/osc/visibility"),
            -- mpv's window dragging takes the mouse from the script after a few pixels of movement while the button
            -- is held, which breaks dragging a scrollbar; it stays off while a dialog is up
            dragging=dragging,
        }
        -- false is a meaningful inherited pause state.
        if type(active)=="table" then self.lease.paused=active.paused end
        mp.set_property_native("user-data/crt-modal",self.lease)
        mp.set_property_bool("window-dragging",false)
        mp.set_property_native("user-data/crt-menu-open",true)
        mp.set_property_bool("pause",true)
        if self.lease.osc then mp.commandv("script-message","osc-visibility","never","yes") end
    end
    function self:release(resume)
        local lease=self.lease
        self.lease=nil
        local active=mp.get_property_native("user-data/crt-modal")
        if not lease or type(active)~="table" or active.owner~=owner then return end
        mp.set_property_native("user-data/crt-modal",nil)
        mp.set_property_native("user-data/crt-menu-open",false)
        if lease.dragging~=nil then mp.set_property_bool("window-dragging",lease.dragging) end
        if resume then mp.set_property_bool("pause",lease.paused) end
        if lease.osc then mp.commandv("script-message","osc-visibility",lease.osc,"yes") end
    end
    return self
end
return M
