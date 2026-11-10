-- Run from the repository root with Lua 5.1: lua tests\VolumeControlTest.lua
local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function NewEnvironment(saved, mode, addonIcon)
    local state = {
        frames = {}, timers = {}, messages = {}, now = 0, cvars = {},
        sliderMouseDowns = 0, sliderMouseUps = 0,
    }
    for _, channel in ipairs({ "Master", "SFX", "Music", "Ambience", "Dialog" }) do
        state.cvars["Sound_" .. channel .. "Volume"] = "0.5"
    end
    for _, channel in ipairs({ "AllSound", "SFX", "Music", "Ambience", "Dialog" }) do
        state.cvars["Sound_Enable" .. channel] = "1"
    end
    local env = setmetatable({
        WOW_PROJECT_ID = mode == "forever" and 18 or 1,
        WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CAMELOT = 18,
        WildDB = saved,
        SlashCmdList = {},
        tremove = table.remove,
        strtrim = function(text) return text:match("^%s*(.-)%s*$") end,
        wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end end,
        print = function(message) state.messages[#state.messages + 1] = message end,
        GetCVar = function(key) return state.cvars[key] end,
        SetCVar = function(key, value) state.cvars[key] = tostring(value) end,
        C_AddOns = { GetAddOnMetadata = function(addon, key)
            Equal(addon, "Wild")
            Equal(key, "IconTexture")
            return addonIcon or "Interface\\AddOns\\Wild\\Media\\Wild.tga"
        end },
    }, { __index = _G })
    local methods = {}
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:SetScript(event, callback) self.scripts[event] = callback end
    function methods:RunScript(event, ...)
        if self.scripts[event] then self.scripts[event](self, ...) end
    end
    function methods:HookScript(event, callback)
        local previous = self.scripts[event]
        self.scripts[event] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end
    function methods:Show()
        local changed = not self.shown
        self.shown = true
        if changed then self:RunScript("OnShow") end
    end
    function methods:Hide()
        local changed = self.shown
        self.shown = false
        if changed then self:RunScript("OnHide") end
    end
    function methods:IsShown() return self.shown end
    function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function methods:Click() self:RunScript("OnClick") end
    function methods:SetText(text) self.text = text end
    function methods:SetTexture(texture) self.texture = texture end
    function methods:SetTexCoord(...) self.coordinates = { ... } end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:GetPoint() return unpack(self.point) end
    function methods:ClearAllPoints() self.point = nil end
    function methods:SetValue(value)
        if self.value ~= value then
            self.value = value
            self:RunScript("OnValueChanged", value, false)
        end
    end
    for _, name in ipairs({
        "SetSize", "SetWidth", "SetHeight", "SetFrameStrata", "SetClampedToScreen",
        "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetAllPoints",
        "SetAlpha", "SetJustifyH", "SetMovable",
        "RegisterForDrag", "RegisterForClicks", "SetMinMaxValues", "SetValueStep",
        "SetObeyStepOnDrag", "EnableMouse", "StartMoving", "StopMovingOrSizing",
    }) do
        methods[name] = function() end
    end
    local function Region(kind)
        return setmetatable({ kind = kind, scripts = {}, events = {}, shown = true }, { __index = methods })
    end
    function methods:CreateTexture(_, layer)
        local texture = Region("Texture")
        texture.layer = layer
        texture.coordinates = { 0, 1, 0, 1 }
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function methods:CreateFontString() return Region("FontString") end
    env.CreateFrame = function(kind, name, parent, template)
        local frame = Region(kind)
        frame.name, frame.parent, frame.template = name, parent, template
        if kind == "Slider" then
            frame.Low, frame.High = Region("FontString"), Region("FontString")
            frame.scripts.OnMouseDown = function() state.sliderMouseDowns = state.sliderMouseDowns + 1 end
            frame.scripts.OnMouseUp = function() state.sliderMouseUps = state.sliderMouseUps + 1 end
        end
        state.frames[#state.frames + 1] = frame
        return frame
    end
    env.UIParent = env.CreateFrame("Frame")
    env.C_Timer = { NewTimer = function(delay, callback)
        assert(delay > 0 and delay < math.huge, "A hide timer needs a finite positive delay")
        local timer = { at = state.now + delay, callback = callback }
        function timer:Cancel() self.cancelled = true end
        state.timers[#state.timers + 1] = timer
        return timer
    end }
    local Wild = {}
    local function Load(path) setfenv(assert(loadfile(path)), env)("Wild", Wild) end
    local function Fire(event, ...)
        local frames = { unpack(state.frames) }
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame:RunScript("OnEvent", event, ...) end
        end
    end
    Load("Core.lua")
    Fire("ADDON_LOADED", "Wild")
    Load("VolumeControl.lua")
    Load("SlashCommands.lua")
    local function Advance(seconds)
        local finish = state.now + seconds
        while true do
            local nextTimer
            for _, timer in ipairs(state.timers) do
                if not timer.cancelled and not timer.fired and timer.at <= finish and
                   (not nextTimer or timer.at < nextTimer.at) then
                    nextTimer = timer
                end
            end
            if not nextTimer then break end
            state.now, nextTimer.fired = nextTimer.at, true
            nextTimer.callback()
        end
        state.now = finish
    end
    local function Button()
        for _, frame in ipairs(state.frames) do
            if frame.kind == "Button" and frame.parent == env.UIParent then return frame end
        end
    end
    local function Panel()
        for _, frame in ipairs(state.frames) do
            if frame.rows then return frame end
        end
    end
    local function Open()
        Wild.SetFeatureEnabled("volume", true)
        Button():Click()
        local panel = assert(Panel(), "Opening the volume button creates its panel")
        Equal(panel:IsShown(), true)
        return panel
    end
    return Wild, state, Advance, Open, Button, Fire
end

local tests = {
    { "the volume button and hover highlight show Wild's full declared icon in both clients", function()
        for _, mode in ipairs({ "retail", "forever" }) do
            for _, icon in ipairs({
                "Interface\\AddOns\\Wild\\Media\\Wild.tga",
                "Interface\\Icons\\ability_druid_rejuvenation",
            }) do
                local Wild, _, _, _, Button = NewEnvironment(nil, mode, icon)
                Wild.SetFeatureEnabled("volume", true)
                local textures = Button().textures
                Equal(#textures, 2)
                Equal(textures[1].layer, "ARTWORK")
                Equal(textures[1].texture, icon)
                Equal(textures[2].layer, "HIGHLIGHT")
                Equal(textures[2].texture, icon)
                for _, texture in ipairs(textures) do
                    for index, value in ipairs({ 0, 1, 0, 1 }) do
                        Equal(texture.coordinates[index], value, "Show the complete logo without cropping")
                    end
                end
            end
        end
    end },
    { "volume stays opt-in and old saved settings receive the default timeout", function()
        for _, mode in ipairs({ "retail", "forever" }) do
            local Wild, state, _, _, Button, Fire = NewEnvironment(nil, mode)
            Equal(Wild.GetSetting("volumeControl.enabled"), false)
            Equal(Wild.GetSetting("volumeControl.autoHideDelay"), 5)
            Equal(Wild.GetDefaultSetting("volumeControl.autoHideDelay"), 5)
            Fire("PLAYER_ENTERING_WORLD")
            Equal(Button(), nil)
            Equal(#state.timers, 0)
            local Existing = NewEnvironment({ volumeControl = { enabled = true } }, mode)
            Equal(Existing.GetSetting("volumeControl.enabled"), true)
            Equal(Existing.GetSetting("volumeControl.autoHideDelay"), 5)
        end
    end },
    { "opening alone starts the timeout in Retail and Forever", function()
        for _, mode in ipairs({ "retail", "forever" }) do
            local _, _, Advance, Open, Button = NewEnvironment(nil, mode)
            local panel = Open()
            Advance(4.5)
            Equal(panel:IsShown(), true)
            Advance(0.5)
            Equal(panel:IsShown(), false)
            Equal(Button():IsShown(), true, "Only the panel hides, not its launcher")
        end
    end },
    { "reopening starts a new timeout even when no slider value changes", function()
        local _, _, Advance, Open, Button = NewEnvironment()
        local panel = Open()
        Advance(5)
        Button():Click()
        Advance(4.5)
        Equal(panel:IsShown(), true)
        Advance(0.5)
        Equal(panel:IsShown(), false)
    end },
    { "every channel slider and checkbox restarts the full timeout", function()
        for row = 1, 5 do
            local _, state, Advance, Open = NewEnvironment()
            local panel = Open()
            Advance(4)
            panel.rows[row].slider:SetValue(0.75)
            Equal(state.cvars[panel.rows[row].cvar], "0.75")
            Advance(4)
            Equal(panel:IsShown(), true)
            panel.rows[row].cb:Click()
            Equal(state.cvars[panel.rows[row].enable], "0")
            Advance(4.5)
            Equal(panel:IsShown(), true)
            Advance(0.5)
            Equal(panel:IsShown(), false)
        end
    end },
    { "the panel does not hide during a held slider drag and preserves template scripts", function()
        local _, state, Advance, Open = NewEnvironment()
        local panel = Open()
        local slider = panel.rows[1].slider
        Advance(4)
        slider:RunScript("OnMouseDown", "LeftButton")
        slider:SetValue(0.75)
        Advance(20)
        Equal(panel:IsShown(), true)
        slider:RunScript("OnMouseUp", "LeftButton")
        Equal(state.sliderMouseDowns, 1)
        Equal(state.sliderMouseUps, 1)
        Advance(4.5)
        Equal(panel:IsShown(), true)
        Advance(0.5)
        Equal(panel:IsShown(), false)
    end },
    { "clicks on the panel background and unchanged slider also restart the timeout", function()
        for _, target in ipairs({ "panel", "slider" }) do
            local _, _, Advance, Open = NewEnvironment()
            local panel = Open()
            local control = target == "panel" and panel or panel.rows[1].slider
            Advance(4)
            control:RunScript("OnMouseDown", "LeftButton")
            control:RunScript("OnMouseUp", "LeftButton")
            Advance(4.5)
            Equal(panel:IsShown(), true)
            Advance(0.5)
            Equal(panel:IsShown(), false)
        end
    end },
    { "manual close cancels the previous timeout before reopening", function()
        local _, state, Advance, Open, Button = NewEnvironment()
        local panel = Open()
        local timer = assert(state.timers[#state.timers])
        Advance(4)
        Button():Click()
        Equal(timer.cancelled, true)
        Button():Click()
        Advance(4.5)
        Equal(panel:IsShown(), true)
        Advance(0.5)
        Equal(panel:IsShown(), false)
    end },
    { "a changed timeout takes effect on an open panel without another click", function()
        local Wild, _, Advance, Open = NewEnvironment()
        local panel = Open()
        Advance(4)
        Equal(Wild.SetSetting("volumeControl.autoHideDelay", 2.5), true)
        Advance(2)
        Equal(panel:IsShown(), true)
        Advance(0.5)
        Equal(panel:IsShown(), false)
    end },
    { "zero keeps the panel open and a positive timeout starts it again", function()
        local Wild, _, Advance, Open = NewEnvironment()
        local panel = Open()
        Equal(Wild.SetSetting("volumeControl.autoHideDelay", 0), true)
        Advance(100)
        Equal(panel:IsShown(), true)
        Equal(Wild.SetSetting("volumeControl.autoHideDelay", 1.5), true)
        Advance(1.5)
        Equal(panel:IsShown(), false)
    end },
    { "saved zero and fractional delays survive loading", function()
        for _, delay in ipairs({ 0, 2.5, 90.25 }) do
            local Wild, state, Advance, Open = NewEnvironment({ volumeControl = { autoHideDelay = delay } })
            Equal(Wild.GetSetting("volumeControl.autoHideDelay"), delay)
            local panel = Open()
            if delay == 0 then
                Equal(#state.timers, 0)
                Advance(100)
                Equal(panel:IsShown(), true)
            else
                Advance(delay)
                Equal(panel:IsShown(), false)
            end
        end
    end },
    { "invalid API timeouts warn without changing the saved value or current timer", function()
        local Wild, state, Advance, Open = NewEnvironment()
        local panel = Open()
        Advance(4)
        for _, invalid in ipairs({ -1, math.huge, -math.huge, 0 / 0, "3", true, {} }) do
            local messages, timers = #state.messages, #state.timers
            Equal(Wild.SetSetting("volumeControl.autoHideDelay", invalid), false)
            Equal(Wild.GetSetting("volumeControl.autoHideDelay"), 5)
            Equal(#state.messages, messages + 1)
            Equal(#state.timers, timers)
        end
        Equal(Wild.SetSetting("volumeControl.autoHideDelay", nil), false)
        Advance(1)
        Equal(panel:IsShown(), false)
    end },
    { "hidden panels do not create timers and feature disable cancels pending work", function()
        local Wild, state, Advance, Open, Button = NewEnvironment()
        Wild.SetSetting("volumeControl.autoHideDelay", 2)
        Equal(#state.timers, 0)
        local panel = Open()
        local timer = state.timers[#state.timers]
        Wild.SetFeatureEnabled("volume", false)
        Equal(panel:IsShown(), false)
        Equal(Button():IsShown(), false)
        Equal(timer.cancelled, true)
        local timers = #state.timers
        Wild.SetSetting("volumeControl.autoHideDelay", 3)
        Advance(10)
        Equal(#state.timers, timers)
        Equal(panel:IsShown(), false)
    end },
    { "the generic feature setter and reset hide the panel and clear its timeout", function()
        local Wild, state, _, Open, Button = NewEnvironment()
        local panel = Open()
        local timer = state.timers[#state.timers]
        Wild.SetSetting("volumeControl.enabled", false)
        Equal(panel:IsShown(), false)
        Equal(Button():IsShown(), false)
        Equal(timer.cancelled, true)
        panel = Open()
        Wild.SetSetting("volumeControl.autoHideDelay", 9)
        timer = state.timers[#state.timers]
        Wild.ResetSettings()
        Equal(Wild.GetSetting("volumeControl.autoHideDelay"), 5)
        Equal(Wild.IsFeatureEnabled("volume"), false)
        Equal(panel:IsShown(), false)
        Equal(Button():IsShown(), false)
        Equal(timer.cancelled, true)
    end },
    { "slash commands set and query the timeout and preserve existing aliases", function()
        local Wild, state = NewEnvironment()
        Wild.HandleSlashCommand("volume timeout 2.5")
        Equal(Wild.GetSetting("volumeControl.autoHideDelay"), 2.5)
        Wild.HandleSlashCommand("vol timeout")
        assert(state.messages[#state.messages]:find("2.5", 1, true))
        Wild.HandleSlashCommand("vol timeout 0")
        Equal(Wild.GetSetting("volumeControl.autoHideDelay"), 0)
        Wild.HandleSlashCommand("volume on")
        Equal(Wild.IsFeatureEnabled("volume"), true)
        Wild.HandleSlashCommand("vol off")
        Equal(Wild.IsFeatureEnabled("volume"), false)
        for _, command in ipairs({ "volume timeout -1", "volume timeout invalid",
            "volume timeout 1e999", "volume timeout 2 extra", "volume invalid" }) do
            local messages = #state.messages
            Wild.HandleSlashCommand(command)
            Equal(Wild.GetSetting("volumeControl.autoHideDelay"), 0)
            Equal(#state.messages, messages + 1)
            assert(state.messages[#state.messages]:find("|cffff6600", 1, true))
        end
    end },
}

local failures = 0
for _, test in ipairs(tests) do
    local ok, message = pcall(test[2])
    if not ok then
        failures = failures + 1
        print("FAIL: " .. test[1] .. ": " .. tostring(message))
    end
end
assert(failures == 0, failures .. " of " .. #tests .. " volume control tests failed")
print(#tests .. " volume control tests passed")
