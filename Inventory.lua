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
    local destroyedThisPass = 0

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
                for _, intent in ipairs(Wild.db.intents) do
                    if intent.enabled ~= false and intent.action == "destroy" and Wild.ValidateIntent(intent) and Wild.IntentMatchesActor(intent) then
                        if Wild.IntentMatchesItem(intent, info.itemID, info, charCtx) then
                            local shouldDestroy = true
                            local keepQty = intent.keep or 0
                            if keepQty > 0 then
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
                                if totalCount <= keepQty then
                                    shouldDestroy = false
                                end
                            end

                            if shouldDestroy then
                                local itemName = GetItemInfo(info.itemID) or ("Item " .. info.itemID)
                                C_Container.PickupContainerItem(bag, slot)
                                DeleteCursorItem()
                                local stackCount = info.stackCount or 1
                                destroyedThisPass = destroyedThisPass + stackCount
                                destroyTotalCount = destroyTotalCount + stackCount
                                print(string.format("|cff00ccffWild:|r Destroyed %s x%d.", itemName, stackCount))
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    if destroyedThisPass > 0 then
        -- Items destroyed — wait for bags to settle, then re-scan
        destroyFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        destroyFrame:SetScript("OnEvent", function(self, event)
            self:UnregisterEvent("BAG_UPDATE_DELAYED")
            self:SetScript("OnEvent", nil)
            RunDestroyPass()
        end)
    else
        -- Nothing left to destroy — done
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
