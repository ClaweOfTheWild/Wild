-- Wild: Reputation management
local ADDON_NAME, Wild = ...

-- ============================================================
-- Helpers
-- ============================================================

local function GetCurrentExpansionName()
    local level = GetExpansionLevel()
    return _G["EXPANSION_NAME" .. level]
end

-- ============================================================
-- Save current collapse state (for "remember" mode)
-- ============================================================

local function SaveCollapseState()
    if not Wild.db then return end
    local saved = {}
    local numFactions = C_Reputation.GetNumFactions()
    for i = 1, numFactions do
        local data = C_Reputation.GetFactionDataByIndex(i)
        if data and data.isHeader and not data.isChild then
            saved[data.name] = data.isCollapsed and true or false
        end
    end
    Wild.db.reputationCollapsedHeaders = saved
end

-- ============================================================
-- Restore saved collapse state (for "remember" mode)
-- ============================================================

local function RestoreCollapseState()
    if not Wild.db then return end
    local saved = Wild.db.reputationCollapsedHeaders
    if not saved or not next(saved) then return end

    -- First expand all so we can iterate cleanly
    C_Reputation.ExpandAllFactionHeaders()

    local headersToCollapse = {}
    local numFactions = C_Reputation.GetNumFactions()
    for i = 1, numFactions do
        local data = C_Reputation.GetFactionDataByIndex(i)
        if data and data.isHeader and not data.isChild then
            if saved[data.name] then
                table.insert(headersToCollapse, i)
            end
        end
    end
    for j = #headersToCollapse, 1, -1 do
        C_Reputation.CollapseFactionHeader(headersToCollapse[j])
    end
end

-- ============================================================
-- Collapse modes
-- ============================================================

local function CollapseAllExpansions()
    local headersToCollapse = {}
    local numFactions = C_Reputation.GetNumFactions()
    for i = 1, numFactions do
        local data = C_Reputation.GetFactionDataByIndex(i)
        if data and data.isHeader and not data.isChild and not data.isCollapsed then
            table.insert(headersToCollapse, i)
        end
    end
    for j = #headersToCollapse, 1, -1 do
        C_Reputation.CollapseFactionHeader(headersToCollapse[j])
    end
end

local function CollapseNonCurrentExpansions()
    local currentExpName = GetCurrentExpansionName()
    if not currentExpName then return end

    C_Reputation.ExpandAllFactionHeaders()

    local headersToCollapse = {}
    local numFactions = C_Reputation.GetNumFactions()
    for i = 1, numFactions do
        local data = C_Reputation.GetFactionDataByIndex(i)
        if data and data.isHeader and not data.isChild then
            if data.name ~= currentExpName then
                table.insert(headersToCollapse, i)
            end
        end
    end
    for j = #headersToCollapse, 1, -1 do
        C_Reputation.CollapseFactionHeader(headersToCollapse[j])
    end
end

Wild.CollapseNonCurrentExpansions = CollapseNonCurrentExpansions

local function ApplyReputationCollapseMode()
    if not Wild.db then return end
    local mode = Wild.db.reputationCollapseMode
    if mode == "all" then
        CollapseAllExpansions()
    elseif mode == "current" then
        CollapseNonCurrentExpansions()
    elseif mode == "remember" then
        RestoreCollapseState()
    end
    -- "off" — do nothing
end

Wild.ApplyReputationCollapseMode = ApplyReputationCollapseMode

-- ============================================================
-- Hook the reputation frame's OnShow / OnHide
-- ============================================================

local hooked = false

local function TryHookReputationFrame()
    if hooked then return end
    local repFrame = _G.ReputationFrame
    if not repFrame then return end

    repFrame:HookScript("OnShow", function()
        if Wild.db and Wild.db.reputationCollapseMode ~= "off" then
            C_Timer.After(0.1, ApplyReputationCollapseMode)
        end
    end)

    repFrame:HookScript("OnHide", function()
        if Wild.db and Wild.db.reputationCollapseMode == "remember" then
            SaveCollapseState()
        end
    end)

    hooked = true
end

-- The ReputationFrame is loaded on demand with Blizzard_CharacterFrame.
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if addon == ADDON_NAME then
        TryHookReputationFrame()
    end
    if addon == "Blizzard_CharacterFrame" or addon == "Blizzard_ReputationFrame" then
        TryHookReputationFrame()
    end
    if hooked then
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

