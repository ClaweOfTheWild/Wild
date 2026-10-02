-- Run from the repository root with Lua 5.1: lua tests\SpeedIndicatorTest.lua
local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function NewEnvironment(saved)
    local frames, messages = {}, {}
    local state = { speed = 0, gliding = false, glideSpeed = 0, reads = 0 }
    local env = setmetatable({
        WildDB = saved,
        UIParent = {},
        SlashCmdList = {},
        strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end,
        tremove = table.remove,
        SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 },
        PlaySound = function(sound) state.sound = sound end,
        print = function(message) messages[#messages + 1] = message end,
        wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end end,
    }, { __index = _G })
    local methods = {}
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:SetScript(event, callback) self.scripts[event] = callback end
    function methods:SetSize(width, height) self.width, self.height = width, height end
    function methods:SetWidth(width) self.width = width end
    function methods:SetHeight(height) self.height = height end
    function methods:SetScrollChild(child) self.scrollChild = child end
    function methods:HookScript(event, callback) self.scripts[event] = callback end
    function methods:SetChecked(checked) self.checked = checked end
    function methods:GetChecked() return self.checked end
    function methods:SetFrameStrata(strata) self.strata = strata end
    function methods:SetClampedToScreen(clamped) self.clamped = clamped end
    function methods:SetMovable(movable) self.movable = movable end
    function methods:EnableMouse(enabled) self.mouse = enabled end
    function methods:RegisterForDrag(button) self.dragButton = button end
    function methods:SetBackdrop(backdrop) self.backdrop = backdrop end
    function methods:SetBackdropColor(...) self.background = { ... } end
    function methods:SetBackdropBorderColor(...) self.border = { ... } end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:GetPoint() return unpack(self.point) end
    function methods:ClearAllPoints() self.point = nil end
    function methods:StartMoving() self.moving = true end
    function methods:StopMovingOrSizing() self.moving = false end
    function methods:Show() self.shown = true end
    function methods:Hide()
        local wasShown = self.shown
        self.shown = false
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:CreateFontString()
        local text = {}
        function text:SetPoint() end
        function text:SetTextColor() end
        function text:SetJustifyH() end
        function text:SetText(value) self.value = value end
        return text
    end
    env.CreateFrame = function(kind, name, parent, template)
        local frame = setmetatable({
            kind = kind, name = name, parent = parent, template = template,
            events = {}, scripts = {}, shown = true,
        }, { __index = methods })
        frames[#frames + 1] = frame
        if kind == "CheckButton" then frame.Text = frame:CreateFontString() end
        return frame
    end
    env.GetUnitSpeed = function(unit)
        Equal(unit, "player")
        state.reads = state.reads + 1
        return state.speed, 14, 28, 4.72
    end
    env.C_PlayerInfo = {
        GetGlidingInfo = function()
            return state.gliding, true, state.glideSpeed
        end,
    }
    local secret = setmetatable({}, {
        __div = function() error("Arithmetic on a secret speed") end,
        __tostring = function() error("Formatting a secret speed") end,
    })
    state.secret = secret
    env.issecretvalue = function(value) return rawequal(value, secret) end
    local Wild = {}
    local function Load(path)
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)("Wild", Wild)
    end
    Load("Core.lua")
    for _, frame in ipairs(frames) do
        if frame.events.ADDON_LOADED then
            frame.scripts.OnEvent(frame, "ADDON_LOADED", "Wild")
        end
    end
    Load("Speed.lua")
    Load("SlashCommands.lua")

    local function Fire(event)
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event) end
        end
    end
    local function Tick(elapsed)
        for _, frame in ipairs(frames) do
            if frame.shown and frame.scripts.OnUpdate then
                frame.scripts.OnUpdate(frame, elapsed)
            end
        end
    end
    local function Overlay()
        for _, frame in ipairs(frames) do
            if frame.text then return frame end
        end
    end
    local function SpeedPanel()
        Load("Settings.lua")
        local loader = frames[#frames]
        local factory
        for index = 1, 100 do
            local name, value = debug.getupvalue(loader.scripts.OnEvent, index)
            if not name then break end
            if name == "CreateSpeedTab" then factory = value end
        end
        assert(factory, "Settings loader must register the Speed tab")
        local panel = factory()
        local checkbox = frames[#frames]
        Equal(checkbox.kind, "CheckButton")
        return panel, checkbox
    end
    return Wild, state, Fire, Tick, Overlay, messages, SpeedPanel
end

local tests = {
    { "disabled by default without creating or polling an overlay", function()
        local Wild, state, Fire, Tick, Overlay = NewEnvironment()
        Equal(Wild.db.speed.enabled, false)
        Equal(Wild.IsFeatureEnabled("speed"), false)
        Fire("PLAYER_ENTERING_WORLD")
        Tick(1)
        Equal(Overlay(), nil)
        Equal(state.reads, 0)
    end },
    { "current movement speed is a rounded percentage", function()
        local Wild, state, _, Tick, Overlay = NewEnvironment()
        Wild.SetFeatureEnabled("speed", true)
        Equal(Overlay().text.value, "Speed: 0%")
        for _, case in ipairs({
            { 7, "Speed: 100%" },
            { 14, "Speed: 200%" },
            { 4.72, "Speed: 67%" },
            { 28.7, "Speed: 410%" },
            { 7.04, "Speed: 101%" },
            { 0, "Speed: 0%" },
        }) do
            state.speed = case[1]
            Tick(0.1)
            Equal(Overlay().text.value, case[2])
        end
    end },
    { "Skyriding uses forward speed and landing returns to unit speed", function()
        local Wild, state, _, Tick, Overlay = NewEnvironment()
        Wild.SetFeatureEnabled("speed", true)
        state.gliding, state.glideSpeed = true, 65
        Tick(0.1)
        Equal(Overlay().text.value, "Speed: 929%")
        state.glideSpeed = 100
        Tick(0.1)
        Equal(Overlay().text.value, "Speed: 1429%")
        state.gliding, state.speed = false, 7
        Tick(0.1)
        Equal(Overlay().text.value, "Speed: 100%")
    end },
    { "restricted speed is explicit and recovers without arithmetic errors", function()
        local Wild, state, _, Tick, Overlay = NewEnvironment()
        Wild.SetFeatureEnabled("speed", true)
        state.speed = state.secret
        Tick(0.1)
        Equal(Overlay().text.value, "Speed: --")
        state.speed = 7
        Tick(0.1)
        Equal(Overlay().text.value, "Speed: 100%")
    end },
    { "polling is throttled and stops while disabled", function()
        local Wild, state, _, Tick, Overlay = NewEnvironment()
        Wild.SetFeatureEnabled("speed", true)
        local reads = state.reads
        Tick(0.04)
        Tick(0.04)
        Equal(state.reads, reads)
        Tick(0.03)
        Equal(state.reads, reads + 1)
        Wild.SetFeatureEnabled("speed", false)
        Equal(Overlay().shown, false)
        reads = state.reads
        Tick(10)
        Equal(state.reads, reads)
        state.speed = 14
        Wild.SetFeatureEnabled("speed", true)
        Equal(Overlay().shown, true)
        Equal(Overlay().text.value, "Speed: 200%")
    end },
    { "dragged position persists across updates and reloads", function()
        local Wild, state, _, Tick, Overlay = NewEnvironment()
        Wild.SetFeatureEnabled("speed", true)
        local frame = Overlay()
        Equal(frame.point[1], "TOP")
        Equal(frame.point[5], -68)
        Equal(frame.clamped, true)
        Equal(frame.movable, true)
        frame.scripts.OnDragStart(frame)
        frame:SetPoint("CENTER", nil, "CENTER", 120, -150)
        state.speed = 7
        Tick(0.1)
        Equal(frame.point[4], 120, "Polling must not reset the drag position")
        frame.scripts.OnDragStop(frame)
        Equal(frame.moving, false)
        Equal(Wild.db.speed.position.x, 120)
        Equal(Wild.db.speed.position.y, -150)
        Wild.UpdateSpeedIndicator()
        Equal(frame.point[4], 120)
        local _, _, FireReload, _, ReloadedOverlay = NewEnvironment(Wild.db)
        FireReload("PLAYER_ENTERING_WORLD")
        Equal(ReloadedOverlay().shown, true)
        Equal(ReloadedOverlay().point[4], 120)
        Equal(ReloadedOverlay().point[5], -150)
    end },
    { "reset hides the overlay and clears the saved speed position", function()
        local Wild, _, _, _, Overlay = NewEnvironment()
        Wild.SetFeatureEnabled("speed", true)
        Wild.db.speed.position = { point = "CENTER", relPoint = "CENTER", x = 8, y = 9 }
        Wild.ResetSettings()
        Equal(Wild.db.speed.enabled, false)
        Equal(Wild.db.speed.position, nil)
        Equal(Overlay().shown, false)
        Wild.SetFeatureEnabled("speed", true)
        Equal(Overlay().point[5], -68)
    end },
    { "slash commands toggle and report speed without changing durability", function()
        local Wild, _, _, _, Overlay, messages = NewEnvironment()
        Wild.HandleSlashCommand("speed on")
        Equal(Wild.db.speed.enabled, true)
        Equal(Overlay().shown, true)
        Equal(Wild.db.durability.showEquippedTotal, false)
        Wild.HandleSlashCommand("speed")
        assert(messages[#messages]:find("Speed Indicator", 1, true))
        Wild.HandleSlashCommand("speed invalid")
        assert(messages[#messages]:find("Usage: /wild speed", 1, true))
        Equal(Wild.db.speed.enabled, true)
        Wild.HandleSlashCommand("speed off")
        Equal(Overlay().shown, false)
        Wild.HandleSlashCommand("status")
        local status = table.concat(messages, "\n")
        assert(status:find("Speed Indicator", 1, true))
        Wild.HandleSlashCommand("help")
        assert(table.concat(messages, "\n"):find("/wild speed on|off", 1, true))
    end },
    { "settings checkbox uses saved state and the shared feature toggle", function()
        local Wild, state, _, _, Overlay, _, SpeedPanel = NewEnvironment()
        local panel, checkbox = SpeedPanel()
        panel.scripts.OnShow(panel)
        Equal(checkbox:GetChecked(), false)
        checkbox:SetChecked(true)
        checkbox.scripts.OnClick(checkbox)
        Equal(Wild.db.speed.enabled, true)
        Equal(Overlay().shown, true)
        Equal(state.sound, 1)
        Wild.HandleSlashCommand("speed off")
        panel.scripts.OnShow(panel)
        Equal(checkbox:GetChecked(), false)
        checkbox.scripts.OnClick(checkbox)
        Equal(Overlay().shown, false)
        Equal(state.sound, 2)
    end },
}

local failures = 0
for _, test in ipairs(tests) do
    local passed, message = pcall(test[2])
    if passed then
        print("PASS: " .. test[1])
    else
        failures = failures + 1
        print("FAIL: " .. test[1] .. ": " .. tostring(message))
    end
end
assert(failures == 0, failures .. " of " .. #tests .. " speed indicator tests failed")
print(#tests .. " speed indicator tests passed")
