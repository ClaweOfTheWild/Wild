-- Wild: Crafting Orders default filters
local ADDON_NAME, Wild = ...

-- ============================================================
-- Apply saved default filters when the Crafting Orders UI opens
-- ============================================================

local hooked = false

local RARITY_FILTER_KEYS = {
    "PoorQuality", "CommonQuality", "UncommonQuality", "RareQuality",
    "EpicQuality", "LegendaryQuality", "ArtifactQuality",
}

local function ApplyDefaultFilters()
    if not Wild.db or not Wild.db.craftingOrders then return end
    local cfg = Wild.db.craftingOrders
    if not cfg.enabled then return end

    local coFrame = _G.ProfessionsCustomerOrdersFrame
    if not coFrame then return end

    local browse = coFrame.BrowseOrders
    if not browse or not browse.SearchBar or not browse.SearchBar.FilterDropdown then return end

    local filterDropdown = browse.SearchBar.FilterDropdown
    if not filterDropdown.filters then return end

    local ahEnum = Enum and Enum.AuctionHouseFilter
    if not ahEnum then return end

    local filterMap = cfg.filters or {}

    -- Identify rarity enum values and whether the user configured any
    local raritySet = {}
    local anyRarityConfigured = false
    for _, key in ipairs(RARITY_FILTER_KEYS) do
        local ev = ahEnum[key]
        if ev then
            raritySet[ev] = true
            if filterMap[ev] ~= nil then
                anyRarityConfigured = true
            end
        end
    end

    -- Apply non-rarity filters
    for enumVal, enabled in pairs(filterMap) do
        if not raritySet[enumVal] then
            filterDropdown.filters[enumVal] = enabled
        end
    end

    -- If any rarity filter is configured, explicitly set all rarity filters
    -- (unconfigured rarities default to true to match the game defaults)
    if anyRarityConfigured then
        for _, key in ipairs(RARITY_FILTER_KEYS) do
            local ev = ahEnum[key]
            if ev then
                local value = filterMap[ev]
                if value == nil then value = true end
                filterDropdown.filters[ev] = value
            end
        end
    end

    if cfg.minLevel and cfg.minLevel > 0 then
        filterDropdown.minLevel = cfg.minLevel
    end
    if cfg.maxLevel and cfg.maxLevel > 0 then
        filterDropdown.maxLevel = cfg.maxLevel
    end

    if filterDropdown.ValidateResetState then
        filterDropdown:ValidateResetState()
    end
end

local function TryHookCraftingOrders()
    if hooked then return true end

    local coFrame = _G.ProfessionsCustomerOrdersFrame
    if not coFrame then return false end

    local browse = coFrame.BrowseOrders
    if not browse then return false end

    -- Hook SetDefaultFilters so our overrides re-apply after a filter reset
    if browse.SetDefaultFilters then
        hooksecurefunc(browse, "SetDefaultFilters", function()
            C_Timer.After(0, ApplyDefaultFilters)
        end)
    end

    -- Hook InitFilterDropdown so we re-apply after the dropdown is fully set up
    -- (SetDefaultFilters fires before the dropdown's filter table may be ready)
    if browse.InitFilterDropdown then
        hooksecurefunc(browse, "InitFilterDropdown", function()
            C_Timer.After(0, ApplyDefaultFilters)
        end)
    end

    hooked = true
    return true
end

-- ============================================================
-- Event handling
-- ============================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CRAFTINGORDERS_CUSTOMER_OPTIONS_PARSED")
frame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon == ADDON_NAME or addon == "Blizzard_ProfessionsCustomerOrders" then
            TryHookCraftingOrders()
        end
        if hooked then
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "CRAFTINGORDERS_CUSTOMER_OPTIONS_PARSED" then
        TryHookCraftingOrders()
        C_Timer.After(0, ApplyDefaultFilters)
    end
end)
