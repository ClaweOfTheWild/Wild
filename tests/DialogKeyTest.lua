-- Run from the repository root with Lua 5.1: lua tests\DialogKeyTest.lua
local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function NewEnvironment(saved)
    local Wild = {}
    local frames, popups, hooks, messages = {}, {}, {}, {}
    local state = {
        combat = false, focus = nil, modifiers = {}, bindings = {},
        timers = {}, clicks = 0, deletes = 0,
    }
    local methods = {}
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:SetScript(event, callback) self.scripts[event] = callback end
    function methods:HookScript(event, callback)
        self.hooks[event] = self.hooks[event] or {}
        table.insert(self.hooks[event], callback)
    end
    function methods:RunScript(event, ...)
        if self.scripts[event] then self.scripts[event](self, ...) end
        for _, callback in ipairs(self.hooks[event] or {}) do callback(self, ...) end
    end
    function methods:Show() self.shown = true; self:RunScript("OnShow") end
    function methods:Hide() self.shown = false; self:RunScript("OnHide") end
    function methods:IsVisible()
        assert(not self.forbidden, "Cannot inspect a forbidden frame")
        return self.shown
    end
    function methods:IsShown() return self.shown end
    function methods:IsForbidden() return self.forbidden or false end
    function methods:IsEnabled() return self.enabled ~= false end
    function methods:GetName() return self.name end
    function methods:SetFrameStrata(value) self.strata = value end
    function methods:SetFrameLevel(value) self.level = value end
    function methods:SetSize(width, height) self.width, self.height = width, height end
    function methods:SetWidth(value) self.width = value end
    function methods:SetHeight(value) self.height = value end
    function methods:SetScrollChild(child) self.scrollChild = child end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:SetJustifyH(value) self.justifyH = value end
    function methods:SetChecked(value) self.checked = value end
    function methods:GetChecked() return self.checked end
    function methods:CreateFontString()
        return setmetatable({}, { __index = methods })
    end
    function methods:EnableKeyboard(value)
        self.keyboard = value
        if value then state.receiver = state.receiver or self end
    end
    function methods:SetPropagateKeyboardInput(value)
        assert(not state.combat, "Keyboard propagation cannot change in combat")
        self.propagate = value
    end
    function methods:GetTop() return self.top end
    function methods:ClearFocus() if state.focus == self then state.focus = nil end end
    function methods:SetText(value)
        self.text = value
        if self.parent and self.parent.requiresDelete then
            self.parent.button.enabled = value == "SUPPRIMER"
        end
    end
    function methods:GetText() return self.text end
    function methods:GetButton1() return self.button end
    function methods:GetEditBox() return self.editBox end
    function methods:Click()
        assert(state.hardware, "Popup click must originate from a hardware event in this test")
        if not self:IsEnabled() then return end
        state.clicks = state.clicks + 1
        if self.parent.requiresDelete then state.deletes = state.deletes + 1 end
        if self.onClick then self.onClick() else self.parent:Hide() end
        self:RunScript("OnClick")
    end
    local env = setmetatable({
        WildDB = saved, UIParent = {}, SlashCmdList = {},
        tremove = table.remove,
        SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 },
        PlaySound = function(sound) state.sound = sound end,
        StaticPopupDialogs = {},
        DELETE_ITEM_CONFIRM_STRING = "SUPPRIMER",
        strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end,
        wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end end,
        print = function(message) messages[#messages + 1] = message end,
        InCombatLockdown = function() return state.combat end,
        GetCurrentKeyBoardFocus = function() return state.focus end,
        IsControlKeyDown = function() return state.modifiers.CTRL end,
        IsAltKeyDown = function() return state.modifiers.ALT end,
        IsShiftKeyDown = function() return state.modifiers.SHIFT end,
        CursorHasItem = function() return state.cursor ~= false end,
    }, { __index = _G })
    env._G = env
    env.CreateFrame = function(kind, name, parent, template)
        assert(not template or not template:find("Secure") and not template:find("ActionButton"),
            "Dialog Key must not create action or secure frames")
        local frame = setmetatable({
            kind = kind, name = name, parent = parent, template = template,
            events = {}, scripts = {}, hooks = {}, shown = true,
        }, { __index = methods })
        frames[#frames + 1] = frame
        if name then env[name] = frame end
        if kind == "CheckButton" then frame.Text = frame:CreateFontString() end
        return frame
    end
    env.hooksecurefunc = function(name, callback)
        hooks[name] = hooks[name] or {}
        table.insert(hooks[name], callback)
    end
    env.StaticPopup_ForEachShownDialog = function(callback)
        for _, popup in ipairs(popups) do
            if popup.shown then callback(popup) end
        end
    end
    env.ClearOverrideBindings = function(owner)
        assert(not state.combat, "Override bindings cannot change in combat")
        state.bindings[owner] = nil
    end
    env.SetOverrideBindingClick = function(owner, priority, key, name, button)
        assert(not state.combat, "Override bindings cannot change in combat")
        Equal(priority, true)
        Equal(button, "LeftButton")
        assert(env[name], "Must bind to the real named Blizzard button")
        state.bindings[owner] = { key = key, name = name }
    end
    env.C_Timer = { NewTimer = function(_, callback)
        local timer = { callback = callback }
        function timer:Cancel() self.cancelled = true end
        table.insert(state.timers, timer)
        return timer
    end }
    local function Fire(event, ...)
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame:RunScript("OnEvent", event, ...) end
        end
    end
    local function Load(path)
        setfenv(assert(loadfile(path)), env)("Wild", Wild)
    end
    Load("Core.lua")
    Load("DialogKey.lua")
    Load("SlashCommands.lua")
    Fire("ADDON_LOADED", "Wild")

    local function Popup(which, options)
        options = options or {}
        local popup = env.CreateFrame("Frame")
        popup.which, popup.top = which, options.top or 500
        popup.requiresDelete = options.requiresDelete
        popup.special, popup.forbidden = options.special, options.forbidden
        popup.button = env.CreateFrame("Button", "TestPopupButton" .. (#popups + 1), popup)
        popup.button.enabled = options.enabled ~= false and not options.requiresDelete
        if options.unnamed then
            env[popup.button.name] = nil
            popup.button.name = nil
        end
        if options.editBox or options.requiresDelete then
            popup.editBox = env.CreateFrame("EditBox", nil, popup)
            popup.editBox.text = ""
        end
        env.StaticPopupDialogs[which] = {
            hasEditBox = options.editBox or options.requiresDelete,
            ignoreKeys = options.ignoreKeys,
            editBoxSecureText = options.secureText,
        }
        popup.dialogInfo = env.StaticPopupDialogs[which]
        popups[#popups + 1] = popup
        if popup.editBox then state.focus = popup.editBox end
        for _, callback in ipairs(hooks.StaticPopup_Show or {}) do callback(which) end
        return popup
    end
    local function Key(key)
        state.hardware = true
        for _, frame in ipairs(frames) do
            if frame.shown and frame.keyboard and frame.scripts.OnKeyDown then
                frame:RunScript("OnKeyDown", key)
            end
        end
        local fullKey = (state.modifiers.CTRL and "CTRL-" or "") ..
            (state.modifiers.ALT and "ALT-" or "") ..
            (state.modifiers.SHIFT and "SHIFT-" or "") .. key
        if not state.focus then
            for _, binding in pairs(state.bindings) do
                if binding.key == fullKey then env[binding.name]:Click() end
            end
        end
        state.hardware = false
    end
    local function Panel()
        Load("Settings.lua")
        local loader = frames[#frames]
        local factory
        for index = 1, 100 do
            local name, value = debug.getupvalue(loader.scripts.OnEvent, index)
            if not name then break end
            if name == "CreateDialogKeyTab" then factory = value end
        end
        assert(factory, "Settings loader must register the Dialog Key tab")
        local firstIndex = #frames + 1
        local panel = factory()
        local controls = {}
        for index = firstIndex, #frames do
            local frame = frames[index]
            if frame.kind == "CheckButton" then
                controls[frame.Text:GetText():find("destruction") and "destroy" or "enabled"] = frame
            elseif frame.kind == "Button" then controls.key = frame
            elseif frame.keyboard then controls.capture = frame end
        end
        return panel, controls
    end
    return Wild, state, Popup, Key, Fire, env, messages, Panel
end

local tests = {
    { "defaults are off and opening popups never accepts them", function()
        local Wild, state, Popup, Key = NewEnvironment()
        Equal(Wild.db.dialogKey.enabled, false)
        Equal(Wild.db.dialogKey.destroy, false)
        Equal(Wild.db.dialogKey.key, "SPACE")
        Popup("TEST_CONFIRM")
        Key("SPACE")
        Equal(state.clicks, 0)
        Equal(next(state.bindings), nil)
    end },
    { "a configured key clicks the native primary button once", function()
        local Wild, state, Popup, Key = NewEnvironment()
        Wild.SetFeatureEnabled("dialog", true)
        local popup = Popup("TEST_CONFIRM")
        Equal(state.clicks, 0)
        Key("SPACE")
        Equal(state.clicks, 1)
        Equal(popup.shown, false)
        Equal(next(state.bindings), nil)
        Key("SPACE")
        Equal(state.clicks, 1)
    end },
    { "wrong keys and unconfigured modifiers retain their normal binding", function()
        local Wild, state, Popup, Key = NewEnvironment()
        Wild.SetFeatureEnabled("dialog", true)
        Popup("TEST_CONFIRM")
        Key("ENTER")
        state.modifiers.SHIFT = true
        Key("SPACE")
        Equal(state.clicks, 0)
        Equal(next(state.bindings), nil)
        state.modifiers.SHIFT = nil
        Key("SPACE")
        Equal(state.clicks, 1)
    end },
    { "key configuration is persisted and supports modifier chords", function()
        local Wild, state, Popup, Key = NewEnvironment()
        assert(Wild.SetDialogKey(" shift-ctrl-f2 "))
        Equal(Wild.db.dialogKey.key, "CTRL-SHIFT-F2")
        Wild.SetFeatureEnabled("dialog", true)
        Popup("TEST_CONFIRM")
        Key("SPACE")
        state.modifiers.CTRL, state.modifiers.SHIFT = true, true
        Key("F2")
        Equal(state.clicks, 1)
        local reloaded = NewEnvironment(Wild.db)
        Equal(reloaded.db.dialogKey.key, "CTRL-SHIFT-F2")
    end },
    { "invalid key inputs report an error without changing the saved key", function()
        local Wild, _, _, _, _, _, messages = NewEnvironment()
        for _, key in ipairs({ "ESCAPE", "LSHIFT", "NOT_A_KEY", "CTRL-CTRL-A", "F25", "" }) do
            Equal(Wild.SetDialogKey(key), false)
            Equal(Wild.db.dialogKey.key, "SPACE")
        end
        Equal(Wild.SetDialogKey(nil), false)
        Equal(#messages, 7)
    end },
    { "chat focus and ordinary edit boxes are never intercepted", function()
        local Wild, state, Popup, Key, _, env = NewEnvironment()
        Wild.SetFeatureEnabled("dialog", true)
        Popup("TEST_CONFIRM")
        state.focus = env.CreateFrame("EditBox")
        Key("SPACE")
        Equal(state.clicks, 0)
        state.focus = nil
        Popup("RENAME_PET", { editBox = true, top = 600 })
        Key("SPACE")
        state.focus = nil
        Key("SPACE")
        Equal(state.clicks, 0)
    end },
    { "disabled or excluded front popups do not fall through to another popup", function()
        for _, options in ipairs({
            { enabled = false }, { ignoreKeys = true }, { special = true },
            { forbidden = true }, { secureText = true }, { unnamed = true },
        }) do
            local Wild, state, Popup, Key = NewEnvironment()
            Wild.SetFeatureEnabled("dialog", true)
            Popup("LOWER_CONFIRM", { top = 400 })
            options.top = 600
            Popup("UPPER_CONFIRM", options)
            Key("SPACE")
            Equal(state.clicks, 0)
        end
    end },
    { "topmost visible popup wins independent of enumeration order", function()
        local Wild, state, Popup, Key = NewEnvironment()
        Wild.SetFeatureEnabled("dialog", true)
        local lower = Popup("LOWER_CONFIRM", { top = 400 })
        local upper = Popup("UPPER_CONFIRM", { top = 600 })
        Key("SPACE")
        Equal(upper.shown, false)
        Equal(lower.shown, true)
        Equal(state.clicks, 1)
    end },
    { "item destruction remains opt-in for every delete popup", function()
        for _, which in ipairs({
            "DELETE_ITEM", "DELETE_QUEST_ITEM", "DELETE_GOOD_ITEM", "DELETE_GOOD_QUEST_ITEM",
        }) do
            local Wild, state, Popup, Key = NewEnvironment()
            Wild.SetFeatureEnabled("dialog", true)
            local popup = Popup(which, { requiresDelete = which:find("GOOD") ~= nil })
            Key("SPACE")
            Equal(state.clicks, 0)
            if popup.editBox then Equal(popup.editBox.text, "") end
        end
    end },
    { "delete text is localized and is supplied only after an explicit key press", function()
        for _, which in ipairs({ "DELETE_GOOD_ITEM", "DELETE_GOOD_QUEST_ITEM" }) do
            local Wild, state, Popup, Key = NewEnvironment()
            Wild.SetFeatureEnabled("dialog", true)
            Wild.SetSetting("dialogKey.destroy", true)
            local popup = Popup(which, { requiresDelete = true })
            Equal(popup.editBox.text, "")
            Equal(state.deletes, 0)
            Key("SPACE")
            Equal(popup.editBox.text, "SUPPRIMER")
            Equal(state.deletes, 1)
            Equal(popup.shown, false)
        end
    end },
    { "delete confirmation never bypasses other typed confirmations or missing cursor items", function()
        local Wild, state, Popup, Key = NewEnvironment()
        Wild.SetFeatureEnabled("dialog", true)
        Wild.SetSetting("dialogKey.destroy", true)
        local popup = Popup("CONFIRM_DESTROY_COMMUNITY", { requiresDelete = true })
        Key("SPACE")
        Equal(popup.editBox.text, "")
        popup:Hide()
        state.focus = nil
        state.cursor = false
        popup = Popup("DELETE_GOOD_ITEM", { requiresDelete = true })
        Key("SPACE")
        Equal(popup.editBox.text, "")
        Equal(state.clicks, 0)
    end },
    { "public API confirms only in a hardware context and while enabled", function()
        local Wild, state, Popup = NewEnvironment()
        Popup("TEST_CONFIRM")
        Equal(Wild.ConfirmDialog(), false)
        Wild.SetFeatureEnabled("dialog", true)
        state.hardware = true
        Equal(Wild.ConfirmDialog(), true)
        Equal(state.clicks, 1)
        state.hardware = false
    end },
    { "combat suspends keyboard input without protected binding changes", function()
        local Wild, state, Popup, Key, Fire = NewEnvironment()
        Wild.SetFeatureEnabled("dialog", true)
        Popup("TEST_CONFIRM")
        state.combat = true
        Fire("PLAYER_REGEN_DISABLED")
        Key("SPACE")
        Equal(state.clicks, 0)
        Equal(Wild.ConfirmDialog(), false)
        state.combat = false
        Fire("PLAYER_REGEN_ENABLED")
        Key("SPACE")
        Equal(state.clicks, 1)
    end },
    { "slash commands configure status, key, enablement and destruction", function()
        local Wild, state, Popup, Key, _, env, messages = NewEnvironment()
        env.SlashCmdList.WILD("dialog key enter")
        Equal(Wild.db.dialogKey.key, "ENTER")
        env.SlashCmdList.WILD("dialog destroy on")
        Equal(Wild.db.dialogKey.destroy, true)
        env.SlashCmdList.WILD("dialog on")
        Equal(Wild.IsFeatureEnabled("dialog"), true)
        Popup("DELETE_GOOD_ITEM", { requiresDelete = true })
        Key("ENTER")
        Equal(state.deletes, 1)
        env.SlashCmdList.WILD("dialog")
        assert(messages[#messages]:find("ENTER"), "Status must display the configured key")
        env.SlashCmdList.WILD("dialog off")
        Equal(Wild.IsFeatureEnabled("dialog"), false)
    end },
    { "reset disables the feature and restores the default key", function()
        local Wild, state, Popup, Key = NewEnvironment()
        Wild.SetFeatureEnabled("dialog", true)
        Wild.SetDialogKey("F2")
        Wild.SetSetting("dialogKey.destroy", true)
        Wild.ResetSettings()
        Equal(Wild.db.dialogKey.enabled, false)
        Equal(Wild.db.dialogKey.destroy, false)
        Equal(Wild.db.dialogKey.key, "SPACE")
        Popup("TEST_CONFIRM")
        Key("SPACE")
        Equal(state.clicks, 0)
    end },
    { "settings controls reflect saved state and capture modifier keys", function()
        local Wild, state, _, _, _, _, _, Panel = NewEnvironment()
        local panel, controls = Panel()
        panel:RunScript("OnShow")
        Equal(controls.enabled.checked, false)
        Equal(controls.destroy.checked, false)
        Equal(controls.key:GetText(), "SPACE")
        controls.enabled.checked = true
        controls.enabled:RunScript("OnClick")
        Equal(Wild.IsFeatureEnabled("dialog"), true)
        controls.destroy.checked = true
        controls.destroy:RunScript("OnClick")
        Equal(Wild.db.dialogKey.destroy, true)
        controls.key:RunScript("OnClick")
        Equal(controls.capture.shown, true)
        state.modifiers.CTRL = true
        controls.capture:RunScript("OnKeyDown", "LCTRL")
        Equal(controls.capture.shown, true)
        controls.capture:RunScript("OnKeyDown", "F2")
        Equal(Wild.db.dialogKey.key, "CTRL-F2")
        Equal(controls.key:GetText(), "CTRL-F2")
        Equal(controls.capture.shown, false)
    end },
    { "capture cancels on Escape, tab hide, or combat without changing the saved key", function()
        local Wild, state, _, _, Fire, _, _, Panel = NewEnvironment()
        local panel, controls = Panel()
        controls.key:RunScript("OnClick")
        controls.capture:RunScript("OnKeyDown", "ESCAPE")
        Equal(controls.capture.shown, false)
        Equal(Wild.db.dialogKey.key, "SPACE")
        controls.key:RunScript("OnClick")
        panel:Hide()
        Equal(controls.capture.shown, false)
        panel:Show()
        controls.key:RunScript("OnClick")
        state.combat = true
        Fire("PLAYER_REGEN_DISABLED")
        Equal(controls.capture.shown, false)
        controls.key:RunScript("OnClick")
        Equal(controls.capture.shown, false)
        Equal(Wild.db.dialogKey.key, "SPACE")
    end },
    { "native buttons that keep their popup open still clear the temporary binding", function()
        local Wild, state, Popup, Key = NewEnvironment()
        Wild.SetFeatureEnabled("dialog", true)
        local popup = Popup("XP_LOSS")
        popup.button.onClick = function() end
        Key("SPACE")
        Equal(state.clicks, 1)
        Equal(popup.shown, true)
        Equal(next(state.bindings), nil)
        Equal(state.timers[1].cancelled, true)
    end },
    { "the safety timeout clears an unconsumed key binding", function()
        local Wild, state, Popup = NewEnvironment()
        Wild.SetFeatureEnabled("dialog", true)
        Popup("TEST_CONFIRM")
        -- Exercise key-down without WoW's later binding dispatch.
        state.receiver:RunScript("OnKeyDown", "SPACE")
        assert(next(state.bindings))
        state.timers[1].callback()
        Equal(next(state.bindings), nil)
        Equal(state.clicks, 0)
    end },
    { "pending override cleanup is deferred safely until combat ends", function()
        local Wild, state, Popup, _, Fire = NewEnvironment()
        Wild.SetFeatureEnabled("dialog", true)
        local popup = Popup("TEST_CONFIRM")
        state.receiver:RunScript("OnKeyDown", "SPACE")
        assert(next(state.bindings))
        state.combat = true
        Fire("PLAYER_REGEN_DISABLED")
        popup:Hide()
        Equal(state.receiver.shown, false)
        Equal(state.clicks, 0)
        state.combat = false
        Fire("PLAYER_REGEN_ENABLED")
        Equal(next(state.bindings), nil)
    end },
    { "generic settings API updates live enablement and validates the key", function()
        local Wild, state, Popup, Key = NewEnvironment()
        Wild.SetSetting("dialogKey.enabled", true)
        Wild.SetSetting("dialogKey.key", "alt-enter")
        Equal(Wild.db.dialogKey.key, "ALT-ENTER")
        Equal(Wild.SetSetting("dialogKey.key", "ESCAPE"), false)
        Popup("TEST_CONFIRM")
        state.modifiers.ALT = true
        Key("ENTER")
        Equal(state.clicks, 1)
        Wild.SetSetting("dialogKey.enabled", false)
        Popup("TEST_CONFIRM")
        Key("ENTER")
        Equal(state.clicks, 1)
    end },
    { "legacy popup fields and enumeration work without the modern accessor API", function()
        local Wild, state, Popup, Key, _, env = NewEnvironment()
        Wild.SetFeatureEnabled("dialog", true)
        local popup = Popup("TEST_CONFIRM")
        popup.GetButton1, popup.GetEditBox = false, false
        popup.button1 = popup.button
        popup.dialogInfo = nil
        env.StaticPopup_ForEachShownDialog = false
        env.StaticPopup1 = popup
        Key("SPACE")
        Equal(state.clicks, 1)
    end },
    { "popup acceptance delays and error warnings are never bypassed", function()
        for _, which in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED", "TOO_MANY_LUA_ERRORS" }) do
            local Wild, state, Popup, Key = NewEnvironment()
            Wild.SetFeatureEnabled("dialog", true)
            Popup(which)
            Key("SPACE")
            Equal(state.clicks, 0)
        end
        for _, field in ipairs({ "startDelay", "acceptDelay" }) do
            local Wild, state, Popup, Key = NewEnvironment()
            Wild.SetFeatureEnabled("dialog", true)
            Wild.SetSetting("dialogKey.destroy", true)
            local popup = Popup("DELETE_GOOD_ITEM", { requiresDelete = true })
            popup[field] = 3
            Key("SPACE")
            Equal(state.clicks, 0)
            Equal(popup.editBox.text, "")
        end
    end },
    { "the settings window blocks popup confirmation while configuring the key", function()
        local Wild, state, Popup, Key, _, env = NewEnvironment()
        Wild.SetFeatureEnabled("dialog", true)
        Popup("TEST_CONFIRM")
        env.WildSettingsFrame = env.CreateFrame("Frame")
        Key("SPACE")
        Equal(state.clicks, 0)
        env.WildSettingsFrame:Hide()
        Key("SPACE")
        Equal(state.clicks, 1)
    end },
    { "forbidden popup children are not inspected or changed", function()
        for _, field in ipairs({ "button", "editBox" }) do
            local Wild, state, Popup, Key = NewEnvironment()
            Wild.SetFeatureEnabled("dialog", true)
            Wild.SetSetting("dialogKey.destroy", true)
            local popup = Popup("DELETE_GOOD_ITEM", { requiresDelete = true })
            popup[field].forbidden = true
            Key("SPACE")
            Equal(state.clicks, 0)
            Equal(popup.editBox.text, "")
        end
    end },
}

local failures = 0
for _, test in ipairs(tests) do
    local ok, message = pcall(test[2])
    if not ok then
        failures = failures + 1
        print("FAIL: " .. test[1] .. "\n" .. tostring(message))
    end
end
assert(failures == 0, failures .. " of " .. #tests .. " dialog key tests failed")
print(#tests .. " dialog key tests passed")
