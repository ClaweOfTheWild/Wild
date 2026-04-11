-- Wild: Cross-character inventory datastore
local ADDON_NAME, Wild = ...

-- ============================================================
-- Location constants
-- ============================================================

local LOCATION_BAGS    = "bags"
local LOCATION_BANK    = "bank"
local LOCATION_WARBAND = "warband"
local LOCATION_GUILD   = "guild"

-- Expose for external use
Wild.LOCATION_BAGS    = LOCATION_BAGS
Wild.LOCATION_BANK    = LOCATION_BANK
Wild.LOCATION_WARBAND = LOCATION_WARBAND
Wild.LOCATION_GUILD   = LOCATION_GUILD

-- ============================================================
-- Internal helpers
-- ============================================================

local function GetCharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

Wild.GetCharKey = GetCharKey

local function GetGuildKey()
    local guildName = GetGuildInfo("player")
    if not guildName or guildName == "" then return nil end
    return guildName .. "-" .. GetRealmName()
end

local function EnsureDatastore()
    if not Wild.db then return nil end
    if not Wild.db.datastore then Wild.db.datastore = {} end
    if not Wild.db.datastore.characters then Wild.db.datastore.characters = {} end
    if not Wild.db.datastore.guilds then Wild.db.datastore.guilds = {} end
    if not Wild.db.datastore.warband then Wild.db.datastore.warband = {} end
    return Wild.db.datastore
end

local function EnsureCharacterStore(charKey)
    local ds = EnsureDatastore()
    if not ds then return nil end
    if not ds.characters[charKey] then
        ds.characters[charKey] = {
            bags = {},
            bank = {},
            bagsUpdated = 0,
            bankUpdated = 0,
        }
    end
    return ds.characters[charKey]
end

-- ============================================================
-- Container scanner (shared by all snapshot functions)
-- ============================================================

local function ScanContainer(bagID)
    local items = {}
    local numSlots = C_Container.GetContainerNumSlots(bagID)
    if not numSlots or numSlots == 0 then return items end
    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and info.itemID then
            local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType,
                  _, itemEquipLoc, _, sellPrice, classID, subclassID, bindType, expansionID
                  = GetItemInfo(info.hyperlink or info.itemID)
            -- Use link for actual effective ilvl (accounts for upgrades/bonus IDs)
            local effectiveIlvl = itemLevel
            if info.hyperlink then
                local detailedIlvl = GetDetailedItemLevelInfo(info.hyperlink)
                if detailedIlvl then effectiveIlvl = detailedIlvl end
            end
            -- Use tooltip money for actual sell price (accounts for upgrades)
            local containerRef = { itemID = info.itemID, hyperlink = info.hyperlink, bag = bagID, slot = slot }
            local effectiveSellPrice = Wild.GetEffectiveSellPrice(info.itemID, containerRef) or sellPrice
            items[#items + 1] = {
                itemID      = info.itemID,
                name        = itemName or info.itemName or "?",
                link        = info.hyperlink,
                quality     = info.quality or itemQuality,
                count       = info.stackCount or 1,
                isBound     = info.isBound or false,
                bindType    = bindType,
                ilvl        = effectiveIlvl,
                itemType    = itemType,
                itemSubType = itemSubType,
                equipLoc    = itemEquipLoc,
                classID     = classID,
                subclassID  = subclassID,
                expansionID = expansionID,
                sellPrice   = effectiveSellPrice,
                icon        = info.iconFileID,
                bag         = bagID,
                slot        = slot,
            }
        end
    end
    return items
end

-- ============================================================
-- Bank bag indices (computed once at load time)
-- ============================================================

local CHARACTER_BANK_BAGS = {}
if Enum.BagIndex.CharacterBankTab then
    CHARACTER_BANK_BAGS[#CHARACTER_BANK_BAGS + 1] = Enum.BagIndex.CharacterBankTab
end
for i = 1, 6 do
    local key = "CharacterBankTab_" .. i
    if Enum.BagIndex[key] ~= nil then
        CHARACTER_BANK_BAGS[#CHARACTER_BANK_BAGS + 1] = Enum.BagIndex[key]
    end
end
-- Fallback for pre-Midnight (TWW / older): use Bank + BankBag_1..7
if #CHARACTER_BANK_BAGS == 0 then
    if Enum.BagIndex.Bank then
        CHARACTER_BANK_BAGS[#CHARACTER_BANK_BAGS + 1] = Enum.BagIndex.Bank
    end
    for i = 1, 7 do
        local key = "BankBag_" .. i
        if Enum.BagIndex[key] ~= nil then
            CHARACTER_BANK_BAGS[#CHARACTER_BANK_BAGS + 1] = Enum.BagIndex[key]
        end
    end
end

local REAGENT_BANK_BAG = Enum.BagIndex.Reagentbank

local ACCOUNT_BANK_TABS = {}
if Enum and Enum.BagIndex then
    for i = 1, 5 do
        local key = "AccountBankTab_" .. i
        if Enum.BagIndex[key] ~= nil then
            ACCOUNT_BANK_TABS[#ACCOUNT_BANK_TABS + 1] = Enum.BagIndex[key]
        end
    end
end

local GUILD_BANK_SLOTS_PER_TAB = 98

-- ============================================================
-- Snapshot: Player bags (backpack + bag slots + reagent bag)
-- ============================================================

function Wild.SnapshotBags()
    local charKey = GetCharKey()
    local store = EnsureCharacterStore(charKey)
    if not store then return end
    local allItems = {}
    local bags = Wild.GetPlayerBags()
    for _, bagID in ipairs(bags) do
        local items = ScanContainer(bagID)
        for _, item in ipairs(items) do
            allItems[#allItems + 1] = item
        end
    end
    store.bags = allItems
    store.bagsUpdated = time()
end

-- ============================================================
-- Snapshot: Character bank (includes reagent bank)
-- ============================================================

function Wild.SnapshotBank()
    local charKey = GetCharKey()
    local store = EnsureCharacterStore(charKey)
    if not store then return end
    local allItems = {}
    for _, bagID in ipairs(CHARACTER_BANK_BAGS) do
        local items = ScanContainer(bagID)
        for _, item in ipairs(items) do
            allItems[#allItems + 1] = item
        end
    end
    if REAGENT_BANK_BAG then
        local items = ScanContainer(REAGENT_BANK_BAG)
        for _, item in ipairs(items) do
            allItems[#allItems + 1] = item
        end
    end
    store.bank = allItems
    store.bankUpdated = time()
end

-- ============================================================
-- Snapshot: Warband (account) bank
-- ============================================================

function Wild.SnapshotWarbandBank()
    local ds = EnsureDatastore()
    if not ds then return end
    local allItems = {}
    for _, bagID in ipairs(ACCOUNT_BANK_TABS) do
        local items = ScanContainer(bagID)
        for _, item in ipairs(items) do
            allItems[#allItems + 1] = item
        end
    end
    ds.warband.bank = allItems
    ds.warband.updated = time()
end

-- ============================================================
-- Snapshot: Guild bank
-- ============================================================

function Wild.SnapshotGuildBank()
    local ds = EnsureDatastore()
    if not ds then return end
    local guildKey = GetGuildKey()
    if not guildKey then return end

    local numTabs = GetNumGuildBankTabs()
    if not numTabs or numTabs == 0 then return end

    local allItems = {}
    for tab = 1, numTabs do
        local _, _, isViewable = GetGuildBankTabInfo(tab)
        if isViewable then
            for slot = 1, GUILD_BANK_SLOTS_PER_TAB do
                local _, itemCount, locked = GetGuildBankItemInfo(tab, slot)
                if itemCount and itemCount > 0 then
                    local link = GetGuildBankItemLink(tab, slot)
                    if link then
                        local itemID = tonumber(link:match("item:(%d+)"))
                        if itemID then
                            local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType,
                                  _, itemEquipLoc, _, sellPrice, classID, subclassID, bindType, expansionID
                                  = GetItemInfo(link)
                            local effectiveIlvl = itemLevel
                            local detailedIlvl = GetDetailedItemLevelInfo(link)
                            if detailedIlvl then effectiveIlvl = detailedIlvl end
                            local effectiveSellPrice = Wild.GetEffectiveSellPrice(itemID, { hyperlink = link }) or sellPrice
                            allItems[#allItems + 1] = {
                                itemID      = itemID,
                                name        = itemName or "?",
                                link        = link,
                                quality     = itemQuality,
                                count       = itemCount,
                                isBound     = false,
                                bindType    = bindType,
                                ilvl        = effectiveIlvl,
                                itemType    = itemType,
                                itemSubType = itemSubType,
                                equipLoc    = itemEquipLoc,
                                classID     = classID,
                                subclassID  = subclassID,
                                expansionID = expansionID,
                                sellPrice   = effectiveSellPrice,
                                tab         = tab,
                                slot        = slot,
                            }
                        end
                    end
                end
            end
        end
    end

    if not ds.guilds[guildKey] then ds.guilds[guildKey] = {} end
    ds.guilds[guildKey].bank = allItems
    ds.guilds[guildKey].updated = time()
end

-- ============================================================
-- Query: Item total across all locations
-- ============================================================

--- Get total count of an item by ID across all known locations.
--- Returns total, breakdown where breakdown is an array of
--- { location, character, guild, count } entries.
function Wild.GetItemTotal(itemID)
    local ds = Wild.db and Wild.db.datastore
    if not ds then return 0, {} end

    local total = 0
    local breakdown = {}

    -- Character bags and banks
    if ds.characters then
        for charKey, store in pairs(ds.characters) do
            if store.bags then
                local count = 0
                for _, item in ipairs(store.bags) do
                    if item.itemID == itemID then count = count + item.count end
                end
                if count > 0 then
                    total = total + count
                    breakdown[#breakdown + 1] = {
                        location  = LOCATION_BAGS,
                        character = charKey,
                        count     = count,
                    }
                end
            end
            if store.bank then
                local count = 0
                for _, item in ipairs(store.bank) do
                    if item.itemID == itemID then count = count + item.count end
                end
                if count > 0 then
                    total = total + count
                    breakdown[#breakdown + 1] = {
                        location  = LOCATION_BANK,
                        character = charKey,
                        count     = count,
                    }
                end
            end
        end
    end

    -- Warband bank
    if ds.warband and ds.warband.bank then
        local count = 0
        for _, item in ipairs(ds.warband.bank) do
            if item.itemID == itemID then count = count + item.count end
        end
        if count > 0 then
            total = total + count
            breakdown[#breakdown + 1] = {
                location = LOCATION_WARBAND,
                count    = count,
            }
        end
    end

    -- Guild banks
    if ds.guilds then
        for guildKey, store in pairs(ds.guilds) do
            if store.bank then
                local count = 0
                for _, item in ipairs(store.bank) do
                    if item.itemID == itemID then count = count + item.count end
                end
                if count > 0 then
                    total = total + count
                    breakdown[#breakdown + 1] = {
                        location = LOCATION_GUILD,
                        guild    = guildKey,
                        count    = count,
                    }
                end
            end
        end
    end

    return total, breakdown
end

-- ============================================================
-- Query: Search items by name across all locations
-- ============================================================

--- Search items by name (partial, case-insensitive) across all characters and banks.
--- Returns array of { itemID, name, link, icon, total, breakdown }.
function Wild.FindItems(query)
    local ds = Wild.db and Wild.db.datastore
    if not ds then return {} end

    local lowerQuery = query:lower()
    local results = {}  -- keyed by itemID
    local order = {}    -- maintain insertion order

    local function AddResult(itemID, item, location, charKey, guildKey)
        if not results[itemID] then
            results[itemID] = {
                itemID    = itemID,
                name      = item.name,
                link      = item.link,
                icon      = item.icon,
                total     = 0,
                breakdown = {},
            }
            order[#order + 1] = itemID
        end
        local r = results[itemID]
        r.total = r.total + item.count
        r.breakdown[#r.breakdown + 1] = {
            location  = location,
            character = charKey,
            guild     = guildKey,
            count     = item.count,
        }
    end

    local function SearchItems(items, location, charKey, guildKey)
        if not items then return end
        for _, item in ipairs(items) do
            if item.name and item.name:lower():find(lowerQuery, 1, true) then
                AddResult(item.itemID, item, location, charKey, guildKey)
            end
        end
    end

    -- Characters
    if ds.characters then
        for charKey, store in pairs(ds.characters) do
            SearchItems(store.bags, LOCATION_BAGS, charKey)
            SearchItems(store.bank, LOCATION_BANK, charKey)
        end
    end

    -- Warband
    if ds.warband and ds.warband.bank then
        SearchItems(ds.warband.bank, LOCATION_WARBAND)
    end

    -- Guilds
    if ds.guilds then
        for guildKey, store in pairs(ds.guilds) do
            SearchItems(store.bank, LOCATION_GUILD, nil, guildKey)
        end
    end

    -- Build ordered results
    local out = {}
    for _, itemID in ipairs(order) do
        out[#out + 1] = results[itemID]
    end
    return out
end

-- ============================================================
-- Query: Get all item entries for a specific item in a location
-- ============================================================

--- Get entries for a specific item in a specific character+location.
--- Useful for the intent engine to inspect remote item details.
function Wild.GetItemEntries(itemID, location, key)
    local ds = Wild.db and Wild.db.datastore
    if not ds then return {} end

    local entries = {}
    local source

    if location == LOCATION_BAGS or location == LOCATION_BANK then
        local store = ds.characters and ds.characters[key]
        if store then source = store[location] end
    elseif location == LOCATION_WARBAND then
        source = ds.warband and ds.warband.bank
    elseif location == LOCATION_GUILD then
        local gStore = ds.guilds and ds.guilds[key]
        if gStore then source = gStore.bank end
    end

    if source then
        for _, item in ipairs(source) do
            if item.itemID == itemID then
                entries[#entries + 1] = item
            end
        end
    end
    return entries
end

-- ============================================================
-- Query: Formatted breakdown for chat output
-- ============================================================

function Wild.FormatItemBreakdown(breakdown)
    local parts = {}
    for _, entry in ipairs(breakdown) do
        if entry.location == LOCATION_BAGS then
            parts[#parts + 1] = entry.count .. "x " .. entry.character .. " bags"
        elseif entry.location == LOCATION_BANK then
            parts[#parts + 1] = entry.count .. "x " .. entry.character .. " bank"
        elseif entry.location == LOCATION_WARBAND then
            parts[#parts + 1] = "x Warband bank"
            parts[#parts] = entry.count .. parts[#parts]
        elseif entry.location == LOCATION_GUILD then
            parts[#parts + 1] = entry.count .. "x " .. (entry.guild or "Guild") .. " bank"
        end
    end
    return table.concat(parts, ", ")
end

-- ============================================================
-- Query: Datastore summary (for /wild datastore status)
-- ============================================================

function Wild.GetDatastoreSummary()
    local ds = Wild.db and Wild.db.datastore
    if not ds then return "Datastore not initialized." end

    local lines = {}
    lines[#lines + 1] = "|cff00ccff--- Wild Datastore ---|r"

    -- Characters
    if ds.characters then
        local count = 0
        for _ in pairs(ds.characters) do count = count + 1 end
        lines[#lines + 1] = "Characters tracked: " .. count
        for charKey, store in pairs(ds.characters) do
            local bagCount = store.bags and #store.bags or 0
            local bankCount = store.bank and #store.bank or 0
            local bagTime = store.bagsUpdated and store.bagsUpdated > 0
                and date("%Y-%m-%d %H:%M", store.bagsUpdated) or "never"
            local bankTime = store.bankUpdated and store.bankUpdated > 0
                and date("%Y-%m-%d %H:%M", store.bankUpdated) or "never"
            lines[#lines + 1] = string.format("  %s: %d bag items (%s), %d bank items (%s)",
                charKey, bagCount, bagTime, bankCount, bankTime)
        end
    end

    -- Warband
    if ds.warband and ds.warband.bank then
        local warbandTime = ds.warband.updated and ds.warband.updated > 0
            and date("%Y-%m-%d %H:%M", ds.warband.updated) or "never"
        lines[#lines + 1] = string.format("Warband bank: %d items (%s)",
            #ds.warband.bank, warbandTime)
    else
        lines[#lines + 1] = "Warband bank: no data"
    end

    -- Guilds
    if ds.guilds then
        local count = 0
        for _ in pairs(ds.guilds) do count = count + 1 end
        lines[#lines + 1] = "Guild banks tracked: " .. count
        for guildKey, store in pairs(ds.guilds) do
            local itemCount = store.bank and #store.bank or 0
            local guildTime = store.updated and store.updated > 0
                and date("%Y-%m-%d %H:%M", store.updated) or "never"
            lines[#lines + 1] = string.format("  %s: %d items (%s)",
                guildKey, itemCount, guildTime)
        end
    end

    return lines
end

-- ============================================================
-- Event-driven auto-snapshot: Bags
-- ============================================================

do
    local bagFrame = CreateFrame("Frame")
    local pendingBagUpdate = false

    bagFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    bagFrame:RegisterEvent("BAG_UPDATE_DELAYED")

    bagFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD" then
            -- Delay to let item cache warm up
            C_Timer.After(3, function()
                Wild.SnapshotBags()
            end)
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
            return
        end
        -- Debounce BAG_UPDATE_DELAYED
        if pendingBagUpdate then return end
        pendingBagUpdate = true
        C_Timer.After(1, function()
            pendingBagUpdate = false
            Wild.SnapshotBags()
        end)
    end)
end

-- ============================================================
-- Event-driven auto-snapshot: Character bank + Warband bank
-- ============================================================

do
    local bankSnapFrame = CreateFrame("Frame")
    local pendingBankSnap = false

    bankSnapFrame:RegisterEvent("BANKFRAME_OPENED")
    bankSnapFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    bankSnapFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")

    local function DoBankSnapshot()
        if pendingBankSnap then return end
        pendingBankSnap = true
        C_Timer.After(2, function()
            pendingBankSnap = false
            Wild.SnapshotBank()
            Wild.SnapshotWarbandBank()
        end)
    end

    bankSnapFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "BANKFRAME_OPENED" then
            DoBankSnapshot()
            return
        end
        if event == "PLAYERBANKSLOTS_CHANGED" then
            DoBankSnapshot()
            return
        end
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            local interactionType = ...
            local PIT = Enum.PlayerInteractionType
            if interactionType == PIT.Banker
                or (PIT.CharacterBanker and interactionType == PIT.CharacterBanker)
                or (PIT.AccountBanker and interactionType == PIT.AccountBanker) then
                DoBankSnapshot()
            end
        end
    end)
end

-- ============================================================
-- Event-driven auto-snapshot: Guild bank
-- ============================================================

do
    local guildBankFrame = CreateFrame("Frame")
    local pendingGuildSnap = false

    guildBankFrame:RegisterEvent("GUILDBANKFRAME_OPENED")
    guildBankFrame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")

    local function DoGuildBankSnapshot()
        if pendingGuildSnap then return end
        pendingGuildSnap = true
        C_Timer.After(2, function()
            pendingGuildSnap = false
            Wild.SnapshotGuildBank()
        end)
    end

    guildBankFrame:SetScript("OnEvent", function(self, event)
        DoGuildBankSnapshot()
    end)
end
