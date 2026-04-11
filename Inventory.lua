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
local destroyQueueOnComplete = nil

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

local function FinishDestroyQueue()
    destroyBtnFrame:Hide()
    local cb = destroyQueueOnComplete
    local count = destroyQueueDoneCount
    destroyQueueItems = {}
    destroyQueueTotalCount = 0
    destroyQueueDoneCount = 0
    destroyQueueOnComplete = nil
    if cb then cb(count) end
end

local function UpdateDestroyButton()
    if #destroyQueueItems == 0 then
        FinishDestroyQueue()
        return
    end
    local item = destroyQueueItems[1]
    destroyItemText:SetText(string.format(
        "%s \195\151%d  (%d of %d)",
        item.link or item.name or ("Item " .. (item.itemID or "?")),
        item.count or 1,
        destroyQueueDoneCount + 1,
        destroyQueueTotalCount
    ))
    destroyBtnFrame:Show()
end

destroyBtn:SetScript("OnClick", function()
    if #destroyQueueItems == 0 then return end
    local item = tremove(destroyQueueItems, 1)
    ClearCursor()
    local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
    if info and info.itemID == item.itemID then
        C_Container.PickupContainerItem(item.bag, item.slot)
        DeleteCursorItem()
        destroyQueueDoneCount = destroyQueueDoneCount + 1
        print(string.format("|cff00ccffWild:|r Destroyed %s \195\151%d.", item.link or "?", item.count or 1))
    end
    UpdateDestroyButton()
end)

destroyCancelBtn:SetScript("OnClick", function()
    ClearCursor()
    destroyQueueItems = {}
    FinishDestroyQueue()
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
    destroyQueueOnComplete = onComplete
    UpdateDestroyButton()
end

local function RunDestroyPass()
    if destroyPassNum >= MAX_DESTROY_PASSES then
        if destroyTotalCount > 0 then
            print(string.format("|cff00ccffWild:|r Auto-destroy complete: %d item(s) removed.", destroyTotalCount))
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
                            local itemName = GetItemInfo(info.itemID) or ("Item " .. info.itemID)
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
        Wild.QueueDestroyItems(pendingItems, function(destroyedCount)
            destroyTotalCount = destroyTotalCount + destroyedCount
            if destroyedCount > 0 then
                -- Wait for bags to settle, then re-scan
                destroyFrame:RegisterEvent("BAG_UPDATE_DELAYED")
                destroyFrame:SetScript("OnEvent", function(self, event)
                    self:UnregisterEvent("BAG_UPDATE_DELAYED")
                    self:SetScript("OnEvent", nil)
                    RunDestroyPass()
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
    C_Timer.After(0.3, function() ProcessDestroyIntents() end)
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
