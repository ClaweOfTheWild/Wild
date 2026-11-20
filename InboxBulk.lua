-- Wild: Guarded bulk actions for loaded inbox mail
local ADDON_NAME, Wild = ...

local Inbox = {}
Wild.InboxBulk = Inbox

local CONFIRMATION = "WILD_INBOX_BULK_CONFIRM"
local CONFIRMATION_TIMEOUT = 10
local COMMAND_INTERVAL = 0.15
local batch

function Inbox.ReadMessage(index)
    local _, stationery, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned, textCreated, _, isGM =
        GetInboxHeaderInfo(index)
    if not daysLeft or money == nil or cod == nil then return end

    local message = {
        index = index, stationery = stationery, sender = sender or "Unknown sender",
        subject = subject and subject ~= "" and subject or "(No subject)",
        money = money, cod = cod, itemCount = itemCount or 0, attachments = {},
        wasRead = wasRead, wasReturned = wasReturned, textCreated = textCreated, isGM = isGM,
        canDelete = not not InboxItemCanDelete(index),
    }
    if message.itemCount == 0 then return message end

    for slot = 1, ATTACHMENTS_MAX_RECEIVE do
        if HasInboxItem(index, slot) then
            local name, itemID, icon, count, quality, _, isCurrency = GetInboxItem(index, slot)
            local link = GetInboxItemLink(index, slot)
            message.attachments[#message.attachments + 1] = {
                slot = slot, itemID = itemID, icon = icon, count = count, quality = quality,
                isCurrency = isCurrency, link = link,
                name = name or (link and link:match("|h%[(.-)%]|h")),
            }
            if #message.attachments == message.itemCount then break end
        end
    end
    return message
end

function Inbox.HasItemIdentity(item)
    return item and item.name and item.itemID and item.itemID > 0 and item.count and item.count > 0
        and (item.link or item.isCurrency)
end

local function SameAttachment(before, now)
    return before and now and before.slot == now.slot and before.itemID == now.itemID
        and before.link == now.link and before.count == now.count and before.isCurrency == now.isCurrency
end

function Inbox.SameMessage(before, now)
    if before == now then return true end
    if not before or not now or before.sender ~= now.sender or before.subject ~= now.subject
        or before.stationery ~= now.stationery or before.money ~= now.money or before.cod ~= now.cod
        or before.isGM ~= now.isGM or before.wasReturned ~= now.wasReturned or before.textCreated ~= now.textCreated
        or before.itemCount ~= now.itemCount or #before.attachments ~= #now.attachments then
        return false
    end
    for position, item in ipairs(before.attachments) do
        if not SameAttachment(item, now.attachments[position]) then return false end
    end
    return true
end

function Inbox.ReadLoaded()
    local loaded, total = GetInboxNumItems()
    local messages = {}
    for index = 1, loaded do messages[index] = Inbox.ReadMessage(index) or false end
    return messages, total or loaded
end

-- A removal may shift indexes, but only the requested letter may disappear.
function Inbox.SameLoaded(before, now, changedIndex, replacement)
    local removed = changedIndex and not replacement
    if #now ~= #before - (removed and 1 or 0) then return false end
    for index, message in ipairs(before) do
        if index ~= changedIndex or not removed then
            local currentIndex = removed and index > changedIndex and index - 1 or index
            local expected = index == changedIndex and replacement or message
            if not Inbox.SameMessage(expected, now[currentIndex]) then return false end
        end
    end
    return true
end

local function NextRequest(message, action, keepUnread)
    if not message or message.isGM then return end
    if action == "return" and message.canDelete == false and not message.wasReturned then
        return "return"
    end
    if message.cod ~= 0 then return end
    if action == "delete" and message.canDelete == true and message.money == 0 and message.itemCount == 0
        and (not keepUnread or message.wasRead) then
        return "delete"
    end
    if action == "open" then
        if message.money > 0 then return "money" end
        for _, item in ipairs(message.attachments) do
            if Inbox.HasItemIdentity(item) then return "item", item end
        end
    end
end

local function GetBlock()
    if not MailFrame:IsVisible() or OpenMailFrame:IsShown() then return "Close the letter and return to the inbox." end
    if InCombatLockdown() then return "Leave combat before processing mail." end
    if GetCursorInfo() then return "Clear the cursor before processing mail." end
    if Wild.IsMailSendBusy() then return "Wait for Mail rules to finish." end
    if C_Mail.IsCommandPending() or (SendMailFrameLockSendMail and SendMailFrameLockSendMail:IsShown()) then
        return "Wait for WoW to finish the current mail action."
    end
end

local function Finish(run, message, warning)
    batch = nil
    if run.timer then run.timer:Cancel() end
    if run.confirming then StaticPopup_Hide(CONFIRMATION, run) end
    run.report(message, warning)
    return not warning
end

function Inbox.IsBusy()
    return batch ~= nil
end

function Inbox.Cancel(reason)
    if not batch then return end
    local message = not batch.confirming and reason or nil
    Finish(batch, message, message ~= nil)
end

local function KeepUnread()
    return Wild.GetSetting("mail.keepUnread") == true
end

local function Dispatch(run, current)
    local blocked = GetBlock()
    if blocked then return Finish(run, blocked, true) end
    if run.action == "delete" and KeepUnread() ~= run.keepUnread then
        return Finish(run, "The unread mail setting changed. Start deletion again.", true)
    end

    local index = run.targets[#run.targets]
    local message = current[index]
    local request, item = NextRequest(message, run.action, run.keepUnread)
    if not request then return Finish(run, "A letter is no longer eligible. Start again.", true) end
    if request == "item" and not item.isCurrency and C_Container.CalculateTotalNumberOfFreeBagSlots() == 0 then
        return Finish(run, "The bags are full. Stopped opening mail.", true)
    end

    local remaining
    if request == "item" or request == "money" then
        remaining = {}
        for key, value in pairs(message) do remaining[key] = value end
        if request == "money" then
            remaining.money = 0
        else
            remaining.itemCount = message.itemCount - 1
            remaining.attachments = {}
            for _, attachment in ipairs(message.attachments) do
                if attachment ~= item then remaining.attachments[#remaining.attachments + 1] = attachment end
            end
        end
    end

    run.expected = remaining
    run.timer = C_Timer.NewTimer(CONFIRMATION_TIMEOUT, function()
        if batch == run then Finish(run, "WoW did not confirm the mail action. Stopped the batch.", true) end
    end)
    if request == "money" then
        TakeInboxMoney(index)
    elseif request == "item" then
        TakeInboxItem(index, item.slot)
    elseif request == "return" then
        ReturnInboxItem(index)
    else
        DeleteInboxItem(index)
    end
    return true
end

local function ConfirmProgress(run)
    local current = Inbox.ReadLoaded()
    if Inbox.SameLoaded(run.messages, current) then return end
    local index = run.targets[#run.targets]
    local expected = run.expected
    local empty = not expected or (expected.money == 0 and expected.itemCount == 0)
    local removed = empty and Inbox.SameLoaded(run.messages, current, index)
    if not removed and (not expected or not Inbox.SameLoaded(run.messages, current, index, expected)) then
        return Finish(run, "The inbox changed unexpectedly. Stopped the batch.", true)
    end

    run.timer:Cancel()
    run.messages = current
    if removed or not NextRequest(current[index], run.action, run.keepUnread) then table.remove(run.targets) end
    if #run.targets == 0 then
        local result = run.action == "open" and "Finished opening mail."
            or run.action == "return" and "Mail returned." or "Empty mail deleted."
        return Finish(run, result)
    end
    Dispatch(run, current)
end

local function ScheduleProgress(run)
    if run.stepScheduled then return end
    run.stepScheduled = true
    C_Timer.After(COMMAND_INTERVAL, function()
        if batch ~= run then return end
        run.stepScheduled = false
        -- The update can arrive before the pending flag clears, with no second event.
        if C_Mail.IsCommandPending() then
            ScheduleProgress(run)
        else
            ConfirmProgress(run)
        end
    end)
end

local function Begin(run)
    run.confirming = false
    local current, total = Inbox.ReadLoaded()
    if total ~= run.total or not Inbox.SameLoaded(run.messages, current) then
        return Finish(run, "The inbox changed. Check the mail and start again.", true)
    end
    run.report("Processing mail...")
    return Dispatch(run, current)
end

StaticPopupDialogs[CONFIRMATION] = {
    text = "%s",
    button1 = YES,
    button2 = CANCEL,
    timeout = 0,
    hideOnEscape = true,
    ignoreKeys = true,
    OnAccept = function(_, run)
        if batch == run then Begin(run) end
    end,
    OnHide = function(_, run)
        if batch == run and run.confirming then
            run.confirming = false
            Finish(run)
        end
    end,
}

function Inbox.Start(action, messages, total, selected, report)
    if batch then return false, "Finish the current bulk mail action first." end
    local blocked = GetBlock()
    if blocked then return false, blocked end
    local targets, selectedCount = {}, 0
    local keepUnread = KeepUnread()
    for index, message in ipairs(messages) do
        if not selected or selected[index] then
            selectedCount = selectedCount + 1
            if NextRequest(message, action, keepUnread) then targets[#targets + 1] = index end
        end
    end
    if #targets == 0 then return false, "No eligible mail in that scope." end

    local run = {
        action = action, messages = messages, total = total, targets = targets, report = report, keepUnread = keepUnread,
    }
    batch = run
    if action == "open" then
        return Begin(run)
    end

    local scope = selected and ("%d selected"):format(selectedCount) or "all loaded"
    local prompt
    if action == "return" then
        prompt = ("Return %d eligible letter(s) from %s mail? Any items or gold go back to the sender."):format(#targets, scope)
    else
        local unread = keepUnread and "Unread letters stay in the inbox." or "This can include unread letters."
        prompt = ("Delete %d eligible letter(s) with no items or gold from %s mail? %s Letter text is also deleted.")
            :format(#targets, scope, unread)
    end
    run.confirming = true
    if not StaticPopup_Show(CONFIRMATION, prompt, nil, run) then
        if batch == run then Finish(run) end
        return false, "WoW could not show the confirmation. No mail was changed."
    end
    return true
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "MAIL_INBOX_UPDATE", "MAIL_SUCCESS", "MAIL_FAILED", "MAIL_CLOSED", "PLAYER_REGEN_DISABLED" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    local run = batch
    if not run then return end
    if event == "MAIL_CLOSED" or event == "PLAYER_REGEN_DISABLED" then
        Inbox.Cancel("Stopped the bulk mail action.")
    elseif event == "MAIL_FAILED" and not run.confirming then
        Finish(run, "WoW rejected the mail action. Stopped the batch.", true)
    elseif not run.confirming then
        ScheduleProgress(run)
    end
end)
