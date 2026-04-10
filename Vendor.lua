-- Wild: Vendor auto-repair & auto-sell — Intent-based
local ADDON_NAME, Wild = ...

-- ============================================================
-- Auto-sell processing (uses shared condition engine)
-- Event-driven retry-until-done: scan → sell batch → wait for
-- BAG_UPDATE_DELAYED → re-scan. Done when no matches remain.
-- ============================================================

local SELL_INTERVAL = 0.2
local MAX_SELL_PASSES = 50

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

sellFrame:SetScript("OnUpdate", function(self, elapsed)
    self.timer = self.timer - elapsed
    if self.timer > 0 then return end
    self.timer = SELL_INTERVAL

    if not MerchantFrame or not MerchantFrame:IsShown() then
        self:Hide()
        if self.onBatchDone then self.onBatchDone(false) end
        return
    end

    local item = tremove(self.pending, 1)
    if not item then
        -- Batch done — notify callback with whether anything was sold
        self:Hide()
        local soldThisBatch = self.soldCount > 0
        if self.onBatchDone then self.onBatchDone(soldThisBatch) end
        return
    end

    local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
    if info and info.itemID then
        C_Container.UseContainerItem(item.bag, item.slot)
        self.totalCopper = self.totalCopper + item.copper
        self.soldCount = self.soldCount + item.count
        self.soldEntries[#self.soldEntries + 1] = {
            link = item.link,
            count = item.count,
            copper = item.copper,
        }
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

    -- For intents with keep > 0, pre-count matching items
    local intentCounts = {}
    for idx, intent in ipairs(Wild.db.intents) do
        if intent.enabled ~= false and intent.action == "sell" and Wild.ValidateIntent(intent) and intent.keep and intent.keep > 0 and Wild.IntentMatchesActor(intent) then
            local total = Wild.CountMatchingInBags(intent, charCtx)
            intentCounts[idx] = { total = total, toSell = math.max(0, total - intent.keep), sold = 0 }
        end
    end

    local bags = Wild.GetPlayerBags and Wild.GetPlayerBags() or { BACKPACK_CONTAINER }
    if not Wild.GetPlayerBags then
        for i = 1, NUM_BAG_SLOTS do bags[#bags + 1] = i end
    end
    for _, bag in ipairs(bags) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                info.bag = bag; info.slot = slot
                for idx, intent in ipairs(Wild.db.intents) do
                    if intent.enabled ~= false and intent.action == "sell" and Wild.ValidateIntent(intent) and Wild.IntentMatchesActor(intent) then
                        if Wild.IntentMatchesItem(intent, info.itemID, info, charCtx) then
                            local shouldSell = true
                            local ic = intentCounts[idx]
                            if ic then
                                if ic.sold >= ic.toSell then
                                    shouldSell = false
                                else
                                    ic.sold = ic.sold + (info.stackCount or 1)
                                end
                            end
                            if shouldSell then
                                local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(info.itemID)
                                if sellPrice and sellPrice > 0 then
                                    pending[#pending + 1] = {
                                        bag = bag,
                                        slot = slot,
                                        link = info.hyperlink,
                                        count = info.stackCount or 1,
                                        copper = sellPrice * (info.stackCount or 1),
                                    }
                                elseif intent.destroyUnsellable then
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
    end

    return pending, destroyPending
end

-- ============================================================
-- Event-driven sell loop: scan → sell batch → wait → re-scan
-- ============================================================

local sellLoopActive = false
local sellPassNum = 0

local sellEventFrame = CreateFrame("Frame")
sellEventFrame:Hide()

local function DestroyUnsellableItems(items)
    local destroyed = 0
    for _, item in ipairs(items) do
        local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
        if info and info.itemID == item.itemID then
            C_Container.PickupContainerItem(item.bag, item.slot)
            DeleteCursorItem()
            destroyed = destroyed + item.count
            print(string.format("|cff00ccffWild:|r Destroyed (unsellable) %s \195\151%d.", item.link or "?", item.count))
        end
    end
    return destroyed
end

local function RunSellPass()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        sellLoopActive = false
        return
    end

    sellPassNum = sellPassNum + 1
    if sellPassNum > MAX_SELL_PASSES then
        print("|cffff6600Wild:|r Sell safety cap reached (" .. MAX_SELL_PASSES .. " passes).")
        -- Print final summary
        if sellFrame.soldCount > 0 then
            for _, entry in ipairs(sellFrame.soldEntries) do
                print(string.format("|cff00ccffWild:|r  Sold %s \195\151%d for %s", entry.link or "?", entry.count, Wild.FormatGold(entry.copper)))
            end
            print(string.format("|cff00ccffWild:|r Auto-sold %d item(s) for %s.", sellFrame.soldCount, Wild.FormatGold(sellFrame.totalCopper)))
        end
        sellLoopActive = false
        return
    end

    local pending, destroyPending = BuildSellBatch()

    if #pending == 0 then
        -- Nothing left to sell — destroy unsellable items if any, then print summary and done
        if #destroyPending > 0 then
            DestroyUnsellableItems(destroyPending)
        end
        if sellFrame.soldCount > 0 then
            for _, entry in ipairs(sellFrame.soldEntries) do
                print(string.format("|cff00ccffWild:|r  Sold %s \195\151%d for %s", entry.link or "?", entry.count, Wild.FormatGold(entry.copper)))
            end
            print(string.format("|cff00ccffWild:|r Auto-sold %d item(s) for %s.", sellFrame.soldCount, Wild.FormatGold(sellFrame.totalCopper)))
        end
        sellLoopActive = false
        return
    end

    -- Start selling this batch — keep accumulating into the same soldEntries
    sellFrame.pending = pending
    sellFrame.timer = 0
    sellFrame.onBatchDone = function(soldAny)
        if soldAny then
            -- Wait for bags to settle, then re-scan
            sellEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
            sellEventFrame:SetScript("OnEvent", function(self, event)
                self:UnregisterEvent("BAG_UPDATE_DELAYED")
                self:SetScript("OnEvent", nil)
                RunSellPass()
            end)
        else
            -- Nothing sold in this batch (items vanished?) — done
            if sellFrame.soldCount > 0 then
                for _, entry in ipairs(sellFrame.soldEntries) do
                    print(string.format("|cff00ccffWild:|r  Sold %s \195\151%d for %s", entry.link or "?", entry.count, Wild.FormatGold(entry.copper)))
                end
                print(string.format("|cff00ccffWild:|r Auto-sold %d item(s) for %s.", sellFrame.soldCount, Wild.FormatGold(sellFrame.totalCopper)))
            end
            sellLoopActive = false
        end
    end
    sellFrame:Show()
end

local function ProcessSellIntents()
    if not Wild.db or not Wild.db.intents then return end
    if sellLoopActive then return end

    PreloadBagItems(function()
        if not MerchantFrame or not MerchantFrame:IsShown() then return end

        sellLoopActive = true
        sellPassNum = 0
        -- Reset accumulated state for the whole sell session
        wipe(sellFrame.soldEntries)
        sellFrame.totalCopper = 0
        sellFrame.soldCount = 0
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
    C_Timer.After(0.5, ProcessSellIntents)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        OnMerchantOpened()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        if interactionType == Enum.PlayerInteractionType.Merchant then
            OnMerchantOpened()
        end
    end
end)
