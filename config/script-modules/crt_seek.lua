-- Responsive dragging for the pinned ModernZ seekbar. Loaded by the installer footer.
local mp = require 'mp'
local M = {}
local current
local PREVIEW_INTERVAL = 1 / 4
local PREVIEW_SETTLE = 0.12

local function clear(restore)
    if current then current.cancel(restore) end
end
mp.register_event('end-file', function() clear(true) end)
mp.register_event('shutdown', function() clear(false) end)

function M.attach(element, get_pos, redraw, state, opts)
    clear(true)
    if not element or not element.eventresponder then current = nil; return end

    local timer, target, paused_by_drag, fast
    local last_preview = -math.huge
    local playback_pos = element.slider.posF
    local original_reset = element.eventresponder.reset

    local function stop_timer()
        if timer then timer:kill(); timer = nil end
    end

    local function restore_pause()
        if paused_by_drag then mp.set_property_bool('pause', false) end
        paused_by_drag = false
    end

    local function seek(pos, flags)
        -- A busy decoder/filter must not block ModernZ's mouse event handler.
        mp.command_native_async({'seek', pos, flags}, function(ok, _, err)
            if not ok then mp.msg.warn('CRT seek failed: ' .. tostring(err)) end
        end)
    end

    local function preview()
        timer = nil
        if not element.state.mbtnleft or target == nil then return end
        if target ~= element.state.lastseek then
            seek(target, 'absolute-percent+keyframes')
            element.state.lastseek = target
            last_preview = mp.get_time()
        end
    end

    local function update_target()
        target = get_pos(element)
        redraw()
        stop_timer()
        -- Wait for a brief pause in movement before decoding a preview. Repeated
        -- seeks rebuild the CPU TV filter and otherwise stall the whole bar.
        timer = mp.add_timeout(math.max(PREVIEW_SETTLE,
            last_preview + PREVIEW_INTERVAL - mp.get_time()), preview)
    end

    local function begin(is_fast)
        stop_timer()
        element.state.mbtnleft = true
        element.state.was_paused = mp.get_property_bool('pause')
        element.state.lastseek = nil
        state.playing_and_seeking = false
        paused_by_drag, fast = false, is_fast
        last_preview = -math.huge
        update_target()
    end

    local function finish()
        if not element.state.mbtnleft then return end
        stop_timer()
        target = get_pos(element)
        element.state.mbtnleft = false
        state.playing_and_seeking = false
        -- One accurate seek on release; Shift retains the fast keyframe seek.
        seek(target, fast and 'absolute-percent+keyframes' or 'absolute-percent+exact')
        target = nil
        restore_pause()
        redraw()
    end

    current = {cancel = function(restore)
        stop_timer()
        target = nil
        element.state.mbtnleft = false
        element.state.lastseek = nil
        state.playing_and_seeking = false
        if restore then restore_pause() end
    end}

    element.slider.posF = function()
        -- Draw from the cursor while dragging, independently of decoded video position.
        if target ~= nil then return target end
        return playback_pos()
    end
    element.eventresponder.mbtn_left_down = function() begin(false) end
    element.eventresponder['shift+mbtn_left_down'] = function() begin(true) end
    element.eventresponder.mouse_move = function()
        if not element.state.mbtnleft then return end
        state.playing_and_seeking = true
        if opts.mouse_seek_pause and not element.state.was_paused and not paused_by_drag then
            mp.set_property_bool('pause', true)
            paused_by_drag = true
        end
        update_target()
    end
    element.eventresponder.mbtn_left_up = finish
    element.eventresponder.reset = function(e)
        -- ModernZ calls reset even when release happens outside the slider hitbox.
        finish()
        if original_reset then original_reset(e) end
    end
end

return M
