-- Wild: Standalone settings window
local ADDON_NAME, Wild = ...

local mainFrame
local currentTab

-- ============================================================
-- Helper: create an EditBox linked to a slider
-- ============================================================
local function CreateSliderEditBox(parent, slider, minVal, maxVal, isInt)
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(50, 20)
    editBox:SetPoint("LEFT", slider, "RIGHT", 16, 0)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(false)
    editBox:SetMaxLetters(6)
    editBox:SetFontObject("GameFontHighlightSmall")

    local function ApplyValue()
        local text = editBox:GetText()
        local num = tonumber(text)
        if num then
            num = math.max(minVal, math.min(maxVal, num))
            if isInt then num = math.floor(num + 0.5) end
            slider:SetValue(num)
        end
        editBox:ClearFocus()
    end

    editBox:SetScript("OnEnterPressed", ApplyValue)
    editBox:SetScript("OnEditFocusLost", ApplyValue)

    slider:HookScript("OnValueChanged", function(_, value)
        if isInt then value = math.floor(value + 0.5) end
        editBox:SetText(tostring(value))
    end)

    return editBox
end

-- ============================================================
-- Helper: hook scroll child width to scroll frame
-- ============================================================
local function HookScrollChildWidth(scrollFrame, sc)
    scrollFrame:HookScript("OnSizeChanged", function(self, w)
        sc:SetWidth(w)
    end)
end

-- ============================================================
-- Main window creation
-- ============================================================
local function CreateMainFrame()
    if mainFrame then return mainFrame end

    local f = CreateFrame("Frame", "WildSettingsFrame", UIParent, "BackdropTemplate")
    f:SetSize(720, 520)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(520, 380, 1200, 900)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    f:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 12, 0)
    titleText:SetText("|cff00ccffWild|r")

    local versionText = titleBar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    versionText:SetPoint("LEFT", titleText, "RIGHT", 8, -1)
    versionText:SetText("|cff666666v" .. (C_AddOns.GetAddOnMetadata("Wild", "Version") or "1.0.0") .. "|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", -8, 0)
    closeBtn.label = closeBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    closeBtn.label:SetPoint("CENTER", 0, 0)
    closeBtn.label:SetText("|cffaaaaaa×|r")
    closeBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffff4444×|r") end)
    closeBtn:SetScript("OnLeave", function(self) self.label:SetText("|cffaaaaaa×|r") end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Title bar separator
    local titleSep = titleBar:CreateTexture(nil, "ARTWORK")
    titleSep:SetHeight(1)
    titleSep:SetPoint("BOTTOMLEFT", 0, 0)
    titleSep:SetPoint("BOTTOMRIGHT", 0, 0)
    titleSep:SetColorTexture(0.3, 0.3, 0.35, 1)

    -- Sidebar
    local sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sidebar:SetWidth(150)
    sidebar:SetPoint("TOPLEFT", 0, -32)
    sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    sidebar:SetClipsChildren(true)
    sidebar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    sidebar:SetBackdropColor(0.06, 0.06, 0.08, 1)

    local sidebarSep = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarSep:SetWidth(1)
    sidebarSep:SetPoint("TOPRIGHT", 0, 0)
    sidebarSep:SetPoint("BOTTOMRIGHT", 0, 0)
    sidebarSep:SetColorTexture(0.3, 0.3, 0.35, 1)

    -- Content area
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", 0, 0)

    f.sidebar = sidebar
    f.content = content
    f.tabs = {}
    f.tabButtons = {}
    f.sidebarOrder = {}

    -- Resize grip
    local resizeGrip = CreateFrame("Button", nil, f)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeGrip:SetFrameLevel(f:GetFrameLevel() + 50)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizeGrip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    -- ESC to close
    tinsert(UISpecialFrames, "WildSettingsFrame")

    -- Track visibility for tooltip integration
    f:HookScript("OnShow", function() Wild.settingsVisible = true end)
    f:HookScript("OnHide", function() Wild.settingsVisible = false end)

    f:Hide()
    mainFrame = f
    return f
end

-- ============================================================
-- Tab management
-- ============================================================
local LayoutSidebar -- forward declaration
local function SelectTab(name)
    if not mainFrame then return end
    currentTab = name
    -- Auto-expand parent group if selecting a grouped child
    for _, btn in ipairs(mainFrame.tabButtons) do
        if btn.tabName == name and btn.groupName and mainFrame.sidebarOrder then
            for _, item in ipairs(mainFrame.sidebarOrder) do
                if item.type == "group" and item.name == btn.groupName and not item.expanded then
                    item.expanded = true
                    if item.frame and item.frame.arrow then
                        item.frame.arrow:SetText("|cff888888\226\128\147|r")
                    end
                    LayoutSidebar()
                    break
                end
            end
            break
        end
    end
    for tabName, tabPanel in pairs(mainFrame.tabs) do
        tabPanel:SetShown(tabName == name)
    end
    for _, btn in ipairs(mainFrame.tabButtons) do
        if btn.tabName == name then
            btn.bg:SetColorTexture(0.15, 0.15, 0.20, 1)
            btn.label:SetFontObject("GameFontHighlight")
        else
            btn.bg:SetColorTexture(0, 0, 0, 0)
            btn.label:SetFontObject("GameFontNormalSmall")
        end
    end
end

local function AddTab(name, tabPanel, indent)
    local f = mainFrame
    tabPanel:SetParent(f.content)
    tabPanel:SetAllPoints(f.content)
    tabPanel:Hide()
    f.tabs[name] = tabPanel

    local idx = #f.tabButtons + 1
    local btn = CreateFrame("Button", nil, f.sidebar)
    btn:SetHeight(28)
    btn:SetPoint("TOPLEFT", f.sidebar, "TOPLEFT", 0, 0) -- positioned by LayoutSidebar
    btn:SetPoint("RIGHT", f.sidebar, "RIGHT", -1, 0)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0, 0, 0, 0)

    btn.label = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    btn.label:SetPoint("LEFT", indent and 24 or 12, 0)
    btn.label:SetText(name)

    btn.tabName = name
    btn.isIndented = indent

    btn:SetScript("OnClick", function() SelectTab(name) end)
    btn:SetScript("OnEnter", function(self)
        if self.tabName ~= currentTab then
            self.bg:SetColorTexture(0.12, 0.12, 0.16, 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if self.tabName ~= currentTab then
            self.bg:SetColorTexture(0, 0, 0, 0)
        end
    end)

    f.tabButtons[idx] = btn

    -- If there's an active group being built, register as a child
    if f._currentGroup then
        btn.groupName = f._currentGroup
        btn:Hide()
    else
        -- Top-level tab: register in sidebar order for layout
        if not f.sidebarOrder then f.sidebarOrder = {} end
        table.insert(f.sidebarOrder, { type = "tab", btn = btn })
    end
end

LayoutSidebar = function()
    local f = mainFrame
    if not f then return end
    local slot = 0
    -- Layout groups first, then buttons
    for _, item in ipairs(f.sidebarOrder) do
        if item.type == "group" then
            item.frame:ClearAllPoints()
            item.frame:SetPoint("TOPLEFT", f.sidebar, "TOPLEFT", 0, -(slot * 28))
            item.frame:SetPoint("RIGHT", f.sidebar, "RIGHT", -1, 0)
            item.frame:Show()
            slot = slot + 1
            if item.expanded then
                for _, btn in ipairs(f.tabButtons) do
                    if btn.groupName == item.name then
                        btn:ClearAllPoints()
                        btn:SetPoint("TOPLEFT", f.sidebar, "TOPLEFT", 0, -(slot * 28))
                        btn:SetPoint("RIGHT", f.sidebar, "RIGHT", -1, 0)
                        btn:Show()
                        slot = slot + 1
                    end
                end
            else
                for _, btn in ipairs(f.tabButtons) do
                    if btn.groupName == item.name then
                        btn:Hide()
                    end
                end
            end
        elseif item.type == "tab" then
            local btn = item.btn
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", f.sidebar, "TOPLEFT", 0, -(slot * 28))
            btn:SetPoint("RIGHT", f.sidebar, "RIGHT", -1, 0)
            btn:Show()
            slot = slot + 1
        end
    end
end

local function AddCollapsibleGroup(name)
    local f = mainFrame
    if not f.sidebarOrder then f.sidebarOrder = {} end

    local header = CreateFrame("Button", nil, f.sidebar)
    header:SetHeight(28)
    header:SetPoint("TOPLEFT", 0, 0) -- positioned by LayoutSidebar
    header:SetPoint("RIGHT", f.sidebar, "RIGHT", -1, 0)

    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetColorTexture(0, 0, 0, 0)

    header.arrow = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header.arrow:SetPoint("LEFT", 4, 0)
    header.arrow:SetText("|cff888888\194\183|r") -- collapsed: middle dot as compact indicator

    header.label = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header.label:SetPoint("LEFT", 14, 0)
    header.label:SetText(name)

    local groupEntry = { type = "group", name = name, frame = header, expanded = false }
    table.insert(f.sidebarOrder, groupEntry)

    local function UpdateArrow()
        if groupEntry.expanded then
            header.arrow:SetText("|cff888888\226\128\147|r") -- expanded: dash
        else
            header.arrow:SetText("|cff888888+|r") -- collapsed: plus
        end
    end
    UpdateArrow()

    header:SetScript("OnClick", function()
        groupEntry.expanded = not groupEntry.expanded
        UpdateArrow()
        LayoutSidebar()
    end)
    header:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.12, 0.12, 0.16, 1)
    end)
    header:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(0, 0, 0, 0)
    end)

    f._currentGroup = name
end

local function EndCollapsibleGroup()
    local f = mainFrame
    f._currentGroup = nil
end

-- ============================================================
-- Tab: LFG Quick Apply
-- ============================================================
local function CreateLFGTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(800)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("LFG")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Enhancements for the Premade Groups finder.|r")

    -- ===== Quick Apply Section =====
    local quickApplyCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    quickApplyCB:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    quickApplyCB.Text:SetText("Enable Quick Apply")
    quickApplyCB.tooltipText = "Single-click a group in the LFG tool to instantly apply instead of the normal multi-step process."

    quickApplyCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.lfg.quickApply = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local quickApplyHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    quickApplyHint:SetPoint("TOPLEFT", quickApplyCB, "BOTTOMLEFT", 22, -4)
    quickApplyHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    quickApplyHint:SetJustifyH("LEFT")
    quickApplyHint:SetText("|cff888888Click a group to auto-apply. Also auto-confirms the application dialog.|r")

    -- ===== Auto Confirm Role =====
    local autoRoleCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    autoRoleCB:SetPoint("TOPLEFT", quickApplyHint, "BOTTOMLEFT", -22, -12)
    autoRoleCB.Text:SetText("Auto-confirm role check")
    autoRoleCB.tooltipText = "Automatically accept the role confirmation popup when invited to a group."

    autoRoleCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.lfg.autoConfirmRole = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    -- ===== Auto Accept Role Check =====
    local autoRoleCheckCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    autoRoleCheckCB:SetPoint("TOPLEFT", autoRoleCB, "BOTTOMLEFT", 0, -12)
    autoRoleCheckCB.Text:SetText("Auto-accept role checks")
    autoRoleCheckCB.tooltipText = "Automatically accept the role check popup when someone in your group queues for a dungeon, raid, or battleground."

    autoRoleCheckCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.lfg.autoAcceptRoleCheck = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    panel:SetScript("OnShow", function()
        if Wild.db and Wild.db.lfg then
            local cfg = Wild.db.lfg
            quickApplyCB:SetChecked(cfg.quickApply)
            autoRoleCB:SetChecked(cfg.autoConfirmRole)
            autoRoleCheckCB:SetChecked(cfg.autoAcceptRoleCheck)
        end
    end)

    return panel
end

-- ============================================================
-- Tab: Screen Center Circle
-- ============================================================
local function CreateCircleTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(800)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Screen Center Circle")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("|cff888888Draws a circle at the center of the screen to show your character position.|r")

    local circleCheckbox = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    circleCheckbox:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    circleCheckbox.Text:SetText("Enable Center Circle")
    circleCheckbox.tooltipText = "Show a circle at the center of the screen."

    circleCheckbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.screenCenterCircle = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if Wild.UpdateScreenCenterCircle then Wild.UpdateScreenCenterCircle() end
    end)

    -- Size slider
    local sizeLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sizeLabel:SetPoint("TOPLEFT", circleCheckbox, "BOTTOMLEFT", 2, -12)
    sizeLabel:SetText("Size")

    local sizeSlider = CreateFrame("Slider", nil, sc, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -4)
    sizeSlider:SetMinMaxValues(1, 200)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    sizeSlider:SetWidth(200)
    sizeSlider.Low:SetText("1")
    sizeSlider.High:SetText("200")

    sizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        Wild.db.screenCenterCircleSize = value
        if Wild.UpdateScreenCenterCircle then Wild.UpdateScreenCenterCircle() end
    end)

    -- Custom editbox: allows values beyond the slider range
    local sizeEditBox = CreateFrame("EditBox", nil, sc, "InputBoxTemplate")
    sizeEditBox:SetSize(50, 20)
    sizeEditBox:SetPoint("LEFT", sizeSlider, "RIGHT", 16, 0)
    sizeEditBox:SetAutoFocus(false)
    sizeEditBox:SetNumeric(false)
    sizeEditBox:SetMaxLetters(6)
    sizeEditBox:SetFontObject("GameFontHighlightSmall")

    local function ApplySizeValue()
        local num = tonumber(sizeEditBox:GetText())
        if num and num >= 1 then
            num = math.floor(num + 0.5)
            Wild.db.screenCenterCircleSize = num
            -- Clamp slider visual to its range without overwriting the db value
            sizeSlider:SetValue(math.min(num, 200))
            if Wild.UpdateScreenCenterCircle then Wild.UpdateScreenCenterCircle() end
        end
        sizeEditBox:ClearFocus()
    end

    sizeEditBox:SetScript("OnEnterPressed", ApplySizeValue)
    sizeEditBox:SetScript("OnEditFocusLost", ApplySizeValue)

    sizeSlider:HookScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        -- Only update text if slider matches db (avoid overwriting custom large values)
        if Wild.db.screenCenterCircleSize and value == math.min(Wild.db.screenCenterCircleSize, 200) then
            sizeEditBox:SetText(tostring(Wild.db.screenCenterCircleSize))
        else
            sizeEditBox:SetText(tostring(value))
        end
    end)

    -- Thickness slider
    local thicknessLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    thicknessLabel:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -20)
    thicknessLabel:SetText("Thickness")

    local thicknessSlider = CreateFrame("Slider", nil, sc, "OptionsSliderTemplate")
    thicknessSlider:SetPoint("TOPLEFT", thicknessLabel, "BOTTOMLEFT", 0, -4)
    thicknessSlider:SetMinMaxValues(1, 50)
    thicknessSlider:SetValueStep(1)
    thicknessSlider:SetObeyStepOnDrag(true)
    thicknessSlider:SetWidth(200)
    thicknessSlider.Low:SetText("1")
    thicknessSlider.High:SetText("50")

    thicknessSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        Wild.db.screenCenterCircleThickness = value
        if Wild.UpdateScreenCenterCircle then Wild.UpdateScreenCenterCircle() end
    end)

    local thicknessEditBox = CreateSliderEditBox(sc, thicknessSlider, 1, 50, true)

    -- Opacity slider
    local opacityLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    opacityLabel:SetPoint("TOPLEFT", thicknessSlider, "BOTTOMLEFT", 0, -20)
    opacityLabel:SetText("Opacity")

    local opacitySlider = CreateFrame("Slider", nil, sc, "OptionsSliderTemplate")
    opacitySlider:SetPoint("TOPLEFT", opacityLabel, "BOTTOMLEFT", 0, -4)
    opacitySlider:SetMinMaxValues(10, 100)
    opacitySlider:SetValueStep(1)
    opacitySlider:SetObeyStepOnDrag(true)
    opacitySlider:SetWidth(200)
    opacitySlider.Low:SetText("10%")
    opacitySlider.High:SetText("100%")

    opacitySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        Wild.db.screenCenterCircleColor.a = value / 100
        if Wild.UpdateScreenCenterCircle then Wild.UpdateScreenCenterCircle() end
    end)

    local opacityEditBox = CreateSliderEditBox(sc, opacitySlider, 10, 100, true)

    -- Color picker
    local colorBtn = CreateFrame("Button", nil, sc)
    colorBtn:SetSize(24, 24)
    colorBtn:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", 0, -20)

    local colorSwatch = colorBtn:CreateTexture(nil, "ARTWORK")
    colorSwatch:SetAllPoints()
    colorSwatch:SetColorTexture(1, 1, 1)

    local colorBorder = colorBtn:CreateTexture(nil, "BORDER")
    colorBorder:SetPoint("TOPLEFT", -1, 1)
    colorBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    colorBorder:SetColorTexture(0.3, 0.3, 0.3)

    local colorLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    colorLabel:SetPoint("LEFT", colorBtn, "RIGHT", 8, 0)
    colorLabel:SetText("Circle Color")

    local function UpdateColorSwatch()
        local c = Wild.db.screenCenterCircleColor
        colorSwatch:SetColorTexture(c.r, c.g, c.b)
    end

    colorBtn:SetScript("OnClick", function()
        local c = Wild.db.screenCenterCircleColor
        local info = {}
        info.r, info.g, info.b = c.r, c.g, c.b
        info.hasOpacity = false
        info.swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            Wild.db.screenCenterCircleColor.r = r
            Wild.db.screenCenterCircleColor.g = g
            Wild.db.screenCenterCircleColor.b = b
            UpdateColorSwatch()
            if Wild.UpdateScreenCenterCircle then Wild.UpdateScreenCenterCircle() end
        end
        info.cancelFunc = function(prev)
            Wild.db.screenCenterCircleColor.r = prev.r
            Wild.db.screenCenterCircleColor.g = prev.g
            Wild.db.screenCenterCircleColor.b = prev.b
            UpdateColorSwatch()
            if Wild.UpdateScreenCenterCircle then Wild.UpdateScreenCenterCircle() end
        end
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    -- X Offset slider
    local offsetXLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    offsetXLabel:SetPoint("TOPLEFT", colorBtn, "BOTTOMLEFT", 0, -20)
    offsetXLabel:SetText("X Offset")

    local offsetXSlider = CreateFrame("Slider", nil, sc, "OptionsSliderTemplate")
    offsetXSlider:SetPoint("TOPLEFT", offsetXLabel, "BOTTOMLEFT", 0, -4)
    offsetXSlider:SetMinMaxValues(-500, 500)
    offsetXSlider:SetValueStep(1)
    offsetXSlider:SetObeyStepOnDrag(true)
    offsetXSlider:SetWidth(200)
    offsetXSlider.Low:SetText("-500")
    offsetXSlider.High:SetText("500")

    offsetXSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        Wild.db.screenCenterCircleOffsetX = value
        if Wild.UpdateScreenCenterCircle then Wild.UpdateScreenCenterCircle() end
    end)

    local offsetXEditBox = CreateSliderEditBox(sc, offsetXSlider, -500, 500, true)

    -- Y Offset slider
    local offsetYLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    offsetYLabel:SetPoint("TOPLEFT", offsetXSlider, "BOTTOMLEFT", 0, -20)
    offsetYLabel:SetText("Y Offset")

    local offsetYSlider = CreateFrame("Slider", nil, sc, "OptionsSliderTemplate")
    offsetYSlider:SetPoint("TOPLEFT", offsetYLabel, "BOTTOMLEFT", 0, -4)
    offsetYSlider:SetMinMaxValues(-500, 500)
    offsetYSlider:SetValueStep(1)
    offsetYSlider:SetObeyStepOnDrag(true)
    offsetYSlider:SetWidth(200)
    offsetYSlider.Low:SetText("-500")
    offsetYSlider.High:SetText("500")

    offsetYSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        Wild.db.screenCenterCircleOffsetY = value
        if Wild.UpdateScreenCenterCircle then Wild.UpdateScreenCenterCircle() end
    end)

    local offsetYEditBox = CreateSliderEditBox(sc, offsetYSlider, -500, 500, true)

    panel:SetScript("OnShow", function()
        if Wild.db then
            circleCheckbox:SetChecked(Wild.db.screenCenterCircle)
            local size = Wild.db.screenCenterCircleSize or 40
            sizeSlider:SetValue(math.min(size, 200))
            sizeEditBox:SetText(tostring(size))
            thicknessSlider:SetValue(Wild.db.screenCenterCircleThickness or 2)
            local opacityVal = math.floor((Wild.db.screenCenterCircleColor.a or 0.7) * 100 + 0.5)
            opacitySlider:SetValue(opacityVal)
            UpdateColorSwatch()
            offsetXSlider:SetValue(Wild.db.screenCenterCircleOffsetX or 0)
            offsetYSlider:SetValue(Wild.db.screenCenterCircleOffsetY or 0)
        end
    end)

    return panel
end

-- ============================================================
-- Bank Tabs (Character, Warband, Guild) - shared rule editor
-- ============================================================

local QUALITY_COLORS = {
    [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00",
    [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000",
}
local QUALITY_NAMES = {
    [0] = "Poor", [1] = "Common", [2] = "Uncommon",
    [3] = "Rare", [4] = "Epic", [5] = "Legendary",
}

local function GetItemClassList()
    local classes = {}
    for classID = 0, 20 do
        local name = GetItemClassInfo(classID)
        if name and name ~= "" then
            table.insert(classes, { classID = classID, name = name })
        end
    end
    return classes
end

local function GetItemSubClassList(classID)
    local subs = {}
    if not classID or classID < 0 then return subs end
    for subID = 0, 30 do
        local name = GetItemSubClassInfo(classID, subID)
        if name and name ~= "" then
            table.insert(subs, { subclassID = subID, name = name })
        end
    end
    return subs
end

-- ============================================================
-- Tab: Character (Reputation + Currency combined)
-- ============================================================
local function CreateCharacterTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(1600)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    -- =========================================
    -- Section: Reputation
    -- =========================================
    local repTitle = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    repTitle:SetPoint("TOPLEFT", 16, -16)
    repTitle:SetText("Reputation")

    local repDesc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    repDesc:SetPoint("TOPLEFT", repTitle, "BOTTOMLEFT", 0, -8)
    repDesc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    repDesc:SetJustifyH("LEFT")
    repDesc:SetText("|cff888888Manage how the reputation panel displays when opened.|r")

    local repModeLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    repModeLabel:SetPoint("TOPLEFT", repDesc, "BOTTOMLEFT", 0, -16)
    repModeLabel:SetText("Collapse mode:")

    local REP_MODES = {
        { text = "Off", value = "off", desc = "Do nothing — leave headers as they are." },
        { text = "Collapse All", value = "all", desc = "Collapse every expansion header." },
        { text = "Current Expansion Only", value = "current", desc = "Keep only the current expansion expanded, collapse the rest." },
        { text = "Remember My Settings", value = "remember", desc = "Save which headers you collapsed and restore them next time." },
    }

    local REP_MODE_DISPLAY = {}
    for _, m in ipairs(REP_MODES) do REP_MODE_DISPLAY[m.value] = m.text end

    local repModeDropdown = CreateFrame("Frame", "WildRepCollapseModeDD", sc, "UIDropDownMenuTemplate")
    repModeDropdown:SetPoint("LEFT", repModeLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(repModeDropdown, 200)

    UIDropDownMenu_Initialize(repModeDropdown, function(self, level)
        for _, opt in ipairs(REP_MODES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.func = function(btn)
                Wild.db.reputationCollapseMode = btn.value
                UIDropDownMenu_SetText(repModeDropdown, btn:GetText())
                CloseDropDownMenus()
            end
            info.checked = (Wild.db and Wild.db.reputationCollapseMode == opt.value)
            UIDropDownMenu_AddButton(info)
        end
    end)

    local repModeHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    repModeHint:SetPoint("TOPLEFT", repModeLabel, "BOTTOMLEFT", 0, -28)
    repModeHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    repModeHint:SetJustifyH("LEFT")
    repModeHint:SetText("|cff888888Controls how expansion headers collapse when you open the reputation panel.|r")

    -- =========================================
    -- Section: Currency
    -- =========================================
    local currSep = sc:CreateTexture(nil, "ARTWORK")
    currSep:SetHeight(1)
    currSep:SetPoint("TOPLEFT", repModeHint, "BOTTOMLEFT", 0, -24)
    currSep:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    currSep:SetColorTexture(0.3, 0.3, 0.35, 0.6)

    local currTitle = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    currTitle:SetPoint("TOPLEFT", currSep, "BOTTOMLEFT", 0, -16)
    currTitle:SetText("Currency")

    local currDesc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    currDesc:SetPoint("TOPLEFT", currTitle, "BOTTOMLEFT", 0, -8)
    currDesc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    currDesc:SetJustifyH("LEFT")
    currDesc:SetText("|cff888888View your currencies. Choose how expansion groups are displayed.|r")

    local currModeLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    currModeLabel:SetPoint("TOPLEFT", currDesc, "BOTTOMLEFT", 0, -16)
    currModeLabel:SetText("Collapse mode:")

    local CURR_MODES = {
        { text = "Off", value = "off", desc = "Show all groups expanded." },
        { text = "Collapse All", value = "all", desc = "Collapse every expansion group." },
        { text = "Current Expansion Only", value = "current", desc = "Keep only the current expansion expanded." },
        { text = "Remember My Settings", value = "remember", desc = "Restore headers exactly as you left them." },
    }

    local CURR_MODE_DISPLAY = {}
    for _, m in ipairs(CURR_MODES) do CURR_MODE_DISPLAY[m.value] = m.text end

    local currModeDropdown = CreateFrame("Frame", "WildCurrCollapseModeDD", sc, "UIDropDownMenuTemplate")
    currModeDropdown:SetPoint("LEFT", currModeLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(currModeDropdown, 200)

    -- Container for currency rows
    local listFrame = CreateFrame("Frame", nil, sc)
    listFrame:SetPoint("TOPLEFT", currModeLabel, "BOTTOMLEFT", 0, -36)
    listFrame:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    listFrame:SetHeight(1)

    local elements = {}

    local function ClearElements()
        for _, el in ipairs(elements) do
            el:Hide()
        end
    end

    local function GetOrCreateHeader(parent, index)
        local key = "h" .. index
        if elements[key] then return elements[key] end

        local row = CreateFrame("Button", nil, parent)
        row:SetHeight(24)
        row:SetPoint("LEFT", 0, 0)
        row:SetPoint("RIGHT", 0, 0)

        row.arrow = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.arrow:SetPoint("LEFT", 4, 0)
        row.arrow:SetWidth(16)

        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.label:SetPoint("LEFT", row.arrow, "RIGHT", 4, 0)
        row.label:SetJustifyH("LEFT")

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0.15, 0.15, 0.18, 0.6)

        elements[key] = row
        return row
    end

    local function GetOrCreateRow(parent, index)
        if elements[index] then return elements[index] end

        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(22)
        row:SetPoint("LEFT", 0, 0)
        row:SetPoint("RIGHT", 0, 0)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 20, 0)

        row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWidth(240)

        row.amount = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.amount:SetPoint("RIGHT", -8, 0)
        row.amount:SetJustifyH("RIGHT")

        elements[index] = row
        return row
    end

    local currentGroups

    local function RefreshList()
        ClearElements()

        local mode = (Wild.db and Wild.db.currencyCollapseMode) or "off"
        local groups = Wild.GetGroupedCurrencies(mode)
        currentGroups = groups

        local yOffset = 0
        local elemIdx = 0
        local headerIdx = 0

        for gi, group in ipairs(groups) do
            headerIdx = headerIdx + 1
            local header = GetOrCreateHeader(listFrame, headerIdx)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, yOffset)
            header.arrow:SetText(group.collapsed and "+" or "\226\128\147")
            header.label:SetText(group.headerName)
            header:SetScript("OnClick", function()
                group.collapsed = not group.collapsed
                RefreshList()
            end)
            header:Show()
            yOffset = yOffset - 24

            if not group.collapsed then
                for _, cur in ipairs(group.currencies) do
                    elemIdx = elemIdx + 1
                    local row = GetOrCreateRow(listFrame, elemIdx)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, yOffset)

                    if cur.iconFileID then
                        row.icon:SetTexture(cur.iconFileID)
                        row.icon:Show()
                    else
                        row.icon:Hide()
                    end

                    row.name:SetText(cur.name or "???")

                    local qtyText = tostring(cur.quantity or 0)
                    if cur.maxQuantity and cur.maxQuantity > 0 then
                        qtyText = qtyText .. " / " .. cur.maxQuantity
                    end
                    row.amount:SetText(qtyText)

                    row:Show()
                    yOffset = yOffset - 22
                end
            end
        end

        listFrame:SetHeight(math.max(1, -yOffset))
        sc:SetHeight(math.max(1600, 500 + (-yOffset)))
    end

    UIDropDownMenu_Initialize(currModeDropdown, function(self, level)
        for _, opt in ipairs(CURR_MODES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.func = function(btn)
                Wild.db.currencyCollapseMode = btn.value
                UIDropDownMenu_SetText(currModeDropdown, btn:GetText())
                CloseDropDownMenus()
                RefreshList()
            end
            info.checked = (Wild.db and Wild.db.currencyCollapseMode == opt.value)
            UIDropDownMenu_AddButton(info)
        end
    end)

    panel:SetScript("OnShow", function()
        if Wild.db then
            UIDropDownMenu_SetText(repModeDropdown, REP_MODE_DISPLAY[Wild.db.reputationCollapseMode] or "Off")
            UIDropDownMenu_SetText(currModeDropdown, CURR_MODE_DISPLAY[Wild.db.currencyCollapseMode] or "Off")
        end
        RefreshList()
    end)

    panel:SetScript("OnHide", function()
        if Wild.db and Wild.db.currencyCollapseMode == "remember" and currentGroups then
            Wild.SaveCurrencyCollapseState(currentGroups)
        end
    end)

    return panel
end

-- ============================================================
-- Tab: Auction House
-- ============================================================

local function CreateAuctionHouseTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(800)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Auction House")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Configure default filters applied every time the Auction House opens.|r")

    -- Enable checkbox
    local enableCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    enableCB.Text:SetText("Enable default Auction House filters")
    enableCB.tooltipText = "Automatically apply the selected filters whenever you open the Auction House."

    enableCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.auctionHouse.enabled = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    -- Filter list: enum key, display label (enum resolved lazily since AH UI loads on demand)
    local filterDefs = {
        { key = "UncollectedOnly",     label = "Uncollected Only" },
        { key = "UsableOnly",          label = "Usable Only" },
        { key = "CurrentExpansionOnly", label = "Current Expansion Only" },
        { section = "Equipment" },
        { key = "UpgradesOnly",        label = "Upgrades Only" },
        { section = "Rarity" },
        { key = "PoorQuality",         label = "|cff9d9d9dPoor|r Quality" },
        { key = "CommonQuality",       label = "|cffffffffCommon|r Quality" },
        { key = "UncommonQuality",     label = "|cff1eff00Uncommon|r Quality" },
        { key = "RareQuality",         label = "|cff0070ddRare|r Quality" },
        { key = "EpicQuality",         label = "|cffa335eeEpic|r Quality" },
        { key = "LegendaryQuality",    label = "|cffff8000Legendary|r Quality" },
        { key = "ArtifactQuality",     label = "|cffe6cc80Artifact|r Quality" },
    }

    local filterHeader = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    filterHeader:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 2, -16)
    filterHeader:SetText("Default Filters")

    -- Level range (positioned first, matching Blizzard AH layout)
    local levelHeader = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local levelDesc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    local minLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    local minBox = CreateFrame("EditBox", nil, sc, "InputBoxTemplate")
    local maxLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    local maxBox = CreateFrame("EditBox", nil, sc, "InputBoxTemplate")

    levelHeader:SetPoint("TOPLEFT", filterHeader, "BOTTOMLEFT", 0, -12)
    levelHeader:SetText("Level Range")
    levelDesc:SetPoint("TOPLEFT", levelHeader, "BOTTOMLEFT", 0, -4)
    levelDesc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    levelDesc:SetJustifyH("LEFT")
    levelDesc:SetText("|cff888888Set minimum and maximum item level. Leave at 0 to ignore.|r")
    minLabel:SetText("Min Level:")
    minLabel:SetPoint("TOPLEFT", levelDesc, "BOTTOMLEFT", 0, -10)
    minBox:SetSize(60, 20)
    minBox:SetPoint("LEFT", minLabel, "RIGHT", 8, 0)
    minBox:SetAutoFocus(false)
    minBox:SetNumeric(true)
    minBox:SetMaxLetters(4)
    minBox:SetScript("OnEnterPressed", function(self)
        Wild.db.auctionHouse.minLevel = tonumber(self:GetText()) or 0
        self:ClearFocus()
    end)
    minBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    maxLabel:SetText("Max Level:")
    maxLabel:SetPoint("LEFT", minBox, "RIGHT", 20, 0)
    maxBox:SetSize(60, 20)
    maxBox:SetPoint("LEFT", maxLabel, "RIGHT", 8, 0)
    maxBox:SetAutoFocus(false)
    maxBox:SetNumeric(true)
    maxBox:SetMaxLetters(4)
    maxBox:SetScript("OnEnterPressed", function(self)
        Wild.db.auctionHouse.maxLevel = tonumber(self:GetText()) or 0
        self:ClearFocus()
    end)
    maxBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Checkboxes are created lazily on first show because Enum.AuctionHouseFilter
    -- may not exist until Blizzard_AuctionHouseUI is loaded.
    local filterCBs = {}
    local filtersBuilt = false

    local function BuildFilterCheckboxes()
        if filtersBuilt then return end
        filtersBuilt = true

        local ahEnum = Enum and Enum.AuctionHouseFilter
        local lastAnchor = minLabel
        local lastType = "levelrange"
        for _, def in ipairs(filterDefs) do
            if def.section then
                local sectionHdr = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                sectionHdr:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", lastType == "cb" and 2 or 0, -16)
                sectionHdr:SetText(def.section)
                lastAnchor = sectionHdr
                lastType = "header"
            else
                local enumVal = ahEnum and ahEnum[def.key]
                if enumVal then
                    local cb = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
                    local xOff = (lastType == "header" or lastType == "levelrange") and -2 or 0
                    local yOff = lastType == "levelrange" and -16 or -4
                    cb:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", xOff, yOff)
                    cb.Text:SetText(def.label)
                    cb.enumVal = enumVal
                    cb:SetScript("OnClick", function(self)
                        local checked = self:GetChecked()
                        Wild.db.auctionHouse.filters[self.enumVal] = checked
                        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
                    end)
                    filterCBs[#filterCBs + 1] = cb
                    lastAnchor = cb
                    lastType = "cb"
                end
            end
        end

        if #filterCBs == 0 then
            local noEnum = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            noEnum:SetPoint("TOPLEFT", minLabel, "BOTTOMLEFT", 0, -8)
            noEnum:SetText("|cffff8888Auction House filters are not yet available. Open the AH once first.|r")
        end
    end

    -- OnShow: build checkboxes lazily, then sync UI with saved data
    panel:SetScript("OnShow", function()
        BuildFilterCheckboxes()
        if not Wild.db then return end
        local cfg = Wild.db.auctionHouse
        enableCB:SetChecked(cfg.enabled)
        for _, cb in ipairs(filterCBs) do
            cb:SetChecked(cfg.filters[cb.enumVal] and true or false)
        end
        minBox:SetText(tostring(cfg.minLevel or 0))
        maxBox:SetText(tostring(cfg.maxLevel or 0))
    end)

    return panel
end

-- ============================================================
-- Tab: Mail
-- ============================================================
local function CreateMailTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(800)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Mail")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Configure mail automation.|r")

    local autoOpenCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    autoOpenCB:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    autoOpenCB.Text:SetText("Auto-open all mail")
    autoOpenCB.tooltipText = "Automatically collect all mail items when you open the mailbox."

    autoOpenCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.mail.autoOpen = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local hint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", autoOpenCB, "BOTTOMLEFT", 22, -4)
    hint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("|cff888888When the mailbox is opened, all mail attachments and gold are automatically collected one by one.|r")

    panel:SetScript("OnShow", function()
        if Wild.db then
            autoOpenCB:SetChecked(Wild.db.mail.autoOpen)
        end
    end)

    return panel
end

-- ============================================================
-- Tab: Inventory (Auto-Destroy)
-- ============================================================
local function CreateInventoryTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(1200)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Inventory")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Automate inventory management. Auto-destroy matching items and simplify the destroy confirmation.|r")

    -- Enable auto-destroy
    local destroyCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    destroyCB:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    destroyCB.Text:SetText("Enable auto-destroy")
    destroyCB.tooltipText = "Automatically destroy items matching your filter rules."

    destroyCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.inventory.destroyEnabled = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local destroyWarn = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    destroyWarn:SetPoint("TOPLEFT", destroyCB, "BOTTOMLEFT", 22, -4)
    destroyWarn:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    destroyWarn:SetJustifyH("LEFT")
    destroyWarn:SetText("|cffff6600Warning:|r Items destroyed this way are |cffff4444permanently deleted|r. Double-check your rules before enabling.")

    -- Triggers section
    local trigSep = sc:CreateTexture(nil, "ARTWORK")
    trigSep:SetHeight(1)
    trigSep:SetPoint("TOPLEFT", destroyWarn, "BOTTOMLEFT", -22, -16)
    trigSep:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    trigSep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    local trigHeader = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    trigHeader:SetPoint("TOPLEFT", trigSep, "BOTTOMLEFT", 0, -12)
    trigHeader:SetText("Triggers")

    local trigDesc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    trigDesc:SetPoint("TOPLEFT", trigHeader, "BOTTOMLEFT", 0, -4)
    trigDesc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    trigDesc:SetJustifyH("LEFT")
    trigDesc:SetText("|cff888888Choose when auto-destroy should run. At least one trigger must be enabled.|r")

    local trigLootCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    trigLootCB:SetPoint("TOPLEFT", trigDesc, "BOTTOMLEFT", -2, -10)
    trigLootCB.Text:SetText("After looting")
    trigLootCB.tooltipText = "Run auto-destroy after the loot window closes."

    trigLootCB:SetScript("OnClick", function(self)
        Wild.db.inventory.destroyTriggers.onLoot = self:GetChecked()
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local trigVendorCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    trigVendorCB:SetPoint("TOPLEFT", trigLootCB, "BOTTOMLEFT", 0, -4)
    trigVendorCB.Text:SetText("When opening a vendor")
    trigVendorCB.tooltipText = "Run auto-destroy when you open a merchant window."

    trigVendorCB:SetScript("OnClick", function(self)
        Wild.db.inventory.destroyTriggers.onVendor = self:GetChecked()
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local trigBankCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    trigBankCB:SetPoint("TOPLEFT", trigVendorCB, "BOTTOMLEFT", 0, -4)
    trigBankCB.Text:SetText("When opening a bank")
    trigBankCB.tooltipText = "Run auto-destroy when opening any bank (character, warband, or guild)."

    trigBankCB:SetScript("OnClick", function(self)
        Wild.db.inventory.destroyTriggers.onBank = self:GetChecked()
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    -- ===== Info =====
    local infoSep = sc:CreateTexture(nil, "ARTWORK")
    infoSep:SetHeight(1)
    infoSep:SetPoint("TOPLEFT", trigBankCB, "BOTTOMLEFT", 2, -16)
    infoSep:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    infoSep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    local infoText = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", infoSep, "BOTTOMLEFT", 0, -12)
    infoText:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("|cff888888Destroy rules are managed in the Intent Rules tab. Create an intent with action 'Destroy' to auto-destroy items.|r")

    panel:SetScript("OnShow", function()
        if Wild.db and Wild.db.inventory then
            local cfg = Wild.db.inventory
            destroyCB:SetChecked(cfg.destroyEnabled)
            trigLootCB:SetChecked(cfg.destroyTriggers and cfg.destroyTriggers.onLoot)
            trigVendorCB:SetChecked(cfg.destroyTriggers and cfg.destroyTriggers.onVendor)
            trigBankCB:SetChecked(cfg.destroyTriggers and cfg.destroyTriggers.onBank)
        end
    end)

    return panel
end
-- ============================================================
-- Tab: Tooltips
-- ============================================================
local function CreateTooltipTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(800)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Tooltips")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Add extra information lines to item tooltips. Choose when each line appears.|r")

    local enableCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    enableCB.Text:SetText("Enable tooltip enhancements")
    enableCB.tooltipText = "Show additional item information in tooltips based on the rules below."

    enableCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.tooltip.enabled = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    -- Line configuration
    local linesSep = sc:CreateTexture(nil, "ARTWORK")
    linesSep:SetHeight(1)
    linesSep:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 2, -16)
    linesSep:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    linesSep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    local linesHeader = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    linesHeader:SetPoint("TOPLEFT", linesSep, "BOTTOMLEFT", 0, -12)
    linesHeader:SetText("Tooltip Lines")

    local linesDesc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    linesDesc:SetPoint("TOPLEFT", linesHeader, "BOTTOMLEFT", 0, -4)
    linesDesc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    linesDesc:SetJustifyH("LEFT")
    linesDesc:SetText("|cff888888For each line, choose when it should appear on item tooltips.|r")

    -- Build visibility mode labels lookup
    local modeLabels = {}
    for _, mode in ipairs(Wild.TOOLTIP_VISIBILITY_MODES) do
        modeLabels[mode.key] = mode.label
    end

    -- Create one row per tooltip line
    local lineRows = {}
    local anchor = linesDesc

    for idx, lineDef in ipairs(Wild.TOOLTIP_LINES) do
        local row = CreateFrame("Frame", nil, sc)
        row:SetHeight(30)
        row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", idx == 1 and 0 or 0, idx == 1 and -12 or -4)
        row:SetPoint("RIGHT", sc, "RIGHT", -16, 0)

        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetWidth(160)
        row.label:SetJustifyH("LEFT")
        row.label:SetText(lineDef.label)

        local ddName = "WildTooltipLineDD_" .. lineDef.key
        row.dropdown = CreateFrame("Frame", ddName, row, "UIDropDownMenuTemplate")
        row.dropdown:SetPoint("LEFT", row.label, "RIGHT", -8, -2)
        UIDropDownMenu_SetWidth(row.dropdown, 160)

        local currentKey = lineDef.key
        UIDropDownMenu_Initialize(row.dropdown, function(self, level)
            for _, mode in ipairs(Wild.TOOLTIP_VISIBILITY_MODES) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = mode.label
                info.value = mode.key
                info.func = function(btn)
                    if Wild.db and Wild.db.tooltip and Wild.db.tooltip.lines then
                        Wild.db.tooltip.lines[currentKey] = btn.value
                    end
                    UIDropDownMenu_SetText(row.dropdown, modeLabels[btn.value] or btn.value)
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)

        lineRows[idx] = row
        anchor = row
    end

    -- Preview hint
    local previewHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    previewHint:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    previewHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    previewHint:SetJustifyH("LEFT")
    previewHint:SetText(
        "|cff888888Visibility modes:|r\n" ..
        "|cffffffffAlways|r |cff888888\226\128\148 show on every item tooltip|r\n" ..
        "|cffffffffWild Settings Open|r |cff888888\226\128\148 only when this settings window is visible|r\n" ..
        "|cffffffffShift/Ctrl/Alt Held|r |cff888888\226\128\148 only while holding that modifier key|r\n" ..
        "|cffffffffNever|r |cff888888\226\128\148 line is disabled|r"
    )

    panel:SetScript("OnShow", function()
        if Wild.db and Wild.db.tooltip then
            enableCB:SetChecked(Wild.db.tooltip.enabled)
            local lines = Wild.db.tooltip.lines or {}
            for idx, lineDef in ipairs(Wild.TOOLTIP_LINES) do
                local row = lineRows[idx]
                if row then
                    local mode = lines[lineDef.key] or "never"
                    UIDropDownMenu_SetText(row.dropdown, modeLabels[mode] or mode)
                end
            end
        end
    end)

    return panel
end

-- ============================================================
-- Tab: Auto-Reply
-- ============================================================
local function CreateAutoReplyTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(800)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Auto-Reply")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Automatically reply to whispers while running Mythic+ keystones.|r")

    -- Enable checkbox
    local enableCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    enableCB.Text:SetText("Enable auto-reply in Mythic+")
    enableCB.tooltipText = "Automatically send a reply to incoming whispers while you are in a Mythic+ keystone."
    enableCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.autoReply.enabled = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local enableHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    enableHint:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 22, -4)
    enableHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    enableHint:SetJustifyH("LEFT")
    enableHint:SetText("|cff888888Sends your custom message once per person (60s cooldown) so they know you're busy.|r")

    -- Reply to whispers
    local whisperCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    whisperCB:SetPoint("TOPLEFT", enableHint, "BOTTOMLEFT", -22, -10)
    whisperCB.Text:SetText("Reply to in-game whispers")
    whisperCB.tooltipText = "Auto-reply to standard /whisper messages."
    whisperCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.autoReply.replyWhispers = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    -- Reply to BNet whispers
    local bnetCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    bnetCB:SetPoint("TOPLEFT", whisperCB, "BOTTOMLEFT", 0, -4)
    bnetCB.Text:SetText("Reply to Battle.net whispers")
    bnetCB.tooltipText = "Auto-reply to Battle.net (Real ID / BattleTag) whisper messages."
    bnetCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.autoReply.replyBNetWhispers = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    -- Only while key timer is running
    local inProgressCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    inProgressCB:SetPoint("TOPLEFT", bnetCB, "BOTTOMLEFT", 0, -4)
    inProgressCB.Text:SetText("Only while key timer is running")
    inProgressCB.tooltipText = "Only auto-reply when the Mythic+ timer is actively running. Disabling this will also reply during downtime inside the instance (e.g. before starting or after completion)."
    inProgressCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.autoReply.onlyInProgress = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local inProgressHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    inProgressHint:SetPoint("TOPLEFT", inProgressCB, "BOTTOMLEFT", 22, -4)
    inProgressHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    inProgressHint:SetJustifyH("LEFT")
    inProgressHint:SetText("|cff888888When enabled, auto-reply only fires while the keystone timer is actively counting down. Turn off to also reply during pre-key and post-key time inside the instance.|r")

    -- Message text
    local sep = sc:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", inProgressHint, "BOTTOMLEFT", -22, -16)
    sep:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    local msgHeader = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    msgHeader:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -12)
    msgHeader:SetText("Reply Message")

    local msgDesc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    msgDesc:SetPoint("TOPLEFT", msgHeader, "BOTTOMLEFT", 0, -4)
    msgDesc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    msgDesc:SetJustifyH("LEFT")
    msgDesc:SetText("|cff888888The message sent to people who whisper you during a key.|r")

    local msgBox = CreateFrame("EditBox", nil, sc, "BackdropTemplate")
    msgBox:SetPoint("TOPLEFT", msgDesc, "BOTTOMLEFT", 0, -8)
    msgBox:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    msgBox:SetHeight(50)
    msgBox:SetMultiLine(true)
    msgBox:SetAutoFocus(false)
    msgBox:SetMaxLetters(255)
    msgBox:SetFontObject("GameFontHighlightSmall")
    msgBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    msgBox:SetBackdropColor(0.12, 0.12, 0.14, 1)
    msgBox:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    msgBox:SetTextInsets(8, 8, 6, 6)

    msgBox:SetScript("OnEditFocusLost", function(self)
        local text = self:GetText()
        if text and #text > 0 then
            Wild.db.autoReply.message = text
        end
    end)
    msgBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local charCount = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    charCount:SetPoint("TOPRIGHT", msgBox, "BOTTOMRIGHT", 0, -2)
    charCount:SetJustifyH("RIGHT")
    msgBox:SetScript("OnTextChanged", function(self, userInput)
        local len = #self:GetText()
        charCount:SetText("|cff888888" .. len .. "/255|r")
    end)

    -- OnShow
    panel:SetScript("OnShow", function()
        if Wild.db and Wild.db.autoReply then
            local ar = Wild.db.autoReply
            enableCB:SetChecked(ar.enabled)
            whisperCB:SetChecked(ar.replyWhispers)
            bnetCB:SetChecked(ar.replyBNetWhispers)
            inProgressCB:SetChecked(ar.onlyInProgress)
            msgBox:SetText(ar.message or "")
            charCount:SetText("|cff888888" .. #(ar.message or "") .. "/255|r")
        end
    end)

    return panel
end

-- ============================================================
-- Tab: Dungeon Bar
-- ============================================================
local function CreateDungeonBarTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(800)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Dungeon Bar")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888A draggable bar with ready check, pull timers, and other M+ utilities. Toggle with |cffffffff/wbar|r.|r")

    local enableCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    enableCB.Text:SetText("Enable Dungeon Bar")
    enableCB.tooltipText = "Show the dungeon bar. You can also toggle it with /wbar."

    enableCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.dungeonBar.enabled = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if checked then
            Wild.ShowDungeonBar()
        else
            Wild.HideDungeonBar()
        end
    end)

    local autoShowCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    autoShowCB:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 20, -8)
    autoShowCB.Text:SetText("Auto-show in dungeons and raids")
    autoShowCB.tooltipText = "Automatically show the bar when entering a dungeon or raid instance, and hide it when leaving."

    autoShowCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.dungeonBar.autoShowInInstance = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local autoShowHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    autoShowHint:SetPoint("TOPLEFT", autoShowCB, "BOTTOMLEFT", 22, -4)
    autoShowHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    autoShowHint:SetJustifyH("LEFT")
    autoShowHint:SetText("|cff888888When enabled, the bar appears automatically inside party/raid instances and hides outside.|r")

    -- ===== Bar Element Visibility =====
    local visSep = sc:CreateTexture(nil, "ARTWORK")
    visSep:SetHeight(1)
    visSep:SetPoint("TOPLEFT", autoShowHint, "BOTTOMLEFT", -42, -16)
    visSep:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    visSep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    local visHeader = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    visHeader:SetPoint("TOPLEFT", visSep, "BOTTOMLEFT", 0, -12)
    visHeader:SetText("Bar Elements")

    local visDesc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    visDesc:SetPoint("TOPLEFT", visHeader, "BOTTOMLEFT", 0, -4)
    visDesc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    visDesc:SetJustifyH("LEFT")
    visDesc:SetText("|cff888888Choose which buttons appear on the dungeon bar.|r")

    local function BarToggle(key, default)
        return function(self)
            local checked = self:GetChecked()
            Wild.db.dungeonBar[key] = checked
            PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            Wild.RebuildDungeonBar()
        end
    end

    local showReadyCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    showReadyCB:SetPoint("TOPLEFT", visDesc, "BOTTOMLEFT", -2, -8)
    showReadyCB.Text:SetText("Show Ready Check button")
    showReadyCB.tooltipText = "Show the ready check button on the bar."
    showReadyCB:SetScript("OnClick", BarToggle("showReadyCheck"))

    local showCancelCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    showCancelCB:SetPoint("TOPLEFT", showReadyCB, "BOTTOMLEFT", 0, -4)
    showCancelCB.Text:SetText("Show Stop (cancel pull) button")
    showCancelCB.tooltipText = "Show the Stop button that cancels pull timers."
    showCancelCB:SetScript("OnClick", BarToggle("showCancelPull"))

    local showCustomCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    showCustomCB:SetPoint("TOPLEFT", showCancelCB, "BOTTOMLEFT", 0, -4)
    showCustomCB.Text:SetText("Show custom pull timer input")
    showCustomCB.tooltipText = "Show the free-form seconds input and go button on the bar."
    showCustomCB:SetScript("OnClick", BarToggle("showCustomPull"))

    local showDisbandCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    showDisbandCB:SetPoint("TOPLEFT", showCustomCB, "BOTTOMLEFT", 0, -4)
    showDisbandCB.Text:SetText("Show Disband button")
    showDisbandCB.tooltipText = "Show a button to disband the group or raid (requires leader or assistant)."
    showDisbandCB:SetScript("OnClick", BarToggle("showDisband"))

    local sep = sc:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", showDisbandCB, "BOTTOMLEFT", 0, -16)
    sep:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- ===== Pull Timer Presets =====
    local presetsHeader = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    presetsHeader:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -12)
    presetsHeader:SetText("Pull Timer Presets")

    local presetsDesc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    presetsDesc:SetPoint("TOPLEFT", presetsHeader, "BOTTOMLEFT", 0, -4)
    presetsDesc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    presetsDesc:SetJustifyH("LEFT")
    presetsDesc:SetText("|cff888888Each box becomes a quick-pull button on the bar (e.g. P3, P5). Set a value to 0 or clear it to remove that slot.|r")

    local presetBoxes = {}
    local presetRow = CreateFrame("Frame", nil, sc)
    presetRow:SetSize(500, 30)
    presetRow:SetPoint("TOPLEFT", presetsDesc, "BOTTOMLEFT", 0, -8)

    local function RebuildPresetBoxes()
        local presets = Wild.db.dungeonBar.pullPresets
        -- Clear old boxes
        for _, box in ipairs(presetBoxes) do
            box:Hide()
            box:SetParent(nil)
        end
        wipe(presetBoxes)

        for i, val in ipairs(presets) do
            local box = CreateFrame("EditBox", nil, presetRow, "InputBoxTemplate")
            box:SetSize(40, 22)
            box:SetAutoFocus(false)
            box:SetNumeric(true)
            box:SetMaxLetters(3)
            box:SetFontObject("GameFontHighlightSmall")
            box:SetJustifyH("CENTER")
            box:SetText(tostring(val))
            if i == 1 then
                box:SetPoint("LEFT", 0, 0)
            else
                box:SetPoint("LEFT", presetBoxes[i - 1], "RIGHT", 8, 0)
            end
            box.index = i
            box:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
            end)
            box:SetScript("OnEditFocusLost", function(self)
                local num = tonumber(self:GetText())
                if num and num > 0 and num <= 999 then
                    Wild.db.dungeonBar.pullPresets[self.index] = num
                    self:SetText(tostring(num))
                else
                    -- Remove this preset
                    table.remove(Wild.db.dungeonBar.pullPresets, self.index)
                    Wild.RebuildDungeonBar()
                    RebuildPresetBoxes()
                    return
                end
                Wild.RebuildDungeonBar()
            end)
            presetBoxes[i] = box
        end

        -- "+" button to add a new preset
        local addBtn = CreateFrame("Button", nil, presetRow, "BackdropTemplate")
        addBtn:SetSize(24, 22)
        addBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        addBtn:SetBackdropColor(0.15, 0.4, 0.25, 0.9)
        addBtn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
        addBtn.label = addBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        addBtn.label:SetPoint("CENTER")
        addBtn.label:SetText("|cffffffff+|r")
        if #presetBoxes > 0 then
            addBtn:SetPoint("LEFT", presetBoxes[#presetBoxes], "RIGHT", 8, 0)
        else
            addBtn:SetPoint("LEFT", 0, 0)
        end
        addBtn:SetScript("OnClick", function()
            table.insert(Wild.db.dungeonBar.pullPresets, 10)
            Wild.RebuildDungeonBar()
            RebuildPresetBoxes()
        end)
        addBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.6, 0.35, 1) end)
        addBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.4, 0.25, 0.9) end)
        -- Track it so we can clean it up
        table.insert(presetBoxes, addBtn)
    end

    local sep2 = sc:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT", presetRow, "BOTTOMLEFT", 0, -16)
    sep2:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    sep2:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    local tooltipHeader = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tooltipHeader:SetPoint("TOPLEFT", sep2, "BOTTOMLEFT", 0, -12)
    tooltipHeader:SetText("Misc")

    local showTooltipsCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    showTooltipsCB:SetPoint("TOPLEFT", tooltipHeader, "BOTTOMLEFT", -2, -8)
    showTooltipsCB.Text:SetText("Show tooltips on bar buttons")
    showTooltipsCB.tooltipText = "Display tooltip hints when hovering over dungeon bar buttons."
    showTooltipsCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.dungeonBar.showTooltips = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    panel:SetScript("OnShow", function()
        if Wild.db and Wild.db.dungeonBar then
            enableCB:SetChecked(Wild.db.dungeonBar.enabled)
            autoShowCB:SetChecked(Wild.db.dungeonBar.autoShowInInstance)
            showReadyCB:SetChecked(Wild.db.dungeonBar.showReadyCheck ~= false)
            showCancelCB:SetChecked(Wild.db.dungeonBar.showCancelPull ~= false)
            showCustomCB:SetChecked(Wild.db.dungeonBar.showCustomPull and true or false)
            showDisbandCB:SetChecked(Wild.db.dungeonBar.showDisband and true or false)
            showTooltipsCB:SetChecked(Wild.db.dungeonBar.showTooltips and true or false)
            RebuildPresetBoxes()
        end
    end)

    return panel
end

-- ============================================================
-- Tab: Quests
-- ============================================================
local function CreateQuestsTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(1000)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Quests")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Automate quest accept, hand-in, and reward selection.|r")

    -- helper: checkbox factory
    local function MakeCB(parent, anchor, anchorPt, xOff, yOff, label, tooltip, dbKey)
        local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", anchor, anchorPt, xOff, yOff)
        cb.Text:SetText(label)
        cb.tooltipText = tooltip
        cb:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            Wild.db.quests[dbKey] = checked
            PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end)
        return cb
    end

    -- helper: hint text factory
    local function MakeHint(parent, anchor, text)
        local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 22, -4)
        hint:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
        hint:SetJustifyH("LEFT")
        hint:SetText("|cff888888" .. text .. "|r")
        return hint
    end

    -- helper: section header with line
    local function MakeHeader(parent, anchor, text)
        local hdr = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
        hdr:SetText(text)
        local line = parent:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetColorTexture(0.4, 0.4, 0.4, 0.6)
        line:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -4)
        line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
        return hdr, line
    end

    -- ================================================================
    -- SECTION 1: Auto-Accept
    -- ================================================================
    local secAcceptHdr, secAcceptLine = MakeHeader(sc, desc, "Auto-Accept")

    local autoAcceptCB = MakeCB(sc, secAcceptLine, "BOTTOMLEFT", -2, -10,
        "Enable auto-accept", "Automatically accept quests when talking to an NPC.", "autoAccept")
    local autoAcceptHint = MakeHint(sc, autoAcceptCB, "Quests are accepted immediately when the quest detail window opens. Use the checkboxes below to control which quest types are accepted.")

    -- Quest type checkboxes (indented under auto-accept)
    local acceptNormalCB = MakeCB(sc, autoAcceptHint, "BOTTOMLEFT", -2, -10,
        "Normal quests", "Accept regular one-time story and side quests.", "acceptNormal")
    local acceptDailyCB = MakeCB(sc, acceptNormalCB, "BOTTOMLEFT", 0, -4,
        "Daily quests", "Accept daily quests (blue ! markers).", "acceptDaily")
    local acceptWeeklyCB = MakeCB(sc, acceptDailyCB, "BOTTOMLEFT", 0, -4,
        "Weekly quests", "Accept weekly quests.", "acceptWeekly")
    local acceptRepeatableCB = MakeCB(sc, acceptWeeklyCB, "BOTTOMLEFT", 0, -4,
        "Repeatable quests", "Accept infinitely repeatable quests.", "acceptRepeatable")
    local acceptTrivialCB = MakeCB(sc, acceptRepeatableCB, "BOTTOMLEFT", 0, -4,
        "Trivial (grey) quests", "Accept low-level quests that appear grey. Usually gives negligible XP.", "acceptTrivial")

    -- Toggle key dropdown
    local TOGGLE_OPTIONS = { NONE_KEY, ALT_KEY, CTRL_KEY, SHIFT_KEY }
    local toggleLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    toggleLabel:SetPoint("TOPLEFT", acceptTrivialCB, "BOTTOMLEFT", 2, -14)
    toggleLabel:SetText("Pause key:")

    local toggleDropdown = CreateFrame("Frame", "WildQuestToggleDD", sc, "UIDropDownMenuTemplate")
    toggleDropdown:SetPoint("LEFT", toggleLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(toggleDropdown, 140)

    UIDropDownMenu_Initialize(toggleDropdown, function(self, level)
        for i, text in ipairs(TOGGLE_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = i
            info.func = function(btn)
                Wild.db.quests.toggleKey = btn.value
                UIDropDownMenu_SetText(toggleDropdown, btn:GetText())
                CloseDropDownMenus()
            end
            info.checked = (Wild.db.quests.toggleKey == i)
            UIDropDownMenu_AddButton(info)
        end
    end)

    local toggleHint = MakeHint(sc, toggleLabel, "Hold this key while interacting with an NPC to temporarily pause all quest automation.")
    toggleHint:ClearAllPoints()
    toggleHint:SetPoint("TOPLEFT", toggleLabel, "BOTTOMLEFT", 0, -26)
    toggleHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)

    -- ================================================================
    -- SECTION 2: Auto-Hand-In
    -- ================================================================
    local secHandInHdr, secHandInLine = MakeHeader(sc, toggleHint, "Auto-Hand-In")

    local autoHandInCB = MakeCB(sc, secHandInLine, "BOTTOMLEFT", -2, -10,
        "Enable auto-hand-in", "Automatically complete and hand in quests when objectives are done.", "autoHandIn")
    local autoHandInHint = MakeHint(sc, autoHandInCB, "Clicks Continue and Complete automatically when talking to an NPC with a finished quest.")

    local autoRewardCB = MakeCB(sc, autoHandInHint, "BOTTOMLEFT", -2, -10,
        "Auto-select best reward", "When a quest offers multiple reward choices, automatically pick the one with the highest vendor sell price.", "autoSelectReward")
    local autoRewardHint = MakeHint(sc, autoRewardCB, "Selects the reward with the highest vendor value. If disabled, the quest completion window stays open for manual choice.")

    -- ================================================================
    -- OnShow: sync checkboxes to saved state
    -- ================================================================
    panel:SetScript("OnShow", function()
        if Wild.db and Wild.db.quests then
            local q = Wild.db.quests
            autoAcceptCB:SetChecked(q.autoAccept)
            acceptNormalCB:SetChecked(q.acceptNormal)
            acceptDailyCB:SetChecked(q.acceptDaily)
            acceptWeeklyCB:SetChecked(q.acceptWeekly)
            acceptRepeatableCB:SetChecked(q.acceptRepeatable)
            acceptTrivialCB:SetChecked(q.acceptTrivial)
            UIDropDownMenu_SetText(toggleDropdown, TOGGLE_OPTIONS[q.toggleKey or 1])
            autoHandInCB:SetChecked(q.autoHandIn)
            autoRewardCB:SetChecked(q.autoSelectReward)
        end
    end)

    return panel
end

-- ============================================================
-- Tab: Gossip
-- ============================================================
local function CreateGossipTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(800)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Gossip")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Automate NPC gossip dialog interactions.|r")

    -- Auto-select single gossip option
    local autoSelectCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    autoSelectCB:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    autoSelectCB.Text:SetText("Auto-select single gossip option")
    autoSelectCB.tooltipText = "Automatically select the gossip option when an NPC only has one."
    autoSelectCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.gossip.autoSelectSingle = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local autoSelectHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    autoSelectHint:SetPoint("TOPLEFT", autoSelectCB, "BOTTOMLEFT", 22, -4)
    autoSelectHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    autoSelectHint:SetJustifyH("LEFT")
    autoSelectHint:SetText("|cff888888When an NPC gossip dialog has only a single option, it is selected automatically so you skip the dialog.|r")

    -- Auto-select quest gossip option
    local autoSelectQuestCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    autoSelectQuestCB:SetPoint("TOPLEFT", autoSelectHint, "BOTTOMLEFT", -22, -10)
    autoSelectQuestCB.Text:SetText("Auto-select quest gossip options")
    autoSelectQuestCB.tooltipText = "Automatically select gossip options that are related to quests."
    autoSelectQuestCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.gossip.autoSelectQuest = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local autoSelectQuestHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    autoSelectQuestHint:SetPoint("TOPLEFT", autoSelectQuestCB, "BOTTOMLEFT", 22, -4)
    autoSelectQuestHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    autoSelectQuestHint:SetJustifyH("LEFT")
    autoSelectQuestHint:SetText("|cff888888When multiple gossip options are presented and one is quest-related, it is selected automatically.|r")

    -- Auto-select delve gossip option
    local autoSelectDelveCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    autoSelectDelveCB:SetPoint("TOPLEFT", autoSelectQuestHint, "BOTTOMLEFT", -22, -10)
    autoSelectDelveCB.Text:SetText("Auto-select delve gossip options")
    autoSelectDelveCB.tooltipText = "Automatically select gossip options that are related to delves."
    autoSelectDelveCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.gossip.autoSelectDelve = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local autoSelectDelveHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    autoSelectDelveHint:SetPoint("TOPLEFT", autoSelectDelveCB, "BOTTOMLEFT", 22, -4)
    autoSelectDelveHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    autoSelectDelveHint:SetJustifyH("LEFT")
    autoSelectDelveHint:SetText("|cff888888When multiple gossip options are presented and one is delve-related, it is selected automatically.|r")

    -- Auto-skip dialog
    local autoSkipCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    autoSkipCB:SetPoint("TOPLEFT", autoSelectDelveHint, "BOTTOMLEFT", -22, -10)
    autoSkipCB.Text:SetText("Auto-select skip options")
    autoSkipCB.tooltipText = "Automatically select gossip options that offer to skip dialog or content."
    autoSkipCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.gossip.autoSkip = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local autoSkipHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    autoSkipHint:SetPoint("TOPLEFT", autoSkipCB, "BOTTOMLEFT", 22, -4)
    autoSkipHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    autoSkipHint:SetJustifyH("LEFT")
    autoSkipHint:SetText("|cff888888When a gossip option contains the word \"skip\", it is selected automatically.|r")

    -- Skip if quest/delve dialog
    local skipIfQuestCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    skipIfQuestCB:SetPoint("TOPLEFT", autoSkipHint, "BOTTOMLEFT", -22, -10)
    skipIfQuestCB.Text:SetText("Skip when quests are available")
    skipIfQuestCB.tooltipText = "Don't auto-select the gossip option if the NPC also offers or accepts quests."
    skipIfQuestCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.gossip.skipIfQuest = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local skipIfQuestHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    skipIfQuestHint:SetPoint("TOPLEFT", skipIfQuestCB, "BOTTOMLEFT", 22, -4)
    skipIfQuestHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    skipIfQuestHint:SetJustifyH("LEFT")
    skipIfQuestHint:SetText("|cff888888Prevents auto-selecting gossip when the NPC also has quest or delve dialogs, so you don't accidentally skip them.|r")

    -- Darkmoon Faire teleport
    local darkmoonCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    darkmoonCB:SetPoint("TOPLEFT", skipIfQuestHint, "BOTTOMLEFT", -22, -20)
    darkmoonCB.Text:SetText("Auto-accept Darkmoon Faire teleport")
    darkmoonCB.tooltipText = "Automatically accept the Darkmoon Faire teleport dialog when talking to the NPC."
    darkmoonCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.gossip.darkmoonTeleport = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local darkmoonHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    darkmoonHint:SetPoint("TOPLEFT", darkmoonCB, "BOTTOMLEFT", 22, -4)
    darkmoonHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    darkmoonHint:SetJustifyH("LEFT")
    darkmoonHint:SetText("|cff888888Selects the Darkmoon Faire teleport option and confirms the popup automatically. Works with any NPC that offers a Darkmoon Faire teleport.|r")

    -- Pause key dropdown
    local TOGGLE_OPTIONS = { NONE_KEY, ALT_KEY, CTRL_KEY, SHIFT_KEY }
    local toggleLabel = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    toggleLabel:SetPoint("TOPLEFT", darkmoonHint, "BOTTOMLEFT", -22, -20)
    toggleLabel:SetText("Pause key:")

    local toggleDropdown = CreateFrame("Frame", "WildGossipToggleDD", sc, "UIDropDownMenuTemplate")
    toggleDropdown:SetPoint("LEFT", toggleLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(toggleDropdown, 140)

    UIDropDownMenu_Initialize(toggleDropdown, function(self, level)
        for i, text in ipairs(TOGGLE_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = i
            info.func = function(btn)
                Wild.db.gossip.toggleKey = btn.value
                UIDropDownMenu_SetText(toggleDropdown, btn:GetText())
                CloseDropDownMenus()
            end
            info.checked = (Wild.db.gossip.toggleKey == i)
            UIDropDownMenu_AddButton(info)
        end
    end)

    local toggleHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    toggleHint:SetPoint("TOPLEFT", toggleLabel, "BOTTOMLEFT", 0, -26)
    toggleHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    toggleHint:SetJustifyH("LEFT")
    toggleHint:SetText("|cff888888Hold this key while interacting with an NPC to temporarily bypass all gossip automation.|r")

    panel:SetScript("OnShow", function()
        if Wild.db and Wild.db.gossip then
            local g = Wild.db.gossip
            autoSelectCB:SetChecked(g.autoSelectSingle)
            autoSelectQuestCB:SetChecked(g.autoSelectQuest)
            autoSelectDelveCB:SetChecked(g.autoSelectDelve)
            autoSkipCB:SetChecked(g.autoSkip)
            skipIfQuestCB:SetChecked(g.skipIfQuest)
            darkmoonCB:SetChecked(g.darkmoonTeleport)
            UIDropDownMenu_SetText(toggleDropdown, TOGGLE_OPTIONS[g.toggleKey or 1])
        end
    end)

    return panel
end

-- ============================================================
-- Tab: Darkmoon Faire
-- ============================================================
local function CreateDarkmoonFaireTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(800)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Darkmoon Faire")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Helpers for the Darkmoon Faire monthly event.|r")

    -- Show profession helper
    local helperCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    helperCB:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    helperCB.Text:SetText("Show profession shopping list")
    helperCB.tooltipText = "When you enter a Darkmoon Faire staging area during the event, show a popup listing items to buy before entering."
    helperCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.darkmoonFaire.showProfessionHelper = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local helperHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    helperHint:SetPoint("TOPLEFT", helperCB, "BOTTOMLEFT", 22, -4)
    helperHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    helperHint:SetJustifyH("LEFT")
    helperHint:SetText("|cff888888Detects your professions and shows which items you need to buy from the trade goods vendor or innkeeper in the staging area before taking the portal to Darkmoon Island. Quests already completed this month are excluded.|r")

    -- Manual show button
    local showBtn = CreateFrame("Button", nil, sc, "UIPanelButtonTemplate")
    showBtn:SetSize(180, 24)
    showBtn:SetPoint("TOPLEFT", helperHint, "BOTTOMLEFT", -22, -16)
    showBtn:SetText("Show Shopping List Now")
    showBtn:SetScript("OnClick", function()
        if Wild.ShowDarkmoonHelper then
            Wild.ShowDarkmoonHelper()
        end
    end)

    local showBtnHint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    showBtnHint:SetPoint("TOPLEFT", showBtn, "BOTTOMLEFT", 0, -4)
    showBtnHint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    showBtnHint:SetJustifyH("LEFT")
    showBtnHint:SetText("|cff888888Manually open the shopping list popup regardless of your current location.|r")

    panel:SetScript("OnShow", function()
        if Wild.db and Wild.db.darkmoonFaire then
            helperCB:SetChecked(Wild.db.darkmoonFaire.showProfessionHelper)
        end
    end)

    return panel
end

-- ============================================================
-- Tab: Delve
-- ============================================================
local function CreateDelveTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(800)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Delve")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Automate interactions inside Delve instances.|r")

    local autoPowerCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    autoPowerCB:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    autoPowerCB.Text:SetText("Auto-select power")
    autoPowerCB.tooltipText = "Automatically pick the first available power when interacting with a power item after killing a rare in a Delve."

    autoPowerCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.delveAutoSelectPower = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local hint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", autoPowerCB, "BOTTOMLEFT", 22, -4)
    hint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("|cff888888When a power choice appears inside a Delve, the first option is selected instantly and the choice window is dismissed. Only active inside Delve instances (difficulty 208).|r")

    panel:SetScript("OnShow", function()
        if Wild.db then
            autoPowerCB:SetChecked(Wild.db.delveAutoSelectPower)
        end
    end)

    return panel
end

-- ============================================================
-- Tab: Loot
-- ============================================================
local function CreateLootTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(800)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Loot")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("|cff888888Configure loot behaviour.|r")

    -- Auto-loot checkbox
    local autoLootCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    autoLootCB:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    autoLootCB.Text:SetText("Enable Auto-Loot")
    autoLootCB.tooltipText = "Automatically loot all items when you interact with a loot window."

    autoLootCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.SetAutoLoot(checked)
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    -- Modifier key dropdown
    local modRow = CreateFrame("Frame", nil, sc)
    modRow:SetSize(400, 30)
    modRow:SetPoint("TOPLEFT", autoLootCB, "BOTTOMLEFT", 22, -8)

    local modLabel = modRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    modLabel:SetPoint("LEFT", 0, 0)
    modLabel:SetText("Skip modifier:")

    local modDropdown = CreateFrame("Frame", "WildLootModifierDD", modRow, "UIDropDownMenuTemplate")
    modDropdown:SetPoint("LEFT", modLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(modDropdown, 100)

    local MODIFIER_OPTIONS = {
        { text = "Shift", value = "SHIFT" },
        { text = "Ctrl",  value = "CTRL" },
        { text = "Alt",   value = "ALT" },
        { text = "None",  value = "NONE" },
    }
    local MODIFIER_LABELS = { SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt", NONE = "None" }

    UIDropDownMenu_Initialize(modDropdown, function(self, level)
        for _, opt in ipairs(MODIFIER_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.func = function(btn)
                Wild.SetAutoLootModifier(btn.value)
                UIDropDownMenu_SetText(modDropdown, MODIFIER_LABELS[btn.value])
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Quick loot checkbox
    local quickLootCheckbox = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    quickLootCheckbox:SetPoint("TOPLEFT", modRow, "BOTTOMLEFT", -22, -12)
    quickLootCheckbox.Text:SetText("Enable Quick Loot")
    quickLootCheckbox.tooltipText = "Speeds up looting by instantly grabbing all items from the loot window."

    quickLootCheckbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if Wild.SetQuickLoot then Wild.SetQuickLoot(checked) end
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    panel:SetScript("OnShow", function()
        if Wild.db then
            autoLootCB:SetChecked(Wild.db.lootAutoLoot)
            quickLootCheckbox:SetChecked(Wild.db.lootQuickLoot)
            local mod = Wild.db.lootAutoLootModifier or "SHIFT"
            UIDropDownMenu_SetText(modDropdown, MODIFIER_LABELS[mod] or "Shift")
        end
    end)

    return panel
end

-- ============================================================
-- Toggle / Open / Close
-- ============================================================
function Wild.ToggleSettings()
    local f = CreateMainFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        if currentTab then SelectTab(currentTab) end
    end
end

function Wild.OpenSettings()
    local f = CreateMainFrame()
    f:Show()
    if currentTab then SelectTab(currentTab) end
end

-- ============================================================
-- Advanced
-- ============================================================

local function CreateAdvancedTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(800)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Advanced")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Developer and troubleshooting options.|r")

    local debugCB = CreateFrame("CheckButton", nil, sc, "InterfaceOptionsCheckButtonTemplate")
    debugCB:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -2, -16)
    debugCB.Text:SetText("Enable debug mode")
    debugCB.tooltipText = "Print diagnostic messages to chat for troubleshooting. Covers bank automation, event handling, and other subsystems."

    debugCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Wild.db.advanced.debug = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    local hint = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", debugCB, "BOTTOMLEFT", 22, -4)
    hint:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("|cff888888When enabled, Wild prints detailed debug output to chat and saves it to WildDB.bankDebug in saved variables. Disable when not actively troubleshooting.|r")

    panel:SetScript("OnShow", function()
        if Wild.db and Wild.db.advanced then
            debugCB:SetChecked(Wild.db.advanced.debug)
        end
    end)

    return panel
end

-- ============================================================
-- Tab: Intents (Unified automation rules)
-- ============================================================
local function CreateIntentRulesTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(400)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local function UpdateIntentsScrollHeight()
        C_Timer.After(0, function()
            local scTop = sc:GetTop()
            if not scTop then return end
            local lowest
            local children = { sc:GetChildren() }
            for _, child in ipairs(children) do
                if child:IsShown() then
                    local bottom = child:GetBottom()
                    if bottom and (not lowest or bottom < lowest) then
                        lowest = bottom
                    end
                end
            end
            if lowest then
                sc:SetHeight(math.max(400, scTop - lowest + 20))
            end
        end)
    end

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Intents")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Define automation intents: deposit, withdraw, sell, destroy, mail, or manage gold. Conditions control which items are matched.|r")

    -- Intent list
    local listFrame = CreateFrame("Frame", nil, sc, "BackdropTemplate")
    listFrame:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -4, -12)
    listFrame:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    listFrame:SetHeight(60)
    listFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    listFrame:SetBackdropColor(0, 0, 0, 0.2)
    listFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)

    local intentScroll = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
    intentScroll:SetPoint("TOPLEFT", 4, -4)
    intentScroll:SetPoint("BOTTOMRIGHT", -26, 4)

    local intentScrollChild = CreateFrame("Frame")
    intentScrollChild:SetWidth(intentScroll:GetWidth() or 460)
    intentScrollChild:SetHeight(1)
    intentScroll:SetScrollChild(intentScrollChild)
    intentScroll:SetScript("OnSizeChanged", function(self, w)
        if w and w > 0 then intentScrollChild:SetWidth(w) end
    end)

    local emptyText = intentScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    emptyText:SetPoint("TOPLEFT", 4, -6)
    emptyText:SetText("|cff666666No intents configured. Click 'Add Intent' to create one.|r")

    local intentRows = {}
    local RefreshIntentList

    -- Add Intent button
    local addBtn = CreateFrame("Button", nil, sc, "UIPanelButtonTemplate")
    addBtn:SetSize(100, 22)
    addBtn:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 4, -8)
    addBtn:SetText("Add Intent")

    -- ===== Intent Editor (condition-based, like vendor but with action/trigger/source) =====
    local editor = CreateFrame("Frame", nil, sc, "BackdropTemplate")
    editor:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", -4, -8)
    editor:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    editor:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    editor:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
    editor:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.8)
    editor:Hide()

    local editorTitle = editor:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    editorTitle:SetPoint("TOPLEFT", 8, -8)

    -- Editor state
    local editorIntent = {}
    local editorGroups = {}         -- working copy: { {mode="include"|"exclude", conditions={...}}, ... }
    local editingIndex = nil
    local editingCondIdx = nil
    local editingGroupIdx = nil     -- which group is currently expanded for editing

    -- Actor filter list
    local actorSectionLabel = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    actorSectionLabel:SetPoint("TOPLEFT", editorTitle, "BOTTOMLEFT", 0, -10)
    actorSectionLabel:SetText("Actors (who this applies to):")

    local actorListFrame = CreateFrame("Frame", nil, editor, "BackdropTemplate")
    actorListFrame:SetPoint("TOPLEFT", actorSectionLabel, "BOTTOMLEFT", 0, -6)
    actorListFrame:SetPoint("RIGHT", editor, "RIGHT", -8, 0)
    actorListFrame:SetHeight(24)
    actorListFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    actorListFrame:SetBackdropColor(0, 0, 0, 0.3)
    actorListFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4)

    local actorRows = {}
    local actorEmptyText = actorListFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    actorEmptyText:SetPoint("TOPLEFT", 6, -6)
    actorEmptyText:SetText("|cff888888Everyone (no filter)|r")

    local editorActors = {}  -- working copy: { {value=, exclude=}, ... }
    local RefreshActorList

    -- Add actor dropdown
    local addActorDD = CreateFrame("Frame", "WildIntentAddActorDD", editor, "UIDropDownMenuTemplate")
    addActorDD:SetPoint("TOPLEFT", actorListFrame, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(addActorDD, 180)
    UIDropDownMenu_SetText(addActorDD, "Add actor...")

    local addExcludeDD = CreateFrame("Frame", "WildIntentAddExcludeDD", editor, "UIDropDownMenuTemplate")
    addExcludeDD:SetPoint("LEFT", addActorDD, "RIGHT", -16, 0)
    UIDropDownMenu_SetWidth(addExcludeDD, 180)
    UIDropDownMenu_SetText(addExcludeDD, "Add exclusion...")

    local function BuildActorMenu(dropdown, isExclude)
        UIDropDownMenu_Initialize(dropdown, function()
            local options = Wild.GetAllActorOptions and Wild.GetAllActorOptions() or {}
            local lastCat = nil
            for _, opt in ipairs(options) do
                    if opt.category ~= lastCat then
                        if lastCat then
                            local sep = UIDropDownMenu_CreateInfo()
                            sep.text = ""; sep.isTitle = true; sep.notCheckable = true
                            UIDropDownMenu_AddButton(sep)
                        end
                        local catHeader = UIDropDownMenu_CreateInfo()
                        catHeader.text = "|cff888888-- " .. opt.category .. " --|r"
                        catHeader.isTitle = true; catHeader.notCheckable = true
                        UIDropDownMenu_AddButton(catHeader)
                        lastCat = opt.category
                    end
                    -- Check if already in the list
                    local alreadyAdded = false
                    for _, existing in ipairs(editorActors) do
                        if existing.value == opt.value and (existing.exclude == true) == isExclude then
                            alreadyAdded = true; break
                        end
                    end
                    if not alreadyAdded then
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = opt.display or opt.value
                        info.value = opt.value
                        info.func = function(btn)
                            table.insert(editorActors, { value = btn.value, exclude = isExclude or nil })
                            RefreshActorList()
                            CloseDropDownMenus()
                        end
                        UIDropDownMenu_AddButton(info)
                    end
            end
        end)
    end

    BuildActorMenu(addActorDD, false)
    BuildActorMenu(addExcludeDD, true)

    RefreshActorList = function()
        for _, row in ipairs(actorRows) do row:Hide() end
        actorEmptyText:SetShown(#editorActors == 0)

        local yOff = 0
        for i, entry in ipairs(editorActors) do
            local row = actorRows[i]
            if not row then
                row = CreateFrame("Frame", nil, actorListFrame)
                row:SetHeight(20)
                row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 4, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -20, 0)
                row.text:SetJustifyH("LEFT")
                row.removeBtn = CreateFrame("Button", nil, row)
                row.removeBtn:SetSize(14, 14)
                row.removeBtn:SetPoint("RIGHT", -2, 0)
                row.removeBtn.label = row.removeBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                row.removeBtn.label:SetPoint("CENTER")
                row.removeBtn.label:SetText("|cffff4444X|r")
                row.removeBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffff0000X|r") end)
                row.removeBtn:SetScript("OnLeave", function(self) self.label:SetText("|cffff4444X|r") end)
                actorRows[i] = row
            end
            row:SetPoint("TOPLEFT", actorListFrame, "TOPLEFT", 0, -yOff)
            row:SetPoint("RIGHT", actorListFrame, "RIGHT", 0, 0)

            if entry.exclude then
                row.text:SetText("|cffff6666- Exclude:|r " .. entry.value)
            else
                row.text:SetText("|cff66ff66+ Include:|r " .. entry.value)
            end

            local idx = i
            row.removeBtn:SetScript("OnClick", function()
                table.remove(editorActors, idx)
                RefreshActorList()
            end)
            row:Show()
            yOff = yOff + 22
        end
        actorListFrame:SetHeight(math.max(24, yOff + 4))
        -- Rebuild menus to hide already-added options
        BuildActorMenu(addActorDD, false)
        BuildActorMenu(addExcludeDD, true)
        if UpdateSaveBtnAnchor then UpdateSaveBtnAnchor() end
    end

    -- Table layout constants
    local COL_LEFT = 8     -- label left padding
    local COL_INPUT = 80   -- input/dropdown X offset from editor left
    local ROW_SPACING = -6 -- vertical spacing between rows

    -- Action dropdown
    local actionLabel = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    actionLabel:SetPoint("TOPLEFT", addActorDD, "BOTTOMLEFT", 16, -8)
    actionLabel:SetText("Action:")

    local ACTION_OPTIONS = {
        { text = "Deposit", value = "deposit" },
        { text = "Withdraw", value = "withdraw" },
        { text = "Transfer", value = "transfer" },
        { text = "Sell", value = "sell" },
        { text = "Destroy", value = "destroy" },
        { text = "Mail", value = "mail" },
        { text = "Gold", value = "gold" },
    }

    local actionDD = CreateFrame("Frame", "WildIntentActionDD", editor, "UIDropDownMenuTemplate")
    actionDD:SetPoint("TOPLEFT", editor, "TOPLEFT", COL_INPUT - 16, 0)  -- repositioned dynamically
    UIDropDownMenu_SetWidth(actionDD, 180)

    -- Source/Destination dropdown (shown for deposit/withdraw/gold)
    local sourceLabel = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sourceLabel:SetText("Target:")

    local TARGET_OPTIONS = {
        { text = "Personal Bank", value = "character" },
        { text = "Warband Bank", value = "warband" },
        { text = "Guild Bank", value = "guild" },
    }

    local TARGET_OPTIONS_GOLD = {
        { text = "Warband Bank", value = "warband" },
        { text = "Guild Bank", value = "guild" },
    }

    local sourceDD = CreateFrame("Frame", "WildIntentSourceDD", editor, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(sourceDD, 160)

    -- Transfer source dropdown (where to pull FROM)
    local transferSourceLabel = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    transferSourceLabel:SetText("From:")

    local TRANSFER_SOURCE_OPTIONS = {
        { text = "Personal Bank", value = "character" },
        { text = "Warband Bank", value = "warband" },
        { text = "Guild Bank", value = "guild" },
    }

    local transferSourceDD = CreateFrame("Frame", "WildIntentTransferSourceDD", editor, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(transferSourceDD, 160)

    -- Transfer target label (override for transfer action)
    local transferTargetLabel = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    transferTargetLabel:SetText("To:")

    -- Recipient input (for mail)
    local recipientLabel = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    recipientLabel:SetText("Recipient:")

    local recipientInput = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    recipientInput:SetSize(180, 22)
    recipientInput:SetAutoFocus(false)
    recipientInput:SetMaxLetters(50)
    recipientInput:SetFontObject("GameFontHighlight")

    -- Gold target input (for gold action)
    local goldLabel = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    goldLabel:SetText("Gold:")

    local goldInput = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    goldInput:SetSize(100, 22)
    goldInput:SetAutoFocus(false)
    goldInput:SetNumeric(true)
    goldInput:SetMaxLetters(9)
    goldInput:SetFontObject("GameFontHighlight")

    local goldSuffix = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    goldSuffix:SetPoint("LEFT", goldInput, "RIGHT", 6, 0)
    goldSuffix:SetText("|cffffd700gold to keep on character|r")

    local goldHint = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    goldHint:SetText("|cff888888Deposits excess / withdraws deficit to maintain this amount.|r")

    -- Keep row (for deposit/withdraw/mail/destroy/sell)
    local qtyLabel = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    qtyLabel:SetText("Keep:")

    local qtyAllCB = CreateFrame("CheckButton", nil, editor, "InterfaceOptionsCheckButtonTemplate")
    qtyAllCB.Text:SetText("None")
    qtyAllCB:SetScale(0.85)

    local qtyInput = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    qtyInput:SetSize(60, 22)
    qtyInput:SetAutoFocus(false)
    qtyInput:SetNumeric(true)
    qtyInput:SetMaxLetters(5)
    qtyInput:SetFontObject("GameFontHighlight")

    local qtyHint = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    qtyHint:SetText("")

    qtyAllCB:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        qtyInput:SetEnabled(not checked)
        if checked then
            qtyInput:SetText("0")
            qtyInput:SetTextColor(0.5, 0.5, 0.5)
        else
            qtyInput:SetTextColor(1, 1, 1)
        end
    end)

    -- Destroy unsellable checkbox (for sell action only)
    local destroyUnsellableCB = CreateFrame("CheckButton", nil, editor, "InterfaceOptionsCheckButtonTemplate")
    destroyUnsellableCB.Text:SetFontObject("GameFontHighlightSmall")
    destroyUnsellableCB.Text:SetText("Destroy items with no sell price")
    destroyUnsellableCB:SetScale(0.85)
    destroyUnsellableCB:SetScript("OnClick", function(self)
        editorIntent.destroyUnsellable = self:GetChecked() and true or false
    end)

    -- Conditions section — group-based (include/exclude sets with OR between groups)
    local condLabel = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    condLabel:SetText("Item Groups (include sets are OR'd, exclude sets filter out):")

    local condListFrame = CreateFrame("Frame", nil, editor, "BackdropTemplate")
    condListFrame:SetPoint("TOPLEFT", condLabel, "BOTTOMLEFT", 0, -6)
    condListFrame:SetPoint("RIGHT", editor, "RIGHT", -8, 0)
    condListFrame:SetHeight(80)
    condListFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    condListFrame:SetBackdropColor(0, 0, 0, 0.3)
    condListFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4)

    local condRows = {}
    local condEmptyText = condListFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    condEmptyText:SetPoint("TOPLEFT", 6, -6)
    condEmptyText:SetText("|cff666666No item groups. Add at least one include group.|r")

    local RefreshCondList

    local addCondBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    addCondBtn:SetSize(130, 20)
    addCondBtn:SetPoint("TOPLEFT", condListFrame, "BOTTOMLEFT", 2, -4)
    addCondBtn:SetText("Add Include Group")

    local addExclGroupBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    addExclGroupBtn:SetSize(130, 20)
    addExclGroupBtn:SetPoint("LEFT", addCondBtn, "RIGHT", 6, 0)
    addExclGroupBtn:SetText("Add Exclude Group")

    -- ===== Condition Sub-Editor =====
    local condEditor = CreateFrame("Frame", nil, editor, "BackdropTemplate")
    condEditor:SetPoint("TOPLEFT", addCondBtn, "BOTTOMLEFT", -2, -8)
    condEditor:SetPoint("RIGHT", editor, "RIGHT", -8, 0)
    condEditor:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    condEditor:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
    condEditor:SetBackdropBorderColor(0.35, 0.35, 0.45, 0.6)
    condEditor:Hide()

    local condEditorState = {}

    -- Layout constants for the condition sub-editor.
    -- WoW UIDropDownMenuTemplate frames are ~30px tall; labels are ~12px.
    -- We anchor labels TOPLEFT relative to the previous label's BOTTOMLEFT.
    -- The gap must be large enough that the dropdown sitting on one row
    -- doesn't visually collide with the label of the next row.
    local CE_PAD       = 8   -- inset from condEditor edges
    local CE_COL_INPUT = 90  -- X where inputs/dropdowns start (from condEditor LEFT)
    local CE_DD_X      = CE_COL_INPUT - 16 -- UIDropDown has 16px built-in left padding
    local CE_ROW_H     = 28  -- vertical distance between label baselines

    local ceAttrLabel = condEditor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ceAttrLabel:SetPoint("TOPLEFT", CE_PAD, -10)
    ceAttrLabel:SetText("Attribute:")

    local ceAttrDD = CreateFrame("Frame", "WildIntentCondAttrDD", condEditor, "UIDropDownMenuTemplate")
    ceAttrDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceAttrDD:SetPoint("TOP", ceAttrLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceAttrDD, 180)

    local ceOpLabel = condEditor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ceOpLabel:SetPoint("TOPLEFT", ceAttrLabel, "BOTTOMLEFT", 0, -CE_ROW_H)
    ceOpLabel:SetText("Operator:")

    local ceOpDD = CreateFrame("Frame", "WildIntentCondOpDD", condEditor, "UIDropDownMenuTemplate")
    ceOpDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceOpDD:SetPoint("TOP", ceOpLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceOpDD, 140)

    local ceValLabel = condEditor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ceValLabel:SetPoint("TOPLEFT", ceOpLabel, "BOTTOMLEFT", 0, -CE_ROW_H)
    ceValLabel:SetText("Value:")

    -- Value inputs — all anchored at the same column, vertically centered on ceValLabel
    local ceNumInput = CreateFrame("EditBox", nil, condEditor, "InputBoxTemplate")
    ceNumInput:SetSize(80, 22)
    ceNumInput:SetPoint("LEFT", condEditor, "LEFT", CE_COL_INPUT, 0)
    ceNumInput:SetPoint("TOP", ceValLabel, "TOP", 0, 4)
    ceNumInput:SetAutoFocus(false)
    ceNumInput:SetMaxLetters(10)
    ceNumInput:SetFontObject("GameFontHighlight")

    local ceStrInput = CreateFrame("EditBox", nil, condEditor, "InputBoxTemplate")
    ceStrInput:SetSize(180, 22)
    ceStrInput:SetPoint("LEFT", condEditor, "LEFT", CE_COL_INPUT, 0)
    ceStrInput:SetPoint("TOP", ceValLabel, "TOP", 0, 4)
    ceStrInput:SetAutoFocus(false)
    ceStrInput:SetMaxLetters(50)
    ceStrInput:SetFontObject("GameFontHighlight")

    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not link then return end
        if ceStrInput:IsVisible() and ceStrInput:HasFocus() then
            local itemID = link:match("item:(%d+)")
            if itemID then ceStrInput:SetText(itemID) else ceStrInput:SetText(link) end
        elseif ceNumInput:IsVisible() and ceNumInput:HasFocus() then
            local itemID = link:match("item:(%d+)")
            if itemID then ceNumInput:SetText(itemID) end
        end
    end)

    local ceQualDD = CreateFrame("Frame", "WildIntentCondQualDD", condEditor, "UIDropDownMenuTemplate")
    ceQualDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceQualDD:SetPoint("TOP", ceValLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceQualDD, 120)

    UIDropDownMenu_Initialize(ceQualDD, function()
        for q = 0, 5 do
            local info = UIDropDownMenu_CreateInfo()
            info.text = (QUALITY_COLORS[q] or "") .. QUALITY_NAMES[q] .. "|r"
            info.value = q
            info.func = function(btn)
                condEditorState.value = btn.value
                UIDropDownMenu_SetText(ceQualDD, (QUALITY_COLORS[btn.value] or "") .. QUALITY_NAMES[btn.value] .. "|r")
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local ceTypeDD = CreateFrame("Frame", "WildIntentCondTypeDD", condEditor, "UIDropDownMenuTemplate")
    ceTypeDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceTypeDD:SetPoint("TOP", ceValLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceTypeDD, 160)

    UIDropDownMenu_Initialize(ceTypeDD, function()
        for _, cls in ipairs(GetItemClassList()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = cls.name
            info.value = cls.classID
            info.func = function(btn)
                condEditorState.value = btn.value
                UIDropDownMenu_SetText(ceTypeDD, btn:GetText())
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local ceSubParentDD = CreateFrame("Frame", "WildIntentCondSubParDD", condEditor, "UIDropDownMenuTemplate")
    ceSubParentDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceSubParentDD:SetPoint("TOP", ceValLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceSubParentDD, 120)

    local ceSubTypeDD = CreateFrame("Frame", "WildIntentCondSubDD", condEditor, "UIDropDownMenuTemplate")
    ceSubTypeDD:SetPoint("LEFT", ceSubParentDD, "RIGHT", -12, 0)
    UIDropDownMenu_SetWidth(ceSubTypeDD, 120)

    UIDropDownMenu_Initialize(ceSubParentDD, function()
        for _, cls in ipairs(GetItemClassList()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = cls.name
            info.value = cls.classID
            info.func = function(btn)
                condEditorState.subtypeParent = btn.value
                condEditorState.value = nil
                UIDropDownMenu_SetText(ceSubParentDD, btn:GetText())
                UIDropDownMenu_SetText(ceSubTypeDD, "Select...")
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_Initialize(ceSubTypeDD, function()
        local parentID = condEditorState.subtypeParent
        if not parentID or parentID < 0 then return end
        for _, sub in ipairs(GetItemSubClassList(parentID)) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = sub.name
            info.value = sub.subclassID
            info.func = function(btn)
                condEditorState.value = parentID * 1000 + btn.value
                UIDropDownMenu_SetText(ceSubTypeDD, btn:GetText())
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local ceEquipDD = CreateFrame("Frame", "WildIntentCondEquipDD", condEditor, "UIDropDownMenuTemplate")
    ceEquipDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceEquipDD:SetPoint("TOP", ceValLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceEquipDD, 140)

    UIDropDownMenu_Initialize(ceEquipDD, function()
        local seen = {}
        for loc, label in pairs(Wild.EQUIP_LOC_LABELS) do
            if not seen[label] then
                seen[label] = true
                local info = UIDropDownMenu_CreateInfo()
                info.text = label
                info.value = loc
                info.func = function(btn)
                    condEditorState.value = btn.value
                    UIDropDownMenu_SetText(ceEquipDD, btn:GetText())
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end)

    local ceProfDD = CreateFrame("Frame", "WildIntentCondProfDD", condEditor, "UIDropDownMenuTemplate")
    ceProfDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceProfDD:SetPoint("TOP", ceValLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceProfDD, 140)

    UIDropDownMenu_Initialize(ceProfDD, function()
        local sorted = {}
        for skillLine, name in pairs(Wild.PROFESSION_SKILL_LINES) do
            table.insert(sorted, { skillLine = skillLine, name = name })
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)
        for _, prof in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = prof.name
            info.value = prof.skillLine
            info.func = function(btn)
                condEditorState.value = btn.value
                UIDropDownMenu_SetText(ceProfDD, btn:GetText())
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local ceClassDD = CreateFrame("Frame", "WildIntentCondClassDD", condEditor, "UIDropDownMenuTemplate")
    ceClassDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceClassDD:SetPoint("TOP", ceValLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceClassDD, 140)

    UIDropDownMenu_Initialize(ceClassDD, function()
        for _, classFile in ipairs(Wild.CLASS_FILES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = Wild.CLASS_LABELS[classFile] or classFile
            info.value = classFile
            info.func = function(btn)
                condEditorState.value = btn.value
                UIDropDownMenu_SetText(ceClassDD, btn:GetText())
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local ceBindDD = CreateFrame("Frame", "WildIntentCondBindDD", condEditor, "UIDropDownMenuTemplate")
    ceBindDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceBindDD:SetPoint("TOP", ceValLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceBindDD, 140)

    UIDropDownMenu_Initialize(ceBindDD, function()
        for val, label in pairs(Wild.BIND_LABELS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = label
            info.value = val
            info.func = function(btn)
                condEditorState.value = btn.value
                UIDropDownMenu_SetText(ceBindDD, btn:GetText())
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local ceBoolDD = CreateFrame("Frame", "WildIntentCondBoolDD", condEditor, "UIDropDownMenuTemplate")
    ceBoolDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceBoolDD:SetPoint("TOP", ceValLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceBoolDD, 100)

    UIDropDownMenu_Initialize(ceBoolDD, function()
        for _, opt in ipairs({{text = "Yes", value = true}, {text = "No", value = false}}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.func = function(btn)
                condEditorState.value = btn.value
                UIDropDownMenu_SetText(ceBoolDD, btn:GetText())
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local ceExpanDD = CreateFrame("Frame", "WildIntentCondExpanDD", condEditor, "UIDropDownMenuTemplate")
    ceExpanDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceExpanDD:SetPoint("TOP", ceValLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceExpanDD, 140)

    UIDropDownMenu_Initialize(ceExpanDD, function()
        -- Build sorted list by expansion ID (ascending)
        local sorted = {}
        for id, name in pairs(Wild.EXPANSION_NAMES) do
            table.insert(sorted, { id = id, name = name })
        end
        table.sort(sorted, function(a, b) return a.id < b.id end)
        for _, expac in ipairs(sorted) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = expac.name
            info.value = expac.name
            info.func = function(btn)
                condEditorState.value = btn.value
                UIDropDownMenu_SetText(ceExpanDD, btn:GetText())
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local ceTrackDD = CreateFrame("Frame", "WildIntentCondTrackDD", condEditor, "UIDropDownMenuTemplate")
    ceTrackDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceTrackDD:SetPoint("TOP", ceValLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceTrackDD, 140)

    UIDropDownMenu_Initialize(ceTrackDD, function()
        -- Build sorted list by track rank (ascending), skip 0=None
        for rank = 1, 6 do
            local name = Wild.UPGRADE_TRACK_NAMES[rank]
            if name then
                local info = UIDropDownMenu_CreateInfo()
                info.text = name
                info.value = rank
                info.func = function(btn)
                    condEditorState.value = btn.value
                    UIDropDownMenu_SetText(ceTrackDD, btn:GetText())
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end)

    -- Compare to label (dynamic numeric types only)
    local ceValModeLabel = condEditor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ceValModeLabel:SetPoint("TOPLEFT", ceValLabel, "BOTTOMLEFT", 0, -CE_ROW_H)
    ceValModeLabel:SetText("Compare to:")

    local ceValModeDD = CreateFrame("Frame", "WildIntentCondValModeDD", condEditor, "UIDropDownMenuTemplate")
    ceValModeDD:SetPoint("LEFT", condEditor, "LEFT", CE_DD_X, 0)
    ceValModeDD:SetPoint("TOP", ceValModeLabel, "TOP", 0, 8)
    UIDropDownMenu_SetWidth(ceValModeDD, 160)

    -- Offset label (dynamic reference mode)
    local ceOffsetLabel = condEditor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ceOffsetLabel:SetPoint("TOPLEFT", ceValModeLabel, "BOTTOMLEFT", 0, -CE_ROW_H)
    ceOffsetLabel:SetText("Offset (+/-):")

    local ceOffsetInput = CreateFrame("EditBox", nil, condEditor, "InputBoxTemplate")
    ceOffsetInput:SetSize(60, 22)
    ceOffsetInput:SetPoint("LEFT", condEditor, "LEFT", CE_COL_INPUT, 0)
    ceOffsetInput:SetPoint("TOP", ceOffsetLabel, "TOP", 0, 4)
    ceOffsetInput:SetAutoFocus(false)
    ceOffsetInput:SetMaxLetters(6)
    ceOffsetInput:SetFontObject("GameFontHighlight")

    local ceOffsetHint = condEditor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ceOffsetHint:SetPoint("LEFT", ceOffsetInput, "RIGHT", 6, 0)
    ceOffsetHint:SetText("|cff888888e.g. -50|r")

    -- OK / Cancel buttons
    local ceOkBtn = CreateFrame("Button", nil, condEditor, "UIPanelButtonTemplate")
    ceOkBtn:SetSize(60, 22)
    ceOkBtn:SetText("OK")

    local ceCancelBtn = CreateFrame("Button", nil, condEditor, "UIPanelButtonTemplate")
    ceCancelBtn:SetSize(60, 22)
    ceCancelBtn:SetPoint("LEFT", ceOkBtn, "RIGHT", 6, 0)
    ceCancelBtn:SetText("Cancel")

    local function UpdateCondEditorLayout()
        local attrKey = condEditorState.attr
        local attrDef = attrKey and Wild.ATTR_BY_KEY[attrKey]
        local vt = attrDef and attrDef.valueType or "string"
        local isDynamic = condEditorState.ref ~= nil

        -- Hide all optional widgets
        ceNumInput:Hide(); ceStrInput:Hide(); ceQualDD:Hide()
        ceTypeDD:Hide(); ceSubParentDD:Hide(); ceSubTypeDD:Hide()
        ceEquipDD:Hide(); ceProfDD:Hide(); ceClassDD:Hide()
        ceBindDD:Hide(); ceBoolDD:Hide(); ceExpanDD:Hide()
        ceTrackDD:Hide()
        ceValLabel:Hide()
        ceValModeLabel:Hide(); ceValModeDD:Hide()
        ceOffsetLabel:Hide(); ceOffsetInput:Hide(); ceOffsetHint:Hide()

        local canDynamic = (vt == "number" or vt == "quality" or vt == "upgradetrack")
        local bottomAnchor = ceOpLabel

        if canDynamic then
            ceValModeLabel:Show(); ceValModeDD:Show()
            ceValModeLabel:ClearAllPoints()
            ceValModeLabel:SetPoint("TOPLEFT", ceOpLabel, "BOTTOMLEFT", 0, -CE_ROW_H)
            bottomAnchor = ceValModeLabel

            if isDynamic then
                ceOffsetLabel:Show(); ceOffsetInput:Show(); ceOffsetHint:Show()
                ceOffsetLabel:ClearAllPoints()
                ceOffsetLabel:SetPoint("TOPLEFT", ceValModeLabel, "BOTTOMLEFT", 0, -CE_ROW_H)
                bottomAnchor = ceOffsetLabel
            else
                ceValLabel:Show()
                ceValLabel:ClearAllPoints()
                ceValLabel:SetPoint("TOPLEFT", ceValModeLabel, "BOTTOMLEFT", 0, -CE_ROW_H)
                bottomAnchor = ceValLabel
                if vt == "quality" then ceQualDD:Show()
                elseif vt == "upgradetrack" then ceTrackDD:Show()
                else ceNumInput:Show() end
            end
        else
            ceValLabel:Show()
            ceValLabel:ClearAllPoints()
            ceValLabel:SetPoint("TOPLEFT", ceOpLabel, "BOTTOMLEFT", 0, -CE_ROW_H)
            bottomAnchor = ceValLabel

            if vt == "string" then ceStrInput:Show()
            elseif vt == "id" then ceNumInput:Show()
            elseif vt == "itemtype" then ceTypeDD:Show()
            elseif vt == "itemsubtype" then ceSubParentDD:Show(); ceSubTypeDD:Show()
            elseif vt == "equiploc" then ceEquipDD:Show()
            elseif vt == "profession" then ceProfDD:Show()
            elseif vt == "class" then ceClassDD:Show()
            elseif vt == "bind" then ceBindDD:Show()
            elseif vt == "boolean" then ceBoolDD:Show()
            elseif vt == "expansion" then ceExpanDD:Show()
            end
        end

        ceOkBtn:ClearAllPoints()
        ceOkBtn:SetPoint("TOPLEFT", bottomAnchor, "BOTTOMLEFT", 0, -CE_ROW_H)
        -- Dynamically size condEditor to fit content
        C_Timer.After(0, function()
            local top = condEditor:GetTop()
            local bottom = ceOkBtn:GetBottom()
            if top and bottom then
                condEditor:SetHeight(top - bottom + 12)
            end
            if UpdateSaveBtnAnchor then UpdateSaveBtnAnchor() end
        end)
    end

    UIDropDownMenu_Initialize(ceValModeDD, function()
        local staticInfo = UIDropDownMenu_CreateInfo()
        staticInfo.text = "Fixed value"
        staticInfo.value = "_static"
        staticInfo.func = function()
            condEditorState.ref = nil
            condEditorState.offset = nil
            UIDropDownMenu_SetText(ceValModeDD, "Fixed value")
            CloseDropDownMenus()
            UpdateCondEditorLayout()
        end
        UIDropDownMenu_AddButton(staticInfo)
        for _, ref in ipairs(Wild.DYNAMIC_REFS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = ref.label
            info.value = ref.key
            info.func = function(btn)
                condEditorState.ref = btn.value
                condEditorState.value = nil
                UIDropDownMenu_SetText(ceValModeDD, btn:GetText())
                CloseDropDownMenus()
                UpdateCondEditorLayout()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_Initialize(ceAttrDD, function()
        local lastCat = nil
        for _, attr in ipairs(Wild.ATTRIBUTES) do
            if attr.category ~= lastCat then
                if lastCat then
                    local sep = UIDropDownMenu_CreateInfo()
                    sep.text = ""; sep.isTitle = true; sep.notCheckable = true
                    UIDropDownMenu_AddButton(sep)
                end
                local catHeader = UIDropDownMenu_CreateInfo()
                catHeader.text = "|cff888888-- " .. attr.category .. " --|r"
                catHeader.isTitle = true; catHeader.notCheckable = true
                UIDropDownMenu_AddButton(catHeader)
                lastCat = attr.category
            end
            local info = UIDropDownMenu_CreateInfo()
            info.text = attr.label
            info.value = attr.key
            info.func = function(btn)
                condEditorState.attr = btn.value
                condEditorState.op = nil
                condEditorState.value = nil
                condEditorState.ref = nil
                condEditorState.offset = nil
                condEditorState.subtypeParent = nil
                UIDropDownMenu_SetText(ceAttrDD, btn:GetText())
                local newAttrDef = Wild.ATTR_BY_KEY[btn.value]
                local newVt = newAttrDef and newAttrDef.valueType or "string"
                for _, op in ipairs(Wild.OPERATORS) do
                    if op.forTypes[newVt] then
                        condEditorState.op = op.key
                        UIDropDownMenu_SetText(ceOpDD, op.label)
                        break
                    end
                end
                CloseDropDownMenus()
                UpdateCondEditorLayout()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_Initialize(ceOpDD, function()
        local attrKey = condEditorState.attr
        local attrDef = attrKey and Wild.ATTR_BY_KEY[attrKey]
        local vt = attrDef and attrDef.valueType or "string"
        for _, op in ipairs(Wild.OPERATORS) do
            if op.forTypes[vt] then
                local info = UIDropDownMenu_CreateInfo()
                info.text = op.label; info.value = op.key
                info.func = function(btn)
                    condEditorState.op = btn.value
                    UIDropDownMenu_SetText(ceOpDD, btn:GetText())
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end)

    local function PopulateCondEditor(cond)
        condEditorState = {}
        if cond then
            condEditorState.attr = cond.attr
            condEditorState.op = cond.op
            condEditorState.value = cond.value
            condEditorState.ref = cond.ref
            condEditorState.offset = cond.offset
        end
        local attrDef = condEditorState.attr and Wild.ATTR_BY_KEY[condEditorState.attr]
        UIDropDownMenu_SetText(ceAttrDD, attrDef and attrDef.label or "Select...")
        local opLabel = "Select..."
        if condEditorState.op then
            for _, op in ipairs(Wild.OPERATORS) do
                if op.key == condEditorState.op then opLabel = op.label; break end
            end
        end
        UIDropDownMenu_SetText(ceOpDD, opLabel)

        local vt = attrDef and attrDef.valueType or "string"
        if condEditorState.ref then
            for _, ref in ipairs(Wild.DYNAMIC_REFS) do
                if ref.key == condEditorState.ref then
                    UIDropDownMenu_SetText(ceValModeDD, ref.label); break
                end
            end
            ceOffsetInput:SetText(tostring(condEditorState.offset or 0))
        else
            UIDropDownMenu_SetText(ceValModeDD, "Fixed value")
            ceOffsetInput:SetText("0")
            if vt == "number" or vt == "id" then
                ceNumInput:SetText(tostring(condEditorState.value or ""))
            elseif vt == "string" then
                ceStrInput:SetText(tostring(condEditorState.value or ""))
            elseif vt == "quality" then
                local q = condEditorState.value
                if q and q >= 0 then
                    UIDropDownMenu_SetText(ceQualDD, (QUALITY_COLORS[q] or "") .. QUALITY_NAMES[q] .. "|r")
                else UIDropDownMenu_SetText(ceQualDD, "Select...") end
            elseif vt == "upgradetrack" then
                local t = condEditorState.value
                if t and Wild.UPGRADE_TRACK_NAMES[t] then
                    UIDropDownMenu_SetText(ceTrackDD, Wild.UPGRADE_TRACK_NAMES[t])
                else UIDropDownMenu_SetText(ceTrackDD, "Select...") end
            elseif vt == "itemtype" then
                UIDropDownMenu_SetText(ceTypeDD, condEditorState.value and GetItemClassInfo(condEditorState.value) or "Select...")
            elseif vt == "itemsubtype" then
                local packed = condEditorState.value
                if packed then
                    local cid = math.floor(packed / 1000)
                    local sid = packed % 1000
                    condEditorState.subtypeParent = cid
                    UIDropDownMenu_SetText(ceSubParentDD, GetItemClassInfo(cid) or "?")
                    UIDropDownMenu_SetText(ceSubTypeDD, GetItemSubClassInfo(cid, sid) or "?")
                else
                    UIDropDownMenu_SetText(ceSubParentDD, "Select type...")
                    UIDropDownMenu_SetText(ceSubTypeDD, "Select...")
                end
            elseif vt == "equiploc" then
                UIDropDownMenu_SetText(ceEquipDD, condEditorState.value and (Wild.EQUIP_LOC_LABELS[condEditorState.value] or condEditorState.value) or "Select...")
            elseif vt == "profession" then
                UIDropDownMenu_SetText(ceProfDD, condEditorState.value and (Wild.PROFESSION_SKILL_LINES[condEditorState.value] or tostring(condEditorState.value)) or "Select...")
            elseif vt == "class" then
                UIDropDownMenu_SetText(ceClassDD, condEditorState.value and (Wild.CLASS_LABELS[condEditorState.value] or condEditorState.value) or "Select...")
            elseif vt == "bind" then
                UIDropDownMenu_SetText(ceBindDD, condEditorState.value and (Wild.BIND_LABELS[condEditorState.value] or condEditorState.value) or "Select...")
            elseif vt == "expansion" then
                UIDropDownMenu_SetText(ceExpanDD, condEditorState.value or "Select...")
            elseif vt == "boolean" then
                UIDropDownMenu_SetText(ceBoolDD, condEditorState.value == true and "Yes" or (condEditorState.value == false and "No" or "Select..."))
            end
        end
        UpdateCondEditorLayout()
    end

    local function CollectCondEditorValues()
        local attrDef = condEditorState.attr and Wild.ATTR_BY_KEY[condEditorState.attr]
        local vt = attrDef and attrDef.valueType or "string"
        if not condEditorState.ref then
            if vt == "number" or vt == "id" then condEditorState.value = tonumber(ceNumInput:GetText())
            elseif vt == "string" then condEditorState.value = ceStrInput:GetText() end
        end
        if condEditorState.ref then
            condEditorState.offset = tonumber(ceOffsetInput:GetText()) or 0
            if condEditorState.offset == 0 then condEditorState.offset = nil end
            condEditorState.value = nil
        end
    end

    local function ValidateCondition()
        if not condEditorState.attr then print("|cffff6600Wild:|r Select an attribute."); return false end
        if not condEditorState.op then print("|cffff6600Wild:|r Select an operator."); return false end
        if not condEditorState.ref and condEditorState.value == nil then print("|cffff6600Wild:|r Enter a value."); return false end
        return true
    end

    local UpdateSaveBtnAnchor  -- forward declaration

    local function ShowCondEditor(groupIdx, condIdx)
        editingGroupIdx = groupIdx
        editingCondIdx = condIdx
        local group = groupIdx and editorGroups[groupIdx]
        if condIdx and group and group.conditions[condIdx] then
            PopulateCondEditor(group.conditions[condIdx])
        else
            editingCondIdx = nil
            PopulateCondEditor(nil)
        end
        condEditor:Show()
        UpdateSaveBtnAnchor()
    end

    local function HideCondEditor()
        condEditor:Hide()
        editingCondIdx = nil
        editingGroupIdx = nil
        UpdateSaveBtnAnchor()
    end

    ceOkBtn:SetScript("OnClick", function()
        CollectCondEditorValues()
        if not ValidateCondition() then return end
        local saved = {
            attr = condEditorState.attr, op = condEditorState.op,
            value = condEditorState.value, ref = condEditorState.ref,
            offset = condEditorState.offset,
        }
        if editingGroupIdx and editorGroups[editingGroupIdx] then
            local group = editorGroups[editingGroupIdx]
            if editingCondIdx then
                group.conditions[editingCondIdx] = saved
            else
                table.insert(group.conditions, saved)
            end
        end
        HideCondEditor()
        RefreshCondList()
    end)

    ceCancelBtn:SetScript("OnClick", HideCondEditor)

    addCondBtn:SetScript("OnClick", function()
        -- Add a new include group with no conditions, then open the condition editor for it
        table.insert(editorGroups, { mode = "include", conditions = {} })
        local gi = #editorGroups
        RefreshCondList()
        ShowCondEditor(gi, nil)
    end)

    addExclGroupBtn:SetScript("OnClick", function()
        -- Add a new exclude group with no conditions, then open the condition editor for it
        table.insert(editorGroups, { mode = "exclude", conditions = {} })
        local gi = #editorGroups
        RefreshCondList()
        ShowCondEditor(gi, nil)
    end)

    RefreshCondList = function()
        for _, row in ipairs(condRows) do row:Hide() end
        condEmptyText:SetShown(#editorGroups == 0)
        local yOff = 0
        local rowIdx = 0

        for gi, group in ipairs(editorGroups) do
            -- Group header row
            rowIdx = rowIdx + 1
            local headerRow = condRows[rowIdx]
            if not headerRow then
                headerRow = CreateFrame("Frame", nil, condListFrame)
                headerRow:SetHeight(22)
                headerRow.text = headerRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                headerRow.text:SetPoint("LEFT", 4, 0)
                headerRow.text:SetPoint("RIGHT", headerRow, "RIGHT", -44, 0)
                headerRow.text:SetJustifyH("LEFT")
                headerRow.addBtn = CreateFrame("Button", nil, headerRow)
                headerRow.addBtn:SetSize(14, 14)
                headerRow.addBtn:SetPoint("RIGHT", -38, 0)
                headerRow.addBtn.label = headerRow.addBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                headerRow.addBtn.label:SetPoint("CENTER")
                headerRow.addBtn.label:SetText("|cff44ff44+|r")
                headerRow.addBtn:SetScript("OnEnter", function(self) self.label:SetText("|cff88ff88+|r") end)
                headerRow.addBtn:SetScript("OnLeave", function(self) self.label:SetText("|cff44ff44+|r") end)
                headerRow.toggleBtn = CreateFrame("Button", nil, headerRow)
                headerRow.toggleBtn:SetSize(14, 14)
                headerRow.toggleBtn:SetPoint("RIGHT", -20, 0)
                headerRow.toggleBtn.label = headerRow.toggleBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                headerRow.toggleBtn.label:SetPoint("CENTER")
                headerRow.removeBtn = CreateFrame("Button", nil, headerRow)
                headerRow.removeBtn:SetSize(14, 14)
                headerRow.removeBtn:SetPoint("RIGHT", -2, 0)
                headerRow.removeBtn.label = headerRow.removeBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                headerRow.removeBtn.label:SetPoint("CENTER")
                headerRow.removeBtn.label:SetText("|cffff4444X|r")
                headerRow.removeBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffff0000X|r") end)
                headerRow.removeBtn:SetScript("OnLeave", function(self) self.label:SetText("|cffff4444X|r") end)
                condRows[rowIdx] = headerRow
            end
            -- Ensure header-specific buttons exist (row may have been recycled from a condition row)
            if not headerRow.toggleBtn then
                headerRow.toggleBtn = CreateFrame("Button", nil, headerRow)
                headerRow.toggleBtn:SetSize(14, 14)
                headerRow.toggleBtn:SetPoint("RIGHT", -20, 0)
                headerRow.toggleBtn.label = headerRow.toggleBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                headerRow.toggleBtn.label:SetPoint("CENTER")
            end
            if not headerRow.addBtn then
                headerRow.addBtn = CreateFrame("Button", nil, headerRow)
                headerRow.addBtn:SetSize(14, 14)
                headerRow.addBtn:SetPoint("RIGHT", -38, 0)
                headerRow.addBtn.label = headerRow.addBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                headerRow.addBtn.label:SetPoint("CENTER")
                headerRow.addBtn.label:SetText("|cff44ff44+|r")
                headerRow.addBtn:SetScript("OnEnter", function(self) self.label:SetText("|cff88ff88+|r") end)
                headerRow.addBtn:SetScript("OnLeave", function(self) self.label:SetText("|cff44ff44+|r") end)
            end
            headerRow.toggleBtn:Show()
            headerRow.addBtn:Show()
            if headerRow.editBtn then headerRow.editBtn:Hide() end
            headerRow:SetPoint("TOPLEFT", condListFrame, "TOPLEFT", 0, -yOff)
            headerRow:SetPoint("RIGHT", condListFrame, "RIGHT", 0, 0)

            local modeColor = group.mode == "exclude" and "|cffff6666" or "|cff66ff66"
            local modeLabel = group.mode == "exclude" and "EXCLUDE" or "INCLUDE"
            local condCount = group.conditions and #group.conditions or 0
            local condSummary = ""
            if condCount > 0 then
                condSummary = " — " .. Wild.GetConditionsSummary(group.conditions)
            else
                condSummary = " — |cff888888(empty)|r"
            end
            headerRow.text:SetText(modeColor .. modeLabel .. "|r" .. condSummary)

            -- Toggle between include/exclude
            local toggleLabel = group.mode == "exclude" and "|cff66ff66I|r" or "|cffff6666E|r"
            headerRow.toggleBtn.label:SetText(toggleLabel)
            local capturedGi = gi
            headerRow.toggleBtn:SetScript("OnClick", function()
                editorGroups[capturedGi].mode = editorGroups[capturedGi].mode == "exclude" and "include" or "exclude"
                HideCondEditor()
                RefreshCondList()
            end)
            headerRow.toggleBtn:SetScript("OnEnter", function(self)
                local tip = editorGroups[capturedGi] and editorGroups[capturedGi].mode == "exclude" and "Switch to Include" or "Switch to Exclude"
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tip, 1, 1, 1)
                GameTooltip:Show()
            end)
            headerRow.toggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Add condition to this group
            headerRow.addBtn:SetScript("OnClick", function()
                ShowCondEditor(capturedGi, nil)
            end)
            headerRow.addBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Add condition to this group", 1, 1, 1)
                GameTooltip:Show()
            end)
            headerRow.addBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Remove this group
            headerRow.removeBtn:SetScript("OnClick", function()
                table.remove(editorGroups, capturedGi)
                HideCondEditor()
                RefreshCondList()
            end)
            headerRow:Show()
            yOff = yOff + 22

            -- Condition rows within this group
            if group.conditions then
                for ci, cond in ipairs(group.conditions) do
                    rowIdx = rowIdx + 1
                    local row = condRows[rowIdx]
                    if not row then
                        row = CreateFrame("Frame", nil, condListFrame)
                        row:SetHeight(20)
                        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                        row.text:SetPoint("LEFT", 16, 0)
                        row.text:SetPoint("RIGHT", row, "RIGHT", -44, 0)
                        row.text:SetJustifyH("LEFT")
                        row.editBtn = CreateFrame("Button", nil, row)
                        row.editBtn:SetSize(14, 14)
                        row.editBtn:SetPoint("RIGHT", -20, 0)
                        row.editBtn.label = row.editBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                        row.editBtn.label:SetPoint("CENTER")
                        row.editBtn.label:SetText("|cff88aaff...|r")
                        row.editBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffaaccff...|r") end)
                        row.editBtn:SetScript("OnLeave", function(self) self.label:SetText("|cff88aaff...|r") end)
                        row.removeBtn = CreateFrame("Button", nil, row)
                        row.removeBtn:SetSize(14, 14)
                        row.removeBtn:SetPoint("RIGHT", -2, 0)
                        row.removeBtn.label = row.removeBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                        row.removeBtn.label:SetPoint("CENTER")
                        row.removeBtn.label:SetText("|cffff4444X|r")
                        row.removeBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffff0000X|r") end)
                        row.removeBtn:SetScript("OnLeave", function(self) self.label:SetText("|cffff4444X|r") end)
                        condRows[rowIdx] = row
                    end
                    row:SetPoint("TOPLEFT", condListFrame, "TOPLEFT", 0, -yOff)
                    row:SetPoint("RIGHT", condListFrame, "RIGHT", 0, 0)
                    local attrDef = cond.attr and Wild.ATTR_BY_KEY[cond.attr]
                    local attrLbl = attrDef and attrDef.label or (cond.attr or "?")
                    local opLbl = cond.op or "?"
                    for _, op in ipairs(Wild.OPERATORS) do
                        if op.key == cond.op then opLbl = op.label; break end
                    end
                    local valStr = Wild.FormatConditionValue(cond, attrDef)
                    row.text:SetText("|cffcccccc" .. ci .. ".|r " .. attrLbl .. " |cff88aaff" .. opLbl .. "|r " .. (valStr or "?"))
                    local capturedGi2, capturedCi = gi, ci
                    if not row.editBtn then
                        row.editBtn = CreateFrame("Button", nil, row)
                        row.editBtn:SetSize(14, 14)
                        row.editBtn:SetPoint("RIGHT", -20, 0)
                        row.editBtn.label = row.editBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                        row.editBtn.label:SetPoint("CENTER")
                        row.editBtn.label:SetText("|cff88aaff...|r")
                        row.editBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffaaccff...|r") end)
                        row.editBtn:SetScript("OnLeave", function(self) self.label:SetText("|cff88aaff...|r") end)
                    end
                    row.editBtn:Show()
                    row.editBtn:SetScript("OnClick", function() ShowCondEditor(capturedGi2, capturedCi) end)
                    row.removeBtn:SetScript("OnClick", function()
                        table.remove(editorGroups[capturedGi2].conditions, capturedCi)
                        HideCondEditor()
                        RefreshCondList()
                    end)
                    -- Hide header-only buttons if they exist on recycled rows
                    if row.addBtn then row.addBtn:Hide() end
                    if row.toggleBtn then row.toggleBtn:Hide() end
                    row:Show()
                    yOff = yOff + 20
                end
            end
        end
        condListFrame:SetHeight(math.max(24, yOff + 4))
        if UpdateSaveBtnAnchor then UpdateSaveBtnAnchor() end
    end

    -- Intent-level Save / Cancel
    local saveBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    saveBtn:SetSize(80, 22)

    local cancelBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    cancelBtn:SetText("Cancel")

    UpdateSaveBtnAnchor = function()
        saveBtn:ClearAllPoints()
        if condEditor:IsShown() then
            saveBtn:SetPoint("TOPLEFT", condEditor, "BOTTOMLEFT", 2, -8)
        elseif addCondBtn:IsShown() then
            saveBtn:SetPoint("TOPLEFT", addCondBtn, "BOTTOMLEFT", -2, -12)
        elseif goldHint:IsShown() then
            saveBtn:SetPoint("TOPLEFT", goldHint, "BOTTOMLEFT", 0, -12)
        else
            saveBtn:SetPoint("TOPLEFT", actionLabel, "BOTTOMLEFT", 0, -40)
        end
        -- Resize editor to fit content after layout settles
        C_Timer.After(0, function()
            local top = editor:GetTop()
            local bottom = saveBtn:GetBottom()
            if top and bottom then
                editor:SetHeight(top - bottom + 16)
            end
            UpdateIntentsScrollHeight()
        end)
    end

    -- Layout helper — positions rows in table layout based on action
    local function UpdateEditorLayout()
        local action = editorIntent.action or "deposit"
        local isGold = (action == "gold")
        local isMail = (action == "mail")
        local isTransfer = (action == "transfer")
        local needsTarget = (action == "deposit" or action == "withdraw" or action == "gold" or action == "transfer")
        local needsKeep = (action ~= "gold")
        local needsCond = (action ~= "gold")

        sourceLabel:SetShown(needsTarget and not isTransfer)
        sourceDD:SetShown(needsTarget)
        transferSourceLabel:SetShown(isTransfer)
        transferSourceDD:SetShown(isTransfer)
        transferTargetLabel:SetShown(isTransfer)
        recipientLabel:SetShown(isMail)
        recipientInput:SetShown(isMail)
        goldLabel:SetShown(isGold)
        goldInput:SetShown(isGold)
        goldSuffix:SetShown(isGold)
        goldHint:SetShown(isGold)
        qtyLabel:SetShown(needsKeep)
        qtyAllCB:SetShown(needsKeep)
        qtyInput:SetShown(needsKeep)
        qtyHint:SetShown(needsKeep)
        destroyUnsellableCB:SetShown(action == "sell")
        condLabel:SetShown(needsCond)
        condListFrame:SetShown(needsCond)
        addCondBtn:SetShown(needsCond)
        addExclGroupBtn:SetShown(needsCond)

        -- Update keep hint based on action
        if action == "withdraw" then
            qtyHint:SetText("|cff888888items to keep in bank|r")
        elseif action == "transfer" then
            qtyHint:SetText("|cff888888items to keep in source bank|r")
        else
            qtyHint:SetText("|cff888888items to keep on character|r")
        end

        -- For gold, exclude character bank from target options
        if isGold and editorIntent.target == "character" then
            editorIntent.target = "warband"
            UIDropDownMenu_SetText(sourceDD, "Warband Bank")
        end

        -- For transfer, ensure source != target
        if isTransfer then
            if not editorIntent.source then editorIntent.source = "character" end
            if not editorIntent.target then editorIntent.target = "warband" end
            if editorIntent.source == editorIntent.target then
                editorIntent.target = editorIntent.source == "warband" and "character" or "warband"
            end
            local targetText = "Warband Bank"
            for _, opt in ipairs(TARGET_OPTIONS) do
                if opt.value == editorIntent.target then targetText = opt.text; break end
            end
            UIDropDownMenu_SetText(sourceDD, targetText)
        end

        -- Table layout: labels at COL_LEFT, inputs at COL_INPUT
        -- Action row is the first row below the actor section
        local rowY = 0  -- offset from actionLabel top

        actionLabel:ClearAllPoints()
        actionLabel:SetPoint("TOPLEFT", addActorDD, "BOTTOMLEFT", 16, -8)
        actionDD:ClearAllPoints()
        actionDD:SetPoint("LEFT", editor, "LEFT", COL_INPUT - 16, 0)
        actionDD:SetPoint("TOP", actionLabel, "TOP", 0, 2)

        local lastRowAnchor = actionLabel

        if isTransfer then
            -- From (source) row
            transferSourceLabel:ClearAllPoints()
            transferSourceLabel:SetPoint("TOPLEFT", lastRowAnchor, "BOTTOMLEFT", 0, ROW_SPACING)
            transferSourceDD:ClearAllPoints()
            transferSourceDD:SetPoint("LEFT", editor, "LEFT", COL_INPUT - 16, 0)
            transferSourceDD:SetPoint("TOP", transferSourceLabel, "TOP", 0, 2)
            lastRowAnchor = transferSourceLabel

            -- To (target) row
            transferTargetLabel:ClearAllPoints()
            transferTargetLabel:SetPoint("TOPLEFT", lastRowAnchor, "BOTTOMLEFT", 0, ROW_SPACING)
            sourceDD:ClearAllPoints()
            sourceDD:SetPoint("LEFT", editor, "LEFT", COL_INPUT - 16, 0)
            sourceDD:SetPoint("TOP", transferTargetLabel, "TOP", 0, 2)
            lastRowAnchor = transferTargetLabel
        elseif needsTarget then
            sourceLabel:ClearAllPoints()
            sourceLabel:SetPoint("TOPLEFT", lastRowAnchor, "BOTTOMLEFT", 0, ROW_SPACING)
            sourceDD:ClearAllPoints()
            sourceDD:SetPoint("LEFT", editor, "LEFT", COL_INPUT - 16, 0)
            sourceDD:SetPoint("TOP", sourceLabel, "TOP", 0, 2)
            lastRowAnchor = sourceLabel
        elseif isMail then
            recipientLabel:ClearAllPoints()
            recipientLabel:SetPoint("TOPLEFT", lastRowAnchor, "BOTTOMLEFT", 0, ROW_SPACING)
            recipientInput:ClearAllPoints()
            recipientInput:SetPoint("LEFT", editor, "LEFT", COL_INPUT, 0)
            recipientInput:SetPoint("TOP", recipientLabel, "TOP", 0, 0)
            lastRowAnchor = recipientLabel
        end

        if isGold then
            goldLabel:ClearAllPoints()
            goldLabel:SetPoint("TOPLEFT", lastRowAnchor, "BOTTOMLEFT", 0, ROW_SPACING)
            goldInput:ClearAllPoints()
            goldInput:SetPoint("LEFT", editor, "LEFT", COL_INPUT, 0)
            goldInput:SetPoint("TOP", goldLabel, "TOP", 0, 0)
            goldHint:ClearAllPoints()
            goldHint:SetPoint("TOPLEFT", goldLabel, "BOTTOMLEFT", 0, -4)
            lastRowAnchor = goldHint
        end

        if needsKeep then
            qtyLabel:ClearAllPoints()
            qtyLabel:SetPoint("TOPLEFT", lastRowAnchor, "BOTTOMLEFT", 0, ROW_SPACING - 4)
            qtyAllCB:ClearAllPoints()
            qtyAllCB:SetPoint("LEFT", editor, "LEFT", COL_INPUT, 0)
            qtyAllCB:SetPoint("TOP", qtyLabel, "TOP", 0, 3)
            qtyInput:ClearAllPoints()
            qtyInput:SetPoint("LEFT", qtyAllCB.Text, "RIGHT", 16, 0)
            qtyHint:ClearAllPoints()
            qtyHint:SetPoint("LEFT", qtyInput, "RIGHT", 8, 0)
            lastRowAnchor = qtyLabel
        end

        if action == "sell" then
            destroyUnsellableCB:ClearAllPoints()
            destroyUnsellableCB:SetPoint("TOPLEFT", lastRowAnchor, "BOTTOMLEFT", COL_INPUT - COL_LEFT, ROW_SPACING - 2)
            lastRowAnchor = destroyUnsellableCB
        end

        if needsCond then
            condLabel:ClearAllPoints()
            condLabel:SetPoint("TOPLEFT", lastRowAnchor, "BOTTOMLEFT", 0, -12)
        end

        UpdateSaveBtnAnchor()
    end

    UIDropDownMenu_Initialize(actionDD, function()
        for _, opt in ipairs(ACTION_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text; info.value = opt.value
            info.func = function(btn)
                editorIntent.action = btn.value
                UIDropDownMenu_SetText(actionDD, btn:GetText())
                CloseDropDownMenus()
                UpdateEditorLayout()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_Initialize(sourceDD, function()
        local action = editorIntent.action or "deposit"
        local opts
        if action == "gold" then
            opts = TARGET_OPTIONS_GOLD
        elseif action == "transfer" then
            -- For transfer, filter out the source value
            opts = {}
            for _, o in ipairs(TARGET_OPTIONS) do
                if o.value ~= editorIntent.source then
                    opts[#opts + 1] = o
                end
            end
        else
            opts = TARGET_OPTIONS
        end
        for _, opt in ipairs(opts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text; info.value = opt.value
            info.func = function(btn)
                editorIntent.target = btn.value
                UIDropDownMenu_SetText(sourceDD, btn:GetText())
                CloseDropDownMenus()
                UpdateEditorLayout()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_Initialize(transferSourceDD, function()
        -- Filter out the current target value
        local opts = {}
        for _, o in ipairs(TRANSFER_SOURCE_OPTIONS) do
            if o.value ~= editorIntent.target then
                opts[#opts + 1] = o
            end
        end
        for _, opt in ipairs(opts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text; info.value = opt.value
            info.func = function(btn)
                editorIntent.source = btn.value
                UIDropDownMenu_SetText(transferSourceDD, btn:GetText())
                CloseDropDownMenus()
                UpdateEditorLayout()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local function ShowEditor(intentIndex)
        editingIndex = intentIndex
        HideCondEditor()
        local intents = Wild.db and Wild.db.intents
        if intentIndex and intents and intents[intentIndex] then
            editorTitle:SetText("Edit Intent")
            saveBtn:SetText("Save")
            local intent = intents[intentIndex]
            editorIntent = {
                action = intent.action or "deposit",
                target = intent.target,
                source = intent.source,
                recipient = intent.recipient,
                goldTarget = intent.goldTarget,
                keep = intent.keep or 0,
                destroyUnsellable = intent.destroyUnsellable or false,
            }
            editorActors = {}
            for _, a in ipairs(intent.actors or {}) do
                table.insert(editorActors, { value = a.value, exclude = a.exclude })
            end
            editorGroups = {}
            for _, g in ipairs(intent.groups or {}) do
                local groupCopy = { mode = g.mode or "include", conditions = {} }
                for _, c in ipairs(g.conditions or {}) do
                    local copy = {}; for k, v in pairs(c) do copy[k] = v end
                    table.insert(groupCopy.conditions, copy)
                end
                table.insert(editorGroups, groupCopy)
            end
        else
            editingIndex = nil
            editorTitle:SetText("New Intent")
            saveBtn:SetText("Add")
            editorIntent = { action = "deposit", target = "warband", keep = 0 }
            editorActors = {}
            editorGroups = {}
        end

        -- Populate dropdowns
        local actionText = "Deposit"
        for _, opt in ipairs(ACTION_OPTIONS) do
            if opt.value == editorIntent.action then actionText = opt.text; break end
        end
        UIDropDownMenu_SetText(actionDD, actionText)

        RefreshActorList()

        local targetText = "Warband Bank"
        for _, opt in ipairs(TARGET_OPTIONS) do
            if opt.value == editorIntent.target then targetText = opt.text; break end
        end
        UIDropDownMenu_SetText(sourceDD, targetText)

        -- Populate transfer source dropdown
        local sourceText = "Personal Bank"
        for _, opt in ipairs(TRANSFER_SOURCE_OPTIONS) do
            if opt.value == editorIntent.source then sourceText = opt.text; break end
        end
        UIDropDownMenu_SetText(transferSourceDD, sourceText)

        recipientInput:SetText(editorIntent.recipient or "")
        goldInput:SetText(tostring(editorIntent.goldTarget or 1000))

        -- Keep
        local keep = editorIntent.keep or 0
        qtyAllCB:SetChecked(keep == 0)
        qtyInput:SetText(tostring(keep))
        qtyInput:SetEnabled(keep ~= 0)
        qtyInput:SetTextColor(keep == 0 and 0.5 or 1, keep == 0 and 0.5 or 1, keep == 0 and 0.5 or 1)

        -- Destroy unsellable
        destroyUnsellableCB:SetChecked(editorIntent.destroyUnsellable or false)

        RefreshCondList()
        UpdateEditorLayout()
        editor:Show()
    end

    local function HideEditor()
        editor:Hide()
        HideCondEditor()
        editingIndex = nil
        UpdateIntentsScrollHeight()
    end

    saveBtn:SetScript("OnClick", function()
        local action = editorIntent.action or "deposit"

        if action ~= "gold" then
            -- Validate: need at least one include group with conditions
            local hasInclude = false
            for _, g in ipairs(editorGroups) do
                if g.mode ~= "exclude" and g.conditions and #g.conditions > 0 then
                    hasInclude = true
                    break
                end
            end
            if not hasInclude then
                print("|cffff6600Wild:|r Add at least one include group with conditions.")
                return
            end
            -- Remove empty groups
            for i = #editorGroups, 1, -1 do
                if not editorGroups[i].conditions or #editorGroups[i].conditions == 0 then
                    table.remove(editorGroups, i)
                end
            end
        end

        if action == "mail" and (not editorIntent.recipient or editorIntent.recipient == "") then
            editorIntent.recipient = recipientInput:GetText()
            if not editorIntent.recipient or editorIntent.recipient == "" then
                print("|cffff6600Wild:|r Enter a recipient name.")
                return
            end
        end

        if not Wild.db.intents then Wild.db.intents = {} end

        local savedIntent = {
            enabled = true,
            action = action,
            actors = {},
            groups = {},
            keep = 0,
        }

        -- Copy actor filter entries
        for _, a in ipairs(editorActors) do
            table.insert(savedIntent.actors, { value = a.value, exclude = a.exclude or nil })
        end

        -- Preserve enabled state when editing
        if editingIndex and Wild.db.intents[editingIndex] then
            savedIntent.enabled = Wild.db.intents[editingIndex].enabled ~= false
        end

        if action == "deposit" or action == "withdraw" then
            savedIntent.target = editorIntent.target or "warband"
        elseif action == "transfer" then
            savedIntent.source = editorIntent.source or "character"
            savedIntent.target = editorIntent.target or "warband"
        elseif action == "gold" then
            savedIntent.target = editorIntent.target or "warband"
            savedIntent.goldTarget = tonumber(goldInput:GetText()) or 1000
        elseif action == "mail" then
            savedIntent.recipient = recipientInput:GetText() or ""
        end

        if action == "sell" and destroyUnsellableCB:GetChecked() then
            savedIntent.destroyUnsellable = true
        end

        if action ~= "gold" then
            if qtyAllCB:GetChecked() then
                savedIntent.keep = 0
            else
                savedIntent.keep = tonumber(qtyInput:GetText()) or 0
            end
            for _, g in ipairs(editorGroups) do
                local savedGroup = { mode = g.mode or "include", conditions = {} }
                for _, c in ipairs(g.conditions or {}) do
                    local copy = {}; for k, v in pairs(c) do copy[k] = v end
                    table.insert(savedGroup.conditions, copy)
                end
                table.insert(savedIntent.groups, savedGroup)
            end
        end

        if editingIndex then
            Wild.db.intents[editingIndex] = savedIntent
        else
            table.insert(Wild.db.intents, savedIntent)
        end

        HideEditor()
        RefreshIntentList()
    end)

    cancelBtn:SetScript("OnClick", HideEditor)
    addBtn:SetScript("OnClick", function() ShowEditor(nil) end)

    RefreshIntentList = function()
        for _, row in ipairs(intentRows) do row:Hide() end
        local intents = Wild.db and Wild.db.intents or {}
        emptyText:SetShown(#intents == 0)

        local yOffset = 0
        for i, intent in ipairs(intents) do
            local row = intentRows[i]
            if not row then
                row = CreateFrame("Frame", nil, intentScrollChild)
                row:SetHeight(24)
                row.enableBtn = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
                row.enableBtn:SetPoint("LEFT", 2, 0)
                row.enableBtn:SetScale(0.75)
                row.enableBtn.Text:SetText("")
                row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row.enableBtn, "RIGHT", 4, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -82, 0)
                row.text:SetJustifyH("LEFT")
                row.upBtn = CreateFrame("Button", nil, row)
                row.upBtn:SetSize(16, 16)
                row.upBtn:SetPoint("RIGHT", -62, 0)
                row.upBtn.label = row.upBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                row.upBtn.label:SetPoint("CENTER")
                row.upBtn.label:SetText("|cff88aaff^|r")
                row.upBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffaaccff^|r") end)
                row.upBtn:SetScript("OnLeave", function(self) self.label:SetText("|cff88aaff^|r") end)
                row.downBtn = CreateFrame("Button", nil, row)
                row.downBtn:SetSize(16, 16)
                row.downBtn:SetPoint("RIGHT", -46, 0)
                row.downBtn.label = row.downBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                row.downBtn.label:SetPoint("CENTER")
                row.downBtn.label:SetText("|cff88aaffv|r")
                row.downBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffaaccffv|r") end)
                row.downBtn:SetScript("OnLeave", function(self) self.label:SetText("|cff88aaffv|r") end)
                row.editBtn = CreateFrame("Button", nil, row)
                row.editBtn:SetSize(16, 16)
                row.editBtn:SetPoint("RIGHT", -22, 0)
                row.editBtn.label = row.editBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                row.editBtn.label:SetPoint("CENTER")
                row.editBtn.label:SetText("|cff88aaff...|r")
                row.editBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffaaccff...|r") end)
                row.editBtn:SetScript("OnLeave", function(self) self.label:SetText("|cff88aaff...|r") end)
                row.removeBtn = CreateFrame("Button", nil, row)
                row.removeBtn:SetSize(16, 16)
                row.removeBtn:SetPoint("RIGHT", -2, 0)
                row.removeBtn.label = row.removeBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                row.removeBtn.label:SetPoint("CENTER")
                row.removeBtn.label:SetText("|cffff4444X|r")
                row.removeBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffff0000X|r") end)
                row.removeBtn:SetScript("OnLeave", function(self) self.label:SetText("|cffff4444X|r") end)
                intentRows[i] = row
            end

            row:SetPoint("TOPLEFT", intentScrollChild, "TOPLEFT", 0, -yOffset)
            row:SetPoint("RIGHT", intentScrollChild, "RIGHT", 0, 0)
            row.text:SetText(Wild.GetIntentSummary(intent))
            row.enableBtn:SetChecked(intent.enabled ~= false)

            local idx = i
            local numIntents = #intents
            row.upBtn:SetShown(idx > 1)
            row.downBtn:SetShown(idx < numIntents)
            row.upBtn:SetScript("OnClick", function()
                if idx > 1 then
                    intents[idx], intents[idx - 1] = intents[idx - 1], intents[idx]
                    HideEditor()
                    RefreshIntentList()
                end
            end)
            row.downBtn:SetScript("OnClick", function()
                if idx < numIntents then
                    intents[idx], intents[idx + 1] = intents[idx + 1], intents[idx]
                    HideEditor()
                    RefreshIntentList()
                end
            end)
            row.enableBtn:SetScript("OnClick", function(self)
                intents[idx].enabled = self:GetChecked()
            end)
            row.editBtn:SetScript("OnClick", function() ShowEditor(idx) end)
            row.removeBtn:SetScript("OnClick", function()
                table.remove(Wild.db.intents, idx)
                HideEditor()
                RefreshIntentList()
            end)

            row:Show()
            yOffset = yOffset + 26
        end

        intentScrollChild:SetHeight(math.max(1, yOffset))
        listFrame:SetHeight(math.max(30, math.min(yOffset + 8, 300)))
        local containerWidth = intentScroll:GetWidth()
        if containerWidth > 0 then intentScrollChild:SetWidth(containerWidth) end
        UpdateIntentsScrollHeight()
    end

    panel:SetScript("OnShow", function()
        RefreshIntentList()
    end)

    return panel
end

-- ============================================================
-- Tab: Actors (Character data & labels)
-- ============================================================

local function CreateActorsTab()
    local panel = CreateFrame("Frame")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local sc = CreateFrame("Frame")
    sc:SetWidth(520)
    sc:SetHeight(400)
    scrollFrame:SetScrollChild(sc)
    HookScrollChildWidth(scrollFrame, sc)

    local function UpdateActorsScrollHeight()
        C_Timer.After(0, function()
            local scTop = sc:GetTop()
            if not scTop then return end
            local lowest
            local children = { sc:GetChildren() }
            for _, child in ipairs(children) do
                if child:IsShown() then
                    local bottom = child:GetBottom()
                    if bottom and (not lowest or bottom < lowest) then
                        lowest = bottom
                    end
                end
            end
            if lowest then
                sc:SetHeight(math.max(400, scTop - lowest + 20))
            end
        end)
    end

    local title = sc:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Actors")

    local desc = sc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff888888Characters are automatically discovered when they log in. You can assign custom labels to group characters together.|r")

    -- =========================================
    -- Section: Custom Labels
    -- =========================================
    local labelSectionTitle = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    labelSectionTitle:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
    labelSectionTitle:SetText("Custom Labels")

    local labelListFrame = CreateFrame("Frame", nil, sc, "BackdropTemplate")
    labelListFrame:SetPoint("TOPLEFT", labelSectionTitle, "BOTTOMLEFT", -4, -8)
    labelListFrame:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    labelListFrame:SetHeight(80)
    labelListFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    labelListFrame:SetBackdropColor(0, 0, 0, 0.2)
    labelListFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)

    local labelRows = {}
    local labelEmptyText = labelListFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    labelEmptyText:SetPoint("TOPLEFT", 6, -6)
    labelEmptyText:SetText("|cff666666No custom labels. Add one below.|r")

    local RefreshLabelList
    local RefreshCharList

    local addLabelInput = CreateFrame("EditBox", nil, sc, "InputBoxTemplate")
    addLabelInput:SetSize(180, 22)
    addLabelInput:SetPoint("TOPLEFT", labelListFrame, "BOTTOMLEFT", 6, -8)
    addLabelInput:SetAutoFocus(false)
    addLabelInput:SetMaxLetters(30)
    addLabelInput:SetFontObject("GameFontHighlight")

    local addLabelBtn = CreateFrame("Button", nil, sc, "UIPanelButtonTemplate")
    addLabelBtn:SetSize(90, 22)
    addLabelBtn:SetPoint("LEFT", addLabelInput, "RIGHT", 8, 0)
    addLabelBtn:SetText("Add Label")
    addLabelBtn:SetScript("OnClick", function()
        local text = addLabelInput:GetText()
        if not text or text:match("^%s*$") then return end
        text = text:match("^%s*(.-)%s*$") -- trim

        if not Wild.db.actors then Wild.db.actors = { characters = {}, labels = {} } end
        if not Wild.db.actors.labels then Wild.db.actors.labels = {} end

        -- Prevent duplicates
        for _, lbl in ipairs(Wild.db.actors.labels) do
            if lbl.name == text then
                print("|cffff6600Wild:|r Label '" .. text .. "' already exists.")
                return
            end
        end

        table.insert(Wild.db.actors.labels, { name = text })
        addLabelInput:SetText("")
        RefreshLabelList()
    end)

    addLabelInput:SetScript("OnEnterPressed", function()
        addLabelBtn:Click()
    end)

    RefreshLabelList = function()
        for _, row in ipairs(labelRows) do row:Hide() end
        local labels = Wild.db and Wild.db.actors and Wild.db.actors.labels or {}
        labelEmptyText:SetShown(#labels == 0)

        local yOffset = 0
        for i, lbl in ipairs(labels) do
            local row = labelRows[i]
            if not row then
                row = CreateFrame("Frame", nil, labelListFrame)
                row:SetHeight(22)
                row.enableCB = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
                row.enableCB:SetPoint("LEFT", 2, 0)
                row.enableCB:SetScale(0.75)
                row.enableCB.Text:SetText("")
                row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row.enableCB, "RIGHT", 4, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -24, 0)
                row.text:SetJustifyH("LEFT")
                row.removeBtn = CreateFrame("Button", nil, row)
                row.removeBtn:SetSize(16, 16)
                row.removeBtn:SetPoint("RIGHT", -2, 0)
                row.removeBtn.label = row.removeBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                row.removeBtn.label:SetPoint("CENTER")
                row.removeBtn.label:SetText("|cffff4444X|r")
                row.removeBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffff0000X|r") end)
                row.removeBtn:SetScript("OnLeave", function(self) self.label:SetText("|cffff4444X|r") end)
                labelRows[i] = row
            end

            row:SetPoint("TOPLEFT", labelListFrame, "TOPLEFT", 0, -yOffset)
            row:SetPoint("RIGHT", labelListFrame, "RIGHT", 0, 0)
            row.text:SetText(lbl.name)
            row.enableCB:SetChecked(lbl.enabled ~= false)

            if lbl.enabled == false then
                row.text:SetText("|cff666666" .. lbl.name .. "|r")
            else
                row.text:SetText(lbl.name)
            end

            local idx = i
            row.enableCB:SetScript("OnClick", function(self)
                labels[idx].enabled = self:GetChecked()
                RefreshLabelList()
            end)
            row.removeBtn:SetScript("OnClick", function()
                -- Remove label from all characters
                local chars = Wild.db.actors.characters or {}
                for _, char in pairs(chars) do
                    if char.labels then
                        for j = #char.labels, 1, -1 do
                            if char.labels[j] == lbl.name then
                                table.remove(char.labels, j)
                            end
                        end
                    end
                end
                table.remove(Wild.db.actors.labels, idx)
                RefreshLabelList()
                RefreshCharList()
            end)

            row:Show()
            yOffset = yOffset + 22
        end

        labelListFrame:SetHeight(math.max(28, yOffset + 4))
        UpdateActorsScrollHeight()
    end

    -- =========================================
    -- Section: Characters
    -- =========================================
    local charSep = sc:CreateTexture(nil, "ARTWORK")
    charSep:SetHeight(1)
    charSep:SetPoint("TOPLEFT", addLabelInput, "BOTTOMLEFT", -6, -20)
    charSep:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    charSep:SetColorTexture(0.3, 0.3, 0.35, 0.6)

    local charSectionTitle = sc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    charSectionTitle:SetPoint("TOPLEFT", charSep, "BOTTOMLEFT", 0, -12)
    charSectionTitle:SetText("Characters")

    local charListFrame = CreateFrame("Frame", nil, sc)
    charListFrame:SetPoint("TOPLEFT", charSectionTitle, "BOTTOMLEFT", 0, -8)
    charListFrame:SetPoint("RIGHT", sc, "RIGHT", -16, 0)
    charListFrame:SetHeight(1)

    local charWidgets = {}
    local charEmptyText = charListFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    charEmptyText:SetPoint("TOPLEFT", 0, 0)
    charEmptyText:SetText("|cff666666No characters discovered yet. Log in on your alts.|r")

    local function FormatAutoLabels(char)
        local parts = {}
        -- Class
        local classLabel = Wild.CLASS_LABELS and Wild.CLASS_LABELS[char.class] or char.class
        if classLabel then parts[#parts + 1] = classLabel end
        -- Race
        if char.race then parts[#parts + 1] = char.race end
        -- Faction
        if char.faction then parts[#parts + 1] = char.faction end
        -- Professions
        if char.professions then
            for skillLine, profName in pairs(char.professions) do
                if type(profName) == "string" then
                    parts[#parts + 1] = profName
                elseif Wild.PROFESSION_SKILL_LINES and Wild.PROFESSION_SKILL_LINES[skillLine] then
                    parts[#parts + 1] = Wild.PROFESSION_SKILL_LINES[skillLine]
                end
            end
        end
        return table.concat(parts, ", ")
    end

    local function FormatCustomLabels(char)
        if not char.labels or #char.labels == 0 then return "" end
        return table.concat(char.labels, ", ")
    end

    local function GetSortedCharKeys()
        local keys = {}
        local chars = Wild.db and Wild.db.actors and Wild.db.actors.characters or {}
        for k in pairs(chars) do
            keys[#keys + 1] = k
        end
        -- Sort: current character first, then by name
        local currentFullName = UnitName("player") .. "-" .. GetRealmName()
        table.sort(keys, function(a, b)
            if a == currentFullName then return true end
            if b == currentFullName then return false end
            return a < b
        end)
        return keys
    end

    RefreshCharList = function()
        for _, w in ipairs(charWidgets) do w:Hide() end
        local chars = Wild.db and Wild.db.actors and Wild.db.actors.characters or {}
        local keys = GetSortedCharKeys()
        charEmptyText:SetShown(#keys == 0)

        local currentFullName = UnitName("player") .. "-" .. GetRealmName()
        local yOffset = 0

        for i, charKey in ipairs(keys) do
            local char = chars[charKey]
            local w = charWidgets[i]
            if not w then
                w = CreateFrame("Frame", nil, charListFrame, "BackdropTemplate")
                w:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                w:SetBackdropColor(0.08, 0.08, 0.12, 0.6)
                w:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.5)

                w.nameText = w:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                w.nameText:SetPoint("TOPLEFT", 8, -6)

                w.infoText = w:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                w.infoText:SetPoint("TOPLEFT", w.nameText, "BOTTOMLEFT", 0, -2)
                w.infoText:SetPoint("RIGHT", w, "RIGHT", -8, 0)
                w.infoText:SetJustifyH("LEFT")

                w.autoLabelsTitle = w:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                w.autoLabelsTitle:SetPoint("TOPLEFT", w.infoText, "BOTTOMLEFT", 0, -4)
                w.autoLabelsTitle:SetText("|cff888888Auto:|r")

                w.autoLabels = w:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                w.autoLabels:SetPoint("LEFT", w.autoLabelsTitle, "RIGHT", 4, 0)
                w.autoLabels:SetPoint("RIGHT", w, "RIGHT", -8, 0)
                w.autoLabels:SetJustifyH("LEFT")

                w.customLabelsTitle = w:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                w.customLabelsTitle:SetPoint("TOPLEFT", w.autoLabelsTitle, "BOTTOMLEFT", 0, -2)
                w.customLabelsTitle:SetText("|cff888888Labels:|r")

                w.customLabels = w:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                w.customLabels:SetPoint("LEFT", w.customLabelsTitle, "RIGHT", 4, 0)
                w.customLabels:SetPoint("RIGHT", w, "RIGHT", -40, 0)
                w.customLabels:SetJustifyH("LEFT")

                w.editBtn = CreateFrame("Button", nil, w)
                w.editBtn:SetSize(16, 16)
                w.editBtn:SetPoint("RIGHT", -6, 0)
                w.editBtn.label = w.editBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                w.editBtn.label:SetPoint("CENTER")
                w.editBtn.label:SetText("|cff88aaff...|r")
                w.editBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffaaccff...|r") end)
                w.editBtn:SetScript("OnLeave", function(self) self.label:SetText("|cff88aaff...|r") end)

                w.removeBtn = CreateFrame("Button", nil, w)
                w.removeBtn:SetSize(16, 16)
                w.removeBtn:SetPoint("TOPRIGHT", -6, -6)
                w.removeBtn.label = w.removeBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                w.removeBtn.label:SetPoint("CENTER")
                w.removeBtn.label:SetText("|cffff4444X|r")
                w.removeBtn:SetScript("OnEnter", function(self) self.label:SetText("|cffff0000X|r") end)
                w.removeBtn:SetScript("OnLeave", function(self) self.label:SetText("|cffff4444X|r") end)

                -- Label toggle dropdown (on editBtn click)
                w.labelMenu = CreateFrame("Frame", "WildActorLabelMenu" .. i, w, "UIDropDownMenuTemplate")
                w.labelMenu:SetPoint("CENTER", w, "CENTER", 0, 0)
                w.labelMenu:Hide()

                charWidgets[i] = w
            end

            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", charListFrame, "TOPLEFT", 0, -yOffset)
            w:SetPoint("RIGHT", charListFrame, "RIGHT", 0, 0)

            -- Name with class color
            local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.class]
            local nameStr = char.name or charKey
            if classColor then
                nameStr = string.format("|cff%02x%02x%02x%s|r", classColor.r * 255, classColor.g * 255, classColor.b * 255, nameStr)
            end
            if charKey == currentFullName then
                nameStr = nameStr .. "  |cff00ff00(current)|r"
            end
            w.nameText:SetText(nameStr)

            -- Info line: Level, iLvl, Realm
            local infoParts = {}
            if char.level then infoParts[#infoParts + 1] = "Level " .. char.level end
            if char.ilvl and char.ilvl > 0 then infoParts[#infoParts + 1] = "iLvl " .. char.ilvl end
            if char.realm then infoParts[#infoParts + 1] = char.realm end
            w.infoText:SetText("|cffaaaaaa" .. table.concat(infoParts, "  ·  ") .. "|r")

            w.autoLabels:SetText(FormatAutoLabels(char))

            local customStr = FormatCustomLabels(char)
            w.customLabels:SetText(customStr ~= "" and customStr or "|cff666666none|r")

            -- Edit button: toggle label menu
            local thisCharKey = charKey
            w.editBtn:SetScript("OnClick", function(self)
                local labels = Wild.db.actors.labels or {}
                if #labels == 0 then
                    print("|cffff6600Wild:|r Create custom labels first.")
                    return
                end

                local menuFrame = w.labelMenu
                UIDropDownMenu_Initialize(menuFrame, function()
                    local charData = Wild.db.actors.characters[thisCharKey]
                    if not charData then return end
                    if not charData.labels then charData.labels = {} end

                    for _, lbl in ipairs(labels) do
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = lbl.name
                        info.isNotRadio = true
                        info.keepShownOnClick = true

                        -- Check if character has this label
                        local hasLabel = false
                        for _, cl in ipairs(charData.labels) do
                            if cl == lbl.name then hasLabel = true; break end
                        end
                        info.checked = hasLabel

                        info.func = function(btn)
                            if not charData.labels then charData.labels = {} end
                            if hasLabel then
                                for j = #charData.labels, 1, -1 do
                                    if charData.labels[j] == lbl.name then
                                        table.remove(charData.labels, j)
                                    end
                                end
                            else
                                table.insert(charData.labels, lbl.name)
                            end
                            RefreshCharList()
                        end
                        UIDropDownMenu_AddButton(info)
                    end
                end, "MENU")
                ToggleDropDownMenu(1, nil, menuFrame, self, 0, 0)
            end)

            -- Remove button: remove character (don't allow removing current)
            w.removeBtn:SetShown(charKey ~= currentFullName)
            w.removeBtn:SetScript("OnClick", function()
                Wild.db.actors.characters[thisCharKey] = nil
                RefreshCharList()
            end)

            w:SetHeight(76)
            w:Show()
            yOffset = yOffset + 80
        end

        charListFrame:SetHeight(math.max(1, yOffset))
        UpdateActorsScrollHeight()
    end

    panel:SetScript("OnShow", function()
        RefreshLabelList()
        RefreshCharList()
    end)

    return panel
end

-- ============================================================
-- Initialize
-- ============================================================
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addon)
    if addon ~= ADDON_NAME then return end

    -- Build the window and tabs
    CreateMainFrame()
    AddTab("LFG", CreateLFGTab())
    AddTab("Center Circle", CreateCircleTab())
    AddCollapsibleGroup("Intents")
    AddTab("Intent Rules", CreateIntentRulesTab(), true)
    AddTab("Actors", CreateActorsTab(), true)
    EndCollapsibleGroup()
    AddTab("Character", CreateCharacterTab())
    AddTab("Auction House", CreateAuctionHouseTab())
    AddTab("Mail", CreateMailTab())
    AddTab("Inventory", CreateInventoryTab())
    AddTab("Loot", CreateLootTab())
    AddTab("Quests", CreateQuestsTab())
    AddTab("Gossip", CreateGossipTab())
    AddTab("Darkmoon Faire", CreateDarkmoonFaireTab())
    AddTab("Tooltips", CreateTooltipTab())
    AddCollapsibleGroup("Group and Raid")
    AddTab("Dungeon Bar", CreateDungeonBarTab(), true)
    AddTab("Auto-Reply", CreateAutoReplyTab(), true)
    EndCollapsibleGroup()
    AddTab("Delve", CreateDelveTab())
    AddTab("Advanced", CreateAdvancedTab())
    LayoutSidebar()
    SelectTab("LFG")
    mainFrame:Hide()

    self:UnregisterEvent("ADDON_LOADED")
end)
