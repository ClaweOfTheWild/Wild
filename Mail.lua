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
local pendingMail
local mailGeneration = 0
local mailConfirmationTimer
local waitingForBags = false
local bagsUpdated = false
local RescanMailQueue
local rescanFrame = CreateFrame("Frame")
local CONFIRMATION_TIMEOUT = 10

local function StopMailQueue(warning, keepPending)
    if warning then Wild.Print("|cffff6600Wild:|r " .. warning) end
    local keep = keepPending and pendingMail
    if not keep and mailConfirmationTimer then mailConfirmationTimer:Cancel(); mailConfirmationTimer = nil end
    rescanFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
    rescanFrame:SetScript("OnEvent", nil)
    mailQueue = {}
    if not keep then pendingMail = nil end
    waitingForBags = false
    isSending = false
    mailGeneration = mailGeneration + 1
end

local function ScheduleMailStep(delay, callback)
    local generation = mailGeneration
    C_Timer.After(delay, function()
        if isSending and mailGeneration == generation then callback() end
    end)
end

local function BuildMailQueue()
    if not Wild.db or not Wild.db.intents then return end

    local charCtx = Wild.BuildCharContext()
    local byRecipient = {}
    local seen = {}

    local bags = Wild.GetPlayerBags and Wild.GetPlayerBags() or { BACKPACK_CONTAINER }
    if not Wild.GetPlayerBags then
        for i = 1, NUM_BAG_SLOTS do bags[#bags + 1] = i end
        if Enum.BagIndex.ReagentBag then bags[#bags + 1] = Enum.BagIndex.ReagentBag end
    end

    for _, intent in ipairs(Wild.db.intents) do
        if intent.enabled ~= false and intent.action == "mail" and Wild.ValidateIntent(intent) and Wild.IntentMatchesActor(intent) then
            local recipient = intent.recipient
            if not byRecipient[recipient] then
                byRecipient[recipient] = {}
            end

            for _, group in ipairs(Wild.GetItemGroups(intent)) do
                local count = group.count or 0
                local subIntent = Wild.SubIntentForGroup(intent, group)
                local sent = 0
                local maxSend = 0

                if count > 0 then
                    local totalMatching = Wild.CountMatchingInBags(subIntent, charCtx)
                    maxSend = totalMatching - count
                    if maxSend <= 0 then maxSend = -1 end
                end

                if maxSend ~= -1 then
                    for _, bag in ipairs(bags) do
                        local numSlots = C_Container.GetContainerNumSlots(bag)
                        for slot = 1, numSlots do
                            if maxSend > 0 and sent >= maxSend then break end
                            local info = C_Container.GetContainerItemInfo(bag, slot)
                            if info then info.bag = bag; info.slot = slot end
                            local slotKey = bag .. ":" .. slot
                            if info and info.itemID and not seen[slotKey] and Wild.IntentMatchesItem(subIntent, info.itemID, info, charCtx) then
                                local stackCount = info.stackCount or 1
                                seen[slotKey] = true
                                table.insert(byRecipient[recipient], {
                                    bag = bag, slot = slot, count = stackCount, link = info.hyperlink, itemID = info.itemID,
                                })
                                sent = sent + stackCount
                            end
                        end
                        if maxSend > 0 and sent >= maxSend then break end
                    end
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
    if not isSending or pendingMail or #mailQueue == 0 then return end
    if GetSendMailItem(1) or GetCursorInfo() then
        StopMailQueue("Mail attachments or the cursor are already occupied; stopped mail queue.")
        return
    end

    local entry = table.remove(mailQueue, 1)
    local recipient = entry.recipient
    local items = entry.items

    local attached = 0
    local confirmedItems = {}
    local count = 0
    bagsUpdated = false
    for _, item in ipairs(items) do
        local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
        if info and info.itemID == item.itemID and info.hyperlink == item.link and not info.isLocked then
            C_Container.PickupContainerItem(item.bag, item.slot)
            ClickSendMailItemButton(attached + 1)
            local _, itemID, _, stackCount = GetSendMailItem(attached + 1)
            local link = GetSendMailItemLink(attached + 1)
            if itemID ~= info.itemID or not stackCount or stackCount <= 0 or GetCursorInfo()
                or (link and info.hyperlink and link ~= info.hyperlink) then
                ClearCursor()
                StopMailQueue("Mail attachment was not confirmed; stopped mail queue.")
                return
            end
            attached = attached + 1
            count = count + stackCount
            confirmedItems[#confirmedItems + 1] = {
                key = link or info.hyperlink or itemID, link = link or info.hyperlink,
                itemID = itemID, count = stackCount,
            }
        else
            Wild.Log("Mail", "Skipped a mail attachment because its bag slot changed or is locked.")
        end
    end

    if attached > 0 then
        local batch = { recipient = recipient, items = {}, count = count }
        Wild.MergeItemActionEntries(batch.items, confirmedItems)
        pendingMail = batch
        mailConfirmationTimer = C_Timer.NewTimer(CONFIRMATION_TIMEOUT, function()
            if pendingMail == batch then StopMailQueue("Mail send was not confirmed; stopped mail queue.") end
        end)
        local subject = "Wild: " .. count .. " item(s)"
        SendMail(recipient, subject, "")
    else
        StopMailQueue("No mail attachments could be prepared; stopped mail queue.")
    end
end

-- Called after each MAIL_SEND_SUCCESS to continue or re-scan
local function OnMailSendComplete()
    if #mailQueue > 0 then
        -- More batches in this pass — send next
        local batchDelay = Wild.db.advanced.mailBatchDelay
        local passDelay = Wild.db.advanced.passDelay
        if passDelay and passDelay > batchDelay then batchDelay = passDelay end
        ScheduleMailStep(batchDelay, ProcessNextMail)
    else
        waitingForBags = true
        if bagsUpdated then
            RescanMailQueue()
        else
            local generation = mailGeneration
            mailConfirmationTimer = C_Timer.NewTimer(CONFIRMATION_TIMEOUT, function()
                if isSending and mailGeneration == generation and waitingForBags then RescanMailQueue() end
            end)
        end
    end
end

RescanMailQueue = function()
    waitingForBags = false
    if mailConfirmationTimer then mailConfirmationTimer:Cancel(); mailConfirmationTimer = nil end
    BuildMailQueue()
    if #mailQueue == 0 then
        if mailTotalSent > 0 then
            Wild.Print(string.format("|cff00ccffWild:|r Mail complete: %d item(s) sent across %d pass(es).", mailTotalSent, mailPassNum))
        end
        StopMailQueue()
    elseif mailPassNum >= MAX_MAIL_PASSES then
        StopMailQueue("Mail safety cap reached (" .. MAX_MAIL_PASSES .. " passes).")
    else
        mailPassNum = mailPassNum + 1
        ScheduleMailStep(Wild.db.advanced.passDelay, ProcessNextMail)
    end
end

local function StartMailSend()
    if isSending or pendingMail then return end
    BuildMailQueue()
    if #mailQueue == 0 then return end
    isSending = true
    mailGeneration = mailGeneration + 1
    mailPassNum = 1
    mailTotalSent = 0
    bagsUpdated = false
    rescanFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    rescanFrame:SetScript("OnEvent", function()
        bagsUpdated = true
        if waitingForBags then RescanMailQueue() end
    end)
    ScheduleMailStep(Wild.db.advanced.mailBatchDelay, ProcessNextMail)
end

-- ============================================================
-- Event handling
-- ============================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_CLOSED")
frame:RegisterEvent("MAIL_SEND_SUCCESS")
frame:RegisterEvent("MAIL_FAILED")

frame:SetScript("OnEvent", function(self, event)
    if event == "MAIL_SHOW" then
        AutoOpenMail()
        local generation = mailGeneration
        C_Timer.After(Wild.db.advanced.mailStartDelay, function()
            if mailGeneration == generation then StartMailSend() end
        end)
    elseif event == "MAIL_CLOSED" then
        StopMailQueue(pendingMail and "Mailbox closed before the send was confirmed; stopped mail queue." or nil, true)
    elseif event == "MAIL_SEND_SUCCESS" then
        if pendingMail then
            local batch = pendingMail
            pendingMail = nil
            if mailConfirmationTimer then mailConfirmationTimer:Cancel(); mailConfirmationTimer = nil end
            mailTotalSent = mailTotalSent + batch.count
            for _, item in ipairs(batch.items) do
                Wild.Print(string.format("|cff00ccffWild:|r Mailed %s \195\151%d to %s.", item.link or ("Item " .. item.itemID), item.count, batch.recipient))
            end
            if isSending then OnMailSendComplete() end
        end
    elseif event == "MAIL_FAILED" then
        if isSending or pendingMail then
            StopMailQueue("Mail send failed. Stopping mail queue.")
        end
    end
end)
