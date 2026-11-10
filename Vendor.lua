-- Wild: Vendor auto-repair & auto-sell — Intent-based
local ADDON_NAME, Wild = ...

-- ============================================================
-- Auto-sell processing (uses shared condition engine)
-- Event-driven retry-until-done: scan → sell batch → wait for
-- BAG_UPDATE_DELAYED → re-scan. Done when no matches remain.
-- ============================================================

local SELL_INTERVAL = 0.2 -- fallback; overridden by Wild.db.advanced.sellInterval at runtime
local MAX_SELL_PASSES = 50
local CollectSellResults

-- ============================================================
-- Sell frame: OnUpdate-driven item selling (one per tick)
-- After exhausting a batch it fires onBatchDone callback.
-- ============================================================

local sellFrame = CreateFrame("Frame")
sellFrame:Hide()

sellFrame.pending = {}
sellFrame.soldEntries = {}
sellFrame.totalCopper = 0
sellFrame.soldCount = 0
sellFrame.timer = 0
sellFrame.onBatchDone = nil
sellFrame.batch = nil
sellFrame.batchDone = false
sellFrame.newBatch = false
sellFrame.settlingBatches = {}
local skippedSales = {}

local function HasPendingSale(batch, key)
    if not batch then return false end
    for _, entry in ipairs(batch.entries) do
        if (not key or entry.key == key) and entry.confirmed < entry.count then return true end
    end
    return false
end

local function LogSkippedSale(item, reason)
    local key = item.bag .. ":" .. item.slot .. ":" .. (item.link or item.itemID) .. ":" .. reason
    if skippedSales[key] then return end
    skippedSales[key] = true
    Wild.LogUnconfirmedItemActions("Vendor", "sell", { entries = { item } }, {
        source = "bags", target = "vendor", status = "skipped", reason = reason,
    })
end

sellFrame:SetScript("OnUpdate", function(self, elapsed)
    self.timer = self.timer - elapsed
    if self.timer > 0 then return end
    self.timer = (Wild.db and Wild.db.advanced and Wild.db.advanced.sellInterval) or SELL_INTERVAL

    if not MerchantFrame or not MerchantFrame:IsShown() then
        self:Hide()
        if self.onBatchDone then self.onBatchDone(false, true) end
        return
    end

    if GetCursorInfo() then return end
    local item = self.pending[1]
    if item and Wild.IsDestroyItemPending and Wild.IsDestroyItemPending(item.itemID, item.link) then return end
    item = tremove(self.pending, 1)
    if not item then
        -- Requests are complete; bag changes still have to confirm the sales.
        self:Hide()
        if self.onBatchDone then self.onBatchDone(self.batch and #self.batch.entries > 0, false) end
        return
    end

    local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
    local matchesRequest = info and info.itemID == item.itemID and info.hyperlink == item.link
    if matchesRequest and not info.isLocked then
        info.bag = item.bag; info.slot = item.slot
        local price = Wild.GetEffectiveSellPrice(info.itemID, info)
        if price and price > 0 then
            local key = info.hyperlink or info.itemID
            if self.newBatch or not self.batch.requestedKeys[key] then
                CollectSellResults()
                if self.newBatch then
                    if self.batch and not self.batch.complete then
                        self.settlingBatches[#self.settlingBatches + 1] = self.batch
                    end
                    self.batch = Wild.CreateItemActionBatch(Wild.CapturePlayerItemCounts, nil, self.observedCounts)
                    self.batch.requestedKeys = {}
                    self.newBatch = false
                end
                -- A retry owns future changes for this key, not other pending items.
                for _, batch in ipairs(self.settlingBatches) do
                    for _, entry in ipairs(batch.entries) do
                        if entry.key == key then entry.count = entry.confirmed end
                    end
                end
                local counts = self.observedCounts or self.batch.sourceBefore
                self.batch.sourceBefore[key] = counts[key] or 0
                self.batch.requestedKeys[key] = true
            end
            self.batch.observedBagUpdate = false
            Wild.RecordItemAction(self.batch, info, info.stackCount or 1, price)
            C_Container.UseContainerItem(item.bag, item.slot)
        else
            LogSkippedSale(item, "sell_price_unavailable")
        end
    else
        LogSkippedSale(item, matchesRequest and info.isLocked and "item_locked" or "slot_changed")
    end
end)

-- ============================================================
-- Preload all bag item data so GetItemInfo returns valid info
-- ============================================================

local function PreloadBagItems(onReady)
    local remaining = 0
    local fired = false
    local function CheckDone()
        if remaining == 0 and not fired then
            fired = true
            onReady()
        end
    end
    local bags = Wild.GetPlayerBags and Wild.GetPlayerBags() or { BACKPACK_CONTAINER }
    if not Wild.GetPlayerBags then
        for i = 1, NUM_BAG_SLOTS do bags[#bags + 1] = i end
        if Enum.BagIndex.ReagentBag then bags[#bags + 1] = Enum.BagIndex.ReagentBag end
    end
    for _, bag in ipairs(bags) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local item = Item:CreateFromItemID(info.itemID)
                if not item:IsItemDataCached() then
                    remaining = remaining + 1
                    item:ContinueOnItemLoad(function()
                        remaining = remaining - 1
                        CheckDone()
                    end)
                end
            end
        end
    end
    C_Timer.After(3, function()
        if not fired then fired = true; onReady() end
    end)
    CheckDone()
end

-- ============================================================
-- Scan bags and build a pending list for ONE sell pass
-- Returns the pending array (empty if nothing to sell)
-- ============================================================

local function BuildSellBatch()
    local charCtx = Wild.BuildCharContext()
    local pending = {}
    local destroyPending = {}

    -- Build per-group sell entries with individual quotas
    local groupEntries = {}
    for _, intent in ipairs(Wild.db.intents) do
        if intent.enabled ~= false and intent.action == "sell" and Wild.ValidateIntent(intent) and Wild.IntentMatchesActor(intent) then
            for _, group in ipairs(Wild.GetItemGroups(intent)) do
                local subIntent = Wild.SubIntentForGroup(intent, group)
                local count = group.count or 0
                local entry = {
                    subIntent = subIntent,
                    destroyUnsellable = intent.destroyUnsellable,
                }
                if count > 0 then
                    local total = Wild.CountMatchingInBags(subIntent, charCtx)
                    entry.toSell = math.max(0, total - count)
                    entry.sold = 0
                end
                groupEntries[#groupEntries + 1] = entry
            end
        end
    end

    local bags = Wild.GetPlayerBags and Wild.GetPlayerBags() or { BACKPACK_CONTAINER }
    if not Wild.GetPlayerBags then
        for i = 1, NUM_BAG_SLOTS do bags[#bags + 1] = i end
        if Enum.BagIndex.ReagentBag then bags[#bags + 1] = Enum.BagIndex.ReagentBag end
    end
    for _, bag in ipairs(bags) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                info.bag = bag; info.slot = slot
                for _, ge in ipairs(groupEntries) do
                    if Wild.IntentMatchesItem(ge.subIntent, info.itemID, info, charCtx) then
                        local shouldSell = true
                        if ge.toSell then
                            if ge.sold >= ge.toSell then
                                shouldSell = false
                            else
                                ge.sold = ge.sold + (info.stackCount or 1)
                            end
                        end
                        if shouldSell then
                            local sellPrice = Wild.GetEffectiveSellPrice(info.itemID, info)
                            if sellPrice and sellPrice > 0 then
                                pending[#pending + 1] = {
                                    bag = bag,
                                    slot = slot,
                                    itemID = info.itemID,
                                    link = info.hyperlink,
                                    count = info.stackCount or 1,
                                    copper = sellPrice * (info.stackCount or 1),
                                }
                            elseif ge.destroyUnsellable then
                                destroyPending[#destroyPending + 1] = {
                                    bag = bag,
                                    slot = slot,
                                    link = info.hyperlink,
                                    count = info.stackCount or 1,
                                    itemID = info.itemID,
                                }
                            end
                        end
                        break
                    end
                end
            end
        end
    end

    return pending, destroyPending
end

-- ============================================================
-- Event-driven sell loop: scan → sell batch → wait → re-scan
-- ============================================================

local sellLoopActive = false
local sellPassNum = 0
local sellGeneration = 0
local sellConfirmationTimer
local RunSellPass
local CONFIRMATION_TIMEOUT = 5

local sellEventFrame = CreateFrame("Frame")
sellEventFrame:Hide()

function Wild.IsVendorItemPending(itemID, link)
    if not sellLoopActive then return false end
    local key = link or itemID
    if HasPendingSale(sellFrame.batch, key) then return true end
    for _, batch in ipairs(sellFrame.settlingBatches) do
        if HasPendingSale(batch, key) then return true end
    end
    return false
end

local function DestroyUnsellableItems(items)
    Wild.QueueDestroyItems(items)
end

local function CollectSellBatch(batch, counts)
    local entries, complete = Wild.ConfirmItemActionBatch(batch, counts)
    batch.complete = complete
    Wild.MergeItemActionEntries(sellFrame.soldEntries, entries)
    for _, entry in ipairs(entries) do
        sellFrame.soldCount = sellFrame.soldCount + entry.count
        sellFrame.totalCopper = sellFrame.totalCopper + entry.copper
        Wild.LogAction("Vendor", "sell", entry)
    end
    return complete
end

CollectSellResults = function()
    if not sellFrame.batch and #sellFrame.settlingBatches == 0 then return true end
    if GetCursorInfo() and Wild.IsVendorItemPending() then return false end
    local counts = Wild.CapturePlayerItemCounts()
    sellFrame.observedCounts = counts
    local complete = true
    for index = #sellFrame.settlingBatches, 1, -1 do
        if CollectSellBatch(sellFrame.settlingBatches[index], counts) then
            tremove(sellFrame.settlingBatches, index)
        else
            complete = false
        end
    end
    if sellFrame.batch and not CollectSellBatch(sellFrame.batch, counts) then complete = false end
    return complete
end

local function HasSellProgress()
    if not sellFrame.batch then return false end
    for _, count in pairs(sellFrame.batch.confirmed) do
        if count > 0 then return true end
    end
    return false
end

local function FinishSellLoop(warning)
    local complete = CollectSellResults()
    if not complete then
        warning = warning or "Some vendor sales were not confirmed; stopped selling."
        local context = { source = "bags", target = "vendor", reason = "sale_not_confirmed" }
        for _, batch in ipairs(sellFrame.settlingBatches) do
            Wild.LogUnconfirmedItemActions("Vendor", "sell", batch, context)
        end
        if sellFrame.batch then Wild.LogUnconfirmedItemActions("Vendor", "sell", sellFrame.batch, context) end
    end
    sellLoopActive = false
    sellGeneration = sellGeneration + 1
    sellEventFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
    sellEventFrame:SetScript("OnEvent", nil)
    if sellConfirmationTimer then sellConfirmationTimer:Cancel(); sellConfirmationTimer = nil end
    sellFrame:Hide()
    sellFrame.pending = {}
    sellFrame.batch = nil
    sellFrame.newBatch = false
    sellFrame.settlingBatches = {}
    sellFrame.observedCounts = nil
    sellFrame.onBatchDone = nil
    if warning then
        Wild.Warn("Vendor", warning, { action = "sell", status = "unconfirmed", reason = "sale_not_confirmed" })
    end
    if sellFrame.soldCount > 0 then
        for _, entry in ipairs(sellFrame.soldEntries) do
            Wild.Print("|cff00ccffWild:|r " .. Wild.FormatActionResult("sell", entry))
        end
        Wild.Print(string.format("|cff00ccffWild:|r Auto-sold %d item(s) for %s.", sellFrame.soldCount, Wild.FormatGold(sellFrame.totalCopper)))
    end
end

local function ScheduleSellPass()
    local batch = sellFrame.batch
    if batch and batch.nextPassScheduled then return end
    if batch then batch.nextPassScheduled = true end
    if sellConfirmationTimer then sellConfirmationTimer:Cancel(); sellConfirmationTimer = nil end
    local generation = sellGeneration
    C_Timer.After(Wild.db.advanced.passDelay, function()
        if sellLoopActive and sellGeneration == generation then
            CollectSellResults()
            RunSellPass()
        end
    end)
end

RunSellPass = function()
    if not sellLoopActive then return end
    if not MerchantFrame or not MerchantFrame:IsShown() then
        FinishSellLoop()
        return
    end
    sellPassNum = sellPassNum + 1
    if sellPassNum > MAX_SELL_PASSES then
        FinishSellLoop("Sell safety cap reached (" .. MAX_SELL_PASSES .. " passes).")
        return
    end
    local pending, destroyPending = BuildSellBatch()
    if #pending == 0 then
        if #destroyPending > 0 then DestroyUnsellableItems(destroyPending) end
        FinishSellLoop()
        return
    end

    sellFrame.newBatch = true
    if sellFrame.batch then sellFrame.batch.nextPassScheduled = nil end
    sellFrame.batchDone = false
    sellFrame.pending = pending
    sellFrame.timer = 0
    sellFrame.onBatchDone = function(requestedAny, merchantClosed)
        sellFrame.batchDone = true
        if merchantClosed then
            local complete = CollectSellResults()
            FinishSellLoop(not complete and "Some vendor sales were not confirmed before the merchant closed." or nil)
        elseif not requestedAny then
            ScheduleSellPass()
        elseif sellFrame.batch.observedBagUpdate and (CollectSellResults() or HasSellProgress()) then
            ScheduleSellPass()
        else
            local batch = sellFrame.batch
            sellConfirmationTimer = C_Timer.NewTimer(CONFIRMATION_TIMEOUT, function()
                if not sellLoopActive or sellFrame.batch ~= batch then return end
                if CollectSellResults() or HasSellProgress() then
                    ScheduleSellPass()
                else
                    FinishSellLoop("Some vendor sales were not confirmed; stopped selling.")
                end
            end)
        end
    end
    sellFrame:Show()
end

local function ProcessSellIntents()
    if not Wild.db or not Wild.db.intents or sellLoopActive then return end
    sellLoopActive = true
    sellGeneration = sellGeneration + 1
    local generation = sellGeneration
    sellPassNum = 0
    wipe(skippedSales)
    wipe(sellFrame.soldEntries)
    sellFrame.totalCopper = 0
    sellFrame.soldCount = 0
    PreloadBagItems(function()
        if not sellLoopActive or sellGeneration ~= generation then return end
        if not MerchantFrame or not MerchantFrame:IsShown() then
            FinishSellLoop()
            return
        end
        -- Listen while selling, since updates can arrive before the final tick.
        sellEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        sellEventFrame:SetScript("OnEvent", function()
            if sellLoopActive and sellFrame.batch then
                sellFrame.batch.observedBagUpdate = true
                local complete = CollectSellResults()
                if sellFrame.batchDone and (complete or HasSellProgress()) then ScheduleSellPass() end
            end
        end)
        RunSellPass()
    end)
end

-- ============================================================
-- Auto-repair processing
-- ============================================================

local function ProcessAutoRepair()
    if not Wild.db or not Wild.db.vendorAutoRepair then return end
    if not CanMerchantRepair() then return end

    local repairCost, canRepair = GetRepairAllCost()
    if not canRepair or repairCost == 0 then return end

    local useGuild = Wild.db.vendorRepairUseGuild
    local repaired = false
    local source = "personal"

    if useGuild and IsInGuild() then
        local guildCanRepair = CanGuildBankRepair()
        if guildCanRepair then
            RepairAllItems(true)
            repaired = true
            source = "guild"
        end
    end

    if not repaired then
        if GetMoney() >= repairCost then
            RepairAllItems(false)
            repaired = true
            source = "personal"
        else
            print("|cffff6600Wild:|r Not enough gold to repair.")
            return
        end
    end

    if repaired then
        print(string.format(
            "|cff00ccffWild:|r Repaired all items for %s (%s funds).",
            Wild.FormatGold(repairCost), source
        ))
    end
end

-- ============================================================
-- Event handling
-- ============================================================

local lastMerchantOpen = 0
local function OnMerchantOpened()
    local now = GetTime()
    if now - lastMerchantOpen < 1 then return end
    lastMerchantOpen = now
    ProcessAutoRepair()
    C_Timer.After(Wild.db.advanced.sellStartDelay, ProcessSellIntents)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "UI_ERROR_MESSAGE" then
        if sellLoopActive then Wild.LogClientError("Vendor", ...) end
    elseif event == "MERCHANT_SHOW" then
        OnMerchantOpened()
    elseif event == "MERCHANT_CLOSED" then
        if sellLoopActive then
            local complete = CollectSellResults()
            FinishSellLoop(not complete and "Some vendor sales were not confirmed before the merchant closed." or nil)
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        if interactionType == Enum.PlayerInteractionType.Merchant then
            OnMerchantOpened()
        end
    end
end)
