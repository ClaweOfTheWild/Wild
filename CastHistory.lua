-- Wild: Cast History
-- Shows successful player spell casts and item uses from a configurable origin.
local ADDON_NAME, Wild = ...

local MIN_ICON_SIZE = 20
local MAX_ICON_SIZE = 100
local MIN_TEXT_SIZE = 8
local MAX_TEXT_SIZE = 32
local MIN_HISTORY_LENGTH = 1
local MAX_HISTORY_LENGTH = 20
local MIN_FADE_AFTER = 1
local MAX_FADE_AFTER = 30
local MIN_TRACK_SPACING = 0
local MAX_TRACK_SPACING = 100
local GLOBAL_COOLDOWN_SPELL_ID = 61304
local FADE_DURATION = 1

local DIRECTION_VECTORS = {
    LEFT = { x = -1, y = 0 },
    RIGHT = { x = 1, y = 0 },
    UP = { x = 0, y = 1 },
    DOWN = { x = 0, y = -1 },
}

local origin
local entries = {}
local entryPool = {}
local itemSpellCache = {}
local pendingItemLoads = {}
local pendingItem
local itemCacheReady = false
local lastCastGUID
local lastGCDDuration = 1.5

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function GetConfig()
    return Wild.db and Wild.db.castHistory
end

local function GetEntryDimensions(config)
    local iconSize = Clamp(math.floor((config.iconSize or 48) + 0.5), MIN_ICON_SIZE, MAX_ICON_SIZE)
    local showText = config.showText ~= false
    local textSize = Clamp(math.floor((config.textSize or 12) + 0.5), MIN_TEXT_SIZE, MAX_TEXT_SIZE)
    local entryWidth = iconSize
    local entryHeight = iconSize + (showText and textSize + 6 or 0)
    return iconSize, entryWidth, entryHeight
end

local function UpdateGCDDuration()
    local cooldown = C_Spell.GetSpellCooldown(GLOBAL_COOLDOWN_SPELL_ID)
    if cooldown and not (issecretvalue and issecretvalue(cooldown.duration))
        and type(cooldown.duration) == "number" and cooldown.duration > 0 then
        local modRate = cooldown.modRate
        if (issecretvalue and issecretvalue(modRate)) or type(modRate) ~= "number" or modRate <= 0 then
            modRate = 1
        end
        lastGCDDuration = cooldown.duration / modRate
    end
end

local function GetMovementSpeed(config, direction)
    local iconSize, _, entryHeight = GetEntryDimensions(config)
    local spacing = (direction.x ~= 0 and iconSize or entryHeight) + 2
    return spacing / lastGCDDuration
end

local function GetSecondaryTrackOffset(config, track)
    local _, entryWidth, entryHeight = GetEntryDimensions(config)
    local spacing = config.trackSpacing or 8
    local direction = DIRECTION_VECTORS[config.direction] or DIRECTION_VECTORS.RIGHT
    track = track or 1
    if direction.x ~= 0 then
        return 0, -(entryHeight + spacing) * track
    end
    return (entryWidth + spacing) * track, 0
end

local function GetAvailableNonGCDTrack(config)
    local _, entryWidth, entryHeight = GetEntryDimensions(config)
    local occupied = {}
    for _, entry in ipairs(entries) do
        if not entry.isGCD and math.abs(entry.travelX) < entryWidth + 2
            and math.abs(entry.travelY) < entryHeight + 2 then
            occupied[entry.track] = true
        end
    end

    local track = 1
    while occupied[track] do
        track = track + 1
    end
    return track
end

local function UsesGlobalCooldown(spellID)
    if not spellID or not GetSpellBaseCooldown then return true end
    local _, gcdMS = GetSpellBaseCooldown(spellID)
    return (gcdMS or 0) > 0
end

local function SavePosition()
    local config = GetConfig()
    if not config or not origin then return end

    local point, _, relativePoint, x, y = origin:GetPoint()
    config.position = {
        point = point,
        relativePoint = relativePoint,
        x = math.floor((x or 0) + 0.5),
        y = math.floor((y or 0) + 0.5),
    }
end

local function ApplyPosition()
    if not origin then return end

    local config = GetConfig()
    local position = config and config.position
    origin:ClearAllPoints()
    if position then
        origin:SetPoint(
            position.point or "CENTER",
            UIParent,
            position.relativePoint or "CENTER",
            position.x or 0,
            position.y or -180
        )
    else
        origin:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
end

local function CreateOrigin()
    if origin then return origin end

    origin = CreateFrame("Frame", "WildCastHistoryOrigin", UIParent, "BackdropTemplate")
    origin:SetFrameStrata("HIGH")
    origin:SetClampedToScreen(true)
    origin:SetMovable(true)
    origin:RegisterForDrag("LeftButton")
    origin:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    origin.moveLabel = origin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    origin.moveLabel:SetPoint("BOTTOM", origin, "TOP", 0, 5)
    origin.moveLabel:SetText("GCD track")

    origin.secondaryMarker = CreateFrame("Frame", nil, origin, "BackdropTemplate")
    origin.secondaryMarker:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    origin.secondaryMarker:SetBackdropColor(0.25, 0.12, 0.05, 0.35)
    origin.secondaryMarker:SetBackdropBorderColor(1, 0.55, 0, 1)
    origin.secondaryMarker.moveLabel = origin.secondaryMarker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    origin.secondaryMarker.moveLabel:SetPoint("BOTTOM", origin.secondaryMarker, "TOP", 0, 5)
    origin.secondaryMarker.moveLabel:SetText("Non-GCD tracks")
    origin.secondaryMarker:Hide()

    origin:SetScript("OnDragStart", function(self)
        local config = GetConfig()
        if config and not config.locked then
            self:StartMoving()
        end
    end)
    origin:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    ApplyPosition()
    return origin
end

local function PositionEntry(entry, config)
    local trackX, trackY = 0, 0
    if not entry.isGCD then
        trackX, trackY = GetSecondaryTrackOffset(config, entry.track)
    end
    entry:ClearAllPoints()
    entry:SetPoint("CENTER", origin, "CENTER", entry.travelX + trackX, entry.travelY + trackY)
end

local function CreateEntry()
    local entry = table.remove(entryPool)
    if entry then
        entry:Show()
        return entry
    end

    entry = CreateFrame("Frame", nil, CreateOrigin())
    entry:SetFrameLevel(origin:GetFrameLevel() + 1)

    entry.iconBorder = entry:CreateTexture(nil, "BORDER")
    entry.iconBorder:SetColorTexture(0.08, 0.08, 0.10, 0.95)

    entry.icon = entry:CreateTexture(nil, "ARTWORK")
    entry.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    entry.label = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    entry.label:SetJustifyH("CENTER")
    entry.label:SetWordWrap(false)

    entry:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.kind == "item" then
            GameTooltip:SetHyperlink("item:" .. self.id)
        elseif GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(self.id)
        else
            GameTooltip:SetText(self.displayName or "")
        end
        GameTooltip:Show()
    end)
    entry:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return entry
end

local function ReleaseEntry(entry)
    entry:Hide()
    entry:ClearAllPoints()
    entry:SetAlpha(1)
    entryPool[#entryPool + 1] = entry
end

local function StyleEntry(entry, config)
    local iconSize, entryWidth, entryHeight = GetEntryDimensions(config)
    local textSize = Clamp(math.floor((config.textSize or 12) + 0.5), MIN_TEXT_SIZE, MAX_TEXT_SIZE)
    entry:SetSize(entryWidth, entryHeight)

    entry.icon:ClearAllPoints()
    entry.icon:SetPoint("TOP", entry, "TOP", 0, 0)
    entry.icon:SetSize(iconSize, iconSize)

    entry.iconBorder:ClearAllPoints()
    entry.iconBorder:SetPoint("TOPLEFT", entry.icon, "TOPLEFT", -1, 1)
    entry.iconBorder:SetPoint("BOTTOMRIGHT", entry.icon, "BOTTOMRIGHT", 1, -1)

    entry.label:ClearAllPoints()
    entry.label:SetPoint("TOP", entry.icon, "BOTTOM", 0, -2)
    entry.label:SetWidth(entryWidth)
    local fontPath, _, fontFlags = GameFontHighlightSmall:GetFont()
    if fontPath then entry.label:SetFont(fontPath, textSize, fontFlags) end
    entry.label:SetShown(config.showText ~= false)
end

local function RefreshEntries()
    local config = GetConfig()
    if not config or not origin then return end

    for _, entry in ipairs(entries) do
        StyleEntry(entry, config)
        entry:EnableMouse(config.locked ~= false)
        PositionEntry(entry, config)
    end
end

local function AnimateEntries(_, elapsed)
    local config = GetConfig()
    if not config or not config.enabled then return end

    local direction = DIRECTION_VECTORS[config.direction] or DIRECTION_VECTORS.RIGHT
    local movementSpeed = GetMovementSpeed(config, direction)
    local fadeAfter = config.fadeAfter or 5

    for index = #entries, 1, -1 do
        local entry = entries[index]
        entry.age = entry.age + elapsed
        entry.travelX = entry.travelX + direction.x * movementSpeed * elapsed
        entry.travelY = entry.travelY + direction.y * movementSpeed * elapsed
        PositionEntry(entry, config)

        if entry.age >= fadeAfter then
            local alpha = 1 - ((entry.age - fadeAfter) / FADE_DURATION)
            if alpha <= 0 then
                table.remove(entries, index)
                ReleaseEntry(entry)
            else
                entry:SetAlpha(alpha)
            end
        end
    end

    if #entries == 0 then
        origin:SetScript("OnUpdate", nil)
    end
end

local function TrimHistory()
    local config = GetConfig()
    local limit = config and config.historyLength or 8
    local counts = { gcd = 0, nonGCD = 0 }
    local index = 1
    while index <= #entries do
        local track = entries[index].isGCD and "gcd" or "nonGCD"
        counts[track] = counts[track] + 1
        if counts[track] > limit then
            ReleaseEntry(table.remove(entries, index))
        else
            index = index + 1
        end
    end
end

local function ClearHistory()
    for index = #entries, 1, -1 do
        ReleaseEntry(table.remove(entries, index))
    end
    if origin then origin:SetScript("OnUpdate", nil) end
end

local function RequestItemData(itemID)
    if pendingItemLoads[itemID] or not C_Item.RequestLoadItemDataByID then return end
    pendingItemLoads[itemID] = true
    C_Item.RequestLoadItemDataByID(itemID)
end

local function GetItemData(itemID)
    if not itemID or not C_Item.GetItemSpell then return nil end

    local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    if not name then
        RequestItemData(itemID)
        return nil
    end

    local _, spellID = C_Item.GetItemSpell(itemID)
    if not spellID then return nil end

    return {
        kind = "item",
        id = itemID,
        spellID = spellID,
        name = name,
        icon = icon,
    }
end

local function CacheItem(cache, seen, itemID)
    if not itemID or seen[itemID] then return end
    seen[itemID] = true
    local data = GetItemData(itemID)
    if data then cache[data.spellID] = data end
end

local function RebuildItemSpellCache()
    if not GetConfig() or not GetConfig().enabled then return end

    local cache = {}
    local seen = {}
    local bags = Wild.GetPlayerBags and Wild.GetPlayerBags() or { 0, 1, 2, 3, 4 }

    for _, bag in ipairs(bags) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            CacheItem(cache, seen, C_Container.GetContainerItemID(bag, slot))
        end
    end

    local firstSlot = INVSLOT_FIRST_EQUIPPED or 1
    local lastSlot = INVSLOT_LAST_EQUIPPED or 19
    for slot = firstSlot, lastSlot do
        CacheItem(cache, seen, GetInventoryItemID("player", slot))
    end

    itemSpellCache = cache
    itemCacheReady = true
end

local function SetPendingItem(itemID)
    local data = GetItemData(itemID)
    if not data then return end
    data.time = GetTime()
    pendingItem = data
    itemSpellCache[data.spellID] = data
end

local function InstallItemUseHooks()
    if C_Container and C_Container.UseContainerItem then
        hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
            SetPendingItem(C_Container.GetContainerItemID(bag, slot))
        end)
    end

    if UseInventoryItem then
        hooksecurefunc("UseInventoryItem", function(slot)
            SetPendingItem(GetInventoryItemID("player", slot))
        end)
    end

    if UseAction then
        hooksecurefunc("UseAction", function(slot)
            local actionType, itemID = GetActionInfo(slot)
            if actionType == "item" then SetPendingItem(itemID) end
        end)
    end

    if C_Item and C_Item.UseItemByName then
        hooksecurefunc(C_Item, "UseItemByName", function(itemInfo)
            local itemID = C_Item.GetItemInfoInstant(itemInfo)
            SetPendingItem(itemID)
        end)
    end
end

local function ResolveItem(spellID)
    if pendingItem and GetTime() - pendingItem.time > 30 then
        pendingItem = nil
    end
    if pendingItem and pendingItem.spellID == spellID then
        local item = pendingItem
        pendingItem = nil
        return item
    end
    return itemSpellCache[spellID]
end

local function GetSpellData(spellID)
    local info = C_Spell.GetSpellInfo(spellID)
    if not info then return nil end
    return {
        kind = "spell",
        id = spellID,
        name = info.name,
        icon = info.iconID,
    }
end

local function AddEntry(data, isGCD)
    local config = GetConfig()
    if not config or not config.enabled or not data or not data.name then return end

    local entry = CreateEntry()
    entry.kind = data.kind
    entry.id = data.id
    if isGCD == nil then
        isGCD = UsesGlobalCooldown(data.spellID or data.id)
    end
    entry.isGCD = isGCD
    entry.track = isGCD and 0 or GetAvailableNonGCDTrack(config)
    entry.displayName = data.name
    entry.icon:SetTexture(data.icon or 134400)
    entry.label:SetText(data.name)
    entry.age = 0
    entry.travelX = 0
    entry.travelY = 0
    entry:SetAlpha(1)
    table.insert(entries, 1, entry)

    TrimHistory()
    RefreshEntries()
    origin:SetScript("OnUpdate", AnimateEntries)
end

local function RecordSuccessfulCast(castGUID, spellID)
    local config = GetConfig()
    if not config or not config.enabled or not spellID then return end
    if castGUID and castGUID == lastCastGUID then return end
    lastCastGUID = castGUID

    if not itemCacheReady then RebuildItemSpellCache() end
    AddEntry(ResolveItem(spellID) or GetSpellData(spellID), UsesGlobalCooldown(spellID))
end

function Wild.UpdateCastHistory()
    local config = GetConfig()
    if not config then return end

    config.iconSize = Clamp(math.floor((tonumber(config.iconSize) or 48) + 0.5), MIN_ICON_SIZE, MAX_ICON_SIZE)
    config.showText = config.showText ~= false
    config.textSize = Clamp(math.floor((tonumber(config.textSize) or 12) + 0.5), MIN_TEXT_SIZE, MAX_TEXT_SIZE)
    config.historyLength = Clamp(math.floor((tonumber(config.historyLength) or 8) + 0.5), MIN_HISTORY_LENGTH, MAX_HISTORY_LENGTH)
    config.fadeAfter = Clamp(tonumber(config.fadeAfter) or 5, MIN_FADE_AFTER, MAX_FADE_AFTER)
    config.trackSpacing = Clamp(math.floor((tonumber(config.trackSpacing) or 8) + 0.5), MIN_TRACK_SPACING, MAX_TRACK_SPACING)
    config.direction = DIRECTION_VECTORS[config.direction] and config.direction or "RIGHT"

    CreateOrigin()
    ApplyPosition()

    local _, entryWidth, entryHeight = GetEntryDimensions(config)
    origin:SetSize(entryWidth + 8, entryHeight + 8)
    origin.secondaryMarker:SetSize(entryWidth + 8, entryHeight + 8)
    origin.secondaryMarker:ClearAllPoints()
    local secondaryX, secondaryY = GetSecondaryTrackOffset(config)
    origin.secondaryMarker:SetPoint("CENTER", origin, "CENTER", secondaryX, secondaryY)
    origin:EnableMouse(config.locked == false)
    origin.moveLabel:SetShown(config.locked == false)
    origin.secondaryMarker:SetShown(config.locked == false)
    if config.locked == false then
        origin:SetBackdropColor(0.05, 0.25, 0.35, 0.35)
        origin:SetBackdropBorderColor(0, 0.8, 1, 1)
    else
        origin:SetBackdropColor(0, 0, 0, 0)
        origin:SetBackdropBorderColor(0, 0, 0, 0)
    end

    if not config.enabled then
        ClearHistory()
    end

    if config.enabled or config.locked == false then
        origin:Show()
    else
        origin:Hide()
    end

    if config.enabled then
        UpdateGCDDuration()
        if not itemCacheReady then RebuildItemSpellCache() end
    end
    TrimHistory()
    RefreshEntries()
    if config.enabled and #entries > 0 then
        origin:SetScript("OnUpdate", AnimateEntries)
    end
end

function Wild.SetCastHistoryEnabled(enabled)
    local config = GetConfig()
    if not config then return end
    config.enabled = enabled and true or false
    Wild.UpdateCastHistory()
end

function Wild.SetCastHistorySize(size)
    local config = GetConfig()
    size = tonumber(size)
    if not config or not size then return false end
    config.iconSize = Clamp(math.floor(size + 0.5), MIN_ICON_SIZE, MAX_ICON_SIZE)
    Wild.UpdateCastHistory()
    return true
end

function Wild.SetCastHistoryTextVisible(visible)
    local config = GetConfig()
    if not config then return end
    config.showText = visible and true or false
    Wild.UpdateCastHistory()
end

function Wild.SetCastHistoryTextSize(size)
    local config = GetConfig()
    size = tonumber(size)
    if not config or not size then return false end
    config.textSize = Clamp(math.floor(size + 0.5), MIN_TEXT_SIZE, MAX_TEXT_SIZE)
    Wild.UpdateCastHistory()
    return true
end

function Wild.SetCastHistoryLength(length)
    local config = GetConfig()
    length = tonumber(length)
    if not config or not length then return false end
    config.historyLength = Clamp(math.floor(length + 0.5), MIN_HISTORY_LENGTH, MAX_HISTORY_LENGTH)
    Wild.UpdateCastHistory()
    return true
end

function Wild.SetCastHistoryFadeAfter(seconds)
    local config = GetConfig()
    seconds = tonumber(seconds)
    if not config or not seconds then return false end
    config.fadeAfter = Clamp(seconds, MIN_FADE_AFTER, MAX_FADE_AFTER)
    Wild.UpdateCastHistory()
    return true
end

function Wild.SetCastHistoryTrackSpacing(spacing)
    local config = GetConfig()
    spacing = tonumber(spacing)
    if not config or not spacing then return false end
    config.trackSpacing = Clamp(math.floor(spacing + 0.5), MIN_TRACK_SPACING, MAX_TRACK_SPACING)
    Wild.UpdateCastHistory()
    return true
end

function Wild.SetCastHistoryDirection(direction)
    local config = GetConfig()
    direction = direction and direction:upper()
    if not config or not DIRECTION_VECTORS[direction] then return false end
    config.direction = direction
    Wild.UpdateCastHistory()
    return true
end

function Wild.SetCastHistoryMoveMode(enabled)
    local config = GetConfig()
    if not config then return end
    config.locked = not enabled
    Wild.UpdateCastHistory()
end

function Wild.ResetCastHistoryPosition()
    local config = GetConfig()
    if not config then return end
    config.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 }
    Wild.UpdateCastHistory()
end

function Wild.ClearCastHistory()
    ClearHistory()
end

function Wild.AddCastHistorySpell(spellID, isGCD)
    spellID = tonumber(spellID)
    if spellID then AddEntry(GetSpellData(spellID), isGCD) end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon ~= ADDON_NAME then return end
        CreateOrigin()
        InstallItemUseHooks()
        Wild.UpdateCastHistory()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        local config = GetConfig()
        if config and config.enabled then UpdateGCDDuration() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellID = ...
        if unit == "player" then RecordSuccessfulCast(castGUID, spellID) end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit, _, spellID = ...
        if unit == "player" and pendingItem and pendingItem.spellID == spellID then
            pendingItem = nil
        end
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        local itemID, success = ...
        if pendingItemLoads[itemID] then
            pendingItemLoads[itemID] = nil
            if success then RebuildItemSpellCache() end
        end
    else
        itemCacheReady = false
        if GetConfig() and GetConfig().enabled then RebuildItemSpellCache() end
        if event == "PLAYER_ENTERING_WORLD" then Wild.UpdateCastHistory() end
    end
end)
