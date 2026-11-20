-- Wild: Search and take individual attachments from the loaded inbox
local ADDON_NAME, Wild = ...

local PANEL_WIDTH, PANEL_HEIGHT = 526, 430
local MESSAGE_HEIGHT, ATTACHMENT_HEIGHT = 46, 30
local UNKNOWN_ITEM_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local Lower = strlower or string.lower

local visit, panel, browseButton, wantsBrowser
local messages, loadedCount, totalCount = {}, 0, 0
local selected, body, query
local waitingItems, requestedItems = {}, {}

local function ReadMessage(index)
    local _, stationery, sender, subject, money, cod, daysLeft, itemCount = GetInboxHeaderInfo(index)
    if not daysLeft or money == nil or cod == nil then return end

    local message = {
        index = index, stationery = stationery, sender = sender or "Unknown sender",
        subject = subject and subject ~= "" and subject or "(No subject)",
        money = money, cod = cod, itemCount = itemCount or 0, attachments = {},
    }
    if message.itemCount == 0 then return message end

    for slot = 1, ATTACHMENTS_MAX_RECEIVE do
        if HasInboxItem(index, slot) then
            local name, itemID, icon, count, _, _, isCurrency = GetInboxItem(index, slot)
            local link = GetInboxItemLink(index, slot)
            message.attachments[#message.attachments + 1] = {
                slot = slot, itemID = itemID, icon = icon, count = count, isCurrency = isCurrency, link = link,
                name = name or (link and link:match("|h%[(.-)%]|h")),
            }
            if #message.attachments == message.itemCount then break end
        end
    end
    return message
end

local function HasItemIdentity(item)
    return item and item.name and item.itemID and item.itemID > 0 and item.count and item.count > 0
        and (item.link or item.isCurrency)
end

local function SameAttachment(before, now)
    return before and now and before.slot == now.slot and before.itemID == now.itemID
        and before.link == now.link and before.count == now.count and before.isCurrency == now.isCurrency
end

local function SameMessage(before, now)
    if not now or before.index ~= now.index or before.sender ~= now.sender or before.subject ~= now.subject
        or before.stationery ~= now.stationery or before.money ~= now.money or before.cod ~= now.cod
        or before.itemCount ~= now.itemCount or #before.attachments ~= #now.attachments then
        return false
    end
    for position, item in ipairs(before.attachments) do
        if not SameAttachment(item, now.attachments[position]) then return false end
    end
    return true
end

local function FindMatchingAttachment(message)
    if not query or query == "" then return end
    for _, item in ipairs(message.attachments) do
        if item.name and Lower(item.name):find(query, 1, true) then return item end
    end
end

local function MatchesQuery(message)
    return not query or query == "" or Lower(message.sender):find(query, 1, true)
        or Lower(message.subject):find(query, 1, true) or FindMatchingAttachment(message)
end

local function EscapeText(text)
    return (text:gsub("|", "||"))
end

local function ReadCurrentMessage(index)
    local loaded, total = GetInboxNumItems()
    if loaded ~= loadedCount or (total or loaded) ~= totalCount then return end
    return ReadMessage(index)
end

local function IsInboxVisible()
    return visit and not visit.closed and MailFrame and MailFrame:IsVisible() and InboxFrame and InboxFrame:IsVisible()
        and not (OpenMailFrame and OpenMailFrame:IsVisible())
end

local function IsBrowserVisible()
    return panel and panel:IsVisible() and IsInboxVisible()
end

local function Warn(message)
    if IsBrowserVisible() then panel.status:SetText(message) end
    Wild.Print("|cffff6600Wild:|r " .. message)
    return false
end

local function CreateText(parent, width, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    return text
end

local function CreateButton(parent, width, text, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function CreateCommandButton(parent, getCommand)
    local button = CreateButton(parent, 20, "/", function()
        StaticPopup_Show("WILD_NATIVE_COMMAND", nil, nil, getCommand())
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(EscapeText(getCommand()), 1, 1, 1)
        GameTooltip:AddLine("Click /, then press Ctrl+C to copy.", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function CreateScroll(parent, x, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -87)
    scroll:SetSize(width, 299)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    return scroll, content
end

local function CreateMessageRow(position)
    local row = CreateFrame("Button", nil, panel.results)
    row:SetSize(184, MESSAGE_HEIGHT)
    row:SetPoint("TOPLEFT", panel.results, "TOPLEFT", 0, -(position - 1) * MESSAGE_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.subject = CreateText(row, 180, "GameFontHighlight")
    row.subject:SetPoint("TOPLEFT", 2, -2)
    row.subject:SetWordWrap(false)
    row.sender = CreateText(row, 180, "GameFontHighlightSmall")
    row.sender:SetPoint("TOPLEFT", 2, -18)
    row.sender:SetWordWrap(false)
    row.preview = CreateText(row, 180, "GameFontHighlightSmall")
    row.preview:SetPoint("TOPLEFT", 2, -31)
    row.preview:SetWordWrap(false)
    row:SetScript("OnClick", function(self) Wild.ReadInboxMessage(self.index) end)
    return row
end

local function FormatAttachmentPreview(message)
    local item = FindMatchingAttachment(message)
    local label = item and (item.name .. (item.count and " x" .. item.count or "")) or ""
    if label == "" and message.itemCount > 0 then label = message.itemCount .. " attachments" end
    if message.cod > 0 then return "C.O.D.  " .. label end
    if label == "" and message.money > 0 then return "Enclosed money" end
    return label
end

local function RenderResults(resetScroll)
    local count = 0
    for index = 1, loadedCount do
        local message = messages[index]
        if message and MatchesQuery(message) then
            count = count + 1
            local row = panel.messageRows[count] or CreateMessageRow(count)
            panel.messageRows[count] = row
            row.index = index
            row.subject:SetText(("#%d  %s"):format(index, EscapeText(message.subject)))
            row.sender:SetText(EscapeText(message.sender))
            row.preview:SetText(EscapeText(FormatAttachmentPreview(message)))
            local isSelected = selected and selected.index == index
            row.subject:SetTextColor(1, isSelected and 0.82 or 1, isSelected and 0 or 1)
            row:Show()
        end
    end
    for position = count + 1, #panel.messageRows do
        local row = panel.messageRows[position]
        row:Hide()
        row.subject:SetText("")
        row.sender:SetText("")
        row.preview:SetText("")
    end
    panel.results:SetHeight(math.max(MESSAGE_HEIGHT, count * MESSAGE_HEIGHT))
    if resetScroll then panel.resultsScroll:SetVerticalScroll(0) end
    panel.summary:SetText(("%d of %d messages loaded. %d shown."):format(loadedCount, totalCount, count))
    local empty = ""
    if count == 0 then
        empty = totalCount == 0 and "No mail in the inbox."
            or loadedCount == 0 and "Waiting for mail to load." or "No matching messages."
    end
    panel.empty:SetText(empty)
end

local function CreateAttachmentRow()
    local row = CreateFrame("Frame", nil, panel.details)
    row:SetSize(282, ATTACHMENT_HEIGHT)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name = CreateText(row, 170, "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.take = CreateButton(row, 54, "Take", function()
        if selected then Wild.TakeInboxAttachment(selected.index, row.slot) end
    end)
    row.take:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    row.command = CreateCommandButton(row, function()
        return ("/wild inbox take %d %d"):format(selected.index, row.slot)
    end)
    row.command:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not IsBrowserVisible() or not selected or not SameMessage(selected, ReadCurrentMessage(selected.index)) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetInboxItem(selected.index, self.slot)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnHide", function(self)
        if GameTooltip and (GameTooltip:IsOwned(self) or GameTooltip:IsOwned(self.command)) then GameTooltip:Hide() end
    end)
    return row
end

local function PlaceText(text, y, value)
    text:SetPoint("TOPLEFT", text:GetParent(), "TOPLEFT", 0, -y)
    text:SetText(value)
    return y + math.ceil(text:GetStringHeight()) + 6
end

local function RenderDetails(resetScroll)
    local instruction = "Select a message to read it and view its attachments."
    local y = PlaceText(panel.subject, 0, selected and EscapeText(selected.subject) or instruction)
    y = PlaceText(panel.sender, y, selected and ("From: " .. EscapeText(selected.sender)) or "")
    local money = ""
    if selected and selected.cod > 0 then
        money = "C.O.D.: " .. Wild.FormatGold(selected.cod) .. "\nUse the WoW inbox to confirm payment."
    elseif selected and selected.money > 0 then
        money = "Enclosed: " .. Wild.FormatGold(selected.money)
    end
    if money ~= "" then y = PlaceText(panel.money, y, money) else panel.money:SetText("") end

    local attachments = selected and selected.attachments or {}
    local isLoading = selected and #attachments < selected.itemCount
    for position, item in ipairs(attachments) do
        local row = panel.attachmentRows[position] or CreateAttachmentRow()
        panel.attachmentRows[position] = row
        row.slot = item.slot
        row:SetPoint("TOPLEFT", panel.details, "TOPLEFT", 0, -y)
        row.icon:SetTexture(item.icon or UNKNOWN_ITEM_ICON)
        local label = item.name or "Loading attachment"
        local color = query and query ~= "" and Lower(label):find(query, 1, true)
        row.name:SetTextColor(1, color and 0.82 or 1, color and 0 or 1)
        row.name:SetText(("#%d  %s%s"):format(item.slot, EscapeText(label), item.count and (" x" .. item.count) or ""))
        local hasIdentity = not not HasItemIdentity(item)
        isLoading = isLoading or not hasIdentity
        row.take:SetEnabled(selected.cod == 0 and hasIdentity)
        row.command:SetShown(selected.cod == 0 and hasIdentity)
        row:Show()
        y = y + ATTACHMENT_HEIGHT
    end
    for position = #attachments + 1, #panel.attachmentRows do
        local row = panel.attachmentRows[position]
        row:Hide()
        row.name:SetText("")
        row.icon:SetTexture(nil)
    end
    if isLoading then
        y = PlaceText(panel.loading, y, "Some attachments are not ready. Wait for them to load or use the WoW inbox.")
    else
        panel.loading:SetText("")
    end
    y = PlaceText(panel.body, y + 4, EscapeText(body or ""))
    panel.details:SetHeight(y)
    if resetScroll then panel.detailsScroll:SetVerticalScroll(0) end
end

local function RefreshInbox()
    local loaded, total = GetInboxNumItems()
    total = total or loaded
    local inboxSizeChanged = loaded ~= loadedCount or total ~= totalCount
    loadedCount, totalCount = loaded, total
    local current = {}
    waitingItems = {}
    for index = 1, loadedCount do
        local message = ReadMessage(index)
        current[index] = message
        if message then
            for _, item in ipairs(message.attachments) do
                if item.itemID and item.itemID > 0 and not item.isCurrency and not HasItemIdentity(item) then
                    waitingItems[item.itemID] = true
                end
            end
        end
    end
    messages = current

    local selectionChanged = selected and (inboxSizeChanged or not SameMessage(selected, current[selected.index]))
    if selectionChanged then
        selected, body = nil, nil
        panel.status:SetText("The selected message changed. Select it again.")
    elseif selected then
        selected = current[selected.index]
        if not MatchesQuery(selected) then selected, body = nil, nil end
    end
    RenderResults(false)
    RenderDetails(selectionChanged)
    for itemID in pairs(waitingItems) do
        if not requestedItems[itemID] then
            requestedItems[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
end

local function CreatePanel()
    panel = CreateFrame("Frame", nil, MailFrame, "BackdropTemplate")
    panel:Hide()
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    })
    panel:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    panel:SetBackdropBorderColor(0.29, 0.29, 0.33, 1)
    local title = CreateText(panel, 400, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("Wild Mail Browser")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() Wild.HideInboxBrowser() end)

    panel.search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    panel.search:SetAutoFocus(false)
    panel.search:SetSize(472, 24)
    panel.search:SetPoint("TOPLEFT", 18, -35)
    if panel.search.Instructions then panel.search.Instructions:SetText("Sender, subject, or attachment") end
    panel.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    panel.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local command = CreateCommandButton(panel, function()
        local search = strtrim(panel.search:GetText())
        return search ~= "" and "/wild inbox search " .. search or "/wild inbox search"
    end)
    command:SetPoint("LEFT", panel.search, "RIGHT", 4, 0)
    panel:SetScript("OnHide", function() panel.search:ClearFocus() end)

    panel.summary = CreateText(panel, PANEL_WIDTH - 24, "GameFontHighlightSmall")
    panel.summary:SetPoint("TOPLEFT", 12, -65)
    panel.status = CreateText(panel, PANEL_WIDTH - 24, "GameFontNormalSmall")
    panel.status:SetPoint("BOTTOMLEFT", 12, 12)
    panel.resultsScroll, panel.results = CreateScroll(panel, 12, 184)
    panel.detailsScroll, panel.details = CreateScroll(panel, 218, 282)
    panel.messageRows, panel.attachmentRows = {}, {}
    panel.empty = CreateText(panel.results, 184, "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", 2, -2)
    for _, field in ipairs({ "subject", "sender", "money", "loading", "body" }) do
        panel[field] = CreateText(panel.details, 282, field == "subject" and "GameFontNormal" or "GameFontHighlight")
    end
    panel.search:HookScript("OnTextChanged", function(self)
        query = Lower(strtrim(self:GetText()))
        if not IsBrowserVisible() then return end
        if selected and not MatchesQuery(selected) then selected, body = nil, nil end
        panel.status:SetText("")
        RenderResults(true)
        RenderDetails(false)
    end)
end

local function UpdateVisibility()
    if not browseButton then return end
    local inboxVisible = IsInboxVisible()
    browseButton:SetShown(inboxVisible and not wantsBrowser or false)
    if inboxVisible and wantsBrowser then
        if not panel then CreatePanel() end
        if not panel:IsShown() then
            panel:Show()
            RefreshInbox()
        end
    elseif panel then
        panel:Hide()
    end
end

local function AttachToMailbox()
    if browseButton or not MailFrame or not InboxFrame or not OpenMailFrame then return end
    browseButton = CreateButton(MailFrame, 112, "Browse Mail", function() Wild.ShowInboxBrowser() end)
    browseButton:Hide()
    browseButton:SetClampedToScreen(true)
    browseButton:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
    for _, frame in ipairs({ MailFrame, InboxFrame, OpenMailFrame }) do
        frame:HookScript("OnShow", UpdateVisibility)
        frame:HookScript("OnHide", UpdateVisibility)
    end
end

--- Open the browser at the visible Inbox tab and optionally replace its search.
function Wild.ShowInboxBrowser(search)
    if search ~= nil and type(search) ~= "string" then return Warn("Enter text to search the inbox.") end
    if not IsInboxVisible() then return Warn("Open the WoW Inbox tab and close any open message to browse mail.") end
    AttachToMailbox()
    if not browseButton then return Warn("The WoW inbox controls are not available.") end
    visit.inboxBrowserOpened = true
    wantsBrowser = true
    UpdateVisibility()
    if search then panel.search:SetText(search) end
    return true
end

function Wild.HideInboxBrowser()
    wantsBrowser = false
    UpdateVisibility()
end

function Wild.UpdateInboxBrowser()
    if not visit then return end
    wantsBrowser = Wild.IsFeatureEnabled("inbox")
    if wantsBrowser then visit.inboxBrowserOpened = true end
    UpdateVisibility()
end

--- Open a numbered search result; this marks that message as read.
function Wild.ReadInboxMessage(index)
    if not IsBrowserVisible() then return Warn("Open Browse Mail at a mailbox first.") end
    local message = messages[index]
    if not message or not MatchesQuery(message) then return Warn("Select a message shown in Browse Mail.") end
    if not SameMessage(message, ReadCurrentMessage(index)) then
        RefreshInbox()
        return Warn("The inbox changed. Select a message again.")
    end

    -- GetInboxText marks the mail as read. Call it only for the player's selection.
    selected, body = message, nil
    local text = GetInboxText(index)
    if selected and SameMessage(message, selected) then body = text end
    panel.status:SetText("")
    RenderResults(false)
    RenderDetails(true)
    return true
end

--- Request one numbered attachment from the selected message, not a bulk take.
function Wild.TakeInboxAttachment(index, slot)
    if not IsBrowserVisible() or not selected or selected.index ~= index then
        return Warn("Select this message in Browse Mail before taking an attachment.")
    end
    if InCombatLockdown() then return Warn("Leave combat before taking an attachment.") end
    if GetCursorInfo() then return Warn("Clear the cursor before taking an attachment.") end
    if C_Mail.IsCommandPending() then return Warn("Wait for WoW to finish the current mail action.") end
    local current = ReadCurrentMessage(index)
    if not SameMessage(selected, current) then
        RefreshInbox()
        return Warn("The inbox changed. Select the message and check its attachments again.")
    end
    if current.cod ~= 0 then return Warn("Use the WoW inbox to confirm C.O.D. payment.") end
    local attachment
    for _, item in ipairs(current.attachments) do
        if item.slot == slot then attachment = item; break end
    end
    if not HasItemIdentity(attachment) then return Warn("Select a loaded attachment in this message.") end

    -- Each take requires a fresh selection. Do not retry or report success for a request.
    selected, body = nil, nil
    RenderResults(false)
    RenderDetails(true)
    panel.status:SetText("")
    TakeInboxItem(index, slot)
    return true
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "ITEM_DATA_LOAD_RESULT" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, argument, success)
    if event == "MAIL_SHOW" and Wild.db then
        local current = Wild.OpenIntentVisit("mail")
        AttachToMailbox()
        if visit ~= current then
            visit = current
            Wild.UpdateInboxBrowser()
        else
            UpdateVisibility()
        end
    elseif event == "MAIL_CLOSED" then
        visit, wantsBrowser, selected, body = nil, nil, nil, nil
        messages, waitingItems, requestedItems, query = {}, {}, {}, nil
        loadedCount, totalCount = 0, 0
        UpdateVisibility()
        if panel then
            panel.search:SetText("")
            panel.status:SetText("")
            RenderResults(true)
            RenderDetails(true)
        end
    elseif event == "ADDON_LOADED" and argument == "Blizzard_MailFrame" then
        AttachToMailbox()
        UpdateVisibility()
    elseif event == "MAIL_INBOX_UPDATE" or (event == "ITEM_DATA_LOAD_RESULT" and success and waitingItems[argument]) then
        if IsBrowserVisible() then RefreshInbox() end
    end
end)
