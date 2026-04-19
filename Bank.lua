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
    if not Wild.db or not Wild.db.advanced or not Wild.db.advanced.debug then return end
    local formatted = "|cff00ccffWild [Bank Debug]:|r " .. msg
    print(formatted)
    WildDB.bankDebug = WildDB.bankDebug or {}
    table.insert(WildDB.bankDebug, string.format("[%.3f] %s", GetTime(), msg))
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
-- Deposit from bags (shared across all bank types)
-- ============================================================

local TARGET_BANK_TYPE = {
    warband   = Enum.BankType.Account,
}
-- Character bank deposit: pass nil bankType (UseContainerItem defaults to character bank)
-- Warband bank deposit: pass Enum.BankType.Account explicitly

local function DepositFromBags(intent, charCtx, maxCount, bankType)
    local deposited = 0
    local entries = {}
    for _, bag in ipairs(GetPlayerBags()) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            if maxCount > 0 and deposited >= maxCount then return deposited, entries end
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then info.bag = bag; info.slot = slot end
            if info and info.itemID and Wild.IntentMatchesItem(intent, info.itemID, info, charCtx) then
                local stackCount = info.stackCount or 1
                local remaining = maxCount - deposited
                local moveCount = stackCount
                if remaining < stackCount then
                    moveCount = remaining
                    C_Container.SplitContainerItem(bag, slot, moveCount)
                    if bankType then
                        C_Container.UseContainerItem(bag, slot, nil, bankType)
                    else
                        C_Container.UseContainerItem(bag, slot)
                    end
                else
                    if bankType then
                        C_Container.UseContainerItem(bag, slot, nil, bankType)
                    else
                        C_Container.UseContainerItem(bag, slot)
                    end
                end
                deposited = deposited + moveCount
                entries[#entries + 1] = { link = info.hyperlink, count = moveCount }
            end
        end
    end
    return deposited, entries
end

-- ============================================================
-- Withdraw from Character Bank
-- ============================================================

local function WithdrawFromCharacterBank(intent, charCtx, neededCount)
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
                if info and info.itemID and Wild.IntentMatchesItem(intent, info.itemID, info, charCtx) then
                    local stackCount = info.stackCount or 1
                    local remaining = neededCount - withdrawn
                    local moveCount = stackCount
                    if remaining < stackCount then
                        moveCount = remaining
                        C_Container.SplitContainerItem(bag, slot, moveCount)
                        C_Container.UseContainerItem(bag, slot)
                    else
                        C_Container.UseContainerItem(bag, slot)
                    end
                    withdrawn = withdrawn + moveCount
                    entries[#entries + 1] = { link = info.hyperlink, count = moveCount }
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

local function WithdrawFromWarbandBank(intent, charCtx, neededCount)
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
                if info and info.itemID and Wild.IntentMatchesItem(intent, info.itemID, info, charCtx) then
                    local stackCount = info.stackCount or 1
                    local remaining = neededCount - withdrawn
                    local moveCount = stackCount
                    if remaining < stackCount then
                        moveCount = remaining
                        C_Container.SplitContainerItem(bankBag, slot, moveCount)
                        C_Container.UseContainerItem(bankBag, slot)
                    else
                        C_Container.UseContainerItem(bankBag, slot)
                    end
                    withdrawn = withdrawn + moveCount
                    entries[#entries + 1] = { link = info.hyperlink, count = moveCount }
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

local function WithdrawFromGuildBank(intent, charCtx, neededCount)
    local withdrawn = 0
    local entries = {}
    local numTabs = GetNumGuildBankTabs()
    for tab = 1, numTabs do
        local _, _, isViewable = GetGuildBankTabInfo(tab)
        if isViewable then
            for slot = 1, GUILD_BANK_SLOTS_PER_TAB do
                if neededCount > 0 and withdrawn >= neededCount then return withdrawn, entries end
                local _, itemCount = GetGuildBankItemInfo(tab, slot)
                if itemCount and itemCount > 0 then
                    local link = GetGuildBankItemLink(tab, slot)
                    if link then
                        local itemID = tonumber(link:match("item:(%d+)"))
                        if itemID and Wild.IntentMatchesItem(intent, itemID, { quality = select(3, GetItemInfo(itemID)), hyperlink = link }, charCtx) then
                            AutoStoreGuildBankItem(tab, slot)
                            withdrawn = withdrawn + itemCount
                            entries[#entries + 1] = { link = link, count = itemCount }
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
                        if itemID and Wild.IntentMatchesItem(intent, itemID, { quality = select(3, GetItemInfo(itemID)), hyperlink = link }, charCtx) then
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

local function PreloadBankItemData(bankBagSets, onComplete)
    local pending = {}
    local pendingCount = 0

    for _, bags in ipairs(bankBagSets) do
        for _, bag in ipairs(bags) do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            if numSlots and numSlots > 0 then
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.itemID and not GetItemInfo(info.itemID) then
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

    -- Safety timeout: if items never arrive, proceed anyway after 3s
    local safetyTimer = C_Timer.NewTimer(3.0, function()
        if pendingCount > 0 then
            BlogMsg("PreloadBankItemData: safety timeout with " .. pendingCount .. " item(s) still pending.")
            pendingCount = 0
            preloadFrame:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
            preloadFrame:SetScript("OnEvent", nil)
            onComplete()
        end
    end)

    preloadFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    preloadFrame:SetScript("OnEvent", function(self, event, itemID, success)
        if pending[itemID] then
            pending[itemID] = nil
            pendingCount = pendingCount - 1
            BlogMsg("PreloadBankItemData: loaded itemID " .. itemID .. " (" .. pendingCount .. " remaining)")
            if pendingCount <= 0 then
                self:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
                self:SetScript("OnEvent", nil)
                safetyTimer:Cancel()
                onComplete()
            end
        end
    end)
end

-- ============================================================
-- Event-driven intent queue processor
-- Executes intents one at a time, waiting for BAG_UPDATE_DELAYED
-- between each to let item movements settle.
-- ============================================================

local queueFrame = CreateFrame("Frame")
queueFrame:Hide()

-- Forward declarations
local ProcessQueueStep

-- Active queue state (only one queue runs at a time)
local activeQueue = nil    -- array of { intent, triggerSource }
local activeIndex = 0
local activeLen = 0

local function FinishQueue()
    queueFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
    queueFrame:SetScript("OnEvent", nil)
    queueFrame:Hide()
    activeQueue = nil
    activeIndex = 0
    activeLen = 0
end

-- ============================================================
-- Execute a single intent pass (returns movedItems: true if bags changed)
-- A "pass" moves ONE batch of matching items. The queue will
-- re-run the same intent until a pass returns movedItems=false.
-- ============================================================

local function ExecuteIntentPass(intent, triggerSource, charCtx, queuePos, queueLen, passNum)
    local summary = Wild.GetIntentSummary(intent)
    local prefix = string.format("|cff00ccffWild:|r [%d/%d] ", queuePos, queueLen)
    local movedItems = false

    if intent.action == "hold" then
        local reservoir = intent.target or "warband"

        -- Phase 1: Gold sync (atomic, one pass) from gold-kind groups
        local goldTarget = Wild.GetIntentGoldTarget(intent)
        if goldTarget > 0 and reservoir ~= "character" then
            local currentCopper = GetMoney()
            local keepCopper = goldTarget * Wild.COPPER_PER_GOLD

            if currentCopper > keepCopper then
                local depositCopper = currentCopper - keepCopper
                if reservoir == "warband" then
                    C_Bank.DepositMoney(Enum.BankType.Account, depositCopper)
                elseif reservoir == "guild" then
                    DepositGuildBankMoney(depositCopper)
                end
                print(prefix .. "Deposited " .. Wild.FormatGold(depositCopper) .. ".")
            elseif currentCopper < keepCopper then
                local withdrawCopper = keepCopper - currentCopper
                if reservoir == "warband" and triggerSource == "warband" then
                    C_Bank.WithdrawMoney(Enum.BankType.Account, withdrawCopper)
                    print(prefix .. "Withdrew " .. Wild.FormatGold(withdrawCopper) .. ".")
                elseif reservoir == "guild" and triggerSource == "guild" then
                    WithdrawGuildBankMoney(withdrawCopper)
                    print(prefix .. "Withdrew " .. Wild.FormatGold(withdrawCopper) .. ".")
                else
                    BlogMsg("Gold deficit but trigger source (" .. tostring(triggerSource) .. ") != reservoir (" .. reservoir .. ") — skipping withdraw.")
                end
            else
                BlogMsg("Gold already at target.")
            end
        end

        -- Phase 2: Item sync per include group (bidirectional, retry-until-done)
        for _, group in ipairs(Wild.GetItemGroups(intent)) do
            local keep = group.count or 0
            if keep > 0 then
                local subIntent = Wild.SubIntentForGroup(intent, group)
                local current = Wild.CountMatchingInBags(subIntent, charCtx)
                if current < keep then
                    local deficit = keep - current
                    local withdrawFunc = WITHDRAW_FUNCS[reservoir]
                    if withdrawFunc then
                        local count, entries = withdrawFunc(subIntent, charCtx, deficit)
                        if count > 0 then
                            for _, entry in ipairs(entries) do
                                print(string.format("|cff00ccffWild:|r  \226\134\147 %s \195\151%d", entry.link or "?", entry.count))
                            end
                            if passNum == 1 then
                                print(prefix .. string.format("Withdrew %d item(s) to reach %d on character. [%s]", count, keep, summary))
                            end
                            movedItems = true
                        else
                            if passNum == 1 then
                                print(prefix .. "|cff888888No matching items in bank to withdraw.|r [" .. summary .. "]")
                            end
                        end
                    else
                        print(prefix .. "|cffff6600No withdraw function for target: " .. tostring(reservoir) .. "|r")
                    end
                elseif current > keep then
                    local excess = current - keep
                    local bankType = TARGET_BANK_TYPE[reservoir]
                    local count, entries = DepositFromBags(subIntent, charCtx, excess, bankType)
                    if count > 0 then
                        for _, entry in ipairs(entries) do
                            print(string.format("|cff00ccffWild:|r  \226\134\145 %s \195\151%d", entry.link or "?", entry.count))
                        end
                        if passNum == 1 then
                            print(prefix .. string.format("Deposited %d item(s) to reach %d on character. [%s]", count, keep, summary))
                        end
                        movedItems = true
                    else
                        if passNum == 1 then
                            print(prefix .. "|cff888888No matching items in bags to deposit.|r [" .. summary .. "]")
                        end
                    end
                else
                    if passNum == 1 then
                        BlogMsg("Items already at target (" .. current .. "/" .. keep .. ").")
                    end
                end
            end
        end

    elseif intent.action == "deposit" then
        local bankType = TARGET_BANK_TYPE[intent.target]
        for _, group in ipairs(Wild.GetItemGroups(intent)) do
            local keep = group.count or 0
            local subIntent = Wild.SubIntentForGroup(intent, group)
            local maxDeposit = 0
            if keep > 0 then
                local current = Wild.CountMatchingInBags(subIntent, charCtx)
                local excess = current - keep
                if excess <= 0 then
                    maxDeposit = -1
                else
                    maxDeposit = excess
                end
            end
            if maxDeposit ~= -1 then
                local count, entries = DepositFromBags(subIntent, charCtx, maxDeposit, bankType)
                if count > 0 then
                    for _, entry in ipairs(entries) do
                        print(string.format("|cff00ccffWild:|r  \226\134\145 %s \195\151%d", entry.link or "?", entry.count))
                    end
                    if passNum == 1 then
                        print(prefix .. string.format("Deposited %d item(s). [%s]", count, summary))
                    end
                    movedItems = true
                else
                    if passNum == 1 then
                        print(prefix .. "|cff888888No matching items in bags.|r [" .. summary .. "]")
                    end
                end
            else
                if passNum == 1 then
                    print(prefix .. "|cff888888Keeping all (have " .. Wild.CountMatchingInBags(subIntent, charCtx) .. ", keep " .. keep .. ").|r [" .. summary .. "]")
                end
            end
        end

    elseif intent.action == "withdraw" then
        local bankTarget = intent.target or triggerSource
        local withdrawFunc = WITHDRAW_FUNCS[bankTarget]
        if withdrawFunc then
            for _, group in ipairs(Wild.GetItemGroups(intent)) do
                local keep = group.count or 0
                local subIntent = Wild.SubIntentForGroup(intent, group)
                if keep == 0 then
                    local count, entries = withdrawFunc(subIntent, charCtx, 0)
                    if count > 0 then
                        for _, entry in ipairs(entries) do
                            print(string.format("|cff00ccffWild:|r  \226\134\147 %s \195\151%d", entry.link or "?", entry.count))
                        end
                        if passNum == 1 then
                            print(prefix .. string.format("Withdrew %d item(s). [%s]", count, summary))
                        end
                        movedItems = true
                    else
                        if passNum == 1 then
                            print(prefix .. "|cff888888No matching items in bank.|r [" .. summary .. "]")
                        end
                    end
                else
                    local countFunc = BANK_COUNT_FUNCS[bankTarget]
                    local bankCount = countFunc and countFunc(subIntent, charCtx) or 0
                    local excess = bankCount - keep
                    if excess > 0 then
                        local count, entries = withdrawFunc(subIntent, charCtx, excess)
                        if count > 0 then
                            for _, entry in ipairs(entries) do
                                print(string.format("|cff00ccffWild:|r  \226\134\147 %s \195\151%d", entry.link or "?", entry.count))
                            end
                            if passNum == 1 then
                                print(prefix .. string.format("Withdrew %d item(s). [%s]", count, summary))
                            end
                            movedItems = true
                        else
                            if passNum == 1 then
                                print(prefix .. "|cff888888No matching items in bank.|r [" .. summary .. "]")
                            end
                        end
                    else
                        if passNum == 1 then
                            print(prefix .. "|cff888888Keeping all (" .. bankCount .. " in bank, keep " .. keep .. ").|r [" .. summary .. "]")
                        end
                    end
                end
            end
        else
            print(prefix .. "|cffff6600No withdraw function for target: " .. tostring(bankTarget) .. "|r")
        end

    elseif intent.action == "transfer" then
        local source = intent.source or "character"
        local target = intent.target or "warband"
        local withdrawFunc = WITHDRAW_FUNCS[source]
        local bankType = TARGET_BANK_TYPE[target]
        if withdrawFunc then
            for _, group in ipairs(Wild.GetItemGroups(intent)) do
                local keep = group.count or 0
                local subIntent = Wild.SubIntentForGroup(intent, group)
                local neededCount = 0
                if keep > 0 then
                    local countFunc = BANK_COUNT_FUNCS[source]
                    local bankCount = countFunc and countFunc(subIntent, charCtx) or 0
                    local excess = bankCount - keep
                    if excess <= 0 then
                        neededCount = -1
                    else
                        neededCount = excess
                    end
                end
                if neededCount ~= -1 then
                    local wCount, wEntries = withdrawFunc(subIntent, charCtx, neededCount)
                    if wCount > 0 then
                        for _, entry in ipairs(wEntries) do
                            print(string.format("|cff00ccffWild:|r  \226\134\147 %s \195\151%d", entry.link or "?", entry.count))
                        end
                        movedItems = true
                        intent._transferPending = { count = wCount, bankType = bankType, summary = summary, prefix = prefix }
                    else
                        if passNum == 1 then
                            print(prefix .. "|cff888888No matching items in source bank.|r [" .. summary .. "]")
                        end
                    end
                else
                    if passNum == 1 then
                        print(prefix .. "|cff888888Keeping all in source bank.|r [" .. summary .. "]")
                    end
                end
            end
        else
            print(prefix .. "|cffff6600No withdraw function for source: " .. tostring(source) .. "|r")
        end
    end

    return movedItems
end

-- ============================================================
-- Transfer phase 2: deposit items that were just withdrawn
-- ============================================================

local function ExecuteTransferDeposit(intent, charCtx)
    local tp = intent._transferPending
    if not tp then return false end
    intent._transferPending = nil

    local dCount, dEntries = DepositFromBags(intent, charCtx, tp.count, tp.bankType)
    if dCount > 0 then
        for _, entry in ipairs(dEntries) do
            print(string.format("|cff00ccffWild:|r  \226\134\145 %s \195\151%d", entry.link or "?", entry.count))
        end
    end
    print(tp.prefix .. string.format("Transferred %d item(s). [%s]", tp.count, tp.summary))
    return dCount > 0
end

-- ============================================================
-- Queue step: execute current intent in a retry loop.
-- Each pass scans the source/target containers and acts on
-- ONE batch of matching items. After BAG_UPDATE_DELAYED the
-- same intent runs again. Only when a pass finds ZERO matches
-- (movedItems == false) does it advance to the next intent.
-- A safety cap prevents infinite loops.
-- ============================================================

local MAX_PASSES_PER_INTENT = 50

ProcessQueueStep = function()
    if not activeQueue or activeIndex > activeLen then
        -- Queue is done: ensure no further event handlers are active
        FinishQueue()
        -- Lock out further processing until a new bank open event
        queueFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        queueFrame:SetScript("OnEvent", nil)
        return
    end

    local entry = activeQueue[activeIndex]
    entry.passNum = (entry.passNum or 0) + 1
    local passNum = entry.passNum
    local charCtx = Wild.BuildCharContext()
    local movedItems = ExecuteIntentPass(entry.intent, entry.triggerSource, charCtx, activeIndex, activeLen, passNum)

    -- Safety cap: prevent infinite retry
    if passNum >= MAX_PASSES_PER_INTENT then
        BlogMsg("Intent " .. activeIndex .. " hit safety cap (" .. MAX_PASSES_PER_INTENT .. " passes) — advancing")
        activeIndex = activeIndex + 1
        ProcessQueueStep()
        return
    end

    if entry.intent._transferPending then
        -- Transfer phase 1 done (withdraw) — wait for bags, then deposit
        BlogMsg("Intent " .. activeIndex .. " transfer phase 1 (pass " .. passNum .. ") — waiting for BAG_UPDATE_DELAYED")
        queueFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        queueFrame:SetScript("OnEvent", function(self, event)
            self:UnregisterEvent("BAG_UPDATE_DELAYED")
            self:SetScript("OnEvent", nil)
            BlogMsg("Intent " .. activeIndex .. " transfer phase 2 — depositing")
            local freshCtx = Wild.BuildCharContext()
            local depositMoved = ExecuteTransferDeposit(entry.intent, freshCtx)
            if depositMoved then
                -- Deposit settled — retry the same intent (more items to transfer?)
                self:RegisterEvent("BAG_UPDATE_DELAYED")
                self:SetScript("OnEvent", function(self2, event2)
                    self2:UnregisterEvent("BAG_UPDATE_DELAYED")
                    self2:SetScript("OnEvent", nil)
                    ProcessQueueStep()  -- retry same intent
                end)
            else
                -- Deposit had nothing — retry same intent to check if source has more
                ProcessQueueStep()
            end
        end)
    elseif movedItems then
        -- Items moved — wait for BAG_UPDATE_DELAYED, then retry same intent
        BlogMsg("Intent " .. activeIndex .. " moved items (pass " .. passNum .. ") — waiting for BAG_UPDATE_DELAYED then retrying")
        queueFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        queueFrame:SetScript("OnEvent", function(self, event)
            self:UnregisterEvent("BAG_UPDATE_DELAYED")
            self:SetScript("OnEvent", nil)
            BlogMsg("Intent " .. activeIndex .. " bags settled (pass " .. passNum .. ") — retrying")
            ProcessQueueStep()  -- retry same intent
        end)
    else
        -- No items moved: this intent is done — advance
        if passNum > 1 then
            BlogMsg("Intent " .. activeIndex .. " completed after " .. passNum .. " passes")
        else
            BlogMsg("Intent " .. activeIndex .. " no matches — advancing")
        end
        activeIndex = activeIndex + 1
        -- If this was the last intent, ensure we unregister event handlers
        if activeIndex > activeLen then
            FinishQueue()
            queueFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
            queueFrame:SetScript("OnEvent", nil)
            return
        end
        ProcessQueueStep()
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
    if not Wild.db or not Wild.db.intents then return end
    local intents = Wild.db.intents
    if #intents == 0 then return end

    -- Don't start a new queue if one is already running
    if activeQueue then
        BlogMsg("ProcessIntents: queue already active, skipping.")
        return
    end

    local queue = {}
    for _, intent in ipairs(intents) do
        if intent.enabled ~= false and Wild.ValidateIntent(intent) and Wild.IntentMatchesActor(intent) then
            local triggerSource = IntentFiresFor(intent, accessibleSources)
            if triggerSource then
                queue[#queue + 1] = { intent = intent, triggerSource = triggerSource }
            end
        end
    end

    if #queue == 0 then return end

    print(string.format("|cff00ccffWild:|r Processing %d intent(s)...", #queue))

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

    -- Process warband-specific auto-deposit flags (legacy convenience)
    local warbandCfg = Wild.db.bankWarband
    if warbandCfg and warbandCfg.enabled then
        if warbandCfg.depositWarbound then
            C_Timer.After(0.3, function()
                C_Bank.AutoDepositItemsIntoBank(Enum.BankType.Account)
                BlogMsg("Auto-deposited warbound items.")
            end)
        end
        if warbandCfg.depositReagents then
            C_Timer.After(0.5, function()
                local reagentCount = 0
                for _, bag in ipairs(GetPlayerBags()) do
                    local numSlots = C_Container.GetContainerNumSlots(bag)
                    for slot = 1, numSlots do
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info and info.itemID then
                            local isCraftingReagent = select(17, GetItemInfo(info.itemID))
                            if isCraftingReagent then
                                C_Container.UseContainerItem(bag, slot)
                                reagentCount = reagentCount + 1
                            end
                        end
                    end
                end
                if reagentCount > 0 then
                    print(string.format("|cff00ccffWild:|r [Warband] Depositing %d reagent(s).", reagentCount))
                end
            end)
        end
    end

    -- Event-driven: pre-load item data, then process intents once all data has arrived
    C_Timer.After(0.8, function()
        PreloadBankItemData({ CHARACTER_BANK_BAGS, ACCOUNT_BANK_TABS }, function()
            BlogMsg("All bank item data loaded — starting intent queue.")
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

    -- Guild bank items use GetGuildBankItemLink (always available), so no pre-load needed
    C_Timer.After(0.5, function()
        ProcessIntents({ guild = true })
    end)
end

local function OnBankClosed()
    BlogMsg("Bank closed — resetting intent queue.")
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
