-- Wild: Cross-character inventory datastore
local ADDON_NAME, Wild = ...

-- ============================================================
-- Location constants
-- ============================================================

local LOCATION_BAGS    = "bags"
local LOCATION_REAGENT_BAG = "reagentBag"
local LOCATION_KEYRING = "keyring"
local LOCATION_EQUIPPED = "equipped"
local LOCATION_BANK    = "bank"
local LOCATION_REAGENT_BANK = "reagentBank"
local LOCATION_WARBAND = "warband"
local LOCATION_GUILD   = "guild"
local LOCATION_MAIL = "mail"

-- Expose for external use
Wild.LOCATION_BAGS    = LOCATION_BAGS
Wild.LOCATION_BANK    = LOCATION_BANK
Wild.LOCATION_WARBAND = LOCATION_WARBAND
Wild.LOCATION_GUILD   = LOCATION_GUILD
Wild.LOCATION_MAIL    = LOCATION_MAIL

local LOCATION_LABELS = {
    [LOCATION_BAGS] = "Bags",
    [LOCATION_REAGENT_BAG] = "Reagent Bag",
    [LOCATION_KEYRING] = "Keyring",
    [LOCATION_EQUIPPED] = "Equipped",
    [LOCATION_BANK] = "Bank",
    [LOCATION_REAGENT_BANK] = "Reagent Bank",
    [LOCATION_WARBAND] = "Bank",
    [LOCATION_GUILD] = "Bank",
    [LOCATION_MAIL] = "Mail",
}

--- Return a display label for an inventory location, such as "Mail".
function Wild.GetInventoryLocationLabel(location)
    return LOCATION_LABELS[location]
end

-- ============================================================
-- Internal helpers
-- ============================================================

local GetCharKey = Wild.GetCharKey
local REAGENT_BAG = Enum.BagIndex.ReagentBag
local KEYRING = Enum.BagIndex.Keyring
local REAGENT_BANK_BAG = Enum.BagIndex.Reagentbank
local CHARACTER_BANK_BAGS = Wild.GetCharacterBankBags()
local ACCOUNT_BANK_TABS = Wild.GetAccountBankBags()
local GUILD_BANK_SLOTS_PER_TAB = 98
local SECONDS_PER_DAY = 86400
local SENT_MAIL_RETENTION = 30 * SECONDS_PER_DAY
local isGuildBankOpen = false

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
    if not Wild.db.datastore.sentMail then Wild.db.datastore.sentMail = {} end
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

local function PopulateItemDetails(item)
    local name, _, quality, itemLevel, _, itemType, itemSubType,
          _, equipLoc, _, sellPrice, classID, subclassID, bindType, expansionID =
        C_Item.GetItemInfo(item.link or item.itemID)
    item.name = name or item.name or (item.link and item.link:match("|h%[(.-)%]|h")) or "?"
    item.quality = item.quality or quality
    item.ilvl = (item.link and C_Item.GetDetailedItemLevelInfo(item.link)) or itemLevel
    item.itemType = itemType
    item.itemSubType = itemSubType
    item.equipLoc = equipLoc
    item.classID = classID
    item.subclassID = subclassID
    item.bindType = bindType
    item.expansionID = expansionID
    item.sellPrice = Wild.GetEffectiveSellPrice(item.itemID, {
        itemID = item.itemID, hyperlink = item.link, stackCount = item.count, bag = item.bag, slot = item.slot,
    }) or sellPrice
    return item
end

local function AppendContainerItems(items, bagID)
    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and info.itemID then
            items[#items + 1] = PopulateItemDetails({
                itemID = info.itemID, link = info.hyperlink, name = info.itemName,
                quality = info.quality, count = info.stackCount or 1, isBound = info.isBound or false,
                icon = info.iconFileID, bag = bagID, slot = slot,
            })
        end
    end
    return numSlots
end

local function ReadBankContainers(bags, extraBag)
    local items, slots = {}, 0
    for _, bag in ipairs(bags) do
        slots = slots + AppendContainerItems(items, bag)
    end
    if extraBag then slots = slots + AppendContainerItems(items, extraBag) end
    -- An empty bank still has slots; zero slots can mean its data is not ready.
    if slots > 0 then return items end
end

--- Replace the active character's carried-item snapshot, including read-only bags.
function Wild.SnapshotBags()
    if not Wild.db then return end
    local store = EnsureCharacterStore(GetCharKey())
    if not store then return end
    local items = {}
    for _, bag in ipairs(Wild.GetPlayerStorageBags()) do
        AppendContainerItems(items, bag)
    end
    store.bags = items
    store.bagsUpdated = time()
end

--- Replace the active character's equipment snapshot.
function Wild.SnapshotEquipment()
    if not Wild.db then return end
    local store = EnsureCharacterStore(GetCharKey())
    local items = {}
    for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            items[#items + 1] = PopulateItemDetails({
                itemID = itemID, link = GetInventoryItemLink("player", slot),
                count = GetInventoryItemCount("player", slot) or 1, slot = slot,
            })
        end
    end
    store.equipped = items
end

--- Replace the personal bank snapshot only when the client exposes its contents.
function Wild.SnapshotBank()
    if not Wild.db or not C_Bank.CanViewBank(Enum.BankType.Character) then return end
    local items = ReadBankContainers(CHARACTER_BANK_BAGS, REAGENT_BANK_BAG)
    if not items then return end
    local store = EnsureCharacterStore(GetCharKey())
    store.bank = items
    store.bankUpdated = time()
end

--- Replace the shared Warband bank snapshot only when its contents are available.
function Wild.SnapshotWarbandBank()
    if not Wild.db or not C_Bank.CanViewBank(Enum.BankType.Account) then return end
    local items = ReadBankContainers(ACCOUNT_BANK_TABS)
    if not items then return end
    local ds = EnsureDatastore()
    ds.warband.bank = items
    ds.warband.updated = time()
end

--- Replace the selected guild tab without rewriting tabs the client has not loaded.
function Wild.SnapshotGuildBank()
    if not Wild.db or not isGuildBankOpen then return end
    local guildKey = GetGuildKey()
    if not guildKey then return end
    local tab = GetCurrentGuildBankTab()
    local tabCount = GetNumGuildBankTabs()
    if not tab or not tabCount or tab < 1 or tab > tabCount then return end
    local _, _, canView = GetGuildBankTabInfo(tab)
    if not canView then return end

    local items = {}
    for slot = 1, GUILD_BANK_SLOTS_PER_TAB do
        local icon, count = GetGuildBankItemInfo(tab, slot)
        if count and count > 0 then
            local link = GetGuildBankItemLink(tab, slot)
            if not link then return end
            local itemID = tonumber(link:match("item:(%d+)"))
            if itemID then
                items[#items + 1] = PopulateItemDetails({
                    itemID = itemID, link = link, count = count, isBound = false,
                    icon = icon, tab = tab, slot = slot,
                })
            end
        end
    end

    local ds = EnsureDatastore()
    local guild = ds.guilds[guildKey] or {}
    for _, item in ipairs(guild.bank or {}) do
        if item.tab ~= tab then items[#items + 1] = item end
    end
    guild.bank = items
    guild.updated = time()
    ds.guilds[guildKey] = guild
end

local function NormalizeMailAddress(address)
    if type(address) ~= "string" then return end
    address = address:match("^%s*(.-)%s*$")
    if address == "" then return end
    local name, realm = address:match("^([^-]+)%-(.+)$")
    if not name then
        if address:find("-", 1, true) then return end
        name, realm = address, GetRealmName()
    end
    local lower = strlower or string.lower
    return lower(name .. "-" .. realm:gsub("[%s'%-]", "")), name .. "-" .. realm
end

local function IsUnexpired(item, now)
    return not item.expiresAt or item.expiresAt > now
end

local function AppendInboxItems(items, mailIndex, attachmentCount, expiresAt)
    local seenAttachments = 0
    for slot = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local name, itemID, icon, count, quality, _, isCurrency = GetInboxItem(mailIndex, slot)
        if isCurrency then
            seenAttachments = seenAttachments + 1
        elseif itemID and itemID > 0 and count and count > 0 then
            items[#items + 1] = {
                itemID = itemID, link = GetInboxItemLink(mailIndex, slot), count = count,
                name = name, quality = quality, icon = icon, expiresAt = expiresAt,
            }
            seenAttachments = seenAttachments + 1
        end
        if seenAttachments == attachmentCount then return true end
    end
    return false
end

local function ReadInbox()
    local loaded, total = GetInboxNumItems()
    if not loaded or (loaded == 0 and total and total > 0) then return end
    local items, observedAt = {}, time()
    for mailIndex = 1, loaded do
        local _, _, _, _, _, _, daysLeft, attachmentCount = GetInboxHeaderInfo(mailIndex)
        if not daysLeft then return end
        if attachmentCount and attachmentCount > 0
            and not AppendInboxItems(items, mailIndex, attachmentCount, observedAt + daysLeft * SECONDS_PER_DAY) then
            return
        end
    end
    return items, observedAt, loaded == total
end

local function SnapshotInbox()
    if not Wild.db then return end
    local items, observedAt, isComplete = ReadInbox()
    if not items then return end
    local charKey = GetCharKey()
    local store = EnsureCharacterStore(charKey)
    store.mail, store.mailUpdated = items, observedAt
    -- Unloaded messages may still contain items from a recorded send.
    if isComplete then
        Wild.db.datastore.sentMail[NormalizeMailAddress(charKey)] = nil
    end
end

local function CaptureOutgoingMail(address)
    local key, recipient = NormalizeMailAddress(address)
    if not key then return end
    local items = {}
    for slot = 1, ATTACHMENTS_MAX_SEND or 12 do
        local name, itemID, icon, count, quality = GetSendMailItem(slot)
        if itemID and itemID > 0 and count and count > 0 then
            items[#items + 1] = {
                itemID = itemID, link = GetSendMailItemLink(slot), count = count,
                name = name, quality = quality, icon = icon,
            }
        end
    end
    if #items > 0 then return { key = key, recipient = recipient, items = items } end
end

local function RecordSentMail(batch)
    local ds = EnsureDatastore()
    if not ds then return end
    local sent = ds.sentMail[batch.key] or { recipient = batch.recipient, items = {} }
    local expiresAt = time() + SENT_MAIL_RETENTION
    for _, item in ipairs(batch.items) do
        item.expiresAt = expiresAt
        sent.items[#sent.items + 1] = item
    end
    ds.sentMail[batch.key] = sent
end

local function PruneSentMail()
    local ds = Wild.db and Wild.db.datastore
    local now = time()
    for key, sent in pairs(ds and ds.sentMail or {}) do
        local unexpiredItems = {}
        for _, item in ipairs(sent.items) do
            if IsUnexpired(item, now) then unexpiredItems[#unexpiredItems + 1] = item end
        end
        sent.items = unexpiredItems
        if #unexpiredItems == 0 then ds.sentMail[key] = nil end
    end
end

local function GetItemLocation(item, location)
    if location == LOCATION_BAGS then
        if REAGENT_BAG and item.bag == REAGENT_BAG then return LOCATION_REAGENT_BAG end
        if KEYRING and item.bag == KEYRING then return LOCATION_KEYRING end
    elseif location == LOCATION_BANK and REAGENT_BANK_BAG and item.bag == REAGENT_BANK_BAG then
        return LOCATION_REAGENT_BANK
    end
    return location
end

local function VisitInventory(ds, visit)
    for charKey, store in pairs(ds.characters or {}) do
        visit(store.bags, LOCATION_BAGS, charKey)
        visit(store.bank, LOCATION_BANK, charKey)
        visit(store.equipped, LOCATION_EQUIPPED, charKey)
        visit(store.mail, LOCATION_MAIL, charKey)
    end
    if ds.warband then visit(ds.warband.bank, LOCATION_WARBAND) end
    for guildKey, guild in pairs(ds.guilds or {}) do
        visit(guild.bank, LOCATION_GUILD, nil, guildKey)
    end
    for _, sent in pairs(ds.sentMail or {}) do
        visit(sent.items, LOCATION_MAIL, nil, nil, sent.recipient)
    end
end

local function CollectItemResults(matches)
    local ds = Wild.db and Wild.db.datastore
    if not ds then return {} end
    local results, byID, rowsByID = {}, {}, {}
    local now = time()

    local function Collect(items, location, character, guild, recipient)
        for _, item in ipairs(items or {}) do
            if IsUnexpired(item, now) and matches(item) then
                local result = byID[item.itemID]
                if not result then
                    result = {
                        itemID = item.itemID, name = item.name, link = item.link, icon = item.icon,
                        total = 0, breakdown = {}, sentMail = {},
                    }
                    results[#results + 1] = result
                    byID[item.itemID], rowsByID[item.itemID] = result, {}
                end

                local itemLocation = GetItemLocation(item, location)
                local key = itemLocation .. ":" .. (character or guild or "") .. ":" .. (recipient or "")
                local rows = rowsByID[item.itemID]
                local row = rows[key]
                if not row then
                    row = { location = itemLocation, character = character, guild = guild, recipient = recipient, count = 0 }
                    rows[key] = row
                    local breakdown = recipient and result.sentMail or result.breakdown
                    breakdown[#breakdown + 1] = row
                end
                row.count = row.count + item.count
                if not recipient then result.total = result.total + item.count end
            end
        end
    end

    VisitInventory(ds, Collect)
    return results
end

--- Return the observed total and grouped locations for an item ID, and a separate list of sent mail.
function Wild.GetItemTotal(itemID)
    local result = CollectItemResults(function(item) return item.itemID == itemID end)[1]
    if not result then return 0, {}, {} end
    return result.total, result.breakdown, result.sentMail
end

--- Find items by partial name. Sent-mail quantities are separate from each result's total.
function Wild.FindItems(query)
    local lowerQuery = query:lower()
    return CollectItemResults(function(item)
        return item.name and item.name:lower():find(lowerQuery, 1, true)
    end)
end

--- Get entries for a specific item in a specific character+location.
--- Useful for the intent engine to inspect remote item details.
function Wild.GetItemEntries(itemID, location, key)
    local ds = Wild.db and Wild.db.datastore
    if not ds then return {} end

    local entries = {}
    local source

    local storage = location
    if location == LOCATION_REAGENT_BAG or location == LOCATION_KEYRING then
        storage = LOCATION_BAGS
    elseif location == LOCATION_REAGENT_BANK then
        storage = LOCATION_BANK
    end
    if storage == LOCATION_BAGS or storage == LOCATION_BANK or storage == LOCATION_EQUIPPED or storage == LOCATION_MAIL then
        local store = ds.characters and ds.characters[key]
        if store then source = store[storage] end
    elseif location == LOCATION_WARBAND then
        source = ds.warband and ds.warband.bank
    elseif location == LOCATION_GUILD then
        local gStore = ds.guilds and ds.guilds[key]
        if gStore then source = gStore.bank end
    end

    if source then
        local now = time()
        for _, item in ipairs(source) do
            if item.itemID == itemID and IsUnexpired(item, now)
                and (storage == location or GetItemLocation(item, storage) == location) then
                entries[#entries + 1] = item
            end
        end
    end
    return entries
end

-- ============================================================
-- Query: Formatted breakdown for chat output
-- ============================================================

function Wild.FormatItemBreakdown(breakdown, sentMail)
    local parts = {}
    for _, entry in ipairs(breakdown) do
        local owner = entry.character or entry.guild or (entry.location == LOCATION_WARBAND and "Warband" or "Guild")
        local label = Wild.GetInventoryLocationLabel(entry.location)
        if label then parts[#parts + 1] = entry.count .. "x " .. owner .. " " .. label:lower() end
    end
    for _, entry in ipairs(sentMail or {}) do
        parts[#parts + 1] = entry.count .. "x sent to " .. entry.recipient
    end
    return table.concat(parts, ", ")
end

-- ============================================================
-- Query: Datastore summary (for /wild datastore status)
-- ============================================================

local function FormatSnapshotTime(updated)
    if updated and updated > 0 then return date("%Y-%m-%d %H:%M", updated) end
    return "never"
end

function Wild.GetDatastoreSummary()
    local ds = Wild.db and Wild.db.datastore
    if not ds then return "Datastore not initialized." end

    local lines = {}
    lines[#lines + 1] = "|cff00ccff--- Wild Datastore ---|r"

    -- Characters
    if ds.characters then
        local count = 0
        local now = time()
        for _ in pairs(ds.characters) do count = count + 1 end
        lines[#lines + 1] = "Characters tracked: " .. count
        for charKey, store in pairs(ds.characters) do
            local bagCount = store.bags and #store.bags or 0
            local bankCount = store.bank and #store.bank or 0
            local equipmentCount = store.equipped and #store.equipped or 0
            local mailCount = 0
            for _, item in ipairs(store.mail or {}) do
                if IsUnexpired(item, now) then mailCount = mailCount + 1 end
            end
            lines[#lines + 1] = string.format("  %s: %d bag stacks (%s), %d bank stacks (%s), %d equipped, %d mail stacks (%s)",
                charKey, bagCount, FormatSnapshotTime(store.bagsUpdated), bankCount, FormatSnapshotTime(store.bankUpdated),
                equipmentCount, mailCount, FormatSnapshotTime(store.mailUpdated))
        end
    end

    -- Warband
    if ds.warband and ds.warband.bank then
        lines[#lines + 1] = string.format("Warband bank: %d items (%s)",
            #ds.warband.bank, FormatSnapshotTime(ds.warband.updated))
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
            lines[#lines + 1] = string.format("  %s: %d items (%s)",
                guildKey, itemCount, FormatSnapshotTime(store.updated))
        end
    end

    return lines
end

-- ============================================================
-- Event-driven snapshots
-- ============================================================

do
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

    frame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD" then
            Wild.SnapshotBags()
            Wild.SnapshotEquipment()
            PruneSentMail()
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            Wild.SnapshotEquipment()
        else
            Wild.SnapshotBags()
        end
    end)
end

do
    local frame = CreateFrame("Frame")
    local isBankOpen = false
    for _, event in ipairs({
        "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
        "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED",
        "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "BAG_UPDATE_DELAYED",
    }) do
        frame:RegisterEvent(event)
    end
    if REAGENT_BANK_BAG then
        frame:RegisterEvent("PLAYERREAGENTBANKSLOTS_CHANGED")
        frame:RegisterEvent("REAGENTBANK_PURCHASED")
    end

    local function IsBankInteraction(interactionType)
        local types = Enum.PlayerInteractionType
        return interactionType and (interactionType == types.Banker
            or interactionType == types.CharacterBanker or interactionType == types.AccountBanker)
    end

    frame:SetScript("OnEvent", function(_, event, interactionType)
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            if not IsBankInteraction(interactionType) then return end
            isBankOpen = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        elseif event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED" then
            isBankOpen = event == "BANKFRAME_OPENED"
        end
        if not isBankOpen then return end
        if event ~= "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" then Wild.SnapshotBank() end
        if event ~= "PLAYERBANKSLOTS_CHANGED" and event ~= "PLAYERREAGENTBANKSLOTS_CHANGED"
            and event ~= "REAGENTBANK_PURCHASED" then Wild.SnapshotWarbandBank() end
    end)
end

do
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GUILDBANKFRAME_OPENED")
    frame:RegisterEvent("GUILDBANKFRAME_CLOSED")
    frame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "GUILDBANKBAGSLOTS_CHANGED" then
            Wild.SnapshotGuildBank()
        else
            isGuildBankOpen = event == "GUILDBANKFRAME_OPENED"
        end
    end)
end

do
    local frame = CreateFrame("Frame")
    local isMailboxOpen, pendingSend
    for _, event in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED" }) do
        frame:RegisterEvent(event)
    end

    if SendMail and hooksecurefunc then
        -- Both Blizzard and Wild call SendMail; success may clear the compose slots first.
        hooksecurefunc("SendMail", function(address)
            if isMailboxOpen then pendingSend = CaptureOutgoingMail(address) end
        end)
    end

    frame:SetScript("OnEvent", function(_, event)
        if event == "MAIL_SHOW" then
            isMailboxOpen = true
        elseif event == "MAIL_CLOSED" then
            isMailboxOpen = false
        elseif event == "MAIL_INBOX_UPDATE" then
            if isMailboxOpen then SnapshotInbox() end
        elseif event == "MAIL_SEND_SUCCESS" then
            local batch = pendingSend
            pendingSend = nil
            if batch then
                RecordSentMail(batch)
                Wild.SnapshotBags()
            end
        elseif event == "MAIL_FAILED" then
            pendingSend = nil
        end
    end)
end
