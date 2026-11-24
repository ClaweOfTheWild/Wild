-- Wild: Browse and search recorded inventory
local ADDON_NAME, Wild = ...

local ROW_HEIGHT = 36
local ICON_SIZE = 30
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local MAX_ITEM_LOADS = 12
local ITEM_LOAD_TIMEOUT = 5
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}
local window, launcher

local function HideOwnedTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function ShowResultTooltip(row)
    local item = row:GetElementData()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if item.link and item.link:find("|Hitem:", 1, true) then
        GameTooltip:SetHyperlink(item.link)
    else
        GameTooltip:SetItemByID(item.itemID)
    end
    GameTooltip:Show()
end

local function UpdateResultDetails(row, item, loading)
    row.icon:SetTexture(item.icon or C_Item.GetItemIconByID(item.itemID) or FALLBACK_ICON)
    row.label:SetText(item.name or C_Item.GetItemNameByID(item.itemID)
        or (loading and "Loading item..." or "Item name unavailable"))
end

local function SetResult(row, item, loading)
    if not row.icon then
        row.wildItemSearchResult = true
        row:EnableMouse(true)
        row:SetScript("OnEnter", ShowResultTooltip)
        row:SetScript("OnLeave", HideOwnedTooltip)
        row:SetScript("OnHide", HideOwnedTooltip)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetPoint("LEFT")

        row.idText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.idText:SetPoint("RIGHT", -4, 0)

        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.label:SetPoint("RIGHT", row.idText, "LEFT", -12, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
    else
        HideOwnedTooltip(row)
    end

    UpdateResultDetails(row, item, loading)
    row.idText:SetText("ID: " .. item.itemID)
end

local function CreateSearchWindow()
    local panel = CreateFrame("Frame", "WildItemSearchWindow", UIParent, "BackdropTemplate")
    panel:Hide()
    panel:SetPoint("CENTER")
    panel:SetSize(500, 520)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetDontSavePosition(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:SetBackdrop(BACKDROP)
    panel:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
    panel:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
    tinsert(UISpecialFrames, panel:GetName())

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Wild Item Search")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() panel:Hide() end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", panel, "RIGHT", -28, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Search by partial name or exact item ID. Hover over an item to see its recorded locations.")

    local search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    search:SetAutoFocus(false)
    search:SetHeight(24)
    search:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 4, -10)
    search:SetPoint("RIGHT", panel, "RIGHT", -28, 0)
    if search.Instructions then search.Instructions:SetText("Item name or ID") end

    local scroll = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
    scroll:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -4, -12)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    local bar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)

    local empty = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", scroll, "TOPLEFT")

    local requested, pending, completed = {}, {}, {}
    local pendingCount = 0
    local matches, nextMatch, unnamed, ProcessLoads

    local function CanRequest(itemID)
        return not requested[itemID] and not C_Item.IsItemDataCachedByID(itemID)
    end

    local function IsLoading(itemID)
        return pending[itemID] ~= nil or CanRequest(itemID)
    end

    local function ScheduleLoads()
        if panel:IsVisible() then panel:SetScript("OnUpdate", ProcessLoads) end
    end

    local function Refresh(retainPosition)
        local query = strtrim(search:GetText())
        local items
        items, unnamed = Wild.FindItems(query, true)
        matches, nextMatch = query ~= "" and items or nil, 1
        if #items == 0 then
            local status = query == "" and "No items recorded yet." or "No matching items in your recorded inventory."
            if unnamed and next(unnamed) then
                status = "No matches in available item names."
                for itemID in pairs(unnamed) do
                    if IsLoading(itemID) then
                        status = "Loading item names..."
                        break
                    end
                end
            end
            empty:SetText(status)
        end
        empty:SetShown(#items == 0)
        scroll:SetDataProvider(CreateDataProvider(items), retainPosition)
    end

    local function CompleteLoad(itemID, success)
        local timer = pending[itemID]
        if timer then
            pending[itemID] = nil
            pendingCount = pendingCount - 1
            timer:Cancel()
        end
        if success then requested[itemID] = "loaded" end
        if panel:IsVisible() then
            completed[itemID] = success
            ScheduleLoads()
        end
    end

    ProcessLoads = function()
        panel:SetScript("OnUpdate", nil)
        local changes = completed
        completed = {}
        for itemID in pairs(changes) do
            if unnamed and unnamed[itemID] then
                Refresh(true)
                break
            end
        end

        local budget = MAX_ITEM_LOADS - pendingCount
        local function Request(itemID)
            if budget == 0 or not CanRequest(itemID) then return end
            budget = budget - 1
            requested[itemID] = true
            pendingCount = pendingCount + 1
            pending[itemID] = C_Timer.NewTimer(ITEM_LOAD_TIMEOUT, function() CompleteLoad(itemID, false) end)
            C_Item.RequestLoadItemDataByID(itemID)
        end

        -- Browse the visible page first. Search also resolves unnamed items and loads all matches.
        scroll:ForEachFrame(function(row, item)
            if not row:IsVisible() then return end
            UpdateResultDetails(row, item, IsLoading(item.itemID))
            if changes[item.itemID] and GameTooltip:IsOwned(row) and GameTooltip:IsShown() then
                ShowResultTooltip(row)
            end
            Request(item.itemID)
        end)
        if unnamed then
            for itemID in pairs(unnamed) do
                if budget == 0 then break end
                Request(itemID)
            end
        end
        while matches and budget > 0 and nextMatch <= #matches do
            local itemID = matches[nextMatch].itemID
            nextMatch = nextMatch + 1
            Request(itemID)
        end
    end

    view:SetElementInitializer("Frame", function(row, item)
        local loading = IsLoading(item.itemID)
        SetResult(row, item, loading)
        if loading then ScheduleLoads() end
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scroll, bar, view)

    panel:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    panel:SetScript("OnEvent", function(_, _, itemID, success)
        local state = requested[itemID]
        if pending[itemID] or (success and (state == true or (not state and unnamed and unnamed[itemID]))) then
            CompleteLoad(itemID, success)
        end
    end)

    local function ApplyQuery()
        if not panel:IsVisible() then return end
        Refresh(false)
        if matches then ScheduleLoads() end
    end
    search:HookScript("OnTextChanged", ApplyQuery)
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ApplyQuery()
    end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    panel:SetScript("OnShow", function()
        for itemID in pairs(requested) do
            if not pending[itemID] then requested[itemID] = nil end
        end
        ApplyQuery()
    end)
    panel:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        matches, unnamed, completed = nil, nil, {}
        self:StopMovingOrSizing()
        search:ClearFocus()
    end)
    return panel
end

function Wild.OpenItemSearch()
    if not window then window = CreateSearchWindow() end
    window:Show()
end

local function StopLauncherDrag(button)
    if not button.isDragging then return end
    button.isDragging = nil
    button:StopMovingOrSizing()
    local point, _, relativePoint, x, y = button:GetPoint(1)
    local config = Wild.GetSetting("itemSearch")
    if point and config.showButton and not config.locked then
        config.buttonPos = { point, relativePoint, x, y }
    end
end

local function CreateSearchLauncher()
    local button = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    button:SetSize(28, 28)
    button:SetFrameStrata("HIGH")
    button:SetClampedToScreen(true)
    button:SetDontSavePosition(true)
    button:SetBackdrop(BACKDROP)
    button:SetBackdropColor(0.08, 0.08, 0.10, 0.92)
    button:SetBackdropBorderColor(0.5, 0.42, 0.27, 1)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas("common-search-magnifyingglass")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnMouseDown", function(self) self.wasDragged = false end)
    button:SetScript("OnDragStart", function(self)
        self.isDragging, self.wasDragged = true, true
        self:StartMoving()
    end)
    button:SetScript("OnDragStop", StopLauncherDrag)
    button:SetScript("OnClick", function(self, mouseButton)
        if self.wasDragged then return end
        if mouseButton == "RightButton" then
            Wild.OpenSettings("Item Search")
        elseif mouseButton == "LeftButton" then
            Wild.OpenItemSearch()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Wild Item Search")
        GameTooltip:AddLine("Left-click to open Item Search.\nRight-click for settings.")
        if Wild.GetSetting("itemSearch.locked") then
            GameTooltip:AddLine("Button position is locked.")
        else
            GameTooltip:AddLine("Drag to move.")
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", HideOwnedTooltip)
    button:SetScript("OnHide", HideOwnedTooltip)
    return button
end

function Wild.UpdateItemSearchLauncher()
    local config = Wild.GetSetting("itemSearch")
    if not config or not config.showButton then
        if launcher then
            StopLauncherDrag(launcher)
            launcher:Hide()
        end
        return
    end

    if not launcher then launcher = CreateSearchLauncher() end
    StopLauncherDrag(launcher)
    launcher:SetMovable(not config.locked)
    if config.locked then
        launcher:RegisterForDrag()
    else
        launcher:RegisterForDrag("LeftButton")
    end

    local pos = config.buttonPos
    launcher:ClearAllPoints()
    if pos then
        launcher:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        launcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 54, -20)
    end
    launcher:Show()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    Wild.UpdateItemSearchLauncher()
end)
