-- Wild: Inventory management (auto-destroy) — Intent-based
local ADDON_NAME, Wild = ...

-- ============================================================
-- Auto-destroy processing — event-driven retry-until-done
-- Scans bags → destroys matching items → waits for
-- BAG_UPDATE_DELAYED → re-scans. Done when no matches remain.
-- ============================================================

local MAX_DESTROY_PASSES = 50
local destroyActive = false
local destroyPassNum = 0
local destroyTotalCount = 0
local destroyGeneration = 0
local CONFIRMATION_TIMEOUT = 5
local POPUP_CONFIRMATION_TIMEOUT = 30

local destroyFrame = CreateFrame("Frame")
destroyFrame:Hide()

-- ============================================================
-- Hardware-event destroy button
-- DeleteCursorItem() is hardware-event-protected; it can only
-- run inside an OnClick handler from a real player click.
-- Items are queued and destroyed one-per-click via this button.
-- ============================================================

local destroyQueueItems = {}
local destroyQueueTotalCount = 0
local destroyQueueDoneCount = 0
local destroyQueueRemovedCount = 0
local destroyQueueEntries = {}
local destroyQueueOnComplete = nil
local pendingDestroy
local destroyConfirmationTimer

local destroyBtnFrame = CreateFrame("Frame", "WildDestroyFrame", UIParent, "BackdropTemplate")
destroyBtnFrame:SetSize(300, 100)
destroyBtnFrame:SetPoint("CENTER", 0, 200)
destroyBtnFrame:SetFrameStrata("DIALOG")
destroyBtnFrame:SetFrameLevel(100)
destroyBtnFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
destroyBtnFrame:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
destroyBtnFrame:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
destroyBtnFrame:Hide()
destroyBtnFrame:EnableMouse(true)
destroyBtnFrame:SetMovable(true)
destroyBtnFrame:SetClampedToScreen(true)

-- Title bar
local destroyTitleBar = CreateFrame("Frame", nil, destroyBtnFrame)
destroyTitleBar:SetHeight(28)
destroyTitleBar:SetPoint("TOPLEFT", 0, 0)
destroyTitleBar:SetPoint("TOPRIGHT", 0, 0)
destroyTitleBar:EnableMouse(true)
destroyTitleBar:RegisterForDrag("LeftButton")
destroyTitleBar:SetScript("OnDragStart", function() destroyBtnFrame:StartMoving() end)
destroyTitleBar:SetScript("OnDragStop", function() destroyBtnFrame:StopMovingOrSizing() end)

local destroyTitleText = destroyTitleBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
destroyTitleText:SetPoint("LEFT", 12, 0)
destroyTitleText:SetText("|cff00ccffWild|r |cffaaaaaaDestroy|r")

local destroyTitleSep = destroyTitleBar:CreateTexture(nil, "ARTWORK")
destroyTitleSep:SetHeight(1)
destroyTitleSep:SetPoint("BOTTOMLEFT", 0, 0)
destroyTitleSep:SetPoint("BOTTOMRIGHT", 0, 0)
destroyTitleSep:SetColorTexture(0.3, 0.3, 0.35, 1)

-- Item text
local destroyItemText = destroyBtnFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
destroyItemText:SetPoint("TOP", 0, -36)
destroyItemText:SetWidth(280)

-- Styled destroy button (flat, matching settings look)
local destroyBtn = CreateFrame("Button", nil, destroyBtnFrame, "BackdropTemplate")
destroyBtn:SetSize(100, 24)
destroyBtn:SetPoint("BOTTOMLEFT", 20, 12)
destroyBtn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
destroyBtn:SetBackdropColor(0.15, 0.15, 0.20, 1)
destroyBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
destroyBtn.label = destroyBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
destroyBtn.label:SetPoint("CENTER", 0, 0)
destroyBtn.label:SetText("|cffff4444Destroy|r")
destroyBtn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(0.20, 0.10, 0.10, 1)
end)
destroyBtn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0.15, 0.15, 0.20, 1)
end)

-- Styled cancel button
local destroyCancelBtn = CreateFrame("Button", nil, destroyBtnFrame, "BackdropTemplate")
destroyCancelBtn:SetSize(80, 24)
destroyCancelBtn:SetPoint("BOTTOMRIGHT", -20, 12)
destroyCancelBtn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
destroyCancelBtn:SetBackdropColor(0.15, 0.15, 0.20, 1)
destroyCancelBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
destroyCancelBtn.label = destroyCancelBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
destroyCancelBtn.label:SetPoint("CENTER", 0, 0)
destroyCancelBtn.label:SetText("|cffaaaaaaCancel|r")
destroyCancelBtn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(0.20, 0.20, 0.25, 1)
end)
destroyCancelBtn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0.15, 0.15, 0.20, 1)
end)

local function ClearDestroyWait()
    destroyFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
    destroyFrame:SetScript("OnEvent", nil)
    if destroyConfirmationTimer then destroyConfirmationTimer:Cancel(); destroyConfirmationTimer = nil end
    pendingDestroy = nil
end

local function FinishDestroyQueue(cancelled)
    destroyBtnFrame:Hide()
    local cb = destroyQueueOnComplete
    local count = destroyQueueRemovedCount
    for _, item in ipairs(destroyQueueEntries) do
        Wild.Print(string.format("|cff00ccffWild:|r Destroyed %s \195\151%d.", item.link or ("Item " .. item.itemID), item.count))
    end
    ClearDestroyWait()
    destroyQueueItems = {}
    destroyQueueTotalCount = 0
    destroyQueueDoneCount = 0
    destroyQueueRemovedCount = 0
    destroyQueueEntries = {}
    destroyQueueOnComplete = nil
    if cb then cb(count, cancelled) end
end

local function UpdateDestroyButton()
    if #destroyQueueItems == 0 then
        FinishDestroyQueue()
        return
    end
    local item = destroyQueueItems[1]
    destroyBtn.label:SetText(pendingDestroy and "|cffaaaaaaWaiting...|r" or "|cffff4444Destroy|r")
    destroyItemText:SetText(string.format(
        "%s \195\151%d  (%d of %d)",
        item.link or item.name or ("Item " .. (item.itemID or "?")),
        item.count or 1,
        destroyQueueDoneCount + 1,
        destroyQueueTotalCount
    ))
    destroyBtnFrame:Show()
end

local function StoreDestroyResults(request)
    Wild.MergeItemActionEntries(destroyQueueEntries, request.confirmed)
    for _, item in ipairs(request.confirmed) do destroyQueueRemovedCount = destroyQueueRemovedCount + item.count end
    request.confirmed = {}
end

local function ConfirmDestroy()
    if not pendingDestroy or GetCursorInfo() then return false end
    local request = pendingDestroy
    local entries, complete = Wild.ConfirmItemActionBatch(request.batch)
    Wild.MergeItemActionEntries(request.confirmed, entries)
    if not complete then return false end
    StoreDestroyResults(request)
    destroyQueueDoneCount = destroyQueueDoneCount + 1
    tremove(destroyQueueItems, 1)
    ClearDestroyWait()
    UpdateDestroyButton()
    return true
end

local function IsDestroyPopupVisible()
    if not StaticPopup_Visible then return false end
    return StaticPopup_Visible("DELETE_ITEM") or StaticPopup_Visible("DELETE_QUEST_ITEM")
        or StaticPopup_Visible("DELETE_GOOD_ITEM") or StaticPopup_Visible("DELETE_GOOD_QUEST_ITEM")
end

local function FailDestroy(request)
    if pendingDestroy ~= request then return end
    if ConfirmDestroy() then return end
    if IsDestroyPopupVisible() then
        request.waitingForPopup = true
        destroyConfirmationTimer = C_Timer.NewTimer(POPUP_CONFIRMATION_TIMEOUT, function() FailDestroy(request) end)
        return
    end
    StoreDestroyResults(request)
    local cursorType, cursorItemID = GetCursorInfo()
    if cursorType == "item" and cursorItemID == request.item.itemID then ClearCursor() end
    ClearDestroyWait()
    Wild.Print("|cffff6600Wild:|r Item destruction was not confirmed. Check the item and try again.")
    UpdateDestroyButton()
end

destroyBtn:SetScript("OnClick", function()
    if #destroyQueueItems == 0 or pendingDestroy then return end
    if GetCursorInfo() then
        Wild.Print("|cffff6600Wild:|r Clear the cursor before destroying an item.")
        return
    end
    local item = destroyQueueItems[1]
    local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
    if not info or info.itemID ~= item.itemID or (info.hyperlink and item.link and info.hyperlink ~= item.link) then
        Wild.Log("Inventory", "Skipped a destroy request because its bag slot changed.")
        tremove(destroyQueueItems, 1)
        UpdateDestroyButton()
        return
    end
    if info.isLocked then
        Wild.Print("|cffff6600Wild:|r Item is locked; try destroying it again after it unlocks.")
        return
    end
    local request = { item = item, confirmed = {}, batch = Wild.CreateItemActionBatch(Wild.CapturePlayerItemCounts) }
    Wild.RecordItemAction(request.batch, info, info.stackCount or 1)
    pendingDestroy = request
    destroyFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    destroyFrame:SetScript("OnEvent", function()
        if ConfirmDestroy() then return end
        if pendingDestroy and pendingDestroy.waitingForPopup and not IsDestroyPopupVisible() and not GetCursorInfo() then
            FailDestroy(pendingDestroy)
        end
    end)
    destroyConfirmationTimer = C_Timer.NewTimer(CONFIRMATION_TIMEOUT, function() FailDestroy(request) end)
    C_Container.PickupContainerItem(item.bag, item.slot)
    local cursorType, cursorItemID, cursorLink = GetCursorInfo()
    if cursorType ~= "item" or cursorItemID ~= info.itemID
        or (info.hyperlink and cursorLink and cursorLink ~= info.hyperlink) then
        FailDestroy(request)
        return
    end
    DeleteCursorItem()
    UpdateDestroyButton()
end)

destroyCancelBtn:SetScript("OnClick", function()
    if pendingDestroy and not GetCursorInfo() then
        local entries = Wild.ConfirmItemActionBatch(pendingDestroy.batch)
        Wild.MergeItemActionEntries(pendingDestroy.confirmed, entries)
        StoreDestroyResults(pendingDestroy)
    end
    ClearDestroyWait()
    ClearCursor()
    destroyQueueItems = {}
    FinishDestroyQueue(true)
end)

function Wild.QueueDestroyItems(items, onComplete)
    if #items == 0 then
        if onComplete then onComplete(0) end
        return
    end
    for _, item in ipairs(items) do
        destroyQueueItems[#destroyQueueItems + 1] = item
    end
    destroyQueueTotalCount = destroyQueueTotalCount + #items
    if onComplete then destroyQueueOnComplete = onComplete end
    UpdateDestroyButton()
end

local function RunDestroyPass()
    if not destroyActive then return end
    if destroyPassNum >= MAX_DESTROY_PASSES then
        Wild.Print("|cffff6600Wild:|r Destroy safety cap reached (" .. MAX_DESTROY_PASSES .. " passes).")
        if destroyTotalCount > 0 then
            Wild.Print(string.format("|cff00ccffWild:|r Auto-destroy stopped: %d item(s) removed.", destroyTotalCount))
        end
        destroyActive = false
        return
    end

    destroyPassNum = destroyPassNum + 1
    local charCtx = Wild.BuildCharContext()
    local pendingItems = {}

    local bags = Wild.GetPlayerBags and Wild.GetPlayerBags() or { BACKPACK_CONTAINER }
    if not Wild.GetPlayerBags then
        for i = 1, NUM_BAG_SLOTS do bags[#bags + 1] = i end
        if Enum.BagIndex.ReagentBag then bags[#bags + 1] = Enum.BagIndex.ReagentBag end
    end
    -- Build per-group destroy entries with individual quotas
    local groupEntries = {}
    for _, intent in ipairs(Wild.db.intents) do
        if intent.enabled ~= false and intent.action == "destroy" and Wild.ValidateIntent(intent) and Wild.IntentMatchesActor(intent) then
            for _, group in ipairs(Wild.GetItemGroups(intent)) do
                local subIntent = Wild.SubIntentForGroup(intent, group)
                local count = group.count or 0
                groupEntries[#groupEntries + 1] = {
                    subIntent = subIntent,
                    count = count,
                }
            end
        end
    end

    for _, bag in ipairs(bags) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                info.bag = bag; info.slot = slot
                for _, ge in ipairs(groupEntries) do
                    if Wild.IntentMatchesItem(ge.subIntent, info.itemID, info, charCtx) then
                        local shouldDestroy = true
                        if ge.count > 0 then
                            local totalCount = 0
                            for _, b in ipairs(bags) do
                                local ns = C_Container.GetContainerNumSlots(b)
                                for s = 1, ns do
                                    local bi = C_Container.GetContainerItemInfo(b, s)
                                    if bi and bi.itemID == info.itemID then
                                        totalCount = totalCount + (bi.stackCount or 1)
                                    end
                                end
                            end
                            if totalCount <= ge.count then
                                shouldDestroy = false
                            end
                        end

                        if shouldDestroy then
                            local itemName = C_Item.GetItemInfo(info.itemID) or ("Item " .. info.itemID)
                            pendingItems[#pendingItems + 1] = {
                                bag = bag,
                                slot = slot,
                                itemID = info.itemID,
                                link = info.hyperlink or itemName,
                                name = itemName,
                                count = info.stackCount or 1,
                            }
                            break
                        end
                    end
                end
            end
        end
    end

    if #pendingItems > 0 then
        local generation = destroyGeneration
        Wild.QueueDestroyItems(pendingItems, function(destroyedCount, cancelled)
            destroyTotalCount = destroyTotalCount + destroyedCount
            if cancelled then
                destroyActive = false
                destroyGeneration = destroyGeneration + 1
                if destroyTotalCount > 0 then
                    Wild.Print(string.format("|cff00ccffWild:|r Auto-destroy stopped: %d item(s) removed.", destroyTotalCount))
                end
            elseif destroyedCount > 0 then
                -- The destroy queue has already validated the bag update.
                C_Timer.After(Wild.db.advanced.passDelay, function()
                    if destroyActive and destroyGeneration == generation then RunDestroyPass() end
                end)
            else
                if destroyTotalCount > 0 then
                    print(string.format("|cff00ccffWild:|r Auto-destroy complete: %d item(s) removed.", destroyTotalCount))
                end
                destroyActive = false
            end
        end)
    else
        if destroyTotalCount > 0 then
            print(string.format("|cff00ccffWild:|r Auto-destroy complete: %d item(s) removed.", destroyTotalCount))
        end
        destroyActive = false
    end
end

local function ProcessDestroyIntents()
    if not Wild.db or not Wild.db.intents then return end
    if destroyActive then return end

    -- Check if any destroy intents exist before starting the loop
    local hasDestroy = false
    for _, intent in ipairs(Wild.db.intents) do
        if intent.enabled ~= false and intent.action == "destroy" and Wild.ValidateIntent(intent) and Wild.IntentMatchesActor(intent) then
            hasDestroy = true
            break
        end
    end
    if not hasDestroy then return end

    destroyActive = true
    destroyGeneration = destroyGeneration + 1
    destroyPassNum = 0
    destroyTotalCount = 0
    RunDestroyPass()
end

Wild.ProcessDestroyIntents = ProcessDestroyIntents

-- ============================================================
-- Event handling
-- ============================================================

local lastInventoryTrigger = 0
local function OnInventoryTrigger()
    if not Wild.db or not Wild.db.intents then return end

    local now = GetTime()
    if lastInventoryTrigger > now - 1 then return end
    lastInventoryTrigger = now
    C_Timer.After(Wild.db.advanced.destroyStartDelay, function() ProcessDestroyIntents() end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_CLOSED")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("GUILDBANKFRAME_OPENED")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "LOOT_CLOSED" then
        OnInventoryTrigger()
    elseif event == "MERCHANT_SHOW" then
        OnInventoryTrigger()
    elseif event == "BANKFRAME_OPENED" or event == "GUILDBANKFRAME_OPENED" then
        OnInventoryTrigger()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        if interactionType == Enum.PlayerInteractionType.Merchant then
            OnInventoryTrigger()
        elseif interactionType == Enum.PlayerInteractionType.Banker
            or (Enum.PlayerInteractionType.AccountBanker and interactionType == Enum.PlayerInteractionType.AccountBanker)
            or interactionType == Enum.PlayerInteractionType.GuildBanker then
            OnInventoryTrigger()
        end
    end
end)
