-- Wild: Bank automation (Character, Warband, Guild) — Intent-based
local ADDON_NAME, Wild = ...

-- ============================================================
-- Bank container indices
-- ============================================================

-- Midnight (12.x): character bank uses CharacterBankTab (-2) and
-- CharacterBankTab_1..6 (indices 6-11). The old Bank (-1) and
-- BankBag_1..7 enum names no longer exist.
local CHARACTER_BANK_BAGS = {}
if Enum.BagIndex.CharacterBankTab then
    table.insert(CHARACTER_BANK_BAGS, Enum.BagIndex.CharacterBankTab)
end
for i = 1, 6 do
    local key = "CharacterBankTab_" .. i
    if Enum.BagIndex[key] ~= nil then
        table.insert(CHARACTER_BANK_BAGS, Enum.BagIndex[key])
    end
end
-- Fallback for pre-Midnight (TWW / older): use Bank + BankBag_1..7
if #CHARACTER_BANK_BAGS == 0 then
    if Enum.BagIndex.Bank then
        table.insert(CHARACTER_BANK_BAGS, Enum.BagIndex.Bank)
    end
    for i = 1, 7 do
        local key = "BankBag_" .. i
        if Enum.BagIndex[key] ~= nil then
            table.insert(CHARACTER_BANK_BAGS, Enum.BagIndex[key])
        end
    end
end

local ACCOUNT_BANK_TABS = {}
if Enum and Enum.BagIndex then
    for i = 1, 5 do
        local key = "AccountBankTab_" .. i
        if Enum.BagIndex[key] ~= nil then
            table.insert(ACCOUNT_BANK_TABS, Enum.BagIndex[key])
        end
    end
end

local GUILD_BANK_SLOTS_PER_TAB = 98

-- ============================================================
-- Debug helper (must be above withdraw/deposit functions)
-- ============================================================

local function BlogMsg(msg)
    Wild.Log("Bank", msg)
end

-- ============================================================
-- Player bag list (respects includeReagentBag setting)
-- ============================================================

local function GetPlayerBags()
    local bags = { BACKPACK_CONTAINER }
    for i = 1, NUM_BAG_SLOTS do bags[#bags + 1] = i end
    if Enum.BagIndex.ReagentBag
       and (not Wild.db or Wild.db.includeReagentBag ~= false) then
        bags[#bags + 1] = Enum.BagIndex.ReagentBag
    end
    return bags
end

Wild.GetPlayerBags = GetPlayerBags

-- ============================================================
-- Place cursor item into a free player bag slot
-- Used after SplitContainerItem to drop partial stacks.
-- ============================================================

local function PlaceCursorInBags(itemID)
    -- Phase 1: try to merge into an existing partial stack of the same item
    if itemID then
        local maxStack = select(8, C_Item.GetItemInfo(itemID)) or 1
        if maxStack > 1 then
            for _, bag in ipairs(GetPlayerBags()) do
                local numSlots = C_Container.GetContainerNumSlots(bag)
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.itemID == itemID and (info.stackCount or 1) < maxStack then
                        C_Container.PickupContainerItem(bag, slot)
                        -- If the partial stack absorbed everything, we're done.
                        -- If overflow remains on cursor, WoW keeps it there;
                        -- fall through to find another slot.
                        if not GetCursorInfo() then return true end
                    end
                end
            end
        end
    end
    -- Phase 2: fall back to first empty slot
    for _, bag in ipairs(GetPlayerBags()) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if not info then
                C_Container.PickupContainerItem(bag, slot)
                return true
            end
        end
    end
    ClearCursor()
    return false
end

-- ============================================================
-- Place cursor item into a free bank slot
-- Used after SplitContainerItem to drop partial stacks into bank.
-- ============================================================

local function PlaceCursorInBank(bankType, itemID)
    local bankBags
    if bankType == Enum.BankType.Account then
        bankBags = ACCOUNT_BANK_TABS
    else
        bankBags = CHARACTER_BANK_BAGS
    end
    -- Phase 1: try to merge into an existing partial stack of the same item
    if itemID then
        local maxStack = select(8, C_Item.GetItemInfo(itemID)) or 1
        if maxStack > 1 then
            for _, bag in ipairs(bankBags) do
                local numSlots = C_Container.GetContainerNumSlots(bag)
                if numSlots and numSlots > 0 then
                    for slot = 1, numSlots do
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info and info.itemID == itemID and (info.stackCount or 1) < maxStack then
                            C_Container.PickupContainerItem(bag, slot)
                            if not GetCursorInfo() then return true end
                        end
                    end
                end
            end
        end
    end
    -- Phase 2: fall back to first empty slot
    for _, bag in ipairs(bankBags) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if not info then
                    C_Container.PickupContainerItem(bag, slot)
                    return true
                end
            end
        end
    end
    ClearCursor()
    return false
end

-- ============================================================
-- Deposit from bags (shared across all bank types)
-- ============================================================

local TARGET_BANK_TYPE = {
    warband   = Enum.BankType.Account,
}
-- Character bank deposit: pass nil bankType (UseContainerItem defaults to character bank)
-- Warband bank deposit: pass Enum.BankType.Account explicitly

local function DepositFromBags(intent, charCtx, maxCount, bankType, seen, itemLimits)
    if maxCount == 0 then maxCount = math.huge end
    local deposited = 0
    local entries = {}
    for _, bag in ipairs(GetPlayerBags()) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            if maxCount > 0 and deposited >= maxCount then return deposited, entries end
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then info.bag = bag; info.slot = slot end
            local slotKey = bag .. ":" .. slot
            local itemKey = info and (info.hyperlink or info.itemID)
            if info and info.itemID and not seen[slotKey]
                and (not itemLimits or (itemLimits[itemKey] or 0) > 0)
                and Wild.IntentMatchesItem(intent, info.itemID, info, charCtx) then
                local stackCount = info.stackCount or 1
                local remaining = maxCount - deposited
                local moveCount = math.min(stackCount, remaining)
                if itemLimits then moveCount = math.min(moveCount, itemLimits[itemKey]) end
                seen[slotKey] = true
                if itemLimits then itemLimits[itemKey] = itemLimits[itemKey] - moveCount end
                if moveCount < stackCount then
                    C_Container.SplitContainerItem(bag, slot, moveCount)
                    -- Cursor now holds the split portion; deposit it into the bank
                    PlaceCursorInBank(bankType or Enum.BankType.Character, info.itemID)
                else
                    if bankType then
                        C_Container.UseContainerItem(bag, slot, nil, bankType)
                    else
                        C_Container.UseContainerItem(bag, slot)
                    end
                end
                deposited = deposited + moveCount
                entries[#entries + 1] = { link = info.hyperlink, itemID = info.itemID, count = moveCount }
            end
        end
    end
    return deposited, entries
end

-- ============================================================
-- Withdraw from Character Bank
-- ============================================================

local function WithdrawFromCharacterBank(intent, charCtx, neededCount, seen)
    if neededCount == 0 then neededCount = math.huge end
    local withdrawn = 0
    local entries = {}
    BlogMsg("WithdrawFromCharacterBank: scanning " .. #CHARACTER_BANK_BAGS .. " bank bag(s), neededCount=" .. tostring(neededCount))
    for _, bag in ipairs(CHARACTER_BANK_BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        BlogMsg("  Bank bag " .. tostring(bag) .. ": " .. tostring(numSlots) .. " slot(s)")
        if numSlots and numSlots > 0 then
            local itemCount = 0
            for slot = 1, numSlots do
                if neededCount > 0 and withdrawn >= neededCount then return withdrawn, entries end
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then
                    info.bag = bag; info.slot = slot
                    itemCount = itemCount + 1
                end
                local slotKey = bag .. ":" .. slot
                if info and info.itemID and not seen[slotKey] and Wild.IntentMatchesItem(intent, info.itemID, info, charCtx) then
                    local stackCount = info.stackCount or 1
                    local remaining = neededCount - withdrawn
                    local moveCount = stackCount
                    seen[slotKey] = true
                    if remaining < stackCount then
                        moveCount = remaining
                        C_Container.SplitContainerItem(bag, slot, moveCount)
                        -- Cursor now holds the split portion; place it into bags
                        PlaceCursorInBags(info.itemID)
                    else
                        C_Container.UseContainerItem(bag, slot)
                    end
                    withdrawn = withdrawn + moveCount
                    entries[#entries + 1] = { link = info.hyperlink, itemID = info.itemID, count = moveCount }
                end
            end
            BlogMsg("  Bank bag " .. tostring(bag) .. ": found " .. itemCount .. " item(s) in " .. tostring(numSlots) .. " slot(s)")
        end
    end
    return withdrawn, entries
end

-- ============================================================
-- Withdraw from Warband Bank
-- ============================================================

local function WithdrawFromWarbandBank(intent, charCtx, neededCount, seen)
    if neededCount == 0 then neededCount = math.huge end
    local withdrawn = 0
    local entries = {}
    BlogMsg("WithdrawFromWarbandBank: scanning " .. #ACCOUNT_BANK_TABS .. " warband tab(s), neededCount=" .. tostring(neededCount))
    for _, bankBag in ipairs(ACCOUNT_BANK_TABS) do
        local numSlots = C_Container.GetContainerNumSlots(bankBag)
        BlogMsg("  Warband tab " .. tostring(bankBag) .. ": " .. tostring(numSlots) .. " slot(s)")
        if numSlots and numSlots > 0 then
            local itemCount = 0
            for slot = 1, numSlots do
                if neededCount > 0 and withdrawn >= neededCount then return withdrawn, entries end
                local info = C_Container.GetContainerItemInfo(bankBag, slot)
                if info then
                    info.bag = bankBag; info.slot = slot
                    itemCount = itemCount + 1
                end
                local slotKey = bankBag .. ":" .. slot
                if info and info.itemID and not seen[slotKey] and Wild.IntentMatchesItem(intent, info.itemID, info, charCtx) then
                    local stackCount = info.stackCount or 1
                    local remaining = neededCount - withdrawn
                    local moveCount = stackCount
                    seen[slotKey] = true
                    if remaining < stackCount then
                        moveCount = remaining
                        C_Container.SplitContainerItem(bankBag, slot, moveCount)
                        -- Cursor now holds the split portion; place it into bags
                        PlaceCursorInBags(info.itemID)
                    else
                        C_Container.UseContainerItem(bankBag, slot)
                    end
                    withdrawn = withdrawn + moveCount
                    entries[#entries + 1] = { link = info.hyperlink, itemID = info.itemID, count = moveCount }
                end
            end
            BlogMsg("  Warband tab " .. tostring(bankBag) .. ": found " .. itemCount .. " item(s) in " .. tostring(numSlots) .. " slot(s)")
        end
    end
    return withdrawn, entries
end

-- ============================================================
-- Withdraw from Guild Bank
-- ============================================================

local function WithdrawFromGuildBank(intent, charCtx, neededCount, seen)
    if neededCount == 0 then neededCount = math.huge end
    local withdrawn = 0
    local entries = {}
    local numTabs = GetNumGuildBankTabs()
    for tab = 1, numTabs do
        local _, _, isViewable = GetGuildBankTabInfo(tab)
        if isViewable then
            for slot = 1, GUILD_BANK_SLOTS_PER_TAB do
                if neededCount > 0 and withdrawn >= neededCount then return withdrawn, entries end
                local _, itemCount = GetGuildBankItemInfo(tab, slot)
                local slotKey = tab .. ":" .. slot
                if itemCount and itemCount > 0 and not seen[slotKey] then
                    local link = GetGuildBankItemLink(tab, slot)
                    if link then
                        local itemID = tonumber(link:match("item:(%d+)"))
                        if itemID and Wild.IntentMatchesItem(intent, itemID, { quality = select(3, C_Item.GetItemInfo(itemID)), hyperlink = link }, charCtx) then
                            seen[slotKey] = true
                            AutoStoreGuildBankItem(tab, slot)
                            withdrawn = withdrawn + itemCount
                            entries[#entries + 1] = { link = link, itemID = itemID, count = itemCount }
                        end
                    end
                end
            end
        end
    end
    return withdrawn, entries
end

-- ============================================================
-- Bank source mapping
-- ============================================================

local WITHDRAW_FUNCS = {
    character = WithdrawFromCharacterBank,
    warband   = WithdrawFromWarbandBank,
    guild     = WithdrawFromGuildBank,
}

-- ============================================================
-- Count matching items in bank (for withdraw keep semantics)
-- ============================================================

local function CountMatchingInCharacterBank(intent, charCtx)
    local total = 0
    for _, bag in ipairs(CHARACTER_BANK_BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then info.bag = bag; info.slot = slot end
                if info and info.itemID and Wild.IntentMatchesItem(intent, info.itemID, info, charCtx) then
                    total = total + (info.stackCount or 1)
                end
            end
        end
    end
    return total
end

local function CountMatchingInWarbandBank(intent, charCtx)
    local total = 0
    for _, bankBag in ipairs(ACCOUNT_BANK_TABS) do
        local numSlots = C_Container.GetContainerNumSlots(bankBag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bankBag, slot)
                if info then info.bag = bankBag; info.slot = slot end
                if info and info.itemID and Wild.IntentMatchesItem(intent, info.itemID, info, charCtx) then
                    total = total + (info.stackCount or 1)
                end
            end
        end
    end
    return total
end

local function CountMatchingInGuildBank(intent, charCtx)
    local total = 0
    local numTabs = GetNumGuildBankTabs()
    for tab = 1, numTabs do
        local _, _, isViewable = GetGuildBankTabInfo(tab)
        if isViewable then
            for slot = 1, GUILD_BANK_SLOTS_PER_TAB do
                local _, itemCount = GetGuildBankItemInfo(tab, slot)
                if itemCount and itemCount > 0 then
                    local link = GetGuildBankItemLink(tab, slot)
                    if link then
                        local itemID = tonumber(link:match("item:(%d+)"))
                        if itemID and Wild.IntentMatchesItem(intent, itemID, { quality = select(3, C_Item.GetItemInfo(itemID)), hyperlink = link }, charCtx) then
                            total = total + itemCount
                        end
                    end
                end
            end
        end
    end
    return total
end

local BANK_COUNT_FUNCS = {
    character = CountMatchingInCharacterBank,
    warband   = CountMatchingInWarbandBank,
    guild     = CountMatchingInGuildBank,
}

-- ============================================================
-- Event-driven item data pre-loader
-- Requests uncached item data for all bank slots, then calls
-- onComplete() once every ITEM_DATA_LOAD_RESULT has arrived
-- (or after a safety timeout).
-- ============================================================

local preloadFrame = CreateFrame("Frame")
preloadFrame:Hide()
local preloadTimer

local function ClearBankPreload()
    if preloadTimer then preloadTimer:Cancel(); preloadTimer = nil end
    preloadFrame:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
    preloadFrame:SetScript("OnEvent", nil)
end

local function PreloadBankItemData(bankBagSets, onComplete)
    ClearBankPreload()
    local pending = {}
    local pendingCount = 0

    for _, bags in ipairs(bankBagSets) do
        for _, bag in ipairs(bags) do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            if numSlots and numSlots > 0 then
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.itemID and not C_Item.GetItemInfo(info.itemID) then
                        if not pending[info.itemID] then
                            pending[info.itemID] = true
                            pendingCount = pendingCount + 1
                            C_Item.RequestLoadItemDataByID(info.itemID)
                        end
                    end
                end
            end
        end
    end

    BlogMsg("PreloadBankItemData: " .. pendingCount .. " uncached item(s) to load.")

    -- Nothing to wait for — fire immediately
    if pendingCount == 0 then
        onComplete()
        return
    end

    -- Safety timeout: if items never arrive, proceed anyway
    local safetyTimer
    safetyTimer = C_Timer.NewTimer(Wild.db.advanced.preloadTimeout, function()
        if preloadTimer ~= safetyTimer then return end
        if pendingCount > 0 then
            BlogMsg("PreloadBankItemData: safety timeout with " .. pendingCount .. " item(s) still pending.")
            pendingCount = 0
            ClearBankPreload()
            onComplete()
        end
    end)
    preloadTimer = safetyTimer

    preloadFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    preloadFrame:SetScript("OnEvent", function(self, event, itemID, success)
        if pending[itemID] then
            pending[itemID] = nil
            pendingCount = pendingCount - 1
            BlogMsg("PreloadBankItemData: loaded itemID " .. itemID .. " (" .. pendingCount .. " remaining)")
            if pendingCount <= 0 then
                ClearBankPreload()
                onComplete()
            end
        end
    end)
end

-- ============================================================
-- Event-driven intent queue processor and confirmed results
-- ============================================================

local queueFrame = CreateFrame("Frame")
queueFrame:Hide()

local ProcessQueueStep
local WaitForPass
local CompletePass

local activeQueue = nil
local activeIndex = 0
local activeLen = 0
local pendingPass
local confirmationTimer
local bankGeneration = 0

local MAX_PASSES_PER_INTENT = 50
local CONFIRMATION_TIMEOUT = 5
local BANK_NAMES = { character = "Character bank", warband = "Warband bank", guild = "Guild bank" }
local CONFIRMATION_EVENTS = {
    "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",
    "GUILDBANKBAGSLOTS_CHANGED", "PLAYER_MONEY", "ACCOUNT_MONEY", "GUILDBANK_UPDATE_MONEY",
}

local function ReadPlayerItemCounts()
    return Wild.CapturePlayerItemCounts()
end

local function ReadBankItemCounts(target)
    if target ~= "guild" then
        return Wild.CaptureBagItemCounts(target == "warband" and ACCOUNT_BANK_TABS or CHARACTER_BANK_BAGS)
    end
    local counts = {}
    for tab = 1, GetNumGuildBankTabs() do
        local _, _, viewable = GetGuildBankTabInfo(tab)
        if viewable then
            for slot = 1, GUILD_BANK_SLOTS_PER_TAB do
                local _, count = GetGuildBankItemInfo(tab, slot)
                local link = GetGuildBankItemLink(tab, slot)
                if link and count and count > 0 then counts[link] = (counts[link] or 0) + count end
            end
        end
    end
    return counts
end

local function ReadBankMoney(target)
    if target == "warband" then return C_Bank.FetchDepositedMoney(Enum.BankType.Account) end
    if target == "guild" then return GetGuildBankMoney() end
end

local function PrintBankResults(entry)
    local results = entry.results
    for _, item in ipairs(results.deposit) do
        Wild.Print(string.format("|cff00ccffWild:|r Deposited %s \195\151%d to %s.", item.link or ("Item " .. item.itemID), item.count, BANK_NAMES[item.target]))
    end
    for _, item in ipairs(results.withdraw) do
        Wild.Print(string.format("|cff00ccffWild:|r Withdrew %s \195\151%d from %s.", item.link or ("Item " .. item.itemID), item.count,
            BANK_NAMES[item.source]))
    end
    for _, item in ipairs(results.transfer) do
        Wild.Print(string.format("|cff00ccffWild:|r Transferred %s \195\151%d from %s to %s.", item.link or ("Item " .. item.itemID), item.count,
            BANK_NAMES[item.source], BANK_NAMES[item.target]))
    end
    for bank, copper in pairs(results.goldDeposit or {}) do
        if copper > 0 then Wild.Print("|cff00ccffWild:|r Deposited " .. Wild.FormatGold(copper) .. " to " .. BANK_NAMES[bank] .. ".") end
    end
    for bank, copper in pairs(results.goldWithdraw or {}) do
        if copper > 0 then Wild.Print("|cff00ccffWild:|r Withdrew " .. Wild.FormatGold(copper) .. " from " .. BANK_NAMES[bank] .. ".") end
    end
    entry.results = { deposit = {}, withdraw = {}, transfer = {} }
end

local function CollectPassResults(pass)
    local complete = true
    for action, batch in pairs(pass.batches) do
        local entries, done = Wild.ConfirmItemActionBatch(batch)
        for _, item in ipairs(entries) do
            if action == "deposit" then
                item.target = batch.bank
                if pass.kind == "transferDeposit" then item.source = pass.source end
            else
                item.source = batch.bank
            end
        end
        Wild.MergeItemActionEntries(pass.confirmed[action], entries)
        if not done then complete = false end
    end
    local money = pass.money
    if money then
        local bankMoney = ReadBankMoney(money.target)
        if type(bankMoney) == "number" then
            local removed = money.deposit and money.playerBefore - GetMoney() or GetMoney() - money.playerBefore
            local received = money.deposit and bankMoney - money.bankBefore or money.bankBefore - bankMoney
            money.confirmed = math.max(money.confirmed, math.max(0, math.min(money.count, removed, received)))
        end
        if money.confirmed < money.count then complete = false end
    end
    if pass.kind == "transferDeposit" then
        for _, item in ipairs(pass.withdrawn) do
            local deposited = pass.batches.deposit and pass.batches.deposit.confirmed[item.key] or 0
            if (deposited or 0) < item.count then complete = false end
        end
    end
    return complete
end

local function TransferLeftovers(pass)
    local leftovers = {}
    for _, item in ipairs(pass.withdrawn) do
        local deposited = pass.batches.deposit and pass.batches.deposit.confirmed[item.key] or 0
        local remaining = item.count - (deposited or 0)
        if remaining > 0 then
            leftovers[#leftovers + 1] = {
                key = item.key, link = item.link, itemID = item.itemID, count = remaining, source = item.source,
            }
        end
    end
    return leftovers
end

local function StorePassResults(pass, aborted)
    local results = pass.entry.results
    if pass.kind == "transferDeposit" then
        Wild.MergeItemActionEntries(results.transfer, pass.confirmed.deposit)
        pass.confirmed.deposit = {}
        if aborted and not pass.leftoversStored then
            Wild.MergeItemActionEntries(results.withdraw, TransferLeftovers(pass))
            pass.leftoversStored = true
        end
    elseif pass.kind ~= "transferWithdraw" or aborted then
        Wild.MergeItemActionEntries(results.deposit, pass.confirmed.deposit)
        Wild.MergeItemActionEntries(results.withdraw, pass.confirmed.withdraw)
        pass.confirmed = { deposit = {}, withdraw = {} }
    end
    if pass.money then
        local key = pass.money.deposit and "goldDeposit" or "goldWithdraw"
        local bank = pass.money.target
        results[key] = results[key] or {}
        results[key][bank] = (results[key][bank] or 0) + pass.money.confirmed - (pass.money.stored or 0)
        pass.money.stored = pass.money.confirmed
    end
end

local function HasBankProgress(pass)
    for _, batch in pairs(pass.batches) do
        for _, count in pairs(batch.confirmed) do
            if count > 0 then return true end
        end
    end
    return pass.money and pass.money.confirmed > 0
end

local function HasUnconfirmedRemovals(pass)
    for _, batch in pairs(pass.batches) do
        local sourceAfter = batch.readSource()
        for _, item in ipairs(batch.entries) do
            if item.confirmed < item.count then
                local removed = (batch.sourceBefore[item.key] or 0) - (sourceAfter[item.key] or 0)
                if removed > (batch.confirmed[item.key] or 0) then return true end
            end
        end
    end
    return false
end

local function CanRetryPartialPass(pass)
    return HasBankProgress(pass) and not HasUnconfirmedRemovals(pass)
        and (not pass.money or pass.money.confirmed == pass.money.count)
end

local function ClearConfirmationWait()
    for _, event in ipairs(CONFIRMATION_EVENTS) do queueFrame:UnregisterEvent(event) end
    queueFrame:SetScript("OnEvent", nil)
    if confirmationTimer then confirmationTimer:Cancel(); confirmationTimer = nil end
    pendingPass = nil
end

local function FinishQueue()
    if pendingPass then
        CollectPassResults(pendingPass)
        StorePassResults(pendingPass, true)
    end
    if activeQueue and activeQueue[activeIndex] then
        local entry = activeQueue[activeIndex]
        if entry.settlingPass then
            CollectPassResults(entry.settlingPass)
            StorePassResults(entry.settlingPass, true)
        end
        PrintBankResults(entry)
    end
    ClearConfirmationWait()
    queueFrame:Hide()
    activeQueue = nil
    activeIndex = 0
    activeLen = 0
end

local function ScheduleStep(delay, fn)
    local queue = activeQueue
    C_Timer.After(delay, function()
        if activeQueue == queue then fn() end
    end)
end

local function RequestBankItems(pass, action, target, intent, charCtx, count, itemLimits)
    if not BANK_NAMES[target] then
        Wild.Print("|cffff6600Wild:|r Invalid bank target: " .. tostring(target))
        return
    end
    local batch = pass.batches[action]
    if not batch then
        local function ReadBank() return ReadBankItemCounts(target) end
        if action == "deposit" then
            batch = Wild.CreateItemActionBatch(ReadPlayerItemCounts, ReadBank)
        else
            batch = Wild.CreateItemActionBatch(ReadBank, ReadPlayerItemCounts)
        end
        batch.seen = {}
        batch.bank = target
        pass.batches[action] = batch
    end
    local requested, entries
    if action == "deposit" then
        requested, entries = DepositFromBags(intent, charCtx, count, TARGET_BANK_TYPE[target], batch.seen, itemLimits)
    elseif WITHDRAW_FUNCS[target] then
        requested, entries = WITHDRAW_FUNCS[target](intent, charCtx, count, batch.seen)
    else
        Wild.Print("|cffff6600Wild:|r No withdraw function for target: " .. tostring(target))
        return
    end
    for _, item in ipairs(entries) do Wild.RecordItemAction(batch, item, item.count) end
    BlogMsg("Requested " .. action .. " of " .. requested .. " item(s) for " .. target .. ".")
end

local function RequestGoldSync(pass)
    local intent = pass.entry.intent
    local target = intent.target or "warband"
    local goldTarget = Wild.GetIntentGoldTarget(intent)
    BlogMsg(string.format("Hold phase 1: goldTarget=%s reservoir=%s trigger=%s groups=%d",
        Wild.FormatGold(goldTarget * Wild.COPPER_PER_GOLD), target, pass.entry.triggerSource, #(intent.groups or {})))
    if goldTarget <= 0 or target == "character" then return end
    local playerBefore, keep = GetMoney(), goldTarget * Wild.COPPER_PER_GOLD
    BlogMsg(string.format("Gold sync: target=%s current=%s keep=%s reservoir=%s trigger=%s",
        Wild.FormatGold(keep), Wild.FormatGold(playerBefore), Wild.FormatGold(keep), target, pass.entry.triggerSource))
    if playerBefore == keep then return end
    if playerBefore < keep and pass.entry.triggerSource ~= target then return end
    local bankBefore = ReadBankMoney(target)
    if type(bankBefore) ~= "number" then
        Wild.Print("|cffff6600Wild:|r Cannot read bank gold; skipped gold synchronization.")
        return
    end
    local deposit = playerBefore > keep
    local count = deposit and playerBefore - keep or math.min(keep - playerBefore, bankBefore)
    if count <= 0 then BlogMsg("No bank gold available to withdraw."); return end
    pass.money = { target = target, playerBefore = playerBefore, bankBefore = bankBefore,
        deposit = deposit, count = count, confirmed = 0 }
    if target == "warband" then
        if deposit then C_Bank.DepositMoney(Enum.BankType.Account, count)
        else C_Bank.WithdrawMoney(Enum.BankType.Account, count) end
    elseif deposit then
        DepositGuildBankMoney(count)
    else
        WithdrawGuildBankMoney(count)
    end
end

local function NewPass(entry, kind)
    return { entry = entry, kind = kind, batches = {}, confirmed = { deposit = {}, withdraw = {} } }
end

local function ExecuteIntentPass(entry)
    local intent = entry.intent
    local charCtx = Wild.BuildCharContext()
    local pass = NewPass(entry, intent.action == "transfer" and "transferWithdraw" or "normal")
    if intent.action == "hold" then
        RequestGoldSync(pass)
        local target = intent.target or "warband"
        for _, group in ipairs(Wild.GetItemGroups(intent)) do
            local keep = group.count or 0
            if keep > 0 then
                local subIntent = Wild.SubIntentForGroup(intent, group)
                local current = Wild.CountMatchingInBags(subIntent, charCtx)
                if current < keep then
                    RequestBankItems(pass, "withdraw", target, subIntent, charCtx, keep - current)
                elseif current > keep then
                    RequestBankItems(pass, "deposit", target, subIntent, charCtx, current - keep)
                end
            end
        end
    else
        local withdrawing = intent.action == "withdraw" or intent.action == "transfer"
        local target = intent.action == "transfer" and (intent.source or "character") or (intent.target or entry.triggerSource)
        for _, group in ipairs(Wild.GetItemGroups(intent)) do
            local subIntent = Wild.SubIntentForGroup(intent, group)
            local keep = group.count or 0
            local count = 0
            if keep > 0 then
                local current
                if withdrawing then
                    local countFunc = BANK_COUNT_FUNCS[target]
                    current = countFunc and countFunc(subIntent, charCtx) or 0
                else
                    current = Wild.CountMatchingInBags(subIntent, charCtx)
                end
                count = current - keep
            end
            if keep == 0 or count > 0 then
                RequestBankItems(pass, withdrawing and "withdraw" or "deposit", target, subIntent, charCtx, count)
            else
                BlogMsg("Keeping matching items for " .. Wild.GetIntentSummary(intent))
            end
        end
    end
    return pass
end

local function HasItemRequests(pass)
    for _, batch in pairs(pass.batches) do
        if #batch.entries > 0 then return true end
    end
    return false
end

local function AdvanceIntent()
    PrintBankResults(activeQueue[activeIndex])
    activeIndex = activeIndex + 1
    if activeIndex > activeLen then FinishQueue()
    else ScheduleStep(Wild.db.advanced.ruleDelay, ProcessQueueStep) end
end

local function StartTransferDeposit(entry, withdrawn)
    local pass = NewPass(entry, "transferDeposit")
    pass.withdrawn = withdrawn
    pass.source = withdrawn[1].source
    local limits, count = {}, 0
    for _, item in ipairs(withdrawn) do
        limits[item.key] = item.count
        count = count + item.count
    end
    RequestBankItems(pass, "deposit", entry.intent.target or "warband",
        entry.intent, Wild.BuildCharContext(), count, limits)
    if HasItemRequests(pass) then
        WaitForPass(pass)
    else
        StorePassResults(pass, true)
        Wild.Print("|cffff6600Wild:|r Transfer deposit was not confirmed; stopped intent processing.")
        FinishQueue()
    end
end

CompletePass = function(pass)
    ClearConfirmationWait()
    if pass.kind == "transferWithdraw" and #pass.confirmed.withdraw > 0 then
        StartTransferDeposit(pass.entry, pass.confirmed.withdraw)
        return
    end
    StorePassResults(pass, false)
    pass.entry.settlingPass = pass
    if pass.entry.passNum >= MAX_PASSES_PER_INTENT then
        StorePassResults(pass, true)
        Wild.Print("|cffff6600Wild:|r Bank intent safety cap reached (" .. MAX_PASSES_PER_INTENT .. " passes).")
        AdvanceIntent()
    elseif pass.kind == "transferDeposit" and #TransferLeftovers(pass) > 0 then
        ScheduleStep(Wild.db.advanced.passDelay, function()
            CollectPassResults(pass)
            StorePassResults(pass, false)
            local leftovers = TransferLeftovers(pass)
            pass.entry.settlingPass = nil
            if #leftovers > 0 then
                pass.entry.passNum = pass.entry.passNum + 1
                StartTransferDeposit(pass.entry, leftovers)
            else
                ProcessQueueStep()
            end
        end)
    else
        ScheduleStep(Wild.db.advanced.passDelay, ProcessQueueStep)
    end
end

WaitForPass = function(pass)
    pendingPass = pass
    for _, event in ipairs(CONFIRMATION_EVENTS) do queueFrame:RegisterEvent(event) end
    queueFrame:SetScript("OnEvent", function(_, event)
        if pendingPass ~= pass then return end
        if event == "BAG_UPDATE_DELAYED" then pass.bagsUpdated = true end
        local complete = CollectPassResults(pass)
        local partial = pass.kind ~= "transferWithdraw" and CanRetryPartialPass(pass)
        if (complete or partial) and (not HasItemRequests(pass) or pass.bagsUpdated) then
            CompletePass(pass)
        end
    end)
    confirmationTimer = C_Timer.NewTimer(CONFIRMATION_TIMEOUT, function()
        if pendingPass ~= pass then return end
        if CollectPassResults(pass) or CanRetryPartialPass(pass) then
            CompletePass(pass)
        else
            StorePassResults(pass, true)
            Wild.Print("|cffff6600Wild:|r Some bank actions were not confirmed; stopped intent processing.")
            FinishQueue()
        end
    end)
end

ProcessQueueStep = function()
    if not activeQueue then return end
    local entry = activeQueue[activeIndex]
    if entry.settlingPass then
        CollectPassResults(entry.settlingPass)
        StorePassResults(entry.settlingPass, false)
        entry.settlingPass = nil
    end
    entry.passNum = (entry.passNum or 0) + 1
    local pass = ExecuteIntentPass(entry)
    if HasItemRequests(pass) or pass.money then
        WaitForPass(pass)
    else
        BlogMsg("Intent " .. activeIndex .. " has no remaining actions.")
        AdvanceIntent()
    end
end

-- ============================================================
-- Check whether a single intent fires for the given trigger sources.
-- Returns the triggerSource it should execute against, or nil.
-- ============================================================

local function IntentFiresFor(intent, accessibleSources)
    if intent.action == "deposit" or intent.action == "withdraw" or intent.action == "hold" then
        if accessibleSources[intent.target] then
            return intent.target
        end
    elseif intent.action == "transfer" then
        local source = intent.source or "character"
        local target = intent.target or "warband"
        if accessibleSources[source] and accessibleSources[target] then
            return source
        end
    end
    return nil
end

-- ============================================================
-- Build and start the event-driven intent queue
-- ============================================================

local function ProcessIntents(accessibleSources)
    if not Wild.db or not Wild.db.intents then
        BlogMsg("ProcessIntents: no db or no intents table.")
        return
    end
    local intents = Wild.db.intents
    if #intents == 0 then
        BlogMsg("ProcessIntents: intents table is empty.")
        return
    end

    -- Don't start a new queue if one is already running
    if activeQueue then
        BlogMsg("ProcessIntents: queue already active, skipping.")
        return
    end

    BlogMsg("ProcessIntents: evaluating " .. #intents .. " intent(s). Accessible sources: "
        .. (accessibleSources.character and "character " or "")
        .. (accessibleSources.warband and "warband " or "")
        .. (accessibleSources.guild and "guild " or ""))

    local queue = {}
    for i, intent in ipairs(intents) do
        local summary = Wild.GetIntentSummary(intent) or ("intent #" .. i)
        if intent.enabled == false then
            BlogMsg("  [" .. i .. "] SKIP (disabled): " .. summary)
        else
            local valid, reason = Wild.ValidateIntent(intent)
            if not valid then
                BlogMsg("  [" .. i .. "] SKIP (invalid: " .. tostring(reason) .. "): " .. summary)
            elseif not Wild.IntentMatchesActor(intent) then
                BlogMsg("  [" .. i .. "] SKIP (actor mismatch): " .. summary)
            else
                local triggerSource = IntentFiresFor(intent, accessibleSources)
                if triggerSource then
                    BlogMsg("  [" .. i .. "] QUEUED (trigger=" .. triggerSource .. "): " .. summary)
                    queue[#queue + 1] = {
                        intent = intent, triggerSource = triggerSource,
                        results = { deposit = {}, withdraw = {}, transfer = {} },
                    }
                else
                    BlogMsg("  [" .. i .. "] SKIP (target '" .. tostring(intent.target) .. "' not accessible): " .. summary)
                end
            end
        end
    end

    if #queue == 0 then
        BlogMsg("ProcessIntents: no intents matched — queue empty.")
        return
    end

    activeQueue = queue
    activeIndex = 1
    activeLen = #queue
    queueFrame:Show()
    ProcessQueueStep()
end

-- ============================================================
-- Bank open handlers
-- ============================================================

local lastBankOpen = 0
local function OnBankOpened()
    local now = GetTime()
    BlogMsg("OnBankOpened called. timeSinceLast=" .. string.format("%.2f", now - lastBankOpen))
    if now - lastBankOpen < 1 then
        BlogMsg("Debounce — skipping (< 1s since last open).")
        return
    end
    lastBankOpen = now
    if not Wild.db then
        BlogMsg("Wild.db is nil — aborting.")
        return
    end
    bankGeneration = bankGeneration + 1
    local generation = bankGeneration

    -- Process warband-specific auto-deposit flags (legacy convenience)
    local warbandCfg = Wild.db.bankWarband
    if warbandCfg and warbandCfg.enabled then
        if warbandCfg.depositWarbound then
            C_Timer.After(0.3, function()
                if bankGeneration ~= generation then return end
                C_Bank.AutoDepositItemsIntoBank(Enum.BankType.Account)
                BlogMsg("Requested auto-deposit of warbound items.")
            end)
        end
        if warbandCfg.depositReagents then
            C_Timer.After(0.5, function()
                if bankGeneration ~= generation then return end
                local reagentCount = 0
                for _, bag in ipairs(GetPlayerBags()) do
                    local numSlots = C_Container.GetContainerNumSlots(bag)
                    for slot = 1, numSlots do
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info and info.itemID then
                            local isCraftingReagent = select(17, C_Item.GetItemInfo(info.itemID))
                            if isCraftingReagent then
                                C_Container.UseContainerItem(bag, slot)
                                reagentCount = reagentCount + 1
                            end
                        end
                    end
                end
                if reagentCount > 0 then
                    BlogMsg("Requested deposit of " .. reagentCount .. " reagent stack(s).")
                end
            end)
        end
    end

    -- Event-driven: pre-load item data, then process intents once all data has arrived
    -- Include player bags so deposit/hold intents have cached GetItemInfo data
    C_Timer.After(Wild.db.advanced.bankStartDelay, function()
        if bankGeneration ~= generation then return end
        PreloadBankItemData({ CHARACTER_BANK_BAGS, ACCOUNT_BANK_TABS, GetPlayerBags() }, function()
            if bankGeneration ~= generation then return end
            BlogMsg("All bank and bag item data loaded — starting intent queue.")
            ProcessIntents({ character = true, warband = true })
        end)
    end)
end

local lastGuildBankOpen = 0
local function OnGuildBankOpened()
    local now = GetTime()
    if now - lastGuildBankOpen < 1 then return end
    lastGuildBankOpen = now
    if not Wild.db then return end
    bankGeneration = bankGeneration + 1
    local generation = bankGeneration

    -- Guild bank items use GetGuildBankItemLink (always available), so no pre-load needed
    C_Timer.After(Wild.db.advanced.guildBankStartDelay, function()
        if bankGeneration ~= generation then return end
        ProcessIntents({ guild = true })
    end)
end

local function OnBankClosed()
    bankGeneration = bankGeneration + 1
    ClearBankPreload()
    BlogMsg("Bank closed — resetting intent queue.")
    local entry = activeQueue and activeQueue[activeIndex]
    local unconfirmed = pendingPass and not CollectPassResults(pendingPass)
    if entry and entry.settlingPass and not CollectPassResults(entry.settlingPass) then unconfirmed = true end
    if unconfirmed then
        Wild.Print("|cffff6600Wild:|r Bank closed before all actions were confirmed; stopped intent processing.")
    end
    FinishQueue()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("BANKFRAME_CLOSED")
frame:RegisterEvent("GUILDBANKFRAME_OPENED")
frame:RegisterEvent("GUILDBANKFRAME_CLOSED")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
frame:SetScript("OnEvent", function(self, event, ...)
    local arg1 = select(1, ...)
    BlogMsg("Event: " .. event .. " args=" .. tostring(arg1))
    if event == "BANKFRAME_OPENED" then
        OnBankOpened()
    elseif event == "BANKFRAME_CLOSED" then
        OnBankClosed()
    elseif event == "GUILDBANKFRAME_OPENED" then
        OnGuildBankOpened()
    elseif event == "GUILDBANKFRAME_CLOSED" then
        OnBankClosed()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        local PIT = Enum.PlayerInteractionType
        BlogMsg("InteractionType=" .. tostring(interactionType) .. " Banker=" .. tostring(PIT.Banker) .. " CharacterBanker=" .. tostring(PIT.CharacterBanker) .. " AccountBanker=" .. tostring(PIT.AccountBanker) .. " GuildBanker=" .. tostring(PIT.GuildBanker))
        if interactionType == PIT.Banker
            or (PIT.CharacterBanker and interactionType == PIT.CharacterBanker)
            or (PIT.AccountBanker and interactionType == PIT.AccountBanker) then
            OnBankOpened()
        elseif interactionType == PIT.GuildBanker then
            OnGuildBankOpened()
        else
            BlogMsg("InteractionType " .. tostring(interactionType) .. " did not match any bank type.")
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local interactionType = ...
        local PIT = Enum.PlayerInteractionType
        if interactionType == PIT.Banker
            or (PIT.CharacterBanker and interactionType == PIT.CharacterBanker)
            or (PIT.AccountBanker and interactionType == PIT.AccountBanker)
            or interactionType == PIT.GuildBanker then
            OnBankClosed()
        end
    end
end)

-- Expose for manual trigger / slash commands
Wild.RunBankIntents = function()
    ProcessIntents({ character = true, warband = true, guild = true })
end
