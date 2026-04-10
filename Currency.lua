-- Wild: Currency display helpers
local ADDON_NAME, Wild = ...

-- ============================================================
-- Helpers
-- ============================================================

local function GetCurrentExpansionName()
    local level = GetExpansionLevel()
    return _G["EXPANSION_NAME" .. level]
end

-- ============================================================
-- Gather currencies with header/collapse info
-- ============================================================

-- Returns two lists:
--   headers: { { name, isCollapsed } ... }  (top-level expansion headers)
--   currencies: { { currencyID, name, quantity, iconFileID, maxQuantity, headerName } ... }
local function GetCurrencyData()
    local headers = {}
    local currencies = {}
    local currentHeader = nil

    for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
        if info then
            if info.isHeader then
                currentHeader = info.name
                table.insert(headers, {
                    name = info.name,
                    isCollapsed = info.isShowInBackpack == false, -- track expand state
                })
            else
                local link = C_CurrencyInfo.GetCurrencyListLink(i)
                local currencyID
                if link then
                    currencyID = C_CurrencyInfo.GetCurrencyIDFromLink(link)
                end
                table.insert(currencies, {
                    currencyID = currencyID,
                    name = info.name,
                    quantity = info.quantity,
                    iconFileID = info.iconFileID,
                    maxQuantity = info.maxQuantity or 0,
                    isDiscovered = info.isDiscovered,
                    headerName = currentHeader,
                })
            end
        end
    end
    return headers, currencies
end

-- ============================================================
-- Filtered getters based on collapse mode
-- ============================================================

-- Returns { { headerName, collapsed, currencies = { ... } }, ... }
-- grouped by expansion header, respecting the chosen mode.
local function GetGroupedCurrencies(mode)
    local _, allCurrencies = GetCurrencyData()
    local currentExpName = GetCurrentExpansionName()
    local saved = (Wild.db and Wild.db.currencyCollapsedHeaders) or {}

    -- Group currencies by header
    local headerOrder = {}
    local byHeader = {}
    for _, cur in ipairs(allCurrencies) do
        local h = cur.headerName or "Other"
        if not byHeader[h] then
            byHeader[h] = {}
            table.insert(headerOrder, h)
        end
        table.insert(byHeader[h], cur)
    end

    local groups = {}
    for _, hName in ipairs(headerOrder) do
        local collapsed = false
        if mode == "all" then
            collapsed = true
        elseif mode == "current" then
            collapsed = (hName ~= currentExpName)
        elseif mode == "remember" then
            collapsed = saved[hName] and true or false
        end
        -- "off" => collapsed = false (show all expanded)

        table.insert(groups, {
            headerName = hName,
            collapsed = collapsed,
            currencies = byHeader[hName],
        })
    end
    return groups
end

-- Save which headers the user collapsed in the currency tab
local function SaveCurrencyCollapseState(groups)
    if not Wild.db then return end
    local saved = {}
    for _, g in ipairs(groups) do
        if g.collapsed then
            saved[g.headerName] = true
        end
    end
    Wild.db.currencyCollapsedHeaders = saved
end

-- Legacy convenience functions
local function GetAllCurrencies()
    local _, currencies = GetCurrencyData()
    return currencies
end

local function GetCurrentExpansionCurrencies()
    local _, allCurrencies = GetCurrencyData()
    local expName = GetCurrentExpansionName()
    if not expName then return allCurrencies end
    local results = {}
    for _, cur in ipairs(allCurrencies) do
        if cur.headerName == expName then
            table.insert(results, cur)
        end
    end
    return results
end

Wild.GetAllCurrencies = GetAllCurrencies
Wild.GetCurrentExpansionCurrencies = GetCurrentExpansionCurrencies
Wild.GetGroupedCurrencies = GetGroupedCurrencies
Wild.SaveCurrencyCollapseState = SaveCurrencyCollapseState

