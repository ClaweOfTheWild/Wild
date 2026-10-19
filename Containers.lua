-- Wild: Discover bag containers and open individually enabled item IDs
local ADDON_NAME, Wild = ...

local CONFIRMATION_TIMEOUT = 5
local MAX_ITEM_ID = 2147483647
local BLOCKING_FRAMES = {
    "MerchantFrame", "BankFrame", "GuildBankFrame", "MailFrame", "TradeFrame",
    "AuctionHouseFrame", "ItemInteractionFrame", "ScrappingMachineFrame", "VoidStorageFrame",
    "WildDestroyFrame",
}

local inWorld = false
local scanning = false
local rescanRequested = false
local lootOpen = false
local hasEnabledContainers = false
local interactions = {}
local observedFrames = {}
local failedItems = {}
local requestedData = {}
local pendingData = {}
local pendingOpen
local ScanBags

local function Warn(message)
    Wild.Print("|cffff6600Wild:|r " .. message)
end

local function RequestItemData(itemID)
    if requestedData[itemID] or C_Item.IsItemDataCachedByID(itemID) then return end
    requestedData[itemID] = true
    pendingData[itemID] = true
    C_Item.RequestLoadItemDataByID(itemID)
end

local function ClearPendingOpen()
    if pendingOpen and pendingOpen.timer then pendingOpen.timer:Cancel() end
    pendingOpen = nil
end

local function ConfirmPendingOpen()
    if not pendingOpen then return true end
    local _, complete = Wild.ConfirmItemActionBatch(pendingOpen.batch)
    if not complete then return false end
    Wild.Log("Containers", "Confirmed item count decrease for container ID " .. pendingOpen.itemID .. ".")
    ClearPendingOpen()
    return true
end

local function StartConfirmationTimer(request)
    request.timer = C_Timer.NewTimer(CONFIRMATION_TIMEOUT, function()
        if pendingOpen ~= request then return end
        request.timer = nil
        if ConfirmPendingOpen() then
            ScanBags()
        elseif lootOpen then
            request.waitingForLoot = true
        else
            failedItems[request.itemID] = true
            ClearPendingOpen()
            Warn("Container opening was not confirmed for item ID " .. request.itemID ..
                ". Skipping this ID; use /wild containers scan to retry.")
            ScanBags()
        end
    end)
end

local function CanOpenContainers()
    if not inWorld or InCombatLockdown() or UnitIsDeadOrGhost("player") or GetCursorInfo()
        or SpellIsTargeting() or UnitCastingInfo("player") or UnitChannelInfo("player")
        or lootOpen or GetNumLootItems() > 0 or next(interactions) then
        return false
    end
    for _, name in ipairs(BLOCKING_FRAMES) do
        local frame = _G[name]
        if frame and frame:IsShown() then
            if not observedFrames[frame] then
                observedFrames[frame] = true
                -- Close events can precede Blizzard hiding the interaction frame.
                frame:HookScript("OnHide", function() ScanBags() end)
            end
            return false
        end
    end
    return true
end

local function IsReady(bag, slot, info)
    if not info.hasLoot or info.isLocked or failedItems[info.itemID]
        or Wild.db.containers.items[info.itemID] ~= true
        or not C_Item.IsItemDataCachedByID(info.itemID) then
        return false
    end
    local start, duration, enabled = C_Container.GetContainerItemCooldown(bag, slot)
    return duration == 0 or (enabled ~= 0 and start + duration <= GetTime())
end

local function ScanPass()
    local discovered = 0
    local candidates = {}
    for itemID in pairs(Wild.db.containers.items) do RequestItemData(itemID) end
    for _, bag in ipairs(Wild.GetPlayerBags()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                RequestItemData(info.itemID)
                if info.hasLoot then
                    if Wild.db.containers.items[info.itemID] == nil then
                        local enabled = Wild.db.containers.autoOpenNew == true
                        Wild.db.containers.items[info.itemID] = enabled
                        discovered = discovered + 1
                        Wild.Log("Containers", "Discovered item ID " .. info.itemID ..
                            "; auto-open " .. (enabled and "enabled." or "disabled."))
                    end
                    if Wild.db.containers.items[info.itemID] == true and not failedItems[info.itemID] then
                        candidates[#candidates + 1] = {
                            bag = bag, slot = slot, itemID = info.itemID, hyperlink = info.hyperlink,
                        }
                    end
                end
            end
        end
    end
    hasEnabledContainers = #candidates > 0
    if discovered > 0 then Wild.NotifySettingsChanged("containers.items") end
    if ConfirmPendingOpen() and CanOpenContainers() then
        for _, candidate in ipairs(candidates) do
            local info = C_Container.GetContainerItemInfo(candidate.bag, candidate.slot)
            if info and info.itemID == candidate.itemID and info.hyperlink == candidate.hyperlink
                and IsReady(candidate.bag, candidate.slot, info) then
                local request = {
                    itemID = info.itemID,
                    batch = Wild.CreateItemActionBatch(Wild.CapturePlayerItemCounts),
                }
                Wild.RecordItemAction(request.batch, info, 1)
                pendingOpen = request
                StartConfirmationTimer(request)
                Wild.Log("Containers", "Requesting opening item ID " .. info.itemID .. ".")
                C_Container.UseContainerItem(candidate.bag, candidate.slot)
                break
            end
        end
    end
    return discovered
end

local function ScanQueuedChanges()
    local discovered = 0
    repeat
        rescanRequested = false
        if not inWorld or not Wild.db then return discovered end
        discovered = discovered + ScanPass()
    until not rescanRequested
    return discovered
end

ScanBags = function()
    if not inWorld or not Wild.db then return 0 end
    if scanning then rescanRequested = true; return 0 end
    scanning = true
    -- Item-data and bag events can fire synchronously during requests.
    local ok, result = pcall(ScanQueuedChanges)
    scanning = false
    if not ok then error(result, 0) end
    return result
end

function Wild.SetContainerAutoOpen(itemID, enabled, source)
    if not Wild.db then Warn("Container settings have not loaded yet."); return false end
    if type(itemID) == "string" and itemID:match("^%d+$") then itemID = tonumber(itemID) end
    if type(itemID) ~= "number" or itemID ~= itemID or itemID < 1 or itemID > MAX_ITEM_ID or itemID % 1 ~= 0 then
        Warn("Container item ID must be a whole number from 1 to " .. MAX_ITEM_ID .. ".")
        return false
    end
    if type(enabled) ~= "boolean" then
        Warn("Container auto-open must be true or false.")
        return false
    end
    Wild.db.containers.items[itemID] = enabled
    failedItems[itemID] = nil
    RequestItemData(itemID)
    Wild.NotifySettingsChanged("containers.items", source)
    ScanBags()
    return true
end

function Wild.GetContainers()
    local items = {}
    for itemID, enabled in pairs(Wild.db and Wild.db.containers.items or {}) do
        local name, link = C_Item.GetItemInfo(itemID)
        items[#items + 1] = {
            itemID = itemID, autoOpen = enabled == true, name = name or ("Item " .. itemID), link = link,
        }
    end
    table.sort(items, function(left, right) return left.itemID < right.itemID end)
    return items
end

function Wild.ScanContainers()
    if not Wild.db then Warn("Container settings have not loaded yet."); return false end
    wipe(failedItems)
    wipe(requestedData)
    return ScanBags()
end

local frame = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN",
    "ITEM_UNLOCKED", "ITEM_DATA_LOAD_RESULT", "PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "CURSOR_CHANGED", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "MERCHANT_CLOSED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_CLOSED", "MAIL_CLOSED", "TRADE_CLOSED",
    "AUCTION_HOUSE_CLOSED",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP",
}) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if (event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP") and arg1 ~= "player" then return end
    if event == "PLAYER_LEAVING_WORLD" then
        inWorld = false
        lootOpen = false
        hasEnabledContainers = false
        wipe(interactions)
        ClearPendingOpen()
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        inWorld = true
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        lootOpen = true
        return
    elseif event == "LOOT_CLOSED" then
        lootOpen = false
        if pendingOpen and pendingOpen.waitingForLoot then
            pendingOpen.waitingForLoot = nil
            StartConfirmationTimer(pendingOpen)
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        interactions[arg1] = true
        return
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        interactions[arg1] = nil
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        if not pendingData[arg1] then return end
        pendingData[arg1] = nil
        if Wild.db and Wild.db.containers.items[arg1] ~= nil then
            if not arg2 then
                Warn("Could not load item data for container ID " .. arg1 ..
                    ". Check the ID; its saved opening choice is unchanged.")
            end
            Wild.NotifySettingsChanged("containers.items")
        elseif not arg2 then
            Wild.Log("Containers", "Could not load bag item data for item ID " .. arg1 .. ".")
        end
    end
    local discoveryEvent = event == "PLAYER_ENTERING_WORLD" or event == "BAG_UPDATE_DELAYED"
        or event == "ITEM_DATA_LOAD_RESULT"
    if not discoveryEvent and (not hasEnabledContainers or InCombatLockdown()) then return end
    ScanBags()
end)
