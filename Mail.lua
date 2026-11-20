-- Wild: Mail automation — auto-open & intent-based sending
local ADDON_NAME, Wild = ...

-- ============================================================
-- Mail send queue — event-driven retry-until-done
-- Scans bags → builds batches → sends via MAIL_SEND_SUCCESS
-- chain → re-scans. Done when no more matching items remain.
-- ============================================================

local MAX_ATTACHMENTS = ATTACHMENTS_MAX_SEND or 12
local MAX_MAIL_PASSES = 50
local mailQueue = {}
local isSending = false
local automaticSend = false
local mailPassNum = 0
local mailTotalSent = 0
local mailSummaryCount = 0
local mailboxVisit
local pendingMail
local mailGeneration = 0
local mailConfirmationTimer
local waitingForBags = false
local bagsUpdated = false
local RescanMailQueue
local rescanFrame = CreateFrame("Frame")
local CONFIRMATION_TIMEOUT = 10

function Wild.IsMailSendBusy()
    return isSending or pendingMail ~= nil
end

local function AutoOpenMail(visit)
    if not Wild.GetSetting("mail.autoOpen") or Wild.IsFeatureEnabled("inbox") then return end

    local function OpenNext()
        if visit.closed or visit.inboxBrowserOpened or not Wild.GetSetting("mail.autoOpen")
            or not MailFrame or not MailFrame:IsVisible() or (pendingMail and not isSending) then return end
        if GetInboxNumItems() == 0 then return end
        if not isSending and not C_Mail.IsCommandPending() then AutoLootMailItem(1) end
        C_Timer.After(0.35, OpenNext)
    end

    C_Timer.After(0.5, OpenNext)
end

local function GetMailCommandBlock()
    if C_Mail.IsCommandPending() or (SendMailFrameLockSendMail and SendMailFrameLockSendMail:IsShown()) then
        return "Wait for WoW to finish the current mail action.", "mail_command_pending"
    end
end

local function GetSendBlock()
    if not mailboxVisit or mailboxVisit.closed or not MailFrame or not MailFrame:IsVisible() then
        return "Open a mailbox before running Mail rules.", "mailbox_closed"
    end
    if GameLimitedMode_IsActive and GameLimitedMode_IsActive() then
        return "This account cannot send mail.", "account_restricted"
    end
    if InCombatLockdown() then
        return "Leave combat before running Mail rules.", "in_combat"
    end
    if Wild.InboxBulk and Wild.InboxBulk.IsBusy() then
        return "Finish the bulk inbox action before running Mail rules.", "inbox_bulk_active"
    end
    if not SendMailFrame or not MailFrameTab_OnClick or not SendMailMailButton or not SendMailFrame_CanSend
        or not SendMailNameEditBox or not SendMailSubjectEditBox or not SendMailBodyEditBox
        or not SendMailMoney or not MoneyInputFrame_GetCopper then
        return "Mail send controls are unavailable.", "mail_ui_unavailable"
    end
    local blocked, reason = GetMailCommandBlock()
    if blocked then return blocked, reason end
    if GetCursorInfo() then
        return "The cursor is already occupied. Clear it before running Mail rules.", "cursor_occupied"
    end
    for index = 1, MAX_ATTACHMENTS do
        if HasSendMailItem(index) then
            return "Mail attachments are already occupied. Finish or clear the draft first.", "attachments_occupied"
        end
    end
    if SendMailNameEditBox:GetText() ~= "" or SendMailSubjectEditBox:GetText() ~= ""
        or SendMailBodyEditBox:GetText() ~= "" or MoneyInputFrame_GetCopper(SendMailMoney) > 0 then
        return "Finish or clear your mail draft before running Mail rules.", "mail_draft"
    end
end

local function PrintMailSummary(complete)
    if mailTotalSent == 0 or mailTotalSent == mailSummaryCount then return end
    mailSummaryCount = mailTotalSent
    Wild.Print(string.format("|cff00ccffWild:|r Mail %s: %d item(s) sent across %d pass(es).",
        complete and "complete" or "stopped", mailTotalSent, mailPassNum))
end

local function StopMailQueue(warning, keepPending, reason)
    if warning then
        local status = reason == "mail_failed" and "failed" or pendingMail and "unconfirmed" or "stopped"
        if pendingMail then
            pendingMail.failuresLogged = pendingMail.failuresLogged or {}
            if not pendingMail.failuresLogged[reason] then
                Wild.LogUnconfirmedItemActions("Mail", "mail", { entries = pendingMail.items }, {
                    source = "bags", target = pendingMail.recipient, recipient = pendingMail.recipient,
                    status = status, reason = reason,
                })
                pendingMail.failuresLogged[reason] = true
            end
        end
        Wild.Warn("Mail", warning, {
            action = "mail", status = status, reason = reason,
            recipient = pendingMail and pendingMail.recipient,
        })
    end
    PrintMailSummary(false)
    local keep = keepPending and pendingMail
    if not keep and mailConfirmationTimer then mailConfirmationTimer:Cancel(); mailConfirmationTimer = nil end
    rescanFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
    rescanFrame:SetScript("OnEvent", nil)
    mailQueue = {}
    if not keep then pendingMail = nil end
    waitingForBags = false
    isSending = false
    automaticSend = false
    mailGeneration = mailGeneration + 1
end

local function ScheduleMailStep(delay, callback)
    local generation = mailGeneration
    C_Timer.After(delay, function()
        if isSending and mailGeneration == generation then callback() end
    end)
end

local function BuildMailQueue()
    if not Wild.db or not Wild.db.intents then return {} end

    local charCtx = Wild.BuildCharContext()
    local byRecipient = {}
    local seen = {}

    local bags = Wild.GetPlayerBags()

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

    local queue = {}
    for recipient, items in pairs(byRecipient) do
        for i = 1, #items, MAX_ATTACHMENTS do
            local batch = {}
            for j = i, math.min(i + MAX_ATTACHMENTS - 1, #items) do
                table.insert(batch, items[j])
            end
            table.insert(queue, { recipient = recipient, items = batch })
        end
    end
    return queue
end

local function ProcessNextMail()
    if not isSending or pendingMail or #mailQueue == 0 then return end
    if automaticSend and Wild.GetSetting("mail.autoSend") ~= true then
        StopMailQueue()
        return
    end
    local blocked, reason = GetSendBlock()
    if blocked then
        StopMailQueue(blocked, false, reason)
        return
    end

    if not SendMailFrame:IsShown() or SendMailFrame.sendMode == "reply" then
        MailFrameTab_OnClick(nil, 2)
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
        local matchesRequest = info and info.itemID == item.itemID and info.hyperlink == item.link
        if matchesRequest and not info.isLocked then
            C_Container.PickupContainerItem(item.bag, item.slot)
            ClickSendMailItemButton(attached + 1)
            local _, itemID, _, stackCount = GetSendMailItem(attached + 1)
            local link = GetSendMailItemLink(attached + 1)
            if itemID ~= info.itemID or not stackCount or stackCount <= 0 or GetCursorInfo()
                or (link and info.hyperlink and link ~= info.hyperlink) then
                ClearCursor()
                local context = { source = "bags", target = recipient, recipient = recipient, reason = "attachment_not_confirmed" }
                Wild.LogUnconfirmedItemActions("Mail", "mail", { entries = { item } }, context)
                Wild.LogUnconfirmedItemActions("Mail", "mail", { entries = confirmedItems }, context)
                StopMailQueue("Mail attachment was not confirmed; stopped mail queue.", false, "attachment_not_confirmed")
                return
            end
            attached = attached + 1
            count = count + stackCount
            confirmedItems[#confirmedItems + 1] = {
                key = link or info.hyperlink or itemID, link = link or info.hyperlink,
                itemID = itemID, count = stackCount,
            }
        else
            Wild.LogUnconfirmedItemActions("Mail", "mail", { entries = { item } }, {
                source = "bags", target = recipient, recipient = recipient, status = "skipped",
                reason = matchesRequest and info.isLocked and "item_locked" or "slot_changed",
            })
        end
    end

    if attached > 0 then
        local subject = "Wild: " .. count .. " item(s)"
        SendMailNameEditBox:SetText(recipient)
        SendMailSubjectEditBox:SetText(subject)
        SendMailBodyEditBox:SetText("")
        local batch = { recipient = recipient, items = {}, count = count }
        Wild.MergeItemActionEntries(batch.items, confirmedItems)
        blocked, reason = GetMailCommandBlock()
        if not blocked then
            -- The Send button state can lag behind programmatic edits to the draft.
            SendMailFrame_CanSend()
            if not SendMailMailButton:IsEnabled() then
                blocked, reason = "WoW did not enable Send. Check the prepared mail.", "send_button_disabled"
            end
        end
        if blocked then
            Wild.LogUnconfirmedItemActions("Mail", "mail", { entries = batch.items }, {
                source = "bags", target = recipient, recipient = recipient, reason = reason,
            })
            StopMailQueue(blocked, false, reason)
            return
        end
        pendingMail = batch
        mailConfirmationTimer = C_Timer.NewTimer(CONFIRMATION_TIMEOUT, function()
            if pendingMail == batch then
                StopMailQueue("Mail send was not confirmed; stopped mail queue.", true, "confirmation_timeout")
            end
        end)
        SendMailMailButton:Click()
    else
        StopMailQueue("No mail attachments could be prepared; stopped mail queue.", false, "no_attachments")
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
    mailQueue = BuildMailQueue()
    if #mailQueue == 0 then
        PrintMailSummary(true)
        StopMailQueue()
    elseif mailPassNum >= MAX_MAIL_PASSES then
        StopMailQueue("Mail safety cap reached (" .. MAX_MAIL_PASSES .. " passes).", false, "safety_cap")
    else
        mailPassNum = mailPassNum + 1
        ScheduleMailStep(Wild.db.advanced.passDelay, ProcessNextMail)
    end
end

local function StartMailSend(automatic)
    if isSending then return false, "Mail rules are already running.", "already_running" end
    if pendingMail then return false, "Wait for WoW to confirm the previous rule send.", "send_unconfirmed" end
    local blocked, reason = GetSendBlock()
    if blocked and not automatic then return false, blocked, reason end
    local queue = BuildMailQueue()
    if #queue == 0 then return false, "No bag items match enabled Mail rules.", "no_matches" end
    if blocked then
        Wild.Warn("Mail", blocked, { action = "mail", status = "stopped", reason = reason })
        return false, blocked, reason
    end
    mailQueue = queue
    isSending = true
    automaticSend = automatic
    mailGeneration = mailGeneration + 1
    mailPassNum = 1
    mailTotalSent = 0
    mailSummaryCount = 0
    bagsUpdated = false
    rescanFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    rescanFrame:SetScript("OnEvent", function()
        bagsUpdated = true
        if waitingForBags then RescanMailQueue() end
    end)
    ScheduleMailStep(Wild.db.advanced.mailBatchDelay, ProcessNextMail)
    return true
end

--- Start the same send queue as auto-send without changing the saved setting.
function Wild.RunMailIntents()
    return StartMailSend(false)
end

-- ============================================================
-- Event handling
-- ============================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_CLOSED")
frame:RegisterEvent("MAIL_SEND_SUCCESS")
frame:RegisterEvent("MAIL_FAILED")
frame:RegisterEvent("UI_ERROR_MESSAGE")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "UI_ERROR_MESSAGE" then
        if isSending then Wild.LogClientError("Mail", ...) end
    elseif event == "MAIL_SHOW" then
        if not Wild.db then return end
        local visit = Wild.OpenIntentVisit("mail")
        if mailboxVisit == visit then return end
        mailboxVisit = visit
        if visit.bypassed then return end
        AutoOpenMail(visit)
        if Wild.GetSetting("mail.autoSend") == true then
            local generation = mailGeneration
            C_Timer.After(Wild.db.advanced.mailStartDelay, function()
                if mailboxVisit == visit and mailGeneration == generation and Wild.GetSetting("mail.autoSend") == true then
                    StartMailSend(true)
                end
            end)
        end
    elseif event == "MAIL_CLOSED" then
        Wild.CloseIntentVisit("mail")
        mailboxVisit = nil
        StopMailQueue(pendingMail and "Mailbox closed before the send was confirmed; stopped mail queue." or nil, true, "mailbox_closed")
    elseif event == "MAIL_SEND_SUCCESS" then
        if pendingMail then
            local batch = pendingMail
            pendingMail = nil
            if mailConfirmationTimer then mailConfirmationTimer:Cancel(); mailConfirmationTimer = nil end
            mailTotalSent = mailTotalSent + batch.count
            for _, item in ipairs(batch.items) do
                item.recipient = batch.recipient
                Wild.LogAction("Mail", "mail", item)
                Wild.Print("|cff00ccffWild:|r " .. Wild.FormatActionResult("mail", item))
            end
            if isSending then OnMailSendComplete() else PrintMailSummary(false) end
        end
    elseif event == "MAIL_FAILED" then
        if isSending or pendingMail then
            StopMailQueue("Mail send failed. Stopping mail queue.", false, "mail_failed")
        end
    end
end)
