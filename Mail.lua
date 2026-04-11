-- Wild: Mail automation — auto-open & intent-based sending
local ADDON_NAME, Wild = ...

-- ============================================================
-- Auto-open incoming mail
-- ============================================================

local function AutoOpenMail()
    if not Wild.db or not Wild.db.mail or not Wild.db.mail.autoOpen then return end

    local function OpenNext()
        local numItems = GetInboxNumItems()
        if numItems == 0 then return end
        AutoLootMailItem(1)
        C_Timer.After(0.35, OpenNext)
    end

    C_Timer.After(0.5, OpenNext)
end

-- ============================================================
-- Mail send queue — event-driven retry-until-done
-- Scans bags → builds batches → sends via MAIL_SEND_SUCCESS
-- chain → re-scans. Done when no more matching items remain.
-- ============================================================

local MAX_ATTACHMENTS = ATTACHMENTS_MAX_SEND or 12
local MAX_MAIL_PASSES = 50
local mailQueue = {}
local isSending = false
local mailPassNum = 0
local mailTotalSent = 0

local function BuildMailQueue()
    if not Wild.db or not Wild.db.intents then return end

    local charCtx = Wild.BuildCharContext()
    local byRecipient = {}

    local bags = Wild.GetPlayerBags and Wild.GetPlayerBags() or { BACKPACK_CONTAINER }
    if not Wild.GetPlayerBags then
        for i = 1, NUM_BAG_SLOTS do bags[#bags + 1] = i end
    end

    for _, intent in ipairs(Wild.db.intents) do
        if intent.enabled ~= false and intent.action == "mail" and Wild.ValidateIntent(intent) and Wild.IntentMatchesActor(intent) then
            local recipient = intent.recipient
            if not byRecipient[recipient] then
                byRecipient[recipient] = {}
            end

            local keep = intent.keep or 0
            local sent = 0
            local maxSend = 0

            if keep > 0 then
                local totalMatching = 0
                for _, bag in ipairs(bags) do
                    local numSlots = C_Container.GetContainerNumSlots(bag)
                    for slot = 1, numSlots do
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info then info.bag = bag; info.slot = slot end
                        if info and info.itemID and Wild.IntentMatchesItem(intent, info.itemID, info, charCtx) then
                            totalMatching = totalMatching + (info.stackCount or 1)
                        end
                    end
                end
                maxSend = totalMatching - keep
                if maxSend <= 0 then maxSend = -1 end
            end

            if maxSend ~= -1 then
                for _, bag in ipairs(bags) do
                    local numSlots = C_Container.GetContainerNumSlots(bag)
                    for slot = 1, numSlots do
                        if maxSend > 0 and sent >= maxSend then break end
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info then info.bag = bag; info.slot = slot end
                        if info and info.itemID and Wild.IntentMatchesItem(intent, info.itemID, info, charCtx) then
                            local stackCount = info.stackCount or 1
                            table.insert(byRecipient[recipient], { bag = bag, slot = slot, count = stackCount, link = info.hyperlink })
                            sent = sent + stackCount
                        end
                    end
                    if maxSend > 0 and sent >= maxSend then break end
                end
            end
        end
    end

    mailQueue = {}
    for recipient, items in pairs(byRecipient) do
        for i = 1, #items, MAX_ATTACHMENTS do
            local batch = {}
            for j = i, math.min(i + MAX_ATTACHMENTS - 1, #items) do
                table.insert(batch, items[j])
            end
            table.insert(mailQueue, { recipient = recipient, items = batch })
        end
    end
end

local function ProcessNextMail()
    if #mailQueue == 0 then
        -- Current pass exhausted — wait for bags to settle, then re-scan
        -- (BAG_UPDATE_DELAYED will fire from the last mail send)
        return  -- handled by MAIL_SEND_SUCCESS path below
    end

    local entry = table.remove(mailQueue, 1)
    local recipient = entry.recipient
    local items = entry.items

    local attached = 0
    for _, item in ipairs(items) do
        C_Container.PickupContainerItem(item.bag, item.slot)
        ClickSendMailItemButton(attached + 1)
        attached = attached + 1
    end

    if attached > 0 then
        for _, item in ipairs(items) do
            print(string.format("|cff00ccffWild:|r  \226\156\137 %s \195\151%d", item.link or "?", item.count))
        end
        local subject = "Wild: " .. attached .. " item(s)"
        SendMail(recipient, subject, "")
        mailTotalSent = mailTotalSent + attached
        print(string.format("|cff00ccffWild:|r Mailing %d item(s) to %s.", attached, recipient))
    end
end

-- Called after each MAIL_SEND_SUCCESS to continue or re-scan
local function OnMailSendComplete()
    if #mailQueue > 0 then
        -- More batches in this pass — send next
        C_Timer.After(0.5, ProcessNextMail)
    else
        -- This pass is done — re-scan after bags settle
        mailPassNum = mailPassNum + 1
        if mailPassNum >= MAX_MAIL_PASSES then
            print("|cffff6600Wild:|r Mail safety cap reached (" .. MAX_MAIL_PASSES .. " passes).")
            isSending = false
            return
        end

        -- Wait for BAG_UPDATE_DELAYED, then rebuild queue
        local rescanFrame = CreateFrame("Frame")
        rescanFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        rescanFrame:SetScript("OnEvent", function(self, event)
            self:UnregisterEvent("BAG_UPDATE_DELAYED")
            self:SetScript("OnEvent", nil)

            BuildMailQueue()
            if #mailQueue == 0 then
                -- Nothing left — done
                if mailTotalSent > 0 then
                    print(string.format("|cff00ccffWild:|r Mail complete: %d item(s) sent across %d pass(es).", mailTotalSent, mailPassNum))
                end
                isSending = false
            else
                ProcessNextMail()
            end
        end)
    end
end

local function StartMailSend()
    if isSending then return end
    BuildMailQueue()
    if #mailQueue == 0 then return end
    isSending = true
    mailPassNum = 1
    mailTotalSent = 0
    C_Timer.After(0.5, ProcessNextMail)
end

-- ============================================================
-- Event handling
-- ============================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_SEND_SUCCESS")
frame:RegisterEvent("MAIL_FAILED")

frame:SetScript("OnEvent", function(self, event)
    if event == "MAIL_SHOW" then
        AutoOpenMail()
        C_Timer.After(1.0, StartMailSend)
    elseif event == "MAIL_SEND_SUCCESS" then
        if isSending then
            OnMailSendComplete()
        end
    elseif event == "MAIL_FAILED" then
        if isSending then
            print("|cffff6600Wild:|r Mail send failed. Stopping mail queue.")
            mailQueue = {}
            isSending = false
        end
    end
end)
