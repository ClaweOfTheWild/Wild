-- Wild: Tooltip enhancements
local ADDON_NAME, Wild = ...

-- ============================================================
-- Tooltip info lines
-- ============================================================

local QUALITY_NAMES = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local EXPANSION_NAMES = {
    [0] = "Classic", [1] = "TBC", [2] = "WotLK", [3] = "Cata",
    [4] = "MoP", [5] = "WoD", [6] = "Legion", [7] = "BfA",
    [8] = "SL", [9] = "DF", [10] = "TWW", [11] = "Midnight",
}

-- Each entry: key, label, resolve(itemID, containerInfo) -> text or nil
local TOOLTIP_LINES = {
    {
        key = "itemID",
        label = "Item ID",
        resolve = function(itemID)
            return "Item ID: " .. itemID
        end,
    },
    {
        key = "itemType",
        label = "Item Type / Subtype",
        resolve = function(itemID)
            local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
            if not classID then return nil end
            local typeName = GetItemClassInfo(classID) or "?"
            local subName = GetItemSubClassInfo(classID, subclassID)
            if subName and subName ~= typeName then
                return "Type: " .. typeName .. " > " .. subName .. "  |cff888888(" .. classID .. "/" .. subclassID .. ")|r"
            end
            return "Type: " .. typeName .. "  |cff888888(" .. classID .. ")|r"
        end,
    },
    {
        key = "itemLevel",
        label = "Item Level",
        resolve = function(itemID, containerInfo)
            -- Use item link for actual effective ilvl (accounts for upgrades/bonus IDs)
            local link = containerInfo and containerInfo.hyperlink
            if link then
                local ilvl = GetDetailedItemLevelInfo(link)
                if ilvl then return "iLvl: " .. ilvl end
            end
            local _, _, _, ilvl = GetItemInfo(itemID)
            if ilvl then return "Base iLvl: " .. ilvl end
        end,
    },
    {
        key = "sellPrice",
        label = "Sell Price",
        resolve = function(itemID, containerInfo)
            local sellPrice = Wild.GetEffectiveSellPrice(itemID, containerInfo)
            if not sellPrice or sellPrice == 0 then return "Sell Price: None" end
            local gold = math.floor(sellPrice / 10000)
            local silver = math.floor((sellPrice % 10000) / 100)
            local copper = sellPrice % 100
            return string.format("Sell Price: %dg %ds %dc  |cff888888(%d copper)|r", gold, silver, copper, sellPrice)
        end,
    },
    {
        key = "equipSlot",
        label = "Equip Slot",
        resolve = function(itemID)
            local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemID)
            if equipLoc and equipLoc ~= "" then
                local readable = _G[equipLoc] or equipLoc:gsub("INVTYPE_", "")
                return "Equip: " .. readable .. "  |cff888888(" .. equipLoc .. ")|r"
            end
        end,
    },
    {
        key = "quality",
        label = "Quality",
        resolve = function(itemID, containerInfo)
            local quality = containerInfo and containerInfo.quality
            if not quality then _, _, quality = GetItemInfo(itemID) end
            if quality then
                return "Quality: " .. (QUALITY_NAMES[quality] or tostring(quality)) .. " (" .. quality .. ")"
            end
        end,
    },
    {
        key = "stackSize",
        label = "Max Stack Size",
        resolve = function(itemID)
            local _, _, _, _, _, _, _, stackSize = GetItemInfo(itemID)
            if stackSize and stackSize > 1 then
                return "Max Stack: " .. stackSize
            end
        end,
    },
    {
        key = "expansionID",
        label = "Expansion ID",
        resolve = function(itemID)
            local expacID = select(15, GetItemInfo(itemID))
            if expacID then
                return "Expansion: " .. (EXPANSION_NAMES[expacID] or tostring(expacID)) .. " (" .. expacID .. ")"
            end
        end,
    },
    {
        key = "bindType",
        label = "Bind Type",
        resolve = function(itemID, containerInfo)
            if not Wild.ATTR_BY_KEY then return nil end
            local attrDef = Wild.ATTR_BY_KEY["item.bind"]
            if not attrDef then return nil end
            local bind = attrDef.resolve(itemID, containerInfo)
            local labels = { boe = "Bind on Equip", soulbound = "Soulbound", warbound = "Warbound", none = "None" }
            return "Bind: " .. (labels[bind] or bind or "?") .. "  |cff888888(" .. tostring(bind) .. ")|r"
        end,
    },
    {
        key = "isReagent",
        label = "Is Crafting Reagent",
        resolve = function(itemID)
            local isCraftingReagent = select(17, GetItemInfo(itemID))
            return "Is Reagent: " .. (isCraftingReagent and "|cff00ff00true|r" or "|cff888888false|r")
        end,
    },
    {
        key = "collectionStatus",
        label = "Collection Status",
        resolve = function(itemID)
            local parts = {}
            -- Toy
            if C_ToyBox and C_ToyBox.GetToyInfo then
                local _, toyID = C_ToyBox.GetToyInfo(itemID)
                if toyID then
                    local known = PlayerHasToy(itemID)
                    parts[#parts + 1] = "Toy: " .. (known and "|cff00ff00known|r" or "|cffffff00unknown|r")
                end
            end
            -- Mount
            if C_MountJournal then
                local mountID = C_MountJournal.GetMountFromItem(itemID)
                if mountID then
                    local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                    parts[#parts + 1] = "Mount: " .. (isCollected and "|cff00ff00known|r" or "|cffffff00unknown|r")
                end
            end
            -- Pet
            local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
            if classID == 15 and subclassID == 2 and C_PetJournal then
                local speciesID = C_PetJournal.GetPetInfoByItemID and C_PetJournal.GetPetInfoByItemID(itemID)
                if speciesID then
                    local numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
                    if numCollected and numCollected > 0 then
                        local maxed = limit and numCollected >= limit
                        parts[#parts + 1] = "Pet: |cff00ff00" .. numCollected .. "/" .. (limit or "?") .. (maxed and " (maxed)|r" or "|r")
                    else
                        parts[#parts + 1] = "Pet: |cffffff00unknown|r"
                    end
                end
            end
            -- Appearance
            if C_TransmogCollection then
                local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemID)
                if equipLoc and equipLoc ~= "" then
                    local appearanceID = C_TransmogCollection.GetItemInfo(itemID)
                    if appearanceID then
                        local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
                        local known = false
                        if sources then
                            for _, s in ipairs(sources) do
                                if s.isCollected then known = true; break end
                            end
                        end
                        parts[#parts + 1] = "Appearance: " .. (known and "|cff00ff00known|r" or "|cffffff00unknown|r")
                    end
                end
            end
            -- Recipe
            if classID == 9 then
                local _, spellID = GetItemSpell(itemID)
                if spellID then
                    local known = IsSpellKnown(spellID) or IsPlayerSpell(spellID)
                    parts[#parts + 1] = "Recipe: " .. (known and "|cff00ff00known|r" or "|cffffff00unknown|r")
                end
            end
            if #parts > 0 then return table.concat(parts, "  ") end
        end,
    },
    {
        key = "intentMatch",
        label = "Matching Intents",
        resolve = function(itemID, containerInfo)
            if not Wild.db or not Wild.db.intents then return nil end
            if not Wild.IntentMatchesItem or not Wild.BuildCharContext then return nil end

            local charCtx = Wild.BuildCharContext()
            local matches = {}
            for idx, intent in ipairs(Wild.db.intents) do
                if intent.enabled ~= false and Wild.ValidateIntent and Wild.ValidateIntent(intent) then
                    local actorOk = not Wild.IntentMatchesActor or Wild.IntentMatchesActor(intent)
                    local itemOk = Wild.IntentMatchesItem(intent, itemID, containerInfo, charCtx)
                    if actorOk and itemOk then
                        local action = intent.action or "?"
                        matches[#matches + 1] = string.format("|cff00ff00#%d %s|r", idx, action)
                    end
                end
            end
            if #matches > 0 then
                return "Intents: " .. table.concat(matches, ", ")
            end
            return "Intents: |cff888888none|r"
        end,
    },
    {
        key = "crossCharCount",
        label = "Cross-Character Count",
        multiLine = true,
        resolve = function(itemID)
            if not Wild.GetItemTotal then return nil end
            local total, breakdown = Wild.GetItemTotal(itemID)
            if total == 0 then return nil end
            local lines = {}
            for _, entry in ipairs(breakdown) do
                local name, realm, where
                if entry.location == "warband" then
                    name  = "Warband"
                    realm = ""
                    where = "Bank"
                elseif entry.location == "guild" then
                    name  = entry.guild or "Guild"
                    realm = ""
                    where = "Bank"
                else
                    local char = entry.character or ""
                    name  = char:match("^([^%-]+)") or char
                    realm = char:match("%-(.+)$") or ""
                    where = entry.location == "bank" and "Bank" or "Bags"
                end
                lines[#lines + 1] = {
                    col1 = name,
                    col2 = realm,
                    col3 = where,
                    col4 = tostring(entry.count),
                }
            end
            if #lines > 1 then
                lines[#lines + 1] = {
                    col1 = "|cffffff00Total|r",
                    col2 = "",
                    col3 = "",
                    col4 = "|cffffff00" .. total .. "|r",
                }
            end
            return { header = "Across all characters:", rows = lines }
        end,
    },
}

Wild.TOOLTIP_LINES = TOOLTIP_LINES

-- ============================================================
-- Visibility modes
-- ============================================================

local VISIBILITY_MODES = {
    { key = "always",       label = "Always" },
    { key = "settings",     label = "Wild Settings Open" },
    { key = "shift",        label = "Shift Held" },
    { key = "ctrl",         label = "Ctrl Held" },
    { key = "alt",          label = "Alt Held" },
    { key = "never",        label = "Never" },
}

Wild.TOOLTIP_VISIBILITY_MODES = VISIBILITY_MODES

local function IsSettingsOpen()
    return Wild.settingsVisible == true
end

local function CheckVisibility(mode)
    if mode == "always" then return true end
    if mode == "settings" then return IsSettingsOpen() end
    if mode == "shift" then return IsShiftKeyDown() end
    if mode == "ctrl" then return IsControlKeyDown() end
    if mode == "alt" then return IsAltKeyDown() end
    if mode == "never" then return false end
    return false
end

-- ============================================================
-- Extract bag/slot context from tooltip owner for accurate bind detection
-- ============================================================

local function GetContainerInfoFromTooltip(tooltip)
    -- Try to get bag/slot from the tooltip's owner frame (bag slot buttons)
    local owner = tooltip:GetOwner()
    if not owner then return nil end

    local bag, slot

    -- Standard bag item buttons: GetBagID/GetID or GetSlotAndBagID
    if owner.GetBagID and owner.GetID then
        bag = owner:GetBagID()
        slot = owner:GetID()
    elseif owner.GetSlotAndBagID then
        slot, bag = owner:GetSlotAndBagID()
    end

    -- New bank UI (TWW+): ItemLocation-based buttons
    if not bag and owner.GetItemLocation then
        local loc = owner:GetItemLocation()
        if loc and loc.IsValid and loc:IsValid() and loc.GetBagAndSlot then
            bag, slot = loc:GetBagAndSlot()
        end
    end

    -- Direct fields used by some bank/container frames
    if not bag then
        bag = owner.bagID or owner.bagId
        slot = slot or owner.slotIndex or owner.slotID
    end

    if bag and slot then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            info.bag = bag
            info.slot = slot
            return info
        end
    end
    return nil
end

-- ============================================================
-- Wild tooltip attachment frame
-- A standalone frame anchored below the game tooltip.
-- Uses a proper grid layout for table rows.
-- ============================================================

local FONT_SIZE = 11
local ROW_HEIGHT = 14
local ROW_GAP = 2
local PADDING = 8
local TIP_GAP = 2  -- pixels between game tooltip and our frame

local wildTip  -- the frame, created lazily

-- Measure text width using a hidden scratch FontString
local measureFS

local function MeasureText(text, fontObj)
    if not measureFS then
        local f = CreateFrame("Frame", nil, UIParent)
        measureFS = f:CreateFontString(nil, "ARTWORK")
    end
    measureFS:SetFontObject(fontObj or "GameFontHighlightSmall")
    measureFS:SetText(text)
    return measureFS:GetStringWidth() or 0
end

local function DestroyWildTip()
    if wildTip then
        wildTip:Hide()
        wildTip:SetParent(nil)
        wildTip = nil
    end
end

local function CreateWildTip()
    DestroyWildTip()
    local f = CreateFrame("Frame", "WildTooltipFrame", UIParent, "BackdropTemplate")
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(200)
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    f:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
    f:Hide()
    wildTip = f
    return f
end

local function AddTextLine(tip, fontObj, text, r, g, b)
    local fs = tip:CreateFontString(nil, "ARTWORK")
    fs:SetFontObject(fontObj or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetText(text)
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

local function AddGridRow(tip, numCols)
    local cols = {}
    for i = 1, (numCols or 4) do
        local fs = tip:CreateFontString(nil, "ARTWORK")
        fs:SetFontObject("GameFontHighlightSmall")
        fs:SetWordWrap(false)
        cols[i] = fs
    end
    for i = 1, #cols - 1 do cols[i]:SetJustifyH("LEFT") end
    cols[#cols]:SetJustifyH("RIGHT")
    return cols
end

-- ============================================================
-- Render Wild tooltip content into the attached frame
-- ============================================================

local function RenderWildTip(tooltip, itemID, containerInfo)
    if not Wild.db or not Wild.db.tooltip then return end
    local cfg = Wild.db.tooltip
    if not cfg.enabled then return end

    local tip = CreateWildTip()

    local yPos = -PADDING
    local maxWidth = 0

    -- Helper: add a single text line
    local function AddText(text, fontObj, r, g, b)
        local fs = AddTextLine(tip, fontObj, text, r, g, b)
        fs:SetPoint("TOPLEFT", tip, "TOPLEFT", PADDING, yPos)
        fs:SetPoint("RIGHT", tip, "RIGHT", -PADDING, 0)
        local w = fs:GetStringWidth() or 0
        if w + PADDING * 2 > maxWidth then maxWidth = w + PADDING * 2 end
        yPos = yPos - ROW_HEIGHT - ROW_GAP
    end

    -- Title
    AddText("Wild", "GameFontNormal", 0, 0.8, 1)

    -- Collect grid data for table rows (we need to measure columns first)
    local gridData = {}
    local hasContent = false

    for _, lineDef in ipairs(TOOLTIP_LINES) do
        local mode = cfg.lines and cfg.lines[lineDef.key] or "never"
        if CheckVisibility(mode) then
            local result = lineDef.resolve(itemID, containerInfo)
            if result then
                hasContent = true
                if lineDef.multiLine and type(result) == "table" then
                    if result.header then
                        AddText(result.header, "GameFontHighlightSmall", 0.67, 0.87, 1)
                    end
                    if result.rows then
                        for _, r in ipairs(result.rows) do
                            gridData[#gridData + 1] = r
                        end
                    end
                else
                    AddText(result, "GameFontHighlightSmall", 0.67, 0.87, 1)
                end
            end
        end
    end

    -- Nothing to show?
    if not hasContent then
        tip:Hide()
        return
    end

    -- Render grid rows with pixel-aligned columns
    if #gridData > 0 then
        -- Determine number of columns from data
        local numCols = 0
        for _, d in ipairs(gridData) do
            local n = 0
            for k in pairs(d) do
                local idx = tonumber(k:match("^col(%d+)$"))
                if idx and idx > n then n = idx end
            end
            if n > numCols then numCols = n end
        end

        -- Measure column widths
        local colW = {}
        for i = 1, numCols do colW[i] = 0 end
        for _, d in ipairs(gridData) do
            for i = 1, numCols do
                local w = MeasureText(d["col" .. i] or "")
                if w > colW[i] then colW[i] = w end
            end
        end

        local colGap = 10
        local totalGridW = PADDING * 2
        for i = 1, numCols do
            totalGridW = totalGridW + colW[i]
            if i < numCols then totalGridW = totalGridW + colGap end
        end
        if totalGridW > maxWidth then maxWidth = totalGridW end

        -- Column colors: last column gold, first column white, middle columns grey
        local function ColColor(i)
            if i == numCols then return 1, 0.82, 0 end
            if i == 1 then return 1, 1, 1 end
            return 0.53, 0.53, 0.53
        end

        for _, d in ipairs(gridData) do
            local cols = AddGridRow(tip, numCols)

            -- Last column: right-aligned to frame edge
            cols[numCols]:SetText(d["col" .. numCols] or "")
            cols[numCols]:SetTextColor(ColColor(numCols))
            cols[numCols]:ClearAllPoints()
            cols[numCols]:SetWidth(colW[numCols])
            cols[numCols]:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -PADDING, yPos)

            -- Middle columns: anchor rightward from previous
            for i = numCols - 1, 2, -1 do
                cols[i]:SetText(d["col" .. i] or "")
                cols[i]:SetTextColor(ColColor(i))
                cols[i]:ClearAllPoints()
                cols[i]:SetWidth(colW[i])
                cols[i]:SetPoint("TOPRIGHT", cols[i + 1], "TOPLEFT", -colGap, 0)
            end

            -- First column: left-aligned, stretches to col2
            cols[1]:SetText(d.col1 or "")
            cols[1]:SetTextColor(ColColor(1))
            cols[1]:ClearAllPoints()
            cols[1]:SetPoint("TOPLEFT", tip, "TOPLEFT", PADDING, yPos)
            if numCols > 1 then
                cols[1]:SetPoint("TOPRIGHT", cols[2], "TOPLEFT", -colGap, 0)
            end

            yPos = yPos - ROW_HEIGHT - ROW_GAP
        end
    end

    -- Size the frame
    local totalHeight = -yPos + PADDING - ROW_GAP  -- yPos is negative
    tip:SetHeight(totalHeight)

    -- Width: at least as wide as the anchor tooltip, or our content
    local tooltipWidth = tooltip:GetWidth() or 250
    local frameWidth = math.max(tooltipWidth, maxWidth)
    tip:SetWidth(frameWidth)

    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 0, -TIP_GAP)
    tip:Show()
end

-- ============================================================
-- Tooltip hooking
-- ============================================================

local function OnTooltipSetItem(tooltip, data)
    if tooltip ~= GameTooltip then return end
    if not Wild.db or not Wild.db.tooltip then return end
    local cfg = Wild.db.tooltip
    if not cfg.enabled then return end

    local link
    if data and data.guid then
        link = C_Item.GetItemLinkByGUID(data.guid)
    elseif data and data.hyperlink then
        link = data.hyperlink
    elseif tooltip.GetItem then
        _, link = tooltip:GetItem()
    end
    if not link then return end
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return end

    -- Build container info for bind-type and intent matching
    local containerInfo = GetContainerInfoFromTooltip(tooltip)
    if containerInfo then
        containerInfo.hyperlink = containerInfo.hyperlink or link
    else
        containerInfo = { itemID = itemID, hyperlink = link }
    end

    -- Attach tooltip data lines for bind detection when bag/slot unavailable
    if data and data.lines and not containerInfo.bag then
        containerInfo.tooltipLines = data.lines
    end

    RenderWildTip(tooltip, itemID, containerInfo)
end

local function HideWildTip()
    DestroyWildTip()
end

local function InitTooltipHook()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            OnTooltipSetItem(tooltip, data)
        end)
    else
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end

    -- Hide our frame when the game tooltip hides
    GameTooltip:HookScript("OnHide", HideWildTip)
    GameTooltip:HookScript("OnTooltipCleared", HideWildTip)
end

-- Init on load
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if addon ~= ADDON_NAME then return end
    InitTooltipHook()
    self:UnregisterEvent("ADDON_LOADED")
end)
