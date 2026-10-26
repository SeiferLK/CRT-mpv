-- Run without opening a window:
-- mpv --no-config --idle=yes --vo=null --script=tools/test-seek.lua
local player = require 'mp'
local source = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local script_dir = source:match('^(.*)/') or '.'
local module_path = script_dir .. '/../config/script-modules/crt_seek.lua'
local checks = 0

local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end

local function fixture(paused)
    local now, timers, events, seeks = 0, {}, {}, {}
    local pos, actual, redraws = 10, 5, 0
    local fake = {
        get_time = function() return now end,
        get_property_bool = function(name) assert(name == 'pause'); return paused end,
        set_property_bool = function(name, value) assert(name == 'pause'); paused = value end,
        register_event = function(name, fn) events[name] = fn end,
        msg = {warn = function(message) error(message) end},
        command_native_async = function(command, done)
            seeks[#seeks + 1] = command
            done(true)
        end,
        add_timeout = function(delay, fn)
            local timer = {at = now + delay, fn = fn}
            timer.kill = function(self) self.killed = true end
            timers[#timers + 1] = timer
            return timer
        end,
    }
    local function advance(delta)
        local goal = now + delta
        while true do
            local next_timer
            for _, timer in ipairs(timers) do
                if not timer.killed and timer.at <= goal and
                    (not next_timer or timer.at < next_timer.at) then next_timer = timer end
            end
            if not next_timer then break end
            now = next_timer.at
            next_timer.killed = true
            next_timer.fn()
        end
        now = goal
    end

    -- Only the module under test sees the fake player API.
    package.loaded.mp = fake
    local ok, controller = pcall(dofile, module_path)
    package.loaded.mp = player
    assert(ok, controller)
    local state, opts = {}, {mouse_seek_pause = true}
    local right_click = function() end
    local element = {state = {}, slider = {posF = function() return actual end},
                     eventresponder = {mbtn_right_down = right_click}}
    local function attach(e)
        controller.attach(e, function() return pos end,
            function() redraws = redraws + 1 end, state, opts)
    end
    attach(element)
    return {
        element = element, events = events, seeks = seeks, advance = advance,
        move = function(value)
            pos = value
            element.eventresponder.mouse_move(element)
        end,
        position = function(value) pos = value end,
        paused = function() return paused end,
        attach = attach, right_click = right_click,
    }
end

local function run()
    for _, paused in ipairs({false, true}) do
        local f = fixture(paused)
        local e = f.element
        e.eventresponder.mbtn_left_down(e)
        check(#f.seeks == 0, 'mouse down must not start an exact seek')
        for i = 1, 100 do
            f.move(10 + i * 0.7)
            check(e.slider.posF() == 10 + i * 0.7, 'handle must immediately track cursor')
            f.advance(0.01)
        end
        check(#f.seeks == 0, 'continuous movement must not flood decoder with seeks')
        check(f.paused(), 'drag should pause playback for preview')
        f.advance(0.13)
        check(#f.seeks == 1 and f.seeks[1][3] == 'absolute-percent+keyframes',
            'settled cursor must produce a fast preview')
        e.eventresponder.mbtn_left_up(e)
        e.eventresponder.reset(e)
        check(#f.seeks == 2 and f.seeks[2][2] == 80 and
            f.seeks[2][3] == 'absolute-percent+exact', 'release must commit accurate final target once')
        check(f.paused() == paused, 'release must preserve original playing/paused state')
        f.advance(2)
        check(#f.seeks == 2, 'no delayed preview may overwrite release target')
        check(e.slider.posF() == 5, 'finished drag must return to playback position')
        check(e.eventresponder.mbtn_right_down == f.right_click, 'chapter click must be preserved')
    end

    local f = fixture(false)
    f.element.eventresponder.mbtn_left_down(f.element)
    f.move(100)
    f.element.eventresponder.reset(f.element)
    check(f.seeks[1][2] == 100 and not f.paused(), 'release outside must finish and resume')
    f.advance(2)
    check(#f.seeks == 1, 'outside release must cancel pending preview')

    f = fixture(true)
    f.element.eventresponder['shift+mbtn_left_down'](f.element)
    f.element.eventresponder.mbtn_left_up(f.element)
    check(f.seeks[1][3] == 'absolute-percent+keyframes', 'Shift-click must retain keyframe mode')

    f = fixture(false)
    f.element.eventresponder.mbtn_left_down(f.element)
    f.move(60)
    f.events['end-file']()
    f.advance(2)
    check(#f.seeks == 0 and not f.paused(), 'file change must cancel preview and restore pause')

    f = fixture(false)
    f.element.eventresponder.mbtn_left_down(f.element)
    f.move(60)
    f.attach(nil)
    f.advance(2)
    check(#f.seeks == 0 and not f.paused(), 'layout rebuild must cancel old drag')
    f.attach({slider = {}})
    check(true, 'disabled startup slider must be safe')

    f = fixture(true)
    f.position(45)
    f.element.eventresponder.mbtn_left_down(f.element)
    f.element.eventresponder.mbtn_left_up(f.element)
    f.advance(2)
    check(#f.seeks == 1 and f.seeks[1][2] == 45 and
        f.seeks[1][3] == 'absolute-percent+exact', 'quick click must seek accurately once')
end

local ok, err = pcall(run)
if ok then
    player.msg.info('PASS: ' .. checks .. ' seek controller checks')
    player.commandv('quit', 0)
else
    player.msg.error(tostring(err))
    player.commandv('quit', 1)
end
