-- Wild: Native WoW Settings
local ADDON_NAME, Wild = ...

local rootCategory
local categories = {}
local ownedCategories = {}
local ownedInitializers = {}
local registeredSettings = {}
local canvases = {}
local pendingFilters = {}
local captureFrame
local captureButton

local function Warn(message)
    Wild.Print("|cffff6600Wild:|r " .. message)
end

local function MatchesKey(key, prefix)
    if type(prefix) == "table" then
        for _, child in ipairs(prefix) do
            if MatchesKey(key, child) then return true end
        end
        return false
    end
    return not key or key == prefix or key:sub(1, #prefix + 1) == prefix .. "." or
        prefix:sub(1, #key + 1) == key .. "."
end

local function TrackCategory(category)
    categories[category:GetName():lower()] = category
    ownedCategories[category] = true
    return category
end

local function AddHeader(layout, name, tooltip)
    local initializer = CreateSettingsListSectionHeaderInitializer(name, tooltip)
    ownedInitializers[initializer] = true
    layout:AddInitializer(initializer)
end

local function AddButton(layout, name, text, callback, tooltip)
    local initializer = CreateSettingsButtonInitializer(name, text, callback, tooltip, true)
    ownedInitializers[initializer] = true
    initializer:AddSearchTags("Wild")
    layout:AddInitializer(initializer)
    return initializer
end

local function RegisterSetting(category, key, kind, name, getter, setter, default)
    getter = getter or function() return Wild.GetSetting(key) end
    setter = setter or function(value) Wild.SetSetting(key, value, "native") end
    -- Blizzard evaluates callable defaults before initializing the setting's secure fields.
    if default == nil then
        default = Wild.GetDefaultSetting(key)
    elseif type(default) == "function" then
        default = default()
    end
    local variable = "WILD_" .. key:gsub("[^%w]", "_")
    local entry = { key = key }
    local setting = Settings.RegisterProxySetting(category, variable, kind, name, default, getter, function(value)
        -- Native sliders can fire change callbacks while displaying a clamped value.
        if not entry.refreshing then setter(value) end
    end)
    entry.setting = setting
    registeredSettings[variable] = entry
    return setting
end

local function NotifySetting(variable)
    local entry = registeredSettings[variable]
    local previous = entry.refreshing
    entry.refreshing = true
    local ok, message = pcall(Settings.NotifyUpdate, variable)
    entry.refreshing = previous
    if not ok then error(message, 0) end
end

local function ConfigureInitializer(initializer, category, key, parent)
    ownedInitializers[initializer] = true
    initializer:AddSearchTags("Wild", category:GetName(), key)
    local ancestor = category:GetParentCategory()
    while ancestor and ancestor ~= rootCategory do
        initializer:AddSearchTags(ancestor:GetName())
        ancestor = ancestor:GetParentCategory()
    end
    if parent then
        initializer:SetParentInitializer(parent)
    end
    return initializer
end

local function AddCheckbox(category, key, name, tooltip, feature, update, parent)
    local function SetValue(value)
        if feature then
            Wild.SetFeatureEnabled(feature, value, "native")
        else
            Wild.SetSetting(key, value, "native")
            if update then update() end
        end
    end
    local setting = RegisterSetting(category, key, Settings.VarType.Boolean, name, nil, SetValue)
    local initializer = Settings.CreateCheckbox(category, setting, tooltip)
    return ConfigureInitializer(initializer, category, key, parent), setting
end

local function DropdownOptions(entries)
    return function()
        local container = Settings.CreateControlTextContainer()
        for _, entry in ipairs(entries) do
            container:Add(entry[1], entry[2], entry[3])
        end
        return container:GetData()
    end
end

local function AddDropdown(category, key, name, kind, entries, tooltip, setter, parent)
    local setting = RegisterSetting(category, key, kind, name, nil, setter)
    local options = type(entries) == "function" and entries or DropdownOptions(entries)
    local initializer = Settings.CreateDropdown(category, setting, options, tooltip)
    return ConfigureInitializer(initializer, category, key, parent), setting
end

local function ApplyNumberPopup(popup, data)
    local value = tonumber(popup:GetEditBox():GetText())
    if not value or value ~= value or value == math.huge or value == -math.huge then
        Warn("Enter a finite number.")
        return false
    end
    if value < data.minimum or (data.maximum and value > data.maximum) then
        local range = data.maximum and (data.minimum .. " to " .. data.maximum) or
            (data.minimum .. " or greater")
        Warn("Enter a number in the range " .. range .. ".")
        return false
    end
    data.setting:SetValue(value)
    return true
end

StaticPopupDialogs.WILD_NATIVE_NUMBER = {
    text = "Set %s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 180,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self, data)
        local editBox = self:GetEditBox()
        editBox:SetMaxLetters(12)
        editBox:SetText(tostring(data.setting:GetValue()))
        editBox:SetFocus()
        editBox:HighlightText()
    end,
    OnAccept = function(self, data)
        return not ApplyNumberPopup(self, data)
    end,
    EditBoxOnEnterPressed = function(self)
        local popup = self:GetParent()
        if ApplyNumberPopup(popup, popup.data) then popup:Hide() end
    end,
}

local function ApplyContainerID(popup)
    return Wild.SetContainerAutoOpen(popup:GetEditBox():GetText(), false)
end

StaticPopupDialogs.WILD_CONTAINER_ID = {
    text = "Add a container item ID. Auto-open starts disabled for this ID.",
    button1 = ADD or "Add",
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 180,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self)
        local editBox = self:GetEditBox()
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(10)
        editBox:SetText("")
        editBox:SetFocus()
    end,
    OnAccept = function(self) return not ApplyContainerID(self) end,
    EditBoxOnEnterPressed = function(self)
        local popup = self:GetParent()
        if ApplyContainerID(popup) then popup:Hide() end
    end,
}

local function AddNumber(category, key, name, minimum, maximum, step, tooltip, setter, update, parent, config)
    config = config or {}
    local inputMaximum = maximum
    if config.allowAboveMaximum then inputMaximum = nil end
    local function SetValue(value)
        if value ~= value or value == math.huge or value == -math.huge then
            Warn("Enter a finite number.")
            return
        end
        value = math.max(minimum, value)
        if inputMaximum then value = math.min(inputMaximum, value) end
        if step == 1 then value = math.floor(value + 0.5) end
        if config.roundTenths then value = math.floor(value * 10 + 0.5) / 10 end
        if setter then
            setter(value)
        else
            Wild.SetSetting(key, value, "native")
            if update then update() end
        end
    end
    local setting = RegisterSetting(category, key, Settings.VarType.Number, name,
        config.getter, SetValue, config.default)
    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return config.format and config.format(value) or tostring(value)
    end)
    local initializer = Settings.CreateSlider(category, setting, options, tooltip)
    initializer.reinitializeOnValueChanged = true
    ConfigureInitializer(initializer, category, key, parent)
    local button = AddButton(category.layout, name .. " (exact value)", "Enter Value", function()
        StaticPopup_Show("WILD_NATIVE_NUMBER", name, nil, {
            setting = setting, minimum = minimum, maximum = inputMaximum,
        })
    end, tooltip)
    if parent then
        button:SetParentInitializer(parent)
    end
    return initializer, setting
end

local function AddPage(name, parentCategory)
    local category, layout = Settings.RegisterVerticalLayoutSubcategory(parentCategory or rootCategory, name)
    TrackCategory(category)
    category.layout = layout
    return category, layout
end

local function AddCanvas(name, prefix, defaultKeys, update, parentCategory)
    local frame = CreateFrame("Frame")
    frame:Hide()
    local category = Settings.RegisterCanvasLayoutSubcategory(parentCategory or rootCategory, frame, name)
    TrackCategory(category)
    canvases[#canvases + 1] = { frame = frame, prefix = prefix }
    local defaultsButton
    if defaultKeys then
        frame.OnDefault = function()
            local focus = GetCurrentKeyBoardFocus()
            local parent = focus
            while parent do
                if parent == frame then
                    focus:ClearFocus()
                    break
                end
                parent = parent:GetParent()
            end
            for _, key in ipairs(defaultKeys) do
                Wild.SetSetting(key, Wild.GetDefaultSetting(key), "native")
            end
            if update then update() end
            if frame.content then frame.content:OnRefresh() end
        end
        defaultsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        defaultsButton:SetSize(120, 24)
        defaultsButton:SetPoint("BOTTOMRIGHT", -16, 4)
        defaultsButton:SetText(DEFAULTS or "Defaults")
        defaultsButton:SetScript("OnClick", frame.OnDefault)
    end
    frame:SetScript("OnShow", function(self)
        if not self.content then
            self.content = Wild.CreateSettingsCanvas(name, "Native")
            self.content:SetParent(self)
            self.content:SetPoint("TOPLEFT")
            self.content:SetPoint("BOTTOMRIGHT", 0, defaultsButton and 34 or 0)
        end
        self.content:Show()
    end)
    frame:SetScript("OnHide", function(self)
        if self.content then self.content:Hide() end
    end)
    frame.OnRefresh = function(self)
        if self.content and self:IsVisible() then self.content:OnRefresh() end
    end
    return category
end

local function RefreshCircle()
    Wild.UpdateScreenCenterCircle()
end

local function RefreshKeystone()
    if Wild.__keystonePanelRefresh then Wild.__keystonePanelRefresh() end
end

local function CreateLFGPage()
    local category, layout = AddPage("LFG")
    AddHeader(layout, "Premade Groups", "Configure quick applications and role confirmation.")
    AddCheckbox(category, "lfg.quickApply", "Enable Quick Apply",
        "Apply to a group with a single click and confirm the application dialog.", "lfg")
    AddCheckbox(category, "lfg.autoConfirmRole", "Auto-confirm role check",
        "Automatically confirm your role when invited to a group.", "autoconfirmrole")
    AddCheckbox(category, "lfg.autoAcceptRoleCheck", "Auto-accept role checks",
        "Automatically accept role checks when your group queues.", "autorolecheck")
    AddHeader(layout, "Keystone Panel")
    local enabled = AddCheckbox(category, "lfg.keystoneButtons", "Show keystone panel",
        "Display party member keystones beside the Premade Groups frame.", nil, RefreshKeystone)
    AddDropdown(category, "lfg.keystoneAnchor", "Panel position", Settings.VarType.String, {
        { "RIGHT", "Right" }, { "LEFT", "Left" }, { "TOPLEFT", "Top Left" },
        { "TOPRIGHT", "Top Right" }, { "BOTTOMLEFT", "Bottom Left" }, { "BOTTOMRIGHT", "Bottom Right" },
    }, "Choose which side of the group finder holds the keystone panel.", function(value)
        Wild.SetSetting("lfg.keystoneAnchor", value, "native")
        if Wild.__keystonePanelApplyAnchor then Wild.__keystonePanelApplyAnchor() end
    end, enabled)
end

local function CreateCirclePage()
    local category, layout = AddPage("Center Circle")
    local enabled = AddCheckbox(category, "screenCenterCircle", "Enable Center Circle",
        "Draw a circle at the center of the screen.", "circle")
    AddNumber(category, "screenCenterCircleSize", "Size", 1, 200, 1,
        "Circle diameter in pixels. Enter Value also accepts sizes above the slider's 200-pixel range.",
        nil, RefreshCircle, enabled, { allowAboveMaximum = true })
    AddNumber(category, "screenCenterCircleThickness", "Thickness", 1, 50, 1,
        "Circle line thickness in pixels.", nil, RefreshCircle, enabled)
    AddNumber(category, "screenCenterCircleColor.a", "Opacity", 0, 100, 1,
        "Circle opacity as a percentage.", function(value)
            Wild.SetSetting("screenCenterCircleColor.a", value / 100, "native")
            RefreshCircle()
        end, nil, enabled, {
            getter = function() return Wild.GetSetting("screenCenterCircleColor.a") * 100 end,
            default = function() return Wild.GetDefaultSetting("screenCenterCircleColor.a") * 100 end,
            format = function(value) return value .. "%" end,
        })
    local function GetColor()
        local color = Wild.GetSetting("screenCenterCircleColor")
        return CreateColor(color.r, color.g, color.b, 1):GenerateHexColor()
    end
    local function SetColor(value)
        local r, g, b = CreateColorFromHexString(value):GetRGB()
        Wild.SetSetting("screenCenterCircleColor.r", r, "native")
        Wild.SetSetting("screenCenterCircleColor.g", g, "native")
        Wild.SetSetting("screenCenterCircleColor.b", b, "native")
        RefreshCircle()
    end
    local color = RegisterSetting(category, "screenCenterCircleColor", Settings.VarType.String,
        "Circle Color", GetColor, SetColor, function()
            local default = Wild.GetDefaultSetting("screenCenterCircleColor")
            return CreateColor(default.r, default.g, default.b, 1):GenerateHexColor()
        end)
    ConfigureInitializer(Settings.CreateColorSwatch(category, color,
        "Choose a color with WoW's standard color picker. Cancel restores the previous RGB color."),
        category, "screenCenterCircleColor", enabled)
    AddNumber(category, "screenCenterCircleOffsetX", "X Offset", -500, 500, 1,
        "Horizontal offset from screen center in pixels.", nil, RefreshCircle, enabled)
    AddNumber(category, "screenCenterCircleOffsetY", "Y Offset", -500, 500, 1,
        "Vertical offset from screen center in pixels.", nil, RefreshCircle, enabled)
end

local function CreateSpeedPage()
    local category = AddPage("Speed")
    AddCheckbox(category, "speed.enabled", "Show speed indicator",
        "Display a draggable movement speed indicator. Normal running is 100%; standing still is 0%. " ..
        "Includes swimming, flying, and Skyriding. Drag it to reposition it.", "speed")
end

local function CreateCastHistoryPage()
    local category, layout = AddPage("Cast History")
    local enabled = AddCheckbox(category, "castHistory.enabled", "Enable Cast History",
        "Show GCD casts on the main track and non-GCD casts on parallel tracks.", "casthistory")
    AddNumber(category, "castHistory.iconSize", "Icon Size", 20, 100, 1, "Icon size in pixels.",
        Wild.SetCastHistorySize, nil, enabled)
    local text = AddCheckbox(category, "castHistory.showText", "Show Spell Names",
        "Display spell and item names below their icons.", nil, Wild.UpdateCastHistory, enabled)
    AddNumber(category, "castHistory.textSize", "Text Size", 8, 32, 1, "Spell-name text size in pixels.",
        Wild.SetCastHistoryTextSize, nil, text)
    AddNumber(category, "castHistory.historyLength", "History Length", 1, 20, 1,
        "Maximum entries retained separately for GCD and non-GCD tracks.", Wild.SetCastHistoryLength, nil, enabled)
    AddNumber(category, "castHistory.fadeAfter", "Fade After", 1, 30, 0.5,
        "Seconds before a cast fades. Enter Value supports precise fractional seconds.",
        Wild.SetCastHistoryFadeAfter, nil, enabled)
    AddDropdown(category, "castHistory.direction", "Slide Direction", Settings.VarType.String, {
        { "LEFT", "Left" }, { "RIGHT", "Right" }, { "UP", "Up" }, { "DOWN", "Down" },
    }, "Direction in which cast history slides.", Wild.SetCastHistoryDirection, enabled)
    AddNumber(category, "castHistory.trackSpacing", "Track Spacing", 0, 100, 1,
        "Gap between parallel tracks in pixels.", Wild.SetCastHistoryTrackSpacing, nil, enabled)
    AddHeader(layout, "Start Point")
    AddCheckbox(category, "castHistory.locked", "Lock Start Point",
        "Uncheck to show and drag the cyan start-point marker.", nil, Wild.UpdateCastHistory)
    AddButton(layout, "Start Point", "Reset Position", function() Wild.ResetCastHistoryPosition() end,
        "Restore the default cast-history position.")
    AddButton(layout, "Recorded Casts", "Clear History", function() Wild.ClearCastHistory() end,
        "Clear displayed casts without changing your configuration.")
    local test = AddButton(layout, "Preview", "Test Tracks", function()
        Wild.AddCastHistorySpell(6603, true)
        Wild.AddCastHistorySpell(6603, false)
    end, "Add a test entry to each track.")
    test:AddModifyPredicate(function() return Wild.GetSetting("castHistory.enabled") end)
end

local function CreateAdvancedPage()
    local category, layout = AddPage("Advanced")
    AddHeader(layout, "Intent Processing", "Timing values are in seconds. Lower values process items faster.")
    local delays = {
        { "ruleDelay", "Rule delay", "Seconds before advancing to the next intent rule." },
        { "passDelay", "Pass delay", "Seconds before retrying a rule after bags settle." },
        { "bankStartDelay", "Bank start delay", "Seconds before processing after the bank opens." },
        { "guildBankStartDelay", "Guild bank start delay", "Seconds before guild bank processing." },
        { "sellInterval", "Sell interval", "Seconds between individual vendor sales." },
        { "sellStartDelay", "Sell start delay", "Seconds before processing after a merchant opens." },
        { "mailStartDelay", "Mail start delay", "Seconds before sending after the mailbox opens." },
        { "mailBatchDelay", "Mail batch delay", "Seconds between mail attachment batches." },
        { "destroyStartDelay", "Destroy start delay", "Seconds before inventory destruction processing." },
        { "preloadTimeout", "Preload timeout", "Safety timeout for item-data loading." },
    }
    for _, delay in ipairs(delays) do
        AddNumber(category, "advanced." .. delay[1], delay[2], 0.1, 1, 0.1,
            delay[3], nil, nil, nil, { roundTenths = true })
    end
    AddCheckbox(category, "advanced.debug", "Enable debug mode",
        "Save diagnostic messages without printing scans or planned actions to chat. Use /wild log show to read them.")
end

local FILTERS = {
    { "UncollectedOnly", "Uncollected Only" }, { "UsableOnly", "Usable Only" },
    { "CurrentExpansionOnly", "Current Expansion Only" }, { "UpgradesOnly", "Upgrades Only" },
    { "PoorQuality", "Poor Quality", true }, { "CommonQuality", "Common Quality", true },
    { "UncommonQuality", "Uncommon Quality", true }, { "RareQuality", "Rare Quality", true },
    { "EpicQuality", "Epic Quality", true }, { "LegendaryQuality", "Legendary Quality", true },
    { "ArtifactQuality", "Artifact Quality", true },
}

local function BuildFilters(page)
    if page.built then return true end
    local filters = Enum and Enum.AuctionHouseFilter
    if not filters then return false end
    page.built = true
    AddHeader(page.layout, "Default Filters")
    for _, definition in ipairs(FILTERS) do
        local enumValue = filters[definition[1]]
        if enumValue ~= nil then
            local default = page.key == "craftingOrders" and definition[3] == true
            local key = page.key .. ".filters." .. enumValue
            local setting = RegisterSetting(page.category, key, Settings.VarType.Boolean, definition[2], function()
                local value = Wild.db[page.key].filters[enumValue]
                if value == nil then return default end
                return value
            end, function(value)
                Wild.db[page.key].filters[enumValue] = value
                Wild.NotifySettingsChanged(key, "native")
            end, default)
            ConfigureInitializer(Settings.CreateCheckbox(page.category, setting,
                "Apply this standard filter whenever the " .. page.category:GetName() .. " opens."),
                page.category, key, page.enabled)
        end
    end
    NotifySetting(page.enabled:GetData().setting:GetVariable())
    return true
end

local function CreateFiltersPage(name, key, feature)
    local category, layout = AddPage(name)
    local enabled = AddCheckbox(category, key .. ".enabled", "Enable default " .. name .. " filters",
        "Apply your selected standard filters whenever this window opens.", feature)
    AddHeader(layout, "Level Range", "Leave a value at 0 to ignore that level limit.")
    AddNumber(category, key .. ".minLevel", "Min Level", 0, 9999, 1,
        "Minimum item level; 0 disables this limit.", nil, nil, enabled)
    AddNumber(category, key .. ".maxLevel", "Max Level", 0, 9999, 1,
        "Maximum item level; 0 disables this limit.", nil, nil, enabled)
    local page = { category = category, layout = layout, key = key, enabled = enabled }
    pendingFilters[#pendingFilters + 1] = page
    if not BuildFilters(page) then
        local notice = CreateSettingsListSectionHeaderInitializer("Filters become available when the game loads their UI.")
        notice:AddShownPredicate(function() return not page.built end)
        layout:AddInitializer(notice)
    end
end

local function CreateMailPage()
    local category = AddPage("Mail")
    AddCheckbox(category, "mail.autoOpen", "Auto-open mailbox",
        "Take items and gold from incoming mail automatically when the mailbox opens.", "mail")
end

local function CreateLootPage()
    local category = AddPage("Loot")
    AddCheckbox(category, "lootAutoLoot", "Enable Auto-Loot",
        "Use WoW's built-in auto-loot setting.", "autoloot")
    AddDropdown(category, "lootAutoLootModifier", "Auto-loot modifier key", Settings.VarType.String, {
        { "SHIFT", SHIFT_KEY }, { "CTRL", CTRL_KEY }, { "ALT", ALT_KEY }, { "NONE", NONE_KEY },
    }, "Hold this modifier to invert WoW's normal auto-loot behavior.", Wild.SetAutoLootModifier)
    AddCheckbox(category, "lootQuickLoot", "Enable Quick Loot",
        "Speed up looting by taking eligible loot slots immediately.", "loot")
end

local function CreateContainersPage()
    local category, layout = AddPage("Containers")
    AddCheckbox(category, "containers.autoOpenNew", "Auto-open newly discovered containers",
        "Save newly discovered bag containers with auto-open enabled and open them when safe. " ..
        "Off by default: containers are still added to the list, but remain unopened. " ..
        "Changing this default never changes saved per-item choices.")
    AddButton(layout, "Configure a container in advance", "Add by Item ID", function()
        StaticPopup_Show("WILD_CONTAINER_ID")
    end, "Add a container ID with auto-open disabled, even before you receive the item.")
    AddButton(layout, "Known containers", "Edit Container List", function()
        Wild.OpenNativeSettings("Container List")
    end, "Enable or disable auto-open for each discovered or manually added container ID.")
    AddCanvas("Container List", "containers.items", nil, nil, category)
end

local PAUSE_KEYS = { { 1, NONE_KEY }, { 2, ALT_KEY }, { 3, CTRL_KEY }, { 4, SHIFT_KEY } }

local function CreateQuestsPage()
    local category, layout = AddPage("Quests")
    AddHeader(layout, "Auto-Accept")
    local accept = AddCheckbox(category, "quests.autoAccept", "Enable auto-accept",
        "Accept quests immediately when their detail window opens.", "autoaccept")
    for _, option in ipairs({
        { "acceptNormal", "Normal quests", "Accept regular one-time quests." },
        { "acceptDaily", "Daily quests", "Accept daily quests." },
        { "acceptWeekly", "Weekly quests", "Accept weekly quests." },
        { "acceptRepeatable", "Repeatable quests", "Accept repeatable quests." },
        { "acceptTrivial", "Trivial (grey) quests", "Accept low-level grey quests." },
    }) do
        AddCheckbox(category, "quests." .. option[1], option[2], option[3], nil, nil, accept)
    end
    AddDropdown(category, "quests.toggleKey", "Pause key", Settings.VarType.Number, PAUSE_KEYS,
        "Hold this modifier while interacting with an NPC to invert quest automation.")
    AddHeader(layout, "Auto-Hand-In")
    local handIn = AddCheckbox(category, "quests.autoHandIn", "Enable auto-hand-in",
        "Continue and complete finished quests automatically.", "autohandin")
    AddCheckbox(category, "quests.autoSelectReward", "Auto-select best reward",
        "Select the reward with the highest vendor price. Disable to choose rewards manually.", nil, nil, handIn)
end

local function StopCapture()
    if captureFrame then captureFrame:Hide() end
    if captureButton then captureButton:SetText("Capture Key") end
    captureButton = nil
    if Wild.dialogKeyCaptureStop == StopCapture then Wild.dialogKeyCaptureStop = nil end
end

local function CaptureKey(button)
    if InCombatLockdown() then Warn("Configure the dialog key outside combat."); return end
    if captureFrame:IsShown() then StopCapture(); return end
    if Wild.dialogKeyCaptureStop then Wild.dialogKeyCaptureStop() end
    local focus = GetCurrentKeyBoardFocus()
    if focus then focus:ClearFocus() end
    Wild.dialogKeyCaptureStop = StopCapture
    captureButton = button
    captureFrame:SetPropagateKeyboardInput(true)
    captureFrame:Show()
    button:SetText("Press a key (Esc cancels)")
end

local function CreateDialogKeyPage()
    local category, layout = AddPage("Dialog Key")
    AddCheckbox(category, "dialogKey.enabled", "Enable dialog key",
        "Manually confirm standard popups, queue and role checks, and delve entry with a physical key press. " ..
        "Nothing is accepted automatically, in combat, or while Wild settings are open.", "dialog")
    local function KeyOptions()
        local current = Wild.GetSetting("dialogKey.key")
        local container = Settings.CreateControlTextContainer()
        container:Add(current, GetBindingText(current))
        for _, key in ipairs({ "SPACE", "ENTER", "F2", "CTRL-F2" }) do
            if key ~= current then container:Add(key, GetBindingText(key)) end
        end
        return container:GetData()
    end
    AddDropdown(category, "dialogKey.key", "Confirmation key", Settings.VarType.String, KeyOptions,
        "Choose a common key or use Capture Key to enter any supported keyboard key or modifier chord.",
        function(value) Wild.SetDialogKey(value, "native") end)
    AddButton(layout, "Custom confirmation key", "Capture Key", CaptureKey,
        "Press a key or modifier chord. Escape cancels. Normal key bindings are unchanged.")
    AddCheckbox(category, "dialogKey.destroy", "Allow item destruction with the dialog key",
        "Warning: the key can permanently destroy the item on your cursor, including valuable and quest items, " ..
        "without typing DELETE. Other typed confirmations and confirmation delays are never bypassed.")
    AddHeader(layout, "Warning: item destruction is permanent",
        "Item destruction is a separate opt-in and is disabled by default.")
    captureFrame = CreateFrame("Frame", nil, UIParent)
    captureFrame:SetFrameStrata("TOOLTIP")
    captureFrame:EnableKeyboard(true)
    captureFrame:SetPropagateKeyboardInput(true)
    captureFrame:Hide()
    captureFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    captureFrame:SetScript("OnEvent", StopCapture)
    captureFrame:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then StopCapture(); return end
        if GetCurrentKeyBoardFocus() then
            self:SetPropagateKeyboardInput(true)
            StopCapture()
            return
        end
        self:SetPropagateKeyboardInput(false)
        if key == "ESCAPE" then StopCapture(); return end
        if key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" or
            key == "LSHIFT" or key == "RSHIFT" then return end
        local binding = (IsControlKeyDown() and "CTRL-" or "") ..
            (IsAltKeyDown() and "ALT-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        if Wild.SetDialogKey(binding, "native") then StopCapture() end
    end)
end

local function CreateGossipPage()
    local category = AddPage("Gossip")
    for _, option in ipairs({
        { "autoSelectSingle", "Auto-select single gossip option", "Select an NPC's only gossip option automatically." },
        { "autoSelectQuest", "Auto-select quest gossip options", "Select quest-related gossip options automatically." },
        { "autoSelectDelve", "Auto-select delve gossip options", "Select delve-related gossip options automatically." },
        { "autoSkip", "Auto-select skip options", "Select gossip options that offer to skip content." },
        { "skipIfQuest", "Skip when quests are available", "Do not auto-select a lone option when the NPC also offers quests." },
        { "darkmoonTeleport", "Auto-accept Darkmoon Faire teleport", "Accept the Darkmoon Faire teleport dialog automatically." },
    }) do
        AddCheckbox(category, "gossip." .. option[1], option[2], option[3])
    end
    AddDropdown(category, "gossip.toggleKey", "Pause key", Settings.VarType.Number, PAUSE_KEYS,
        "Hold this modifier while interacting with an NPC to bypass gossip automation.")
end

local function CreateDarkmoonPage(parentCategory)
    local category, layout = AddPage("Darkmoon Faire", parentCategory)
    AddCheckbox(category, "darkmoonFaire.showProfessionHelper", "Show profession helper",
        "Show a profession shopping list when entering a Darkmoon Faire staging area.")
    local action = AddButton(layout, "Profession shopping list", "Show Shopping List Now", function()
        Wild.ShowDarkmoonHelper()
    end, "Open the profession shopping list regardless of your location or the automatic helper setting.")
    ConfigureInitializer(action, category, "darkmoonFaire")
    return category
end

local function CreateSoireePage(parentCategory)
    local category, layout = AddPage("Saltheril's Soiree", parentCategory)
    categories["soiree"] = category
    AddCheckbox(category, "soiree.enabled", "Show Soiree reputation advisor",
        "Open advisory help with Saltheril's weekly invitation selector. Enter all four current previews " ..
        "to compare gains, losses, Fortify, and Favor allocation toward Luminary.", "soiree")
    AddHeader(layout, "Advice only",
        "The advisor reads live reputation but requires manual invitation effects. It never selects an " ..
        "invitation or spends Favors. Projections use base quest rewards, not future offers or reputation bonuses.")
    local action = AddButton(layout, "Current invitation selector", "Show Advisor Now", function()
        Wild.ShowSoireeAdvisor()
    end, "Open the advisor while Saltheril's four-invitation selector is open, even if automatic display is off.")
    ConfigureInitializer(action, category, "soiree")
    return category
end

local function CreateEventsPage()
    local category, layout = AddPage("Events")
    AddHeader(layout, "World event helpers", "Choose a recurring world event to configure its helpers.")
    local eventPages = { CreateDarkmoonPage(category), CreateSoireePage(category) }
    for _, eventCategory in ipairs(eventPages) do
        local name = eventCategory:GetName()
        local action = AddButton(layout, name, "Open Settings", function()
            Wild.OpenNativeSettings(name)
        end, "Configure helpers for " .. name .. ".")
        action:AddSearchTags("Events", name)
    end
end

local function CreateTooltipPage()
    local category, layout = AddPage("Tooltips")
    local enabled = AddCheckbox(category, "tooltip.enabled", "Enable tooltip enhancements",
        "Add item information to tooltips using the visibility modes below.", "tooltip")
    AddHeader(layout, "Tooltip Lines", "Wild Settings Open includes Wild's native pages and search results.")
    local modes = {}
    for _, mode in ipairs(Wild.TOOLTIP_VISIBILITY_MODES) do
        modes[#modes + 1] = { mode.key, mode.label }
    end
    for _, line in ipairs(Wild.TOOLTIP_LINES) do
        AddDropdown(category, "tooltip.lines." .. line.key, line.label, Settings.VarType.String, modes,
            "Choose when " .. line.label .. " appears on item tooltips.", nil, enabled)
    end
end

local function CreateDelvePage()
    local category = AddPage("Delve")
    AddCheckbox(category, "delveAutoSelectPower", "Auto-select delve power",
        "Select the first available power when the choice window appears inside a delve.", "delve")
end

local function CreateVolumePage()
    local category = AddPage("Volume")
    AddCheckbox(category, "volumeControl.enabled", "Enable Volume Button",
        "Show a draggable speaker button with WoW volume controls.", "volume")
end

local function CreateDurabilityPage()
    local category = AddPage("Durability")
    AddCheckbox(category, "durability.showEquipped", "Show on equipped items",
        "Show durability on each equipment slot in the character panel.", "durabilityequipped")
    AddCheckbox(category, "durability.showEquippedTotal", "Show total durability overlay",
        "Show a draggable total equipped-durability overlay.", "durabilitytotal")
    AddCheckbox(category, "durability.showBags", "Show on bag items",
        "Show durability on equipment in your bags.", "durabilitybags")
end

function Wild.RefreshNativeSettings(key, source)
    for variable, entry in pairs(registeredSettings) do
        if MatchesKey(key, entry.key) then NotifySetting(variable) end
    end
    if source ~= "native" then
        for _, entry in ipairs(canvases) do
            if MatchesKey(key, entry.prefix) then entry.frame:OnRefresh() end
        end
    end
end

function Wild.OpenNativeSettings(page)
    if not rootCategory then Warn("Native settings have not loaded yet."); return false end
    if page ~= nil and type(page) ~= "string" then
        Warn("Native settings page must be a name.")
        return false
    end
    local category = rootCategory
    if page then category = categories[page:lower()] end
    if not category then Warn("Unknown native settings page: " .. page); return false end
    -- OpenToCategory clears the native panel's pending-settings bookkeeping.
    if SettingsPanel:IsShown() then
        SettingsPanel:SelectCategory(category)
    else
        Settings.OpenToCategory(category:GetID())
    end
    return true
end

function Wild.OpenSettings(page)
    return Wild.OpenNativeSettings(page)
end

function Wild.ToggleSettings(page)
    return Wild.OpenNativeSettings(page)
end

local function RefreshVisibility(selected)
    local visible = false
    if SettingsPanel:IsShown() then
        if SettingsPanel.SearchBox:HasText() then
            local layout = SettingsPanel:GetCurrentLayout()
            if layout and layout:IsVerticalLayout() then
                for _, initializer in ipairs(layout:GetInitializers()) do
                    if ownedInitializers[initializer] then visible = true; break end
                end
            end
        else
            visible = ownedCategories[selected or SettingsPanel:GetCurrentCategory()] == true
        end
    end
    Wild.nativeSettingsVisible = visible
    Wild.UpdateSettingsVisibility()
end

local function Initialize()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Wild")
    rootCategory = category
    rootCategory.layout = layout
    TrackCategory(rootCategory)
    AddHeader(layout, "Wild settings",
        "Choose a category to configure Wild. Changes apply immediately.")
    AddCheckbox(category, "includeReagentBag", "Include reagent bag",
        "Include your reagent bag when scanning player bags for automation rules.")
    CreateLFGPage()
    CreateCirclePage()
    CreateSpeedPage()
    CreateCastHistoryPage()
    AddCanvas("Intent Rules", { "intents", "actors" })
    AddCanvas("Actors", "actors")
    CreateAdvancedPage()
    AddCanvas("Character", {
        "vendorAutoRepair", "vendorRepairUseGuild", "reputationCollapseMode",
        "reputationCollapsedHeaders", "currencyCollapseMode", "currencyCollapsedHeaders",
    }, {
        "vendorAutoRepair", "vendorRepairUseGuild", "reputationCollapseMode", "currencyCollapseMode",
    })
    CreateFiltersPage("Auction House", "auctionHouse", "auctionhouse")
    CreateFiltersPage("Crafting Orders", "craftingOrders", "craftingorders")
    CreateMailPage()
    CreateLootPage()
    CreateContainersPage()
    CreateQuestsPage()
    CreateDialogKeyPage()
    CreateGossipPage()
    CreateEventsPage()
    CreateTooltipPage()
    AddCanvas("Dungeon Bar", "dungeonBar", {
        "dungeonBar.enabled", "dungeonBar.autoShowInInstance", "dungeonBar.showReadyCheck",
        "dungeonBar.showCancelPull", "dungeonBar.showCustomPull", "dungeonBar.customPullSeconds",
        "dungeonBar.showDisband", "dungeonBar.showTooltips", "dungeonBar.pullPresets",
    }, function()
        Wild.RebuildDungeonBar()
        if Wild.GetSetting("dungeonBar.enabled") then Wild.ShowDungeonBar() else Wild.HideDungeonBar() end
    end)
    AddCanvas("Auto-Reply", "autoReply", {
        "autoReply.enabled", "autoReply.message", "autoReply.replyWhispers",
        "autoReply.replyBNetWhispers", "autoReply.onlyInProgress",
    })
    CreateDelvePage()
    CreateVolumePage()
    CreateDurabilityPage()
    Settings.RegisterAddOnCategory(rootCategory)
    EventRegistry:RegisterCallback("Settings.CategoryChanged", function(_, selected)
        RefreshVisibility(selected)
        if selected ~= categories["dialog key"] then StopCapture() end
    end, rootCategory)
    SettingsPanel.SearchBox:HookScript("OnTextChanged", function()
        RefreshVisibility()
        StopCapture()
    end)
    EventRegistry:RegisterCallback("SettingsPanel.OnHide", function()
        Wild.nativeSettingsVisible = false
        Wild.UpdateSettingsVisibility()
        StopCapture()
    end, rootCategory)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, addon)
    if not rootCategory then
        if event == "ADDON_LOADED" and addon ~= ADDON_NAME then return end
        if not Wild.db then return end
        Initialize()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
    local complete = true
    for _, page in ipairs(pendingFilters) do
        if not BuildFilters(page) then complete = false end
    end
    if complete then self:UnregisterEvent("ADDON_LOADED") end
end)
