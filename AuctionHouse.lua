-- Wild: Auction House default filters
local ADDON_NAME, Wild = ...

-- ============================================================
-- Apply saved default filters when the AH opens
-- ============================================================

local hooked = false

local RARITY_FILTER_KEYS = {
    "PoorQuality", "CommonQuality", "UncommonQuality", "RareQuality",
    "EpicQuality", "LegendaryQuality", "ArtifactQuality",
}

local function ApplyDefaultFilters()
    if not Wild.db or not Wild.db.auctionHouse then return end
    local cfg = Wild.db.auctionHouse
    if not cfg.enabled then return end

    local ahFrame = _G.AuctionHouseFrame
    if not ahFrame or not ahFrame.SearchBar or not ahFrame.SearchBar.FilterButton then return end

    local filterBtn = ahFrame.SearchBar.FilterButton
    local filterMap = cfg.filters or {}

    local ahEnum = Enum and Enum.AuctionHouseFilter
    if not ahEnum then return end

    -- Identify rarity enum values and whether the user enabled any
    local raritySet = {}
    local anyRarityEnabled = false
    for _, key in ipairs(RARITY_FILTER_KEYS) do
        local ev = ahEnum[key]
        if ev then
            raritySet[ev] = true
            if filterMap[ev] then
                anyRarityEnabled = true
            end
        end
    end

    -- Apply non-rarity filters
    for enumVal, enabled in pairs(filterMap) do
        if not raritySet[enumVal] then
            filterBtn.filters[enumVal] = enabled
        end
    end

    -- If any rarity filter is enabled, explicitly set all rarity filters
    -- (enabled ones to true, others to false). If none enabled, leave defaults.
    if anyRarityEnabled then
        for _, key in ipairs(RARITY_FILTER_KEYS) do
            local ev = ahEnum[key]
            if ev then
                filterBtn.filters[ev] = filterMap[ev] and true or false
            end
        end
    end

    if cfg.minLevel and cfg.minLevel > 0 then
        filterBtn.minLevel = cfg.minLevel
    end
    if cfg.maxLevel and cfg.maxLevel > 0 then
        filterBtn.maxLevel = cfg.maxLevel
    end

    if ahFrame.SearchBar.UpdateClearFiltersButton then
        ahFrame.SearchBar:UpdateClearFiltersButton()
    end
end

local function TryHookAuctionHouse()
    if hooked then return true end
    local ahFrame = _G.AuctionHouseFrame
    if not ahFrame then return false end

    -- Hook the Reset method to re-apply defaults after user clears filters
    local filterBtn = ahFrame.SearchBar and ahFrame.SearchBar.FilterButton
    if filterBtn and filterBtn.Reset then
        hooksecurefunc(filterBtn, "Reset", function()
            -- Re-apply after reset with a tiny delay so Blizzard's reset finishes first
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
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        -- AuctionHouseFrame is loaded on demand via Blizzard_AuctionHouseUI
        if addon == ADDON_NAME or addon == "Blizzard_AuctionHouseUI" then
            TryHookAuctionHouse()
        end
        if hooked then
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        TryHookAuctionHouse()
        -- Delay to next frame so Blizzard UI finishes initializing
        C_Timer.After(0, ApplyDefaultFilters)
    end
end)
