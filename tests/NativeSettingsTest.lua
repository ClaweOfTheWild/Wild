-- Run from the repository root with Lua 5.1: lua tests\NativeSettingsTest.lua
local MenuTestHelpers = dofile("tests\\MenuTestHelpers.lua")

local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result
end

local function Same(actual, expected)
    Equal(type(actual), type(expected))
    if type(actual) ~= "table" then return Equal(actual, expected) end
    for key, value in pairs(expected) do Same(actual[key], value) end
    for key in pairs(actual) do assert(expected[key] ~= nil, "Unexpected key " .. tostring(key)) end
end

local function NewEnvironment(saved, noFilterEnum)
    local state = {
        frames = {}, categories = {}, settings = {}, layouts = {}, messages = {},
        updates = {}, creates = {}, refreshes = {}, valueCallbacks = {}, opens = 0,
        speedUpdates = 0, circleUpdates = 0, castUpdates = 0, soireeUpdates = 0, combat = false,
    }
    local env = setmetatable({
        WildDB = saved,
        SlashCmdList = {},
        StaticPopupDialogs = {},
        UISpecialFrames = {},
        tinsert = table.insert,
        tremove = table.remove,
        strtrim = function(text) return text:match("^%s*(.-)%s*$") end,
        wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end end,
        print = function(message) state.messages[#state.messages + 1] = message end,
        SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 },
        PlaySound = function() end,
        InCombatLockdown = function() return state.combat end,
        C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end },
        C_Item = {
            GetItemInfo = function(id) return "Item " .. tostring(id) end,
            GetItemClassInfo = function(id) return "Class " .. id end,
            GetItemSubClassInfo = function() end,
            IsItemDataCachedByID = function() return true end,
            RequestLoadItemDataByID = function() end,
        },
        C_Timer = { After = function() end },
        Enum = { AuctionHouseFilter = {
            UncollectedOnly = 0, UsableOnly = 1, CurrentExpansionOnly = 2, UpgradesOnly = 3,
            PoorQuality = 4, CommonQuality = 5, UncommonQuality = 6, RareQuality = 7,
            EpicQuality = 8, LegendaryQuality = 9, ArtifactQuality = 10,
        } },
        NONE_KEY = "None", ALT_KEY = "Alt", CTRL_KEY = "Ctrl", SHIFT_KEY = "Shift",
        ACCEPT = "Accept", CANCEL = "Cancel", DEFAULTS = "Defaults",
        MinimalSliderWithSteppersMixin = { Label = { Right = 1 } },
        GetBindingText = function(key) return key end,
        GetTime = function() return 1 end,
        UnitName = function() return "Test" end,
        GetRealmName = function() return "Realm" end,
        GetMoneyString = function(value) return tostring(value) end,
    }, { __index = _G })
    env._G = env
    if noFilterEnum then env.Enum.AuctionHouseFilter = nil end
    local methods = {}
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:SetScript(event, callback) self.scripts[event] = callback end
    function methods:GetScript(event) return self.scripts[event] end
    function methods:HookScript(event, callback)
        local previous = self.scripts[event]
        self.scripts[event] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end
    function methods:GetChildren() return unpack(self.children) end
    function methods:GetObjectType() return self.kind end
    function methods:SetParent(parent)
        if self.parent then
            for index, child in ipairs(self.parent.children) do
                if child == self then table.remove(self.parent.children, index); break end
            end
        end
        self.parent = parent
        if parent then parent.children[#parent.children + 1] = self end
    end
    function methods:GetParent() return self.parent end
    function methods:GetName() return self.name end
    function methods:GetFrameLevel() return 100 end
    function methods:SetSize(width, height) self.width, self.height = width, height end
    function methods:SetWidth(width) self.width = width end
    function methods:SetHeight(height) self.height = height end
    function methods:GetWidth() return self.width or 520 end
    function methods:GetHeight() return self.height or 400 end
    function methods:GetTop() return 400 end
    function methods:GetBottom() return 0 end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:ClearAllPoints() self.point = nil end
    function methods:SetAllPoints(parent) self.allPoints = parent end
    function methods:SetScrollChild(child) self.scrollChild = child; child:SetParent(self) end
    function methods:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
    function methods:SetValue(value)
        if self.minimum then value = math.max(self.minimum, math.min(self.maximum, value)) end
        if value ~= self.value then
            self.value = value
            if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
        end
    end
    function methods:GetValue() return self.value end
    function methods:SetText(text)
        self.text = text
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
    end
    function methods:GetText() return self.text or "" end
    function methods:HasText() return self:GetText() ~= "" end
    function methods:SetChecked(value) self.checked = value end
    function methods:GetChecked() return self.checked end
    function methods:Show()
        local changed = not self.shown
        self.shown = true
        if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function methods:Hide()
        local changed = self.shown
        self.shown = false
        if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
        local owner = state.contextOwner
        while owner do
            if owner == self then state.contextMenu.open = false; break end
            owner = owner:GetParent()
        end
    end
    function methods:IsShown() return self.shown end
    function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function methods:Enable() self.enabled = true end
    function methods:Disable() self.enabled = false end
    function methods:SetEnabled(enabled) self.enabled = enabled end
    function methods:IsEnabled() return self.enabled ~= false end
    function methods:Click() if self.scripts.OnClick then self.scripts.OnClick(self) end end
    function methods:SetFocus() state.focus = self end
    function methods:HasFocus() return state.focus == self end
    function methods:ClearFocus()
        if state.focus == self then
            state.focus = nil
            if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
        end
    end
    function methods:SetPropagateKeyboardInput(value) self.propagate = value end
    for _, name in ipairs({
        "SetAutoFocus", "SetNumeric", "SetMaxLetters", "SetFontObject", "SetJustifyH",
        "SetJustifyV", "SetTextColor", "SetFrameStrata", "SetFrameLevel", "EnableKeyboard",
        "EnableMouse", "SetClampedToScreen", "SetMovable", "SetResizable", "SetResizeBounds",
        "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetScale",
        "SetValueStep", "SetObeyStepOnDrag", "SetTexture", "SetColorTexture", "SetTextInsets",
        "SetMultiLine", "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture",
        "SetClipsChildren", "RegisterForDrag", "HighlightText",
    }) do
        methods[name] = function() end
    end
    local function Region(kind)
        return setmetatable({ kind = kind, children = {}, scripts = {}, shown = true }, { __index = methods })
    end
    function methods:CreateFontString() return Region("FontString") end
    function methods:CreateTexture() return Region("Texture") end
    env.CreateFrame = function(kind, name, parent, template)
        if name then assert(env[name] == nil, "Duplicate frame name " .. name) end
        local frame = Region(kind)
        frame.name, frame.template, frame.events = name, template, {}
        frame:SetParent(parent)
        if name then env[name] = frame end
        if kind == "CheckButton" then frame.Text = frame:CreateFontString() end
        if kind == "Slider" then
            frame.Low, frame.High, frame.Text = frame:CreateFontString(), frame:CreateFontString(), frame:CreateFontString()
        end
        state.frames[#state.frames + 1] = frame
        return frame
    end
    env.UIParent = env.CreateFrame("Frame")
    env.GetCurrentKeyBoardFocus = function() return state.focus end
    env.IsControlKeyDown = function() return false end
    env.IsAltKeyDown = function() return false end
    env.IsShiftKeyDown = function() return false end
    MenuTestHelpers.Install(env, methods, state)
    env.hooksecurefunc = function(object, name, callback)
        if type(object) == "string" then
            callback = name
            name = object
            object = env
            if not object[name] then object[name] = function() end end
        end
        local original = object[name]
        object[name] = function(...)
            local values = { original(...) }
            callback(...)
            return unpack(values)
        end
    end

    env.EventRegistry = { callbacks = {} }
    function env.EventRegistry:RegisterCallback(event, callback, owner)
        local callbacks = self.callbacks[event] or {}
        self.callbacks[event] = callbacks
        callbacks[#callbacks + 1] = { callback = callback, owner = owner }
    end
    function env.EventRegistry:TriggerEvent(event, ...)
        for _, entry in ipairs(self.callbacks[event] or {}) do entry.callback(entry.owner, ...) end
    end
    local function Initializer(data)
        local initializer = { data = data, tags = {}, predicates = {} }
        function initializer:GetData() return self.data end
        function initializer:AddSearchTags(...) for _, tag in ipairs({ ... }) do self.tags[#self.tags + 1] = tag end end
        function initializer:AddModifyPredicate(predicate) self.predicates[#self.predicates + 1] = predicate end
        function initializer:AddShownPredicate(predicate) self.predicates[#self.predicates + 1] = predicate end
        function initializer:SetParentInitializer(parent, predicate)
            self.parent = parent
            if predicate then self:AddModifyPredicate(predicate) end
        end
        function initializer:EvaluateModifyPredicates()
            for _, predicate in ipairs(self.predicates) do
                if not predicate() then return false end
            end
            return true
        end
        return initializer
    end
    env.Settings = {
        VarType = { Boolean = "boolean", Number = "number", String = "string" },
        CommitFlag = { None = 0 },
    }
    local function Category(parent, name, frame)
        local category = { name = name, parent = parent, ID = #state.categories + 1, subcategories = {} }
        function category:GetID() return self.ID end
        function category:GetName() return self.name end
        function category:GetParentCategory() return self.parent end
        function category:GetSubcategories() return self.subcategories end
        function category:SetShouldSortAlphabetically() end
        local layout = { frame = frame, initializers = {} }
        function layout:AddInitializer(initializer)
            self.initializers[#self.initializers + 1] = initializer
            return initializer
        end
        function layout:AddAnchorPoint() end
        function layout:GetInitializers() return self.initializers end
        function layout:IsVerticalLayout() return not self.frame end
        category.layout = layout
        if parent then parent.subcategories[#parent.subcategories + 1] = category end
        state.categories[#state.categories + 1] = category
        state.layouts[name] = layout
        return category, layout
    end
    env.Settings.RegisterVerticalLayoutCategory = function(name) return Category(nil, name) end
    env.Settings.RegisterVerticalLayoutSubcategory = function(parent, name) return Category(parent, name) end
    env.Settings.RegisterCanvasLayoutSubcategory = function(parent, frame, name) return Category(parent, name, frame) end
    env.Settings.RegisterAddOnCategory = function(category)
        assert(not state.root, "Root category registered twice")
        state.root = category
    end
    env.Settings.RegisterProxySetting = function(category, variable, kind, name, default, getter, setter)
        assert(not state.settings[variable], "Duplicate setting " .. variable)
        local value = getter()
        Equal(type(value), kind, "Getter type for " .. variable)
        local defaultValue = default
        if type(default) == "function" then defaultValue = default() end
        Equal(type(defaultValue), kind, "Default type for " .. variable)
        local setting = { variable = variable, category = category, name = name, getter = getter, setter = setter, default = default }
        function setting:GetValue() return self.getter() end
        function setting:GetDefaultValue()
            if type(self.default) == "function" then return self.default() end
            return self.default
        end
        function setting:TriggerValueChanged(value)
            for _, callback in ipairs(state.valueCallbacks[self.variable] or {}) do callback(self, value) end
        end
        function setting:SetValue(value)
            if self.locked then return end
            if self:GetValue() ~= value then
                Equal(type(value), kind)
                self.locked = true
                self.setter(value)
                self.locked = false
            end
            self:TriggerValueChanged(value)
        end
        function setting:NotifyUpdate() self:TriggerValueChanged(self:GetValue()) end
        function setting:SetValueToDefault() self:SetValue(self:GetDefaultValue()) end
        function setting:GetVariable() return self.variable end
        function setting:GetName() return self.name end
        state.settings[variable] = setting
        return setting
    end
    env.Settings.NotifyUpdate = function(variable)
        state.updates[#state.updates + 1] = variable
        local setting = state.settings[variable]
        if setting then setting:NotifyUpdate() end
    end
    env.Settings.CreateSliderOptions = function(minimum, maximum, step)
        return { minValue = minimum, maxValue = maximum, step = step, SetLabelFormatter = function() end }
    end
    env.Settings.CreateControlTextContainer = function()
        local container = { data = {} }
        function container:Add(value, label, tooltip)
            self.data[#self.data + 1] = { value = value, label = label, tooltip = tooltip }
        end
        function container:GetData() return self.data end
        return container
    end
    for _, name in ipairs({ "Checkbox", "Slider", "Dropdown", "ColorSwatch" }) do
        local controlName = name
        env.Settings["Create" .. name] = function(category, setting, options, tooltip)
            local initializer = Initializer({ kind = controlName, setting = setting, options = options, tooltip = tooltip })
            category.layout:AddInitializer(initializer)
            return initializer
        end
    end
    env.CreateSettingsListSectionHeaderInitializer = function(name, tooltip)
        return Initializer({ name = name, tooltip = tooltip, kind = "Header" })
    end
    env.CreateSettingsButtonInitializer = function(name, text, callback, tooltip)
        return Initializer({ name = name, buttonText = text, buttonClick = callback, tooltip = tooltip, kind = "Button" })
    end
    env.SettingsPanel = env.CreateFrame("Frame")
    env.SettingsPanel:Hide()
    env.SettingsPanel.SearchBox = env.CreateFrame("EditBox", nil, env.SettingsPanel)
    function env.SettingsPanel:GetCurrentCategory() return state.selected end
    function env.SettingsPanel:GetCurrentLayout() return state.searchLayout or (state.selected and state.selected.layout) end
    function env.SettingsPanel:SelectCategory(category)
        if state.selected and state.selected.layout.frame then state.selected.layout.frame:Hide() end
        state.selected = category
        if category.layout.frame then category.layout.frame:Show() end
        env.EventRegistry:TriggerEvent("Settings.CategoryChanged", category)
    end
    function env.SettingsPanel:Close() self:Hide(); env.EventRegistry:TriggerEvent("SettingsPanel.OnHide") end
    env.Settings.OpenToCategory = function(id)
        state.opens = state.opens + 1
        state.pending = nil
        env.SettingsPanel:Show()
        for _, category in ipairs(state.categories) do
            if category.ID == id then env.SettingsPanel:SelectCategory(category); return end
        end
        error("Unknown category ID")
    end
    env.StaticPopup_Show = function(which, _, _, data)
        local popup = env.CreateFrame("Frame")
        popup.data, popup.which = data, which
        popup.editBox = env.CreateFrame("EditBox", nil, popup)
        function popup:GetEditBox() return self.editBox end
        state.popup = popup
        local definition = assert(env.StaticPopupDialogs[which])
        if definition.OnShow then definition.OnShow(popup, data) end
        return popup
    end
    env.CreateColor = function(r, g, b, a)
        return { GenerateHexColor = function()
            return string.format("%02x%02x%02x%02x", math.floor(a * 255 + 0.5),
                math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
        end }
    end
    env.CreateColorFromHexString = function(value)
        local r, g, b = tonumber(value:sub(3, 4), 16) / 255, tonumber(value:sub(5, 6), 16) / 255,
            tonumber(value:sub(7, 8), 16) / 255
        return { GetRGB = function() return r, g, b end }
    end
    local Wild = {}
    local function Load(path) setfenv(assert(loadfile(path)), env)("Wild", Wild) end
    local function Fire(event, ...)
        local frames = { unpack(state.frames) }
        for _, frame in ipairs(frames) do
            if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    Load("Core.lua")
    Fire("ADDON_LOADED", "Wild")
    Wild.UpdateSpeedIndicator = function() state.speedUpdates = state.speedUpdates + 1 end
    Wild.UpdateScreenCenterCircle = function() state.circleUpdates = state.circleUpdates + 1 end
    Wild.UpdateCastHistory = function() state.castUpdates = state.castUpdates + 1 end
    Wild.UpdateSoireeAdvisor = function() state.soireeUpdates = state.soireeUpdates + 1 end
    Wild.ShowSoireeAdvisor = function() state.soireeShows = (state.soireeShows or 0) + 1 end
    Wild.UpdateDialogKey = function() end
    Wild.CreateSettingsCanvas = function(name, namespace)
        state.creates[name] = (state.creates[name] or 0) + 1
        Equal(namespace, "Native")
        local panel = env.CreateFrame("Frame")
        panel.OnRefresh = function() state.refreshes[name] = (state.refreshes[name] or 0) + 1 end
        return panel
    end
    Wild.TOOLTIP_LINES = { { key = "itemID", label = "Item ID" }, { key = "itemType", label = "Item Type" } }
    Wild.TOOLTIP_VISIBILITY_MODES = {
        { key = "always", label = "Always" }, { key = "settings", label = "Wild Settings Open" },
        { key = "shift", label = "Shift Held" }, { key = "ctrl", label = "Ctrl Held" },
        { key = "alt", label = "Alt Held" }, { key = "never", label = "Never" },
    }
    Load("Containers.lua")
    Load("SlashCommands.lua")
    Load("NativeSettings.lua")
    Fire("ADDON_LOADED", "Wild")
    local function Setting(key)
        return assert(state.settings["WILD_" .. key:gsub("[^%w]", "_")], "Missing setting " .. key)
    end
    function state.ShowSlider(key)
        local setting = Setting(key)
        local initializer
        for _, entry in ipairs(setting.category.layout.initializers) do
            if entry.data.kind == "Slider" and entry.data.setting == setting then initializer = entry; break end
        end
        assert(initializer, "Missing native slider " .. key)
        local options = initializer.data.options
        local slider = env.CreateFrame("Slider")
        slider:SetMinMaxValues(options.minValue, options.maxValue)
        slider:SetValue(setting:GetValue())
        local control = { slider = slider, label = setting:GetValue() }
        slider:SetScript("OnValueChanged", function(_, value)
            control.label = value
            setting:SetValue(value)
        end)
        local callbacks = state.valueCallbacks[setting:GetVariable()] or {}
        state.valueCallbacks[setting:GetVariable()] = callbacks
        callbacks[#callbacks + 1] = function(_, value)
            slider:SetValue(value)
            if initializer.reinitializeOnValueChanged then control.label = setting:GetValue() end
        end
        return control
    end
    return Wild, state, env, Setting, Fire, Load
end

local function FindChild(state, panel, predicate)
    for _, frame in ipairs(state.frames) do
        local parent = frame:GetParent()
        while parent do
            if parent == panel then
                if predicate(frame) then return frame end
                break
            end
            parent = parent:GetParent()
        end
    end
end

local function FindMenuEntry(menu, value)
    for _, entry in ipairs(menu.children) do
        if entry.data == value then return entry end
        local child = FindMenuEntry(entry, value)
        if child then return child end
    end
end

local tests = {
    { "registers both native list and lazy canvas pages once without changing saved values", function()
        local Wild, state, _, _, Fire = NewEnvironment({ speed = { enabled = false } })
        Equal(state.root.name, "Wild")
        Equal(#state.categories, 27)
        for _, page in ipairs({
            "LFG", "Center Circle", "Speed", "Cast History", "Advanced", "Loot", "Dialog Key",
            "Events", "Darkmoon Faire", "Saltheril's Soiree", "Containers",
        }) do
            Equal(state.layouts[page].frame, nil, page .. " uses standard controls")
        end
        for _, page in ipairs({ "Intent Rules", "Actors", "Character", "Dungeon Bar", "Auto-Reply", "Container List" }) do
            assert(state.layouts[page].frame, page .. " is an independent canvas")
            Equal(state.creates[page], nil)
        end
        local saved = Copy(Wild.db)
        Fire("ADDON_LOADED", "Wild")
        Same(Wild.db, saved)
        Equal(#state.categories, 27)
        Equal(state.speedUpdates, 0)
        Equal(state.circleUpdates, 0)
    end },
    { "registration waits for saved variables even if the addon event arrives before Core initialization", function()
        local Wild, state, _, _, _, Load = NewEnvironment()
        local saved = Wild.db
        Wild.db = nil
        local originalCount = #state.categories
        Load("NativeSettings.lua")
        local loader = state.frames[#state.frames]
        loader.scripts.OnEvent(loader, "ADDON_LOADED", "Wild")
        Equal(#state.categories, originalCount)
        Equal(loader.events.PLAYER_LOGIN, true)
        Wild.db = saved
        state.root = nil
        state.settings = {}
        loader.scripts.OnEvent(loader, "PLAYER_LOGIN")
        Equal(#state.categories, originalCount + 27)
        Equal(loader.events.PLAYER_LOGIN, nil)
    end },
    { "native feature controls and slash commands share saved settings and update functions", function()
        local Wild, state, _, Setting = NewEnvironment()
        Setting("speed.enabled"):SetValue(true)
        Equal(Wild.IsFeatureEnabled("speed"), true)
        Equal(state.speedUpdates, 1)
        Wild.HandleSlashCommand("speed off")
        Equal(Setting("speed.enabled"):GetValue(), false)
        Equal(state.speedUpdates, 2)
        Equal(state.updates[#state.updates], "WILD_speed_enabled")
    end },
    { "container controls share persistent defaults and independent per-ID choices", function()
        local Wild, state, _, Setting, _, Load = NewEnvironment({
            containers = { items = { [100] = false, [200] = true } },
        })
        Load("Settings.lua")
        Equal(state.layouts.Containers.frame, nil)
        Equal(Setting("containers.autoOpenNew"):GetDefaultValue(), false)
        Setting("containers.autoOpenNew"):SetValue(true)
        Equal(Wild.db.containers.autoOpenNew, true)
        Wild.OpenNativeSettings("Container List")
        local panel = state.layouts["Container List"].frame.content
        local function Checkbox(itemID)
            return assert(FindChild(state, panel, function(frame)
                return frame.kind == "CheckButton" and frame.itemID == itemID
            end))
        end
        Equal(state.selected:GetParentCategory():GetName(), "Containers")
        Equal(Checkbox(100):GetChecked(), false)
        Equal(Checkbox(200):GetChecked(), true)
        Checkbox(100):SetChecked(true)
        Checkbox(100):Click()
        Equal(Wild.db.containers.items[100], true)
        Wild.HandleSlashCommand("containers 200 off")
        Equal(Checkbox(200):GetChecked(), false)
        Wild.HandleSlashCommand("containers add 300")
        Equal(Checkbox(300):GetChecked(), false, "A visible container list includes manually added IDs")
        local saved = Copy(Wild.db)
        panel:OnRefresh()
        Same(Wild.db, saved)
    end },
    { "the native container ID dialog adds disabled exceptions even when the default opens", function()
        local Wild, state, env = NewEnvironment({ containers = { autoOpenNew = true } })
        local action
        for _, initializer in ipairs(state.layouts.Containers.initializers) do
            if initializer.data.buttonText == "Add by Item ID" then action = initializer.data end
        end
        assert(action, "The native container page provides manual ID entry")
        action.buttonClick()
        state.popup.editBox:SetText("100")
        Equal(env.StaticPopupDialogs[state.popup.which].OnAccept(state.popup), false)
        Equal(Wild.db.containers.items[100], false)
        action.buttonClick()
        state.popup.editBox:SetText("invalid")
        Equal(env.StaticPopupDialogs[state.popup.which].OnAccept(state.popup), true)
        Equal(#Wild.GetContainers(), 1)
        assert(state.messages[#state.messages]:find("ID", 1, true))
    end },
    { "container labels refresh loaded names without changing saved choices or focused ID input", function()
        local Wild, state, env, _, _, Load = NewEnvironment()
        Load("Settings.lua")
        env.C_Item.GetItemInfo = function() end
        Wild.SetContainerAutoOpen(100, false)
        Wild.OpenNativeSettings("Containers")
        local action
        for _, initializer in ipairs(state.layouts.Containers.initializers) do
            if initializer.data.buttonText == "Add by Item ID" then action = initializer.data end
        end
        action.buttonClick()
        state.popup.editBox:SetText("234")
        state.popup.editBox:SetFocus()
        Wild.OpenNativeSettings("Container List")
        local panel = state.layouts["Container List"].frame.content
        local checkbox = assert(FindChild(state, panel, function(frame) return frame.itemID == 100 end))
        env.C_Item.GetItemInfo = function() return "Loaded container" end
        local saved = Copy(Wild.db)
        Wild.NotifySettingsChanged("containers.items")
        assert(checkbox.Text:GetText():find("Loaded container", 1, true))
        Equal(state.popup.editBox:GetText(), "234")
        Equal(state.popup.editBox:HasFocus(), true)
        Same(Wild.db, saved)
    end },
    { "native container defaults preserve discovered IDs and never apply the opening default retroactively", function()
        local Wild, _, _, Setting = NewEnvironment({
            containers = { autoOpenNew = true, items = { [100] = true, [200] = false } },
        })
        Setting("containers.autoOpenNew"):SetValueToDefault()
        Equal(Wild.db.containers.autoOpenNew, false)
        Equal(Wild.db.containers.items[100], true)
        Equal(Wild.db.containers.items[200], false)
        Equal(#Wild.GetContainers(), 2)
        Wild.ResetSettings()
        Equal(#Wild.GetContainers(), 0)
        Wild.SetContainerAutoOpen(100, false)
        Equal(Wild.db.containers.items[100], false)
    end },
    { "Soiree native controls slash commands and generic setters share the opt-in setting", function()
        local Wild, state, _, Setting = NewEnvironment()
        Equal(Setting("soiree.enabled"):GetDefaultValue(), false)
        Setting("soiree.enabled"):SetValue(true)
        Equal(Wild.IsFeatureEnabled("soiree"), true)
        Equal(state.soireeUpdates, 1)
        Wild.HandleSlashCommand("soiree off")
        Equal(Setting("soiree.enabled"):GetValue(), false)
        Equal(state.soireeUpdates, 2)
        Wild.SetSetting("soiree.enabled", true)
        Equal(Setting("soiree.enabled"):GetValue(), true)
        Equal(state.soireeUpdates, 3)
        Setting("soiree.enabled"):SetValueToDefault()
        Equal(Wild.IsFeatureEnabled("soiree"), false)
        Equal(state.soireeUpdates, 4)
        for _, initializer in ipairs(state.layouts["Saltheril's Soiree"].initializers) do
            if initializer.data.kind == "Button" then initializer.data.buttonClick() end
        end
        Equal(state.soireeShows, 1)
    end },
    { "world-event helper pages are grouped below Events without changing saved configuration", function()
        local Wild, state, _, Setting = NewEnvironment({
            darkmoonFaire = { showProfessionHelper = true }, soiree = { enabled = true },
        })
        local darkmoon = Setting("darkmoonFaire.showProfessionHelper").category
        local soiree = Setting("soiree.enabled").category
        local events = darkmoon:GetParentCategory()
        Equal(events:GetName(), "Events")
        Equal(events:GetParentCategory(), state.root)
        Equal(soiree:GetParentCategory(), events)
        Equal(darkmoon:GetName(), "Darkmoon Faire")
        Equal(soiree:GetName(), "Saltheril's Soiree")
        Equal(#events:GetSubcategories(), 2)
        for _, category in ipairs(state.root:GetSubcategories()) do
            assert(category ~= darkmoon and category ~= soiree, "Event helpers must not remain top-level pages")
        end
        Equal(Wild.db.darkmoonFaire.showProfessionHelper, true)
        Equal(Wild.db.soiree.enabled, true)
        Equal(state.soireeUpdates, 0, "Registering the group must not toggle a helper")
    end },
    { "Events offers native navigation to each event without toggling helpers or losing pending settings", function()
        local Wild, state = NewEnvironment()
        Equal(Wild.OpenNativeSettings("Events"), true)
        Equal(state.selected:GetName(), "Events")
        state.pending = "unapplied game setting"
        local pages = {}
        for _, initializer in ipairs(state.layouts.Events.initializers) do
            if initializer.data.kind == "Button" then
                initializer.data.buttonClick()
                Equal(state.selected:GetName(), initializer.data.name)
                Equal(state.selected:GetParentCategory():GetName(), "Events")
                pages[state.selected:GetName()] = true
                Equal(state.opens, 1)
                Equal(state.pending, "unapplied game setting")
            end
        end
        Equal(pages["Darkmoon Faire"], true)
        Equal(pages["Saltheril's Soiree"], true)
        Equal(Wild.db.darkmoonFaire.showProfessionHelper, false)
        Equal(Wild.db.soiree.enabled, false)
    end },
    { "event page names and legacy short navigation work through slash commands and public APIs", function()
        local Wild, state = NewEnvironment()
        Wild.HandleSlashCommand("native events")
        Equal(state.selected:GetName(), "Events")
        Wild.HandleSlashCommand("native darkmoon faire")
        Equal(state.selected:GetName(), "Darkmoon Faire")
        Equal(state.selected:GetParentCategory():GetName(), "Events")
        Wild.HandleSlashCommand("native soiree")
        local soiree = state.selected
        Equal(soiree:GetName(), "Saltheril's Soiree")
        Equal(soiree:GetParentCategory():GetName(), "Events")
        Equal(Wild.OpenNativeSettings("Soiree"), true)
        Equal(state.selected, soiree)
        Equal(Wild.OpenSettings("sAlThErIl'S sOiReE"), true)
        Equal(state.selected, soiree)
        Equal(Wild.ToggleSettings("Darkmoon Faire"), true)
        Equal(state.selected:GetParentCategory():GetName(), "Events")
        Equal(state.opens, 1)
    end },
    { "nested event controls and actions keep event search tags and Wild settings visibility", function()
        local Wild, state, env = NewEnvironment()
        for _, page in ipairs({ "Darkmoon Faire", "Saltheril's Soiree" }) do
            for _, initializer in ipairs(state.layouts[page].initializers) do
                if initializer.data.kind == "Checkbox" or initializer.data.kind == "Button" then
                    local tags = {}
                    for _, tag in ipairs(initializer.tags) do tags[tag] = true end
                    Equal(tags.Events, true, page .. " is searchable as an event")
                    Equal(tags[page], true, page .. " keeps its event name in search")
                end
            end
            Equal(Wild.OpenNativeSettings(page), true)
            Equal(Wild.settingsVisible, true)
        end
        env.SettingsPanel:Close()
        Equal(Wild.settingsVisible, false)
    end },
    { "defaults come from Core and cannot be mutated through the UI", function()
        local Wild, _, _, Setting = NewEnvironment()
        Equal(Setting("lfg.quickApply"):GetDefaultValue(), Wild.GetDefaultSetting("lfg.quickApply"))
        local position = Wild.GetDefaultSetting("castHistory.position")
        position.x = 987
        Equal(Wild.GetDefaultSetting("castHistory.position").x, 0)
    end },
    { "native proxy defaults are evaluated before registration to keep setting identifiers untainted", function()
        local _, state, env, Setting = NewEnvironment()
        for variable, setting in pairs(state.settings) do
            Equal(type(setting.default), type(setting:GetValue()),
                "Native registration must receive a scalar default for " .. variable)
            assert(type(setting.getter) == "function")
            assert(type(setting.setter) == "function")
        end
        Equal(Setting("screenCenterCircleColor.a"):GetDefaultValue(), 70)
        Equal(type(Setting("screenCenterCircleColor"):GetDefaultValue()), "string")
        local rarity = env.Enum.AuctionHouseFilter.RareQuality
        Equal(Setting("auctionHouse.filters." .. rarity):GetDefaultValue(), false)
        Equal(Setting("craftingOrders.filters." .. rarity):GetDefaultValue(), true)
    end },
    { "page defaults keep rules actors and collected data", function()
        local Wild, state, _, Setting = NewEnvironment()
        local intent, actor, character = {}, {}, {}
        Wild.db.intents[1] = intent
        Wild.db.actors.characters.Test = actor
        Wild.db.datastore.characters.Test = character
        Setting("speed.enabled"):SetValue(true)
        Setting("speed.enabled"):SetValueToDefault()
        Equal(Wild.db.intents[1], intent)
        Equal(Wild.db.actors.characters.Test, actor)
        Equal(Wild.db.datastore.characters.Test, character)
        Equal(Wild.db.speed.enabled, false)
        Equal(state.layouts["Intent Rules"].frame.OnDefault, nil)
        Equal(state.layouts.Actors.frame.OnDefault, nil)
    end },
    { "setting accessors survive reset replacing nested saved tables", function()
        local Wild, _, _, Setting = NewEnvironment()
        local original = Wild.db.speed
        Wild.ResetSettings()
        assert(Wild.db.speed ~= original)
        Setting("speed.enabled"):SetValue(true)
        Equal(Wild.db.speed.enabled, true)
        Equal(original.enabled, false)
    end },
    { "precise values and large circle sizes are not limited to the slider's visual range", function()
        local Wild, _, _, Setting = NewEnvironment()
        Setting("screenCenterCircleSize"):SetValue(450)
        Equal(Wild.db.screenCenterCircleSize, 450)
        Setting("screenCenterCircleColor.a"):SetValue(37)
        Equal(Wild.db.screenCenterCircleColor.a, 0.37)
        Setting("advanced.ruleDelay"):SetValue(0.34)
        Equal(Wild.db.advanced.ruleDelay, 0.3)
    end },
    { "visible native sliders do not overwrite external values with their clamped display values", function()
        local cases = {
            { "screenCenterCircleSize", 450, 200 },
            { "screenCenterCircleThickness", 80, 50 },
            { "screenCenterCircleOffsetX", 750, 500 },
            { "screenCenterCircleOffsetY", -800, -500 },
            { "advanced.ruleDelay", 1.5, 1 },
        }
        for _, case in ipairs(cases) do
            local Wild, state = NewEnvironment()
            local control = state.ShowSlider(case[1])
            Wild.SetSetting(case[1], case[2])
            Equal(Wild.GetSetting(case[1]), case[2], "Refreshing must not save the slider's visual clamp")
            Equal(control.slider:GetValue(), case[3])
            Equal(control.label, case[2], "The native label keeps the actual saved value")
        end
    end },
    { "slash commands preserve large circle size and offsets while native sliders are visible", function()
        local Wild, state = NewEnvironment()
        local size = state.ShowSlider("screenCenterCircleSize")
        state.ShowSlider("screenCenterCircleOffsetX")
        state.ShowSlider("screenCenterCircleOffsetY")
        Wild.HandleSlashCommand("circle size 450")
        Wild.HandleSlashCommand("circle offset 750 -800")
        Equal(Wild.db.screenCenterCircleSize, 450)
        Equal(size.label, 450)
        Equal(Wild.db.screenCenterCircleOffsetX, 750)
        Equal(Wild.db.screenCenterCircleOffsetY, -800)
        size.slider:SetValue(125)
        Equal(Wild.db.screenCenterCircleSize, 125, "Physical slider changes still save normally")
    end },
    { "canvas exact-value input preserves large sizes with a visible native slider", function()
        local Wild, state, _, _, _, Load = NewEnvironment()
        local native = state.ShowSlider("screenCenterCircleSize")
        Load("Settings.lua")
        local panel = Wild.CreateSettingsCanvas("Center Circle")
        panel:OnRefresh()
        local slider = FindChild(state, panel, function(frame)
            return frame.kind == "Slider" and frame.minimum == 1 and frame.maximum == 200
        end)
        local input = FindChild(state, panel, function(frame)
            return frame.kind == "EditBox" and frame.point and frame.point[2] == slider
        end)
        assert(input)
        input:SetText("450")
        input:SetFocus()
        input.scripts.OnEnterPressed(input)
        Equal(Wild.db.screenCenterCircleSize, 450)
        Equal(native.slider:GetValue(), 200)
        Equal(native.label, 450)
        Equal(input:GetText(), "450")
    end },
    { "native refresh guards recover after a callback error", function()
        local Wild, _, env, Setting = NewEnvironment()
        local notify = env.Settings.NotifyUpdate
        env.Settings.NotifyUpdate = function() error("Injected native callback error") end
        local ok, message = pcall(Wild.RefreshNativeSettings, "screenCenterCircleSize")
        Equal(ok, false)
        assert(tostring(message):find("Injected native callback error", 1, true))
        env.Settings.NotifyUpdate = notify
        Setting("screenCenterCircleSize"):SetValue(90)
        Equal(Wild.db.screenCenterCircleSize, 90, "A failed refresh must not block subsequent user edits")
    end },
    { "native settings stay editable while automation and display features are disabled", function()
        local Wild, state, _, Setting = NewEnvironment()
        Wild.db.screenCenterCircle = false
        Wild.db.castHistory.enabled = false
        Wild.db.castHistory.showText = false
        Wild.db.lfg.keystoneButtons = false
        Wild.db.auctionHouse.enabled = false
        Wild.db.craftingOrders.enabled = false
        Wild.db.quests.autoAccept = false
        Wild.db.quests.autoHandIn = false
        Wild.db.tooltip.enabled = false
        for _, page in ipairs({ "LFG", "Center Circle", "Cast History", "Auction House",
            "Crafting Orders", "Quests", "Tooltips" }) do
            for _, initializer in ipairs(state.layouts[page].initializers) do
                local data = initializer.data
                if data.setting or data.buttonText == "Enter Value" then
                    Equal(initializer:EvaluateModifyPredicates(), true,
                        "Configure " .. (data.name or data.setting:GetName()) .. " before enabling its feature")
                end
            end
        end
        Setting("screenCenterCircleSize"):SetValue(75)
        Setting("castHistory.textSize"):SetValue(18)
        Setting("quests.acceptDaily"):SetValue(false)
        Equal(Wild.db.screenCenterCircle, false)
        Equal(Wild.db.castHistory.enabled, false)
        Equal(Wild.db.quests.autoAccept, false)
    end },
    { "canvas and native opacity controls cover zero through one hundred percent", function()
        local Wild, state, _, Setting, _, Load = NewEnvironment()
        local native = state.ShowSlider("screenCenterCircleColor.a")
        Equal(native.slider.minimum, 0)
        Equal(native.slider.maximum, 100)
        Load("Settings.lua")
        local panel = Wild.CreateSettingsCanvas("Center Circle")
        panel:OnRefresh()
        local opacity = FindChild(state, panel, function(frame)
            return frame.kind == "Slider" and frame.Low:GetText():find("%%")
        end)
        assert(opacity)
        Equal(opacity.minimum, 0)
        Equal(opacity.maximum, 100)
        Equal(opacity.Low:GetText(), "0%")
        Setting("screenCenterCircleColor.a"):SetValue(0)
        panel:OnRefresh()
        Equal(opacity:GetValue(), 0)
        local input = FindChild(state, panel, function(frame)
            return frame.kind == "EditBox" and frame.point and frame.point[2] == opacity
        end)
        assert(input)
        input:SetText("5")
        input:SetFocus()
        input.scripts.OnEnterPressed(input)
        Equal(Wild.db.screenCenterCircleColor.a, 0.05)
        Equal(native.label, 5)
        native.slider:SetValue(100)
        panel:OnRefresh()
        Equal(Wild.db.screenCenterCircleColor.a, 1)
        Equal(opacity:GetValue(), 100)
    end },
    { "native Darkmoon settings retain the manual shopping-list action without enabling automation", function()
        local Wild, state = NewEnvironment()
        local shows = 0
        Wild.ShowDarkmoonHelper = function() shows = shows + 1 end
        local action
        for _, initializer in ipairs(state.layouts["Darkmoon Faire"].initializers) do
            if initializer.data.buttonText == "Show Shopping List Now" then action = initializer; break end
        end
        assert(action, "The native Darkmoon page must include the manual shopping-list action")
        Equal(action:EvaluateModifyPredicates(), true)
        action.data.buttonClick()
        Equal(shows, 1)
        Equal(Wild.db.darkmoonFaire.showProfessionHelper, false)
    end },
    { "numeric entry uses a standard popup and rejects invalid values explicitly", function()
        local Wild, state, env = NewEnvironment()
        local native = state.ShowSlider("screenCenterCircleSize")
        local entry
        for _, initializer in ipairs(state.layouts["Center Circle"].initializers) do
            local data = initializer.data
            if data.kind == "Button" and data.name == "Size (exact value)" then entry = data end
        end
        assert(entry, "Circle size keeps an exact-value input")
        entry.buttonClick()
        state.popup.editBox:SetText("450")
        env.StaticPopupDialogs[state.popup.which].OnAccept(state.popup, state.popup.data)
        Equal(Wild.db.screenCenterCircleSize, 450)
        Equal(native.label, 450)
        Equal(native.slider:GetValue(), 200)
        entry.buttonClick()
        state.popup.editBox:SetText("invalid")
        env.StaticPopupDialogs[state.popup.which].OnAccept(state.popup, state.popup.data)
        Equal(Wild.db.screenCenterCircleSize, 450)
        assert(state.messages[#state.messages]:find("number", 1, true))
    end },
    { "unconfigured auction and crafting filters preserve their different defaults", function()
        local Wild, _, env, Setting = NewEnvironment()
        local rarity = env.Enum.AuctionHouseFilter.RareQuality
        Equal(Setting("auctionHouse.filters." .. rarity):GetValue(), false)
        Equal(Setting("craftingOrders.filters." .. rarity):GetValue(), true)
        Equal(Wild.db.auctionHouse.filters[rarity], nil)
        Equal(Wild.db.craftingOrders.filters[rarity], nil)
        Setting("craftingOrders.filters." .. rarity):SetValue(false)
        Equal(Wild.db.craftingOrders.filters[rarity], false)
        Wild.SetSetting("auctionHouse.filters." .. rarity, true)
        Equal(Setting("auctionHouse.filters." .. rarity):GetValue(), true)
        Equal(Wild.GetSetting("auctionHouse.filters." .. rarity), true)
    end },
    { "the main command and native alias open native settings without toggling the window closed", function()
        local Wild, state = NewEnvironment()
        Wild.HandleSlashCommand("")
        Equal(state.selected, state.root)
        Equal(state.opens, 1)
        state.pending = "unapplied game setting"
        Wild.HandleSlashCommand("   ")
        Equal(state.selected, state.root)
        Equal(state.opens, 1)
        Equal(state.pending, "unapplied game setting")
        Wild.HandleSlashCommand("native speed")
        Equal(state.selected.name, "Speed")
        Equal(state.opens, 1)
        Wild.HandleSlashCommand("native")
        Equal(state.selected, state.root)
        Wild.HandleSlashCommand("native cEnTeR cIrClE")
        Equal(state.selected.name, "Center Circle")
    end },
    { "existing settings APIs redirect to native categories after the canvas module loads", function()
        local Wild, state, env, _, _, Load = NewEnvironment()
        Load("Settings.lua")
        Equal(Wild.OpenSettings("Speed"), true)
        Equal(state.selected.name, "Speed")
        Equal(Wild.ToggleSettings("Loot"), true)
        Equal(state.selected.name, "Loot")
        Equal(env.SettingsPanel:IsShown(), true)
        Equal(Wild.ToggleSettings(), true)
        Equal(state.selected, state.root)
        Wild.OpenNativeSettings("Center Circle")
        Equal(state.selected.name, "Center Circle")
        Equal(Wild.OpenSettings("missing"), false)
        Equal(state.selected.name, "Center Circle")
        Equal(Wild.ToggleSettings({}), false)
        Equal(state.selected.name, "Center Circle")
        Equal(state.opens, 1)
        Equal(env.WildSettingsFrame, nil)
    end },
    { "the native landing page and command help contain no standalone entry points", function()
        local Wild, state = NewEnvironment()
        for _, initializer in ipairs(state.layouts.Wild.initializers) do
            assert(initializer.data.buttonText ~= "Open Standalone Settings")
            assert(initializer.data.name ~= "Compare interfaces")
        end
        Wild.HandleSlashCommand("help")
        local help = table.concat(state.messages, "\n")
        assert(help:find("/wild - Open WoW Settings > AddOns > Wild", 1, true))
        assert(not help:find("Toggle settings window", 1, true))
    end },
    { "navigating an already open native panel does not discard pending game settings", function()
        local Wild, state = NewEnvironment()
        Wild.OpenNativeSettings()
        state.pending = "unapplied game setting"
        Wild.OpenNativeSettings("Loot")
        Equal(state.opens, 1)
        Equal(state.pending, "unapplied game setting")
        Equal(state.selected.name, "Loot")
        Equal(Wild.OpenNativeSettings("missing"), false)
        Equal(state.pending, "unapplied game setting")
    end },
    { "only native Wild pages contribute to settings visibility", function()
        local Wild, _, env = NewEnvironment()
        Wild.OpenNativeSettings("Speed")
        Equal(Wild.settingsVisible, true)
        env.SettingsPanel:Close()
        Equal(Wild.settingsVisible, false)
        env.SettingsPanel:Show()
        env.EventRegistry:TriggerEvent("Settings.CategoryChanged", { GetParentCategory = function() end })
        Equal(Wild.settingsVisible, false)
    end },
    { "Wild controls in native search results count as an open Wild settings interface", function()
        local Wild, state, env = NewEnvironment()
        env.SettingsPanel:Show()
        state.searchLayout = {
            IsVerticalLayout = function() return true end,
            GetInitializers = function() return state.layouts.Speed.initializers end,
        }
        env.SettingsPanel.SearchBox:SetText("speed")
        Equal(Wild.settingsVisible, true)
        state.searchLayout.GetInitializers = function() return {} end
        env.SettingsPanel.SearchBox:SetText("graphics")
        Equal(Wild.settingsVisible, false)
    end },
    { "global canvas refresh does not eagerly construct editors and revisiting reuses the same instance", function()
        local Wild, state = NewEnvironment()
        for _, layout in pairs(state.layouts) do
            if layout.frame and layout.frame.OnRefresh then layout.frame:OnRefresh() end
        end
        Equal(next(state.creates), nil)
        Wild.OpenNativeSettings("Intent Rules")
        Equal(state.creates["Intent Rules"], 1)
        Wild.OpenNativeSettings("Speed")
        Wild.OpenNativeSettings("Intent Rules")
        Equal(state.creates["Intent Rules"], 1)
    end },
    { "load-on-demand filters appear without forcing Blizzard UI addons to load", function()
        local Wild, state, env, Setting, Fire = NewEnvironment(nil, true)
        Wild.OpenNativeSettings("Auction House")
        env.Enum.AuctionHouseFilter = { UncollectedOnly = 0, RareQuality = 7 }
        Fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")
        Equal(Setting("auctionHouse.filters.0"):GetValue(), false)
        Equal(Setting("craftingOrders.filters.7"):GetValue(), true)
        local repaired = false
        for _, variable in ipairs(state.updates) do
            if variable == "WILD_auctionHouse_enabled" then repaired = true end
        end
        Equal(repaired, true, "New filters refresh the visible native list")
        local count = #state.categories
        Fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")
        Equal(#state.categories, count)
    end },
    { "refreshing a real canvas is read-only even when slider display values are clamped", function()
        local Wild, state, _, _, _, Load = NewEnvironment()
        Load("Settings.lua")
        Wild.db.screenCenterCircleSize = 450
        Wild.db.screenCenterCircleColor.a = 0.373
        local panel = Wild.CreateSettingsCanvas("Center Circle", "Native")
        local saved = Copy(Wild.db)
        panel:OnRefresh()
        Same(Wild.db, saved)
        local slider
        for _, frame in ipairs(state.frames) do
            if frame.kind == "Slider" and frame.minimum == 1 and frame.maximum == 200 then slider = frame end
        end
        assert(slider)
        slider:SetValue(50)
        Equal(Wild.db.screenCenterCircleSize, 50)
    end },
    { "a native canvas refresh preserves focused unsaved text", function()
        local Wild, state, _, _, _, Load = NewEnvironment()
        Load("Settings.lua")
        local panel = Wild.CreateSettingsCanvas("Auto-Reply", "Native")
        panel:OnRefresh()
        local box
        for _, frame in ipairs(state.frames) do
            if frame.kind == "EditBox" and frame.parent and frame.text == Wild.db.autoReply.message then box = frame end
        end
        assert(box)
        box:SetText("Unsaved message")
        box:SetFocus()
        panel:OnRefresh()
        Equal(box:GetText(), "Unsaved message")
        box:ClearFocus()
        Equal(Wild.db.autoReply.message, "Unsaved message")
    end },
    { "explicit canvas defaults replace focused drafts rather than letting them undo the reset", function()
        local Wild, state, _, _, _, Load = NewEnvironment()
        Load("Settings.lua")
        Wild.OpenNativeSettings("Auto-Reply")
        local box
        for _, frame in ipairs(state.frames) do
            if frame.kind == "EditBox" and frame.text == Wild.db.autoReply.message then box = frame end
        end
        assert(box)
        box:SetText("Unsaved message")
        box:SetFocus()
        state.layouts["Auto-Reply"].frame:OnDefault()
        Equal(Wild.db.autoReply.message, Wild.GetDefaultSetting("autoReply.message"))
        box:ClearFocus()
        Equal(Wild.db.autoReply.message, Wild.GetDefaultSetting("autoReply.message"))
    end },
    { "independent rule editor canvases reject stale saves", function()
        local Wild, state, _, _, _, Load = NewEnvironment()
        Load("Conditions.lua")
        Load("Settings.lua")
        local intent = { enabled = true, action = "sell", groups = {
            { mode = "include", kind = "items", conditions = { { attr = "item.id", op = "=", value = 123 } } },
        } }
        Wild.db.intents = { intent }
        local first = Wild.CreateSettingsCanvas("Intent Rules")
        local native = Wild.CreateSettingsCanvas("Intent Rules", "Native")
        assert(first ~= native)
        first:OnRefresh()
        native:OnRefresh()
        local add, save
        for _, frame in ipairs(state.frames) do
            if frame.text == "Add Intent" then add = frame end
        end
        assert(add)
        local showEditor
        for index = 1, 20 do
            local name, value = debug.getupvalue(add.scripts.OnClick, index)
            if not name then break end
            if name == "ShowEditor" then showEditor = value end
        end
        assert(showEditor)
        showEditor(1)
        for _, frame in ipairs(state.frames) do
            if frame.text == "Save" then save = frame end
        end
        assert(save)
        local replacement = Copy(intent)
        Wild.db.intents[1] = replacement
        save:Click()
        Equal(Wild.db.intents[1], replacement)
        assert(state.messages[#state.messages]:find("another settings window", 1, true))
    end },
    { "loading settings creates no standalone window or eager editor frames", function()
        local Wild, state, env, _, Fire, Load = NewEnvironment()
        Load("Conditions.lua")
        local saved = Copy(Wild.db)
        local frames = #state.frames
        Load("Settings.lua")
        Fire("ADDON_LOADED", "Wild")
        Same(Wild.db, saved)
        Equal(#state.frames, frames)
        Equal(env.WildSettingsFrame, nil)
        Equal(#env.UISpecialFrames, 0)
        Equal(next(state.creates), nil)
        Wild.OpenSettings()
        Equal(state.selected, state.root)
        Equal(#state.frames, frames)
    end },
    { "startup and every native editor avoid shared legacy dropdown state", function()
        local Wild, state, env, _, Fire, Load = NewEnvironment()
        local shared = {}
        env.UIDROPDOWNMENU_MENU_LEVEL = shared
        env.UIDROPDOWNMENU_INIT_MENU = shared
        env.UIDROPDOWNMENU_OPEN_MENU = shared
        env.DropDownList1 = shared
        Load("Conditions.lua")
        Load("Settings.lua")
        Wild.GetGroupedCurrencies = function() return {} end
        local saved = Copy(Wild.db)
        Fire("ADDON_LOADED", "Wild")
        local editors = 0
        for _, page in ipairs({ "Intent Rules", "Actors", "Character", "Dungeon Bar", "Auto-Reply", "Container List" }) do
            Wild.OpenNativeSettings(page)
            local panel = assert(state.layouts[page].frame.content)
            panel:OnRefresh()
            editors = editors + 1
        end
        Equal(editors, 6)
        local dropdowns = 0
        for _, frame in ipairs(state.frames) do
            if frame.menuGenerator then
                Equal(frame.kind, "DropdownButton")
                Equal(frame.template, "WowStyle1DropdownTemplate")
                frame:GenerateMenu()
                dropdowns = dropdowns + 1
            end
        end
        assert(dropdowns > 0, "Exercise real settings dropdowns")
        Equal(env.UIDROPDOWNMENU_MENU_LEVEL, shared)
        Equal(env.UIDROPDOWNMENU_INIT_MENU, shared)
        Equal(env.UIDROPDOWNMENU_OPEN_MENU, shared)
        Equal(env.DropDownList1, shared)
        Same(Wild.db, saved)
    end },
    { "settings canvas menus preserve every choice and reflect saved values", function()
        for _, namespace in ipairs({ "", "Native" }) do
            local Wild, _, env, _, _, Load = NewEnvironment()
            Load("Settings.lua")
            Wild.GetGroupedCurrencies = function() return {} end
            local pages = {
                Character = Wild.CreateSettingsCanvas("Character", namespace),
                Quests = Wild.CreateSettingsCanvas("Quests", namespace),
                Gossip = Wild.CreateSettingsCanvas("Gossip", namespace),
                Tooltips = Wild.CreateSettingsCanvas("Tooltips", namespace),
            }
            for _, case in ipairs({
                { "Character", "WildRepCollapseModeDD", "reputationCollapseMode", { "off", "all", "current", "remember" } },
                { "Character", "WildCurrCollapseModeDD", "currencyCollapseMode", { "off", "all", "current", "remember" } },
                { "Quests", "WildQuestToggleDD", "quests.toggleKey", { 1, 2, 3, 4 } },
                { "Gossip", "WildGossipToggleDD", "gossip.toggleKey", { 1, 2, 3, 4 } },
                { "Tooltips", "WildTooltipLineDD_", "tooltip.lines.itemID", { "always", "settings", "shift", "ctrl", "alt", "never" } },
            }) do
                local name = case[2] .. namespace
                if case[1] == "Tooltips" then name = name .. "itemID" end
                local dropdown = assert(env[name])
                local saved = Copy(Wild.db)
                Equal(#dropdown:GenerateMenu().children, #case[4])
                Same(Wild.db, saved)
                for _, value in ipairs(case[4]) do
                    local entry = assert(FindMenuEntry(dropdown:GenerateMenu(), value))
                    Equal(entry:Pick(), env.MenuResponse.CloseAll)
                    Equal(Wild.GetSetting(case[3]), value)
                    Equal(dropdown:GetText(), entry.text)
                    pages[case[1]]:OnRefresh()
                    Equal(dropdown:GetText(), entry.text)
                    for _, candidate in ipairs(dropdown:GenerateMenu().children) do
                        Equal(candidate:IsSelected(), candidate.data == value)
                    end
                end
            end
        end
    end },
    { "condition menus preserve false zero and packed subtype values without saving the draft", function()
        local Wild, state, env, _, _, Load = NewEnvironment()
        env.C_Item.GetItemSubClassInfo = function(classID, subclassID)
            if subclassID < 2 then return "Subtype " .. classID .. ":" .. subclassID end
        end
        Load("Conditions.lua")
        Load("Settings.lua")
        local panel = Wild.CreateSettingsCanvas("Intent Rules", "Native")
        local saved = Copy(Wild.db)
        local add = assert(FindChild(state, panel, function(frame) return frame.text == "Add Intent" end))
        add:Click()
        local attributes = assert(env.WildIntentCondAttrDDNative)
        local function SelectAttribute(key)
            assert(FindMenuEntry(attributes:GenerateMenu(), Wild.ATTR_BY_KEY[key])):Pick()
        end
        local booleans = assert(env.WildIntentCondBoolDDNative)
        SelectAttribute("item.isRecipeKnown")
        for _, value in ipairs({ true, false }) do
            local entry = assert(FindMenuEntry(booleans:GenerateMenu(), value))
            entry:Pick()
            Equal(entry:IsSelected(), true)
            Equal(booleans:GetText(), value and "Already known" or "Not yet known")
        end
        SelectAttribute("item.upgradeTrack")
        local tracks = assert(env.WildIntentCondTrackDDNative)
        local none = assert(FindMenuEntry(tracks:GenerateMenu(), 0))
        none:Pick()
        Equal(none:IsSelected(), true)
        Equal(tracks:GetText(), "None")
        SelectAttribute("item.quality")
        local qualities = assert(env.WildIntentCondQualDDNative)
        local poor = assert(FindMenuEntry(qualities:GenerateMenu(), 0))
        poor:Pick()
        Equal(poor:IsSelected(), true)
        Equal(qualities:GetText(), poor.text)
        SelectAttribute("item.subtype")
        local classes = assert(env.WildIntentCondSubParDDNative)
        local subtypes = assert(env.WildIntentCondSubDDNative)
        assert(FindMenuEntry(classes:GenerateMenu(), 4)):Pick()
        local armor = assert(FindMenuEntry(subtypes:GenerateMenu(), 1))
        armor:Pick()
        Equal(armor:IsSelected(), true)
        Equal(subtypes:GetText(), "Subtype 4:1")
        assert(FindMenuEntry(classes:GenerateMenu(), 9)):Pick()
        Equal(subtypes:GetText(), "Select...")
        local recipe = assert(FindMenuEntry(subtypes:GenerateMenu(), 0))
        Equal(recipe:IsSelected(), false)
        recipe:Pick()
        Equal(recipe:IsSelected(), true)
        Equal(subtypes:GetText(), "Subtype 9:0")
        Same(Wild.db, saved)
    end },
    { "transfer menus rebuild exclusions from the current draft without changing saved rules", function()
        local Wild, state, env, _, _, Load = NewEnvironment()
        Load("Conditions.lua")
        Load("Settings.lua")
        local panel = Wild.CreateSettingsCanvas("Intent Rules", "Native")
        local saved = Copy(Wild.db)
        assert(FindChild(state, panel, function(frame) return frame.text == "Add Intent" end)):Click()
        local actions = assert(env.WildIntentActionDDNative)
        Equal(#actions:GenerateMenu().children, 7)
        local transfer = assert(FindMenuEntry(actions:GenerateMenu(), "transfer"))
        transfer:Pick()
        Equal(actions:GetText(), "Transfer")
        local source = assert(env.WildIntentTransferSourceDDNative)
        local target = assert(env.WildIntentSourceDDNative)
        Equal(FindMenuEntry(source:GenerateMenu(), "warband"), nil)
        Equal(FindMenuEntry(target:GenerateMenu(), "character"), nil)
        assert(FindMenuEntry(source:GenerateMenu(), "guild")):Pick()
        Equal(source:GetText(), "Guild Bank")
        Equal(FindMenuEntry(target:GenerateMenu(), "guild"), nil)
        assert(FindMenuEntry(target:GenerateMenu(), "character")):Pick()
        Equal(target:GetText(), "Personal Bank")
        Equal(FindMenuEntry(source:GenerateMenu(), "character"), nil)
        assert(FindMenuEntry(source:GenerateMenu(), "guild")):Pick()
        Equal(source:GetText(), "Guild Bank")
        Same(Wild.db, saved)
    end },
    { "actor context menus stay open for label toggles and close on stale data", function()
        for _, namespace in ipairs({ "", "Native" }) do
            local Wild, state, env, _, _, Load = NewEnvironment()
            Load("Settings.lua")
            Wild.db.actors.characters["Test-Realm"] = { name = "Test", realm = "Realm" }
            Wild.db.actors.labels = { { name = "First" }, { name = "Second" } }
            local panel = Wild.CreateSettingsCanvas("Actors", namespace)
            panel:Show()
            local edit = assert(FindChild(state, panel, function(frame)
                return frame.kind == "Button" and frame.parent.customLabels ~= nil and
                    frame == frame.parent.editBtn
            end))
            local saved = Copy(Wild.db)
            edit:Click()
            Same(Wild.db, saved)
            local menu = assert(state.contextMenu)
            Equal(state.contextOwner, edit)
            Equal(#menu.children, 2)
            Equal(menu.children[1]:IsSelected(), false)
            Equal(menu.children[1]:Pick(), env.MenuResponse.Refresh)
            Equal(menu.open, true)
            Equal(menu.children[1]:IsSelected(), true)
            Equal(edit.parent.customLabels:GetText(), "First")
            Equal(menu.children[2]:Pick(), env.MenuResponse.Refresh)
            Equal(menu.open, true)
            Equal(edit.parent.customLabels:GetText(), "First, Second")
            Equal(menu.children[1]:Pick(), env.MenuResponse.Refresh)
            Equal(menu.open, true)
            Equal(menu.children[1]:IsSelected(), false)
            Equal(edit.parent.customLabels:GetText(), "Second")
            table.remove(Wild.db.actors.labels, 2)
            saved = Copy(Wild.db)
            Equal(menu.children[2]:Pick(), env.MenuResponse.CloseAll)
            Equal(menu.open, false)
            Same(Wild.db, saved)
            assert(state.messages[#state.messages]:find("another settings window", 1, true))
        end
    end },
}

local failed = 0
for _, test in ipairs(tests) do
    local ok, message = pcall(test[2])
    if ok then
        print("PASS " .. test[1])
    else
        failed = failed + 1
        print("FAIL " .. test[1] .. ": " .. tostring(message))
    end
end
assert(failed == 0, failed .. " native settings tests failed")
