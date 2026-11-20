-- Wild: Tabbed mailbox with a searchable attachment grid
local ADDON_NAME, Wild = ...

local Inbox = Wild.InboxBulk
local PANEL_WIDTH, PANEL_HEIGHT = 526, 540
local PAGE_TOP, PAGE_FOOTER = 60, 52
local PLAN_WIDTH, PLAN_INSET, PLAN_TOP, PLAN_BOTTOM = 236, 12, 51, 112
local GRID_LEFT, GRID_TOP, GRID_RIGHT, GRID_BOTTOM = 12, 56, 27, PAGE_FOOTER + 44
local ICON_SIZE, ICON_STEP, ICON_BORDER_SIZE = 36, 41, 2
local ICON_BACKDROP = { edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = ICON_BORDER_SIZE }
local UNKNOWN_ITEM_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local RULE_INSTRUCTIONS = "Send the outgoing plan, one mail at a time."
local Lower = strlower or string.lower

local visit, panel, mailboxHooked, visibilityOverride, nativeLayout
local messages, loadedCount, totalCount = {}, 0, 0
local commandMessage, query
local waitingItems, requestedItems = {}, {}
local planItemRefreshPending
local selected, inboxRevision = {}, 0
local RequestAttachment, SelectPage

local BULK_ACTIONS = {
    { key = "open", width = 104, all = "Open all mail", selected = "Open selected",
      help = "Collect items and gold. Skips C.O.D. and GM mail." },
    { key = "return", width = 104, all = "Return all mail", selected = "Return selected",
      help = "Return eligible letters and anything in them to their senders. Requires confirmation." },
    { key = "delete", width = 136, all = "Delete all empty mail", selected = "Delete selected empty",
      help = "Delete eligible mail with no items or gold. Letter text is also deleted. Requires confirmation." },
}

local function MatchesItem(item)
    return query and query ~= "" and item.name and Lower(item.name):find(query, 1, true)
end

local function MatchesHeader(message)
    return not query or query == "" or Lower(message.sender):find(query, 1, true)
        or Lower(message.subject):find(query, 1, true)
end

local function MatchesMessage(message)
    if MatchesHeader(message) then return true end
    for _, item in ipairs(message.attachments) do
        if MatchesItem(item) then return true end
    end
    return false
end

local function EscapeText(text)
    return (text:gsub("|", "||"))
end

local function ReadCurrentMessage(index)
    local loaded, total = GetInboxNumItems()
    if loaded ~= loadedCount or (total or loaded) ~= totalCount then return end
    return Inbox.ReadMessage(index)
end

local function IsMailboxOpen()
    return visit and not visit.closed and MailFrame and MailFrame:IsVisible()
end

local function IsBrowserVisible()
    return nativeLayout and panel.items:IsVisible() and IsMailboxOpen()
end

local function IsReceivePage()
    return nativeLayout and IsMailboxOpen() and panel.page ~= "Send" and not OpenMailFrame:IsShown()
end

local function FindAttachment(message, slot)
    for _, item in ipairs(message.attachments) do
        if item.slot == slot then return item end
    end
end

local function Warn(message)
    if IsBrowserVisible() then panel.status:SetText(message) end
    Wild.Print("|cffff6600Wild:|r " .. message)
    return false
end

local function CreateText(parent, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetJustifyH("LEFT")
    return text
end

local function ClampPlanScroll(scroll)
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange()))
end

local function FormatPlannedMail(index, batch)
    local lines = { ("|cffffd100%d. To: %s|r"):format(index, EscapeText(batch.recipient)) }
    if batch.pending then lines[#lines + 1] = "Waiting for WoW to confirm" end
    local items = {}
    for _, item in ipairs(batch.items) do
        Wild.MergeItemActionEntries(items, {
            { key = item.link or item.itemID, link = item.link, itemID = item.itemID, count = item.count },
        })
    end
    for _, item in ipairs(items) do
        local name = item.link and item.link:match("|h%[(.-)%]|h")
        name = name or C_Item.GetItemInfo(item.itemID) or ("Item %d"):format(item.itemID)
        lines[#lines + 1] = ("%d x %s"):format(item.count, EscapeText(name))
    end
    return table.concat(lines, "\n")
end

function Wild.UpdateMailRulePlan(warning)
    if not nativeLayout or not IsMailboxOpen() then return end

    local plan, status = Wild.GetMailRulePlan()
    panel.rulePlan = plan
    local suffix = #plan == 1 and "message" or "messages"
    local summary
    if status == "unconfirmed" then
        summary = "Run stopped. Send not confirmed."
    elseif status == "running" then
        summary = #plan > 0 and ("%d %s remaining"):format(#plan, suffix) or "Checking bags for more matches."
    else
        summary = #plan > 0 and ("%d %s ready"):format(#plan, suffix) or "No bag items match enabled Mail rules."
    end
    panel.planSummary:SetText(summary)
    if warning then panel.ruleStatus:SetText(warning) end

    local hint = "Click Process rules on Send. Wild waits for WoW to confirm each message, then checks your bags for more matches."
    if Wild.GetSetting("mail.autoSend") == true then
        local automatic = visit.bypassed and "Run on open is skipped for this visit." or "Run on open is enabled."
        hint = automatic .. "\n\n" .. hint
    end
    panel.planHint:SetText(hint)

    local rows, content = panel.planRows, panel.planContent
    local height = 0
    for index, batch in ipairs(plan) do
        local row = rows[index]
        if not row then
            row = CreateText(content, "GameFontHighlightSmall")
            row:SetWidth(content:GetWidth())
            row:SetWordWrap(true)
            rows[index] = row
        end
        row:SetText(FormatPlannedMail(index, batch))
        row:SetPoint("TOPLEFT", 0, -height)
        row:Show()
        height = height + math.ceil(row:GetStringHeight()) + 10
    end
    for index = #plan + 1, #rows do rows[index]:Hide() end
    content:SetHeight(math.max(1, height))
    ClampPlanScroll(panel.planScroll)
end

local function CreateButton(parent, width, text, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function SetInboxTooltip(owner, message, slot)
    if not IsBrowserVisible() or not message or not Inbox.SameMessage(message, ReadCurrentMessage(message.index)) then return end
    local item = FindAttachment(message, slot)
    if not item then return end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if Inbox.HasItemIdentity(item) then
        GameTooltip:SetInboxItem(message.index, slot)
    else
        GameTooltip:SetText("Attachment not ready")
    end
    GameTooltip:AddLine(("Mail #%d, slot %d: %s"):format(message.index, slot, EscapeText(message.subject)), 1, 1, 1, true)
    GameTooltip:AddLine("From: " .. EscapeText(message.sender), 1, 1, 1, true)
    if message.cod > 0 then
        GameTooltip:AddLine("C.O.D.: " .. Wild.FormatGold(message.cod), 1, 0.82, 0)
        GameTooltip:AddLine("Open the letter on the List tab to confirm payment.", 1, 0.82, 0)
    elseif not Inbox.HasItemIdentity(item) then
        GameTooltip:AddLine("Wait for the attachment to load or use the WoW inbox.", 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

local function HideOwnedTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function GetQualityColor(quality)
    if issecretvalue and issecretvalue(quality) then return end
    return ITEM_QUALITY_COLORS[quality]
end

local function GetCapacityPattern()
    if type(CONTAINER_SLOTS) ~= "string" then return end
    -- Some locales put the bag type first with numbered format arguments.
    local format = CONTAINER_SLOTS:gsub("%%%d+%$([ds])", "%%%1")
    if not format:find("%d", 1, true) then return end
    local escaped = format:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return "^" .. escaped:gsub("%%%%([ds])", { d = "(%d+)", s = ".-" }) .. "$"
end

local function ReadAttachmentCapacity(index, item, pattern)
    if not pattern then return end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(item.itemID)
    if not classID then return nil, true end
    if classID ~= Enum.ItemClass.Container and classID ~= Enum.ItemClass.Quiver then return end

    local tooltip = C_TooltipInfo.GetInboxItem(index, item.slot)
    for _, line in ipairs(tooltip and tooltip.lines or {}) do
        local text = line.leftText
        if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
            local plainText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local capacity = tonumber(plainText:match(pattern))
            if capacity and capacity > 0 then return capacity end
        end
    end
    return nil, true
end

local function CreateGridIcon()
    local icon = CreateFrame("Button", nil, panel.grid, "BackdropTemplate")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetBackdrop(ICON_BACKDROP)
    icon.art = icon:CreateTexture(nil, "ARTWORK")
    icon.art:SetPoint("TOPLEFT", ICON_BORDER_SIZE, -ICON_BORDER_SIZE)
    icon.art:SetPoint("BOTTOMRIGHT", -ICON_BORDER_SIZE, ICON_BORDER_SIZE)
    local labelInset = ICON_BORDER_SIZE + 1
    icon.count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    icon.count:SetPoint("BOTTOMRIGHT", -labelInset, labelInset)
    icon.capacity = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    icon.capacity:SetPoint("TOPLEFT", labelInset, -labelInset)
    icon.capacity:SetTextColor(1, 0.82, 0)
    icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    icon:RegisterForClicks("LeftButtonUp")
    icon:SetScript("OnEnter", function(self)
        local stack = self.stack
        if stack then SetInboxTooltip(self, stack.message, stack.item.slot) end
    end)
    icon:SetScript("OnLeave", HideOwnedTooltip)
    icon:SetScript("OnHide", function(self)
        self.pressedStack = nil
        HideOwnedTooltip(self)
    end)
    icon:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self.pressedStack = self.stack end
    end)
    icon:SetScript("OnClick", function(self)
        local stack = self.pressedStack
        self.pressedStack = nil
        if stack and self:IsVisible() then RequestAttachment(stack.message, stack.item.slot) end
    end)
    return icon
end

local function BindGridIcon(icon, stack, row, column)
    if icon.stack == stack and icon.row == row and icon.column == column then return end
    -- Reflow can move the same stack, so changes to its position also cancel a press.
    icon.stack, icon.row, icon.column, icon.pressedStack = stack, row, column, nil
    HideOwnedTooltip(icon)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", panel.grid, "TOPLEFT", column * ICON_STEP, -row * ICON_STEP)
    local item = stack.item
    icon.art:SetTexture(item.icon or UNKNOWN_ITEM_ICON)
    icon.art:SetDesaturated(stack.message.cod > 0 or not Inbox.HasItemIdentity(item))
    local color = GetQualityColor(item.quality)
    if color then
        icon:SetBackdropBorderColor(color.r, color.g, color.b, 1)
    else
        icon:SetBackdropBorderColor(0, 0, 0, 0)
    end
    local count = item.count
    icon.count:SetText(count and count > 1 and tostring(count) or "")
    icon.capacity:SetText(item.capacity and tostring(item.capacity) or "")
    icon:Show()
end

local function BindGridIcons(offset)
    local columns = panel.gridColumns
    local firstRow = math.floor(offset / ICON_STEP)
    local endRow = math.ceil((offset + panel.gridScroll:GetHeight()) / ICON_STEP)
    local lastIndex = math.min(#panel.stacks, endRow * columns)
    local used = 0
    for index = firstRow * columns + 1, lastIndex do
        used = used + 1
        local icon = panel.gridIcons[used] or CreateGridIcon()
        panel.gridIcons[used] = icon
        BindGridIcon(icon, panel.stacks[index], math.floor((index - 1) / columns), (index - 1) % columns)
    end
    for index = used + 1, #panel.gridIcons do
        local icon = panel.gridIcons[index]
        icon:Hide()
        icon.stack, icon.pressedStack = nil, nil
        icon.art:SetTexture(nil)
        icon:SetBackdropBorderColor(0, 0, 0, 0)
        icon.count:SetText("")
        icon.capacity:SetText("")
    end
end

local function LayoutGrid(offset)
    local scroll = panel.gridScroll
    local rows = math.ceil(#panel.stacks / panel.gridColumns)
    panel.grid:SetHeight(math.max(1, rows * ICON_STEP - (ICON_STEP - ICON_SIZE)))
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(math.min(offset, math.floor(scroll:GetVerticalScrollRange())))
    BindGridIcons(scroll:GetVerticalScroll())
end

local function ResizeGrid(window, width, height)
    local scroll = window.gridScroll
    local offset = scroll:GetVerticalScroll()
    local gridWidth = width - GRID_LEFT - GRID_RIGHT
    window.gridColumns = math.max(1, math.floor((gridWidth + ICON_STEP - ICON_SIZE) / ICON_STEP))
    scroll:SetSize(gridWidth, height - PAGE_TOP - GRID_TOP - GRID_BOTTOM)
    window.grid:SetWidth(gridWidth)
    LayoutGrid(offset)
end

local STACK_SORT_KEYS = {
    name = function(stack)
        local name = stack.item.name
        if name and name ~= "" then return Lower(name) end
    end,
    sender = function(stack) return Lower(stack.message.sender) end,
    size = function(stack)
        local count = stack.item.count
        if count and count > 0 then return -count end
    end,
}

local function SortStacks(stacks, order)
    local getKey = STACK_SORT_KEYS[order]
    if not getKey then return end

    for _, stack in ipairs(stacks) do stack.sortKey = getKey(stack) end
    table.sort(stacks, function(left, right)
        if left.sortKey ~= right.sortKey then
            if left.sortKey == nil then return false end
            if right.sortKey == nil then return true end
            return left.sortKey < right.sortKey
        end
        if left.message.index ~= right.message.index then return left.message.index < right.message.index end
        return left.item.slot < right.item.slot
    end)
end

local function RenderGrid(resetScroll)
    local stacks = {}
    for index = 1, loadedCount do
        local message = messages[index]
        if message then
            local includeAll = MatchesHeader(message)
            for _, item in ipairs(message.attachments) do
                if includeAll or MatchesItem(item) then stacks[#stacks + 1] = { message = message, item = item } end
            end
        end
    end
    SortStacks(stacks, Wild.GetSetting("mail.inboxSort"))
    panel.stacks = stacks
    LayoutGrid(resetScroll and 0 or panel.gridScroll:GetVerticalScroll())

    local empty = ""
    if #stacks == 0 then
        empty = totalCount > 0 and loadedCount == 0 and "Waiting for mail to load."
            or query and query ~= "" and "No matching attachments." or "No attachments in loaded mail."
    end
    panel.gridEmpty:SetText(empty)
    panel.summary:SetText(("%d of %d messages loaded. %d stacks shown."):format(loadedCount, totalCount, #stacks))
end

local function UpdateRowChecks()
    if not panel then return end
    local show = IsReceivePage() and panel.page == "List"
    local busy = Inbox.IsBusy()
    for _, check in ipairs(panel.rowChecks) do
        local row = check.mailButton
        local index = show and row:IsShown() and row.index or nil
        if busy and row:IsEnabled() then
            row:SetEnabled(false)
            check.disabledMailButton = true
        elseif not busy and check.disabledMailButton then
            row:SetEnabled(true)
            check.disabledMailButton = nil
        end
        check.index = index
        check:SetChecked(index ~= nil and selected[index] == true)
        check:SetEnabled(not busy)
        check:SetShown(index ~= nil and not not messages[index])
    end
end

local function UpdateReceiveControls()
    if not panel then return end
    local visible = IsReceivePage()
    panel.receiveActions:SetShown(not not visible)
    UpdateRowChecks()
    if not visible then return end

    local count = 0
    for _ in pairs(selected) do count = count + 1 end
    for _, action in ipairs(BULK_ACTIONS) do
        local button = panel.bulkButtons[action.key]
        button:SetText(count > 0 and action.selected or action.all)
        button:SetEnabled(not Inbox.IsBusy())
    end
    local scope = count > 0 and ("%d selected"):format(count) or ("All loaded mail (%d)"):format(loadedCount)
    panel.receiveStatus:SetText(panel.bulkStatus and scope .. " - " .. panel.bulkStatus or scope)
end

local function RefreshInbox()
    local current, total = Inbox.ReadLoaded()
    local inboxSizeChanged = #current ~= loadedCount or total ~= totalCount
    if inboxSizeChanged or not Inbox.SameLoaded(messages, current) then
        inboxRevision = inboxRevision + 1
        if next(selected) and not Inbox.IsBusy() then panel.bulkStatus = "The inbox changed. Selection cleared." end
        selected = {}
    end
    loadedCount, totalCount = #current, total
    waitingItems = {}
    local capacityPattern = GetCapacityPattern()
    for _, message in ipairs(current) do
        if message then
            for _, item in ipairs(message.attachments) do
                if item.itemID and item.itemID > 0 and not item.isCurrency then
                    local capacity, capacityPending = ReadAttachmentCapacity(message.index, item, capacityPattern)
                    item.capacity = capacity
                    if capacityPending or not Inbox.HasItemIdentity(item) or not GetQualityColor(item.quality) then
                        waitingItems[item.itemID] = true
                    end
                end
            end
        end
    end
    messages = current

    if commandMessage then
        local updated = current[commandMessage.index]
        if inboxSizeChanged or not Inbox.SameMessage(commandMessage, updated) then
            commandMessage = nil
            panel.status:SetText("The selected message changed. Run the read command again.")
        else
            commandMessage = MatchesMessage(updated) and updated or nil
        end
    end
    RenderGrid(false)
    UpdateReceiveControls()
    for itemID in pairs(waitingItems) do
        if not requestedItems[itemID] then
            requestedItems[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
end

local function ReportBulk(message, warning)
    if panel then
        panel.bulkStatus = message
        UpdateReceiveControls()
    end
    if warning then return Warn(message) end
end

function Wild.SetInboxSelection(index, checked)
    if not IsReceivePage() then return ReportBulk("Open the List or Items tab in Wild Mail.", true) end
    if Inbox.IsBusy() then return ReportBulk("Finish the bulk mail action before changing the selection.", true) end
    if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or type(checked) ~= "boolean" then
        return ReportBulk("Enter a loaded mail number and on or off.", true)
    end
    local revision = inboxRevision
    RefreshInbox()
    if revision ~= inboxRevision then return ReportBulk("The inbox changed. Check the letter and select it again.", true) end
    if not messages[index] then return ReportBulk("Enter a loaded mail number.", true) end
    selected[index] = checked or nil
    inboxRevision = inboxRevision + 1
    ReportBulk()
    return true
end

function Wild.RunInboxBulk(action, scope)
    if action ~= "open" and action ~= "return" and action ~= "delete" then
        return ReportBulk("Choose open, return, or delete.", true)
    end
    if scope ~= nil and scope ~= "all" and scope ~= "selected" then
        return ReportBulk("Choose all or selected, or omit the scope to use the current selection.", true)
    end
    if not IsReceivePage() then return ReportBulk("Open the List or Items tab and close any open letter.", true) end
    if Inbox.IsBusy() then return ReportBulk("Finish the current bulk mail action first.", true) end

    local revision = inboxRevision
    RefreshInbox()
    if revision ~= inboxRevision then return ReportBulk("The inbox changed. Check the mail and start again.", true) end
    local checked = scope ~= "all" and next(selected) and selected or nil
    if scope == "selected" and not checked then return ReportBulk("Select mail on the List tab first.", true) end
    local started, warning = Inbox.Start(action, messages, totalCount, checked, ReportBulk)
    if not started then
        if warning then ReportBulk(warning, true) end
        return false
    end
    UpdateReceiveControls()
    return true
end

RequestAttachment = function(message, slot)
    if not IsBrowserVisible() then return Warn("Open the Items tab in Wild Mail.") end
    if Inbox.IsBusy() or Wild.IsMailSendBusy() then return Warn("Wait for the current batch before taking an attachment.") end
    if InCombatLockdown() then return Warn("Leave combat before taking an attachment.") end
    if GetCursorInfo() then return Warn("Clear the cursor before taking an attachment.") end
    if C_Mail.IsCommandPending() then return Warn("Wait for WoW to finish the current mail action.") end
    local current = ReadCurrentMessage(message.index)
    if not Inbox.SameMessage(message, current) then
        RefreshInbox()
        return Warn("The inbox changed. Check the attachment and try again.")
    end
    if current.cod ~= 0 then return Warn("Open the letter on the List tab to confirm C.O.D. payment.") end
    if not Inbox.HasItemIdentity(FindAttachment(current, slot)) then
        return Warn("The attachment is not ready. Wait for it to load or use the List tab.")
    end

    commandMessage = nil
    panel.status:SetText("")
    TakeInboxItem(message.index, slot)
    return true
end

local function AnchorPanel(window)
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", MailFrame, "TOPLEFT")
end

local function FinishResize(window)
    if not window.resizing then return end
    window.resizing = nil
    window:StopMovingOrSizing()
    -- WoW re-anchors the frame to the screen after sizing.
    AnchorPanel(window)
end

local function CreateResizeHandle(window)
    local handle = CreateFrame("Button", nil, window)
    handle:SetSize(16, 16)
    handle:SetPoint("BOTTOMRIGHT", -3, 3)
    handle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    handle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    handle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    handle:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            window.resizing = true
            window:StartSizing("BOTTOMRIGHT")
        end
    end)
    handle:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then FinishResize(window) end
    end)
end

local function CreateSendActions()
    panel.sendActions = CreateFrame("Frame", nil, panel.content)
    panel.sendActions:SetPoint("BOTTOMLEFT", 12, 8)
    panel.sendActions:SetPoint("BOTTOMRIGHT", -24, 8)
    panel.sendActions:SetHeight(42)
    panel.sendActions:Hide()
    local process = CreateButton(panel.sendActions, 112, "Process rules", function(self)
        local reviewed = self.reviewedPlan or panel.rulePlan
        self.reviewedPlan = nil
        local _, message = Wild.RunMailIntents(reviewed)
        panel.ruleStatus:SetText(message or RULE_INSTRUCTIONS)
    end)
    process:SetPoint("BOTTOMLEFT")
    process:SetScript("OnMouseDown", function(self) self.reviewedPlan = panel.rulePlan end)
    process:SetScript("OnHide", function(self) self.reviewedPlan = nil end)
    panel.ruleStatus = CreateText(panel.sendActions, "GameFontHighlightSmall")
    panel.ruleStatus:SetPoint("TOPLEFT")
    panel.ruleStatus:SetPoint("TOPRIGHT")
    panel.ruleStatus:SetText(RULE_INSTRUCTIONS)
    panel.sendActions:SetScript("OnHide", function()
        panel.ruleStatus:SetText(RULE_INSTRUCTIONS)
    end)
end

local function CreateBulkActions()
    local footer = CreateFrame("Frame", nil, panel.content)
    footer:SetPoint("BOTTOMLEFT", 12, 8)
    footer:SetPoint("BOTTOMRIGHT", -24, 8)
    footer:SetHeight(42)
    footer:Hide()
    panel.receiveActions = footer
    panel.receiveStatus = CreateText(footer, "GameFontHighlightSmall")
    panel.receiveStatus:SetPoint("TOPLEFT")
    panel.receiveStatus:SetPoint("TOPRIGHT")
    panel.receiveStatus:SetWordWrap(false)
    panel.bulkButtons = {}

    local previous
    for _, action in ipairs(BULK_ACTIONS) do
        local button = CreateButton(footer, action.width, action.all, function(self)
            local pressed = self.pressedRevision
            self.pressedRevision = nil
            if pressed and pressed ~= inboxRevision then
                return ReportBulk("The inbox or selection changed. Check the mail and try again.", true)
            end
            Wild.RunInboxBulk(action.key)
        end)
        button:SetScript("OnMouseDown", function(self) self.pressedRevision = inboxRevision end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(action.help, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", HideOwnedTooltip)
        button:SetScript("OnHide", function(self)
            self.pressedRevision = nil
            HideOwnedTooltip(self)
        end)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 6, 0) else button:SetPoint("BOTTOMLEFT") end
        panel.bulkButtons[action.key] = button
        previous = button
    end
end

local function CreateListChecks()
    panel.rowChecks = {}
    for index = 1, INBOXITEMS_TO_DISPLAY do
        local row, button = _G["MailItem" .. index], _G["MailItem" .. index .. "Button"]
        if row and button then
            local check = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
            check:SetSize(22, 22)
            check:SetPoint("RIGHT", row, "LEFT", -3, 0)
            check:Hide()
            check.mailButton = button
            check:SetScript("OnMouseDown", function(self)
                self.pressedIndex, self.pressedRevision = self.index, inboxRevision
            end)
            check:SetScript("OnClick", function(self)
                local pressed, revision = self.pressedIndex, self.pressedRevision
                self.pressedIndex, self.pressedRevision = nil, nil
                if self.index and self:IsVisible()
                    and (not revision or (pressed == self.index and revision == inboxRevision))
                    and Wild.SetInboxSelection(self.index, not not self:GetChecked()) then
                    PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                        or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
                else
                    UpdateRowChecks()
                end
            end)
            panel.rowChecks[#panel.rowChecks + 1] = check
        end
    end
end

local function CreateItemsPage()
    panel.items = CreateFrame("Frame", nil, panel.content)
    panel.items:SetPoint("TOPLEFT", 0, -PAGE_TOP)
    panel.items:SetPoint("BOTTOMRIGHT", 0, PAGE_FOOTER)
    panel.items:Hide()
    panel.search = CreateFrame("EditBox", nil, panel.items, "SearchBoxTemplate")
    panel.search:SetAutoFocus(false)
    panel.search:SetHeight(24)
    panel.search:SetPoint("TOPLEFT", 18, -5)
    panel.search:SetPoint("TOPRIGHT", -36, -5)
    if panel.search.Instructions then panel.search.Instructions:SetText("Sender, subject, or attachment") end
    panel.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    panel.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    panel.summary = CreateText(panel.items, "GameFontHighlightSmall")
    panel.summary:SetPoint("TOPLEFT", 12, -35)
    panel.summary:SetPoint("TOPRIGHT", -12, -35)
    local instruction = CreateText(panel.items, "GameFontHighlightSmall")
    instruction:SetPoint("BOTTOMLEFT", 12, 27)
    instruction:SetText("Hover for details. Click to take a stack.")
    panel.status = CreateText(panel.items, "GameFontNormalSmall")
    panel.status:SetPoint("BOTTOMLEFT", 12, 12)
    panel.status:SetPoint("BOTTOMRIGHT", -30, 12)
    panel.status:SetWordWrap(false)

    panel.gridScroll = CreateFrame("ScrollFrame", nil, panel.items, "UIPanelScrollFrameTemplate")
    panel.gridScroll:SetPoint("TOPLEFT", GRID_LEFT, -GRID_TOP)
    panel.grid = CreateFrame("Frame", nil, panel.gridScroll)
    panel.grid:SetSize(1, 1)
    panel.gridScroll:SetScrollChild(panel.grid)
    panel.gridIcons, panel.stacks = {}, {}
    panel.gridEmpty = CreateText(panel.grid, "GameFontHighlight")
    panel.gridEmpty:SetPoint("TOPLEFT")
    panel.gridEmpty:SetPoint("TOPRIGHT")

    panel.gridScroll:HookScript("OnVerticalScroll", function(_, offset) BindGridIcons(offset) end)
    panel.items:SetScript("OnHide", function()
        panel.search:ClearFocus()
    end)
    panel.search:HookScript("OnTextChanged", function(self)
        query = Lower(strtrim(self:GetText()))
        if not IsBrowserVisible() then return end
        if commandMessage and not MatchesMessage(commandMessage) then commandMessage = nil end
        panel.status:SetText("")
        RenderGrid(true)
    end)
end

local function CreateMailRulePlan()
    local sidebar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", 8, -PAGE_TOP)
    sidebar:SetPoint("BOTTOMLEFT", 8, 8)
    sidebar:SetWidth(PLAN_WIDTH - 12)
    sidebar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    })
    sidebar:SetBackdropColor(0.045, 0.045, 0.06, 1)
    sidebar:SetBackdropBorderColor(0.29, 0.29, 0.33, 1)
    local title = CreateText(sidebar, "GameFontNormal")
    title:SetPoint("TOPLEFT", PLAN_INSET, -PLAN_INSET)
    title:SetText("Outgoing plan")
    panel.planSummary = CreateText(sidebar, "GameFontHighlightSmall")
    panel.planSummary:SetPoint("TOPLEFT", PLAN_INSET, -29)
    panel.planSummary:SetPoint("TOPRIGHT", -PLAN_INSET, -29)
    panel.planHint = CreateText(sidebar, "GameFontHighlightSmall")
    panel.planHint:SetPoint("BOTTOMLEFT", PLAN_INSET, PLAN_INSET)
    panel.planHint:SetPoint("BOTTOMRIGHT", -PLAN_INSET, PLAN_INSET)

    local scroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PLAN_INSET, -PLAN_TOP)
    scroll:SetWidth(PLAN_WIDTH - 12 - PLAN_INSET - 26)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(scroll:GetWidth(), 1)
    scroll:SetScrollChild(content)
    panel.planScroll, panel.planContent, panel.planRows = scroll, content, {}
end

local function ResizePanel(window, width, height)
    ResizeGrid(window, width - PLAN_WIDTH, height)
    window.planScroll:SetHeight(height - PAGE_TOP - 8 - PLAN_TOP - PLAN_BOTTOM)
    ClampPlanScroll(window.planScroll)
end

local function CreatePanel()
    panel = CreateFrame("Frame", nil, MailFrame, "BackdropTemplate")
    panel:Hide()
    panel:SetIgnoreParentAlpha(true)
    AnchorPanel(panel)
    -- Retail offsets its controls within a larger page; Forever stretches the page to these bounds.
    local nativeWidth, nativeHeight = MailFrame:GetWidth(), MailFrame:GetHeight()
    local minWidth = math.max(460, math.max(nativeWidth, OpenMailFrame:GetWidth()) + 76)
    local minHeight = PAGE_TOP + math.max(nativeHeight, OpenMailFrame:GetHeight()) + PAGE_FOOTER
    panel:SetSize(math.max(PANEL_WIDTH, minWidth) + PLAN_WIDTH, math.max(PANEL_HEIGHT, minHeight))
    panel:SetResizable(true)
    panel:SetResizeBounds(minWidth + PLAN_WIDTH, minHeight)
    panel:SetDontSavePosition(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        if nativeLayout and nativeLayout.wheel and panel.page == "List" and not OpenMailFrame:IsShown() then
            local wheel = MailFrame:GetScript("OnMouseWheel")
            if wheel then wheel(MailFrame, delta) end
        end
    end)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    })
    panel:SetBackdropColor(0.06, 0.06, 0.08, 1)
    panel:SetBackdropBorderColor(0.29, 0.29, 0.33, 1)
    local title = CreateText(panel, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("Wild Mail")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() HideUIPanel(MailFrame) end)

    panel.content = CreateFrame("Frame", nil, panel)
    panel.content:SetPoint("TOPLEFT", PLAN_WIDTH, 0)
    panel.content:SetPoint("BOTTOMRIGHT")
    panel.tabs = {}
    for index, page in ipairs({ "List", "Items", "Send" }) do
        local tab = CreateButton(panel.content, 72, page, function() SelectPage(page) end)
        tab:SetPoint("TOPLEFT", 12 + (index - 1) * 76, -32)
        panel.tabs[page] = tab
    end
    panel.native = CreateFrame("Frame", nil, panel.content)
    panel.native:SetSize(nativeWidth, nativeHeight)
    panel.native:SetPoint("TOP", panel.content, "TOP", 0, -PAGE_TOP)
    CreateBulkActions()
    CreateListChecks()
    CreateSendActions()
    CreateItemsPage()
    CreateMailRulePlan()
    ResizePanel(panel, panel:GetWidth(), panel:GetHeight())
    CreateResizeHandle(panel)
    panel:SetScript("OnSizeChanged", ResizePanel)
    panel:SetScript("OnHide", FinishResize)
end

local function MountPage(frame, isLetter)
    local layout = {
        parent = frame:GetParent(), alpha = frame:GetAlpha(), mouse = frame:IsMouseEnabled(),
        strata = frame:GetFrameStrata(), level = frame:GetFrameLevel(), points = {},
    }
    for index = 1, frame:GetNumPoints() do layout.points[index] = { frame:GetPoint(index) } end

    frame:ClearAllPoints()
    frame:SetParent(panel.native)
    frame:SetFrameStrata(panel:GetFrameStrata())
    frame:SetFrameLevel(panel.native:GetFrameLevel() + (isLetter and 3 or 1))
    if isLetter then
        frame:SetPoint("TOP", panel.native, "TOP")
    else
        for _, point in ipairs(layout.points) do
            frame:SetPoint(point[1], panel.native, point[3], point[4], point[5])
        end
    end
    return layout
end

local function RestorePage(frame, layout)
    frame:ClearAllPoints()
    frame:SetParent(layout.parent)
    frame:SetFrameStrata(layout.strata)
    frame:SetFrameLevel(layout.level)
    frame:SetAlpha(layout.alpha)
    frame:EnableMouse(layout.mouse)
    for _, point in ipairs(layout.points) do frame:SetPoint(unpack(point, 1, 5)) end
end

local function UpdateLetterPage()
    if not nativeLayout then return end
    local isReading = panel.page == "List" and OpenMailFrame:IsShown()
    local showInbox = panel.page == "List" and not isReading
    InboxFrame:SetShown(showInbox)
    -- Keep the letter open for native Reply, but put it below the mouse-enabled shell on other tabs.
    OpenMailFrame:SetAlpha(isReading and nativeLayout.letter.alpha or 0)
    OpenMailFrame:SetFrameStrata(isReading and panel:GetFrameStrata() or "BACKGROUND")
    OpenMailFrame:EnableMouse(isReading and nativeLayout.letter.mouse)
    if OpenMailFrame:IsShown() then Inbox.Cancel("Opened a letter. Stopped the bulk mail action.") end
    UpdateReceiveControls()
end

local function ShowPage(page)
    panel.page = page
    local showItems = page == "Items"
    local wasShowingItems = panel.items:IsShown()
    panel.items:SetShown(showItems)
    panel.sendActions:SetShown(page == "Send")
    if page == "Send" then Inbox.Cancel("Switched to Send. Stopped the bulk mail action.") end
    for name, tab in pairs(panel.tabs) do
        if name == page then tab:LockHighlight() else tab:UnlockHighlight() end
    end
    UpdateLetterPage()
    if showItems and not wasShowingItems then RefreshInbox() end
end

local function HideNativeBulkActions()
    if not nativeLayout then return end
    if OpenAllMail then OpenAllMail:Hide() end
    local footer = InboxFrame.gamepadFooter
    if footer and footer.isShown then
        footer:HideAndDeactivateBindings()
        nativeLayout.gamepadFooterHidden = true
    end
end

SelectPage = function(page)
    if panel.page == page then return end
    panel.page = page
    MailFrameTab_OnClick(nil, page == "Send" and 2 or 1)
end

local function MountMailbox()
    -- Reparenting an open letter to a hidden host would run its native close script.
    panel:Show()
    nativeLayout = {
        alpha = MailFrame:GetAlpha(), mouse = MailFrame:IsMouseEnabled(), wheel = MailFrame:IsMouseWheelEnabled(),
        close = MailFrame.CloseButton and MailFrame.CloseButton:IsShown(),
        inboxTab = MailFrameTab1:IsShown(), sendTab = MailFrameTab2:IsShown(),
        inboxArt = InboxFrameBg and InboxFrameBg:IsShown(),
        openAll = OpenAllMail and OpenAllMail:IsShown(),
        inbox = MountPage(InboxFrame), send = MountPage(SendMailFrame), letter = MountPage(OpenMailFrame, true),
    }
    MailFrame:SetAlpha(0)
    MailFrame:EnableMouse(false)
    MailFrame:EnableMouseWheel(false)
    MailFrameTab1:Hide()
    MailFrameTab2:Hide()
    if MailFrame.CloseButton then MailFrame.CloseButton:Hide() end
    if InboxFrameBg then InboxFrameBg:Hide() end
    visit.inboxBrowserOpened = true
    HideNativeBulkActions()
    RefreshInbox()
    Wild.UpdateMailRulePlan()
    ShowPage(SendMailFrame:IsShown() and "Send" or OpenMailFrame:IsShown() and "List" or "Items")
end

local function RestoreMailbox()
    local layout = nativeLayout
    local restricted = GameLimitedMode_IsActive and GameLimitedMode_IsActive()
    nativeLayout = nil
    Inbox.Cancel("Closed Wild Mail. Stopped the bulk mail action.")
    selected, inboxRevision = {}, inboxRevision + 1
    panel.bulkStatus = nil
    UpdateReceiveControls()
    -- Moving the letter back first avoids its native OnHide when the Wild shell is hidden.
    RestorePage(OpenMailFrame, layout.letter)
    RestorePage(InboxFrame, layout.inbox)
    RestorePage(SendMailFrame, layout.send)
    panel:Hide()
    panel.rulePlan = nil
    panel.planScroll:SetVerticalScroll(0)
    panel.items:Hide()
    panel.sendActions:Hide()
    if IsMailboxOpen() and (restricted or (panel.page ~= "Send" and not InboxFrame:IsShown())) then
        MailFrameTab_OnClick(nil, 1)
    end
    if InboxFrameBg then InboxFrameBg:SetShown(layout.inboxArt) end
    local gamepad = Wild.isForever and InputUtil and InputUtil.IsGamepadUIEnabled()
    if OpenAllMail then OpenAllMail:SetShown(not gamepad and layout.openAll) end
    if gamepad and layout.gamepadFooterHidden and InboxFrame:IsVisible() then
        InboxFrame.gamepadFooter:ShowAndActivateBindings()
    end
    if MailFrame.CloseButton then MailFrame.CloseButton:SetShown(layout.close) end
    MailFrameTab1:SetShown(layout.inboxTab)
    MailFrameTab2:SetShown(layout.sendTab and not restricted)
    MailFrame:EnableMouse(layout.mouse)
    MailFrame:EnableMouseWheel(layout.wheel)
    MailFrame:SetAlpha(layout.alpha)
    panel.page = nil
end

local function UpdateVisibility()
    if not mailboxHooked then return end
    local showBrowser = visibilityOverride
    if showBrowser == nil then showBrowser = Wild.IsFeatureEnabled("inbox") end
    if showBrowser and IsMailboxOpen() and not (GameLimitedMode_IsActive and GameLimitedMode_IsActive()) then
        if not nativeLayout and not InCombatLockdown() then
            if not panel then CreatePanel() end
            MountMailbox()
        end
    elseif nativeLayout then
        RestoreMailbox()
    end
end

local function OnNativeTabChanged()
    if nativeLayout then
        ShowPage(SendMailFrame:IsShown() and "Send" or panel.page == "Items" and "Items" or "List")
    else
        -- WoW stores the original MailFrame_Show callback, which calls the global tab handler.
        UpdateVisibility()
    end
end

local function AttachToMailbox()
    if mailboxHooked or not MailFrame or not InboxFrame or not OpenMailFrame or not SendMailFrame
        or not MailFrameTab1 or not MailFrameTab2 or not MailFrameTab_OnClick then return end
    mailboxHooked = true
    MailFrame:HookScript("OnHide", UpdateVisibility)
    OpenMailFrame:HookScript("OnShow", UpdateLetterPage)
    OpenMailFrame:HookScript("OnHide", UpdateLetterPage)
    MailFrameTab2:HookScript("OnShow", function(self)
        if nativeLayout then
            nativeLayout.sendTab = true
            self:Hide()
        end
    end)
    if OpenAllMail then
        OpenAllMail:HookScript("OnShow", function(self)
            if nativeLayout then
                nativeLayout.openAll = true
                self:Hide()
            end
        end)
    end
    hooksecurefunc("MailFrameTab_OnClick", OnNativeTabChanged)
    if Wild.isForever and InboxFrame.Update then
        hooksecurefunc(InboxFrame, "Update", UpdateRowChecks)
        if InboxFrame.FocusGamepad then hooksecurefunc(InboxFrame, "FocusGamepad", HideNativeBulkActions) end
    elseif InboxFrame_Update then
        hooksecurefunc("InboxFrame_Update", UpdateRowChecks)
    end
end

local function ShowWildMailboxForVisit()
    if not IsMailboxOpen() then return Warn("Open a mailbox to use Wild Mail.") end
    AttachToMailbox()
    if not mailboxHooked or (GameLimitedMode_IsActive and GameLimitedMode_IsActive()) then
        return Warn("Wild Mail is not available. Use the native mailbox.")
    end
    if not nativeLayout and InCombatLockdown() then return Warn("Leave combat before opening Wild Mail.") end
    visibilityOverride = true
    UpdateVisibility()
    return true
end

--- Show the outgoing plan without switching tabs or sending mail.
function Wild.ShowMailRulePlan()
    if not ShowWildMailboxForVisit() then return false end
    Wild.UpdateMailRulePlan()
    return true
end

--- Open Wild Mail to the Items tab for this visit and optionally replace its search.
function Wild.ShowInboxBrowser(search)
    if search ~= nil and type(search) ~= "string" then return Warn("Enter text to search the inbox.") end
    if not ShowWildMailboxForVisit() then return false end
    SelectPage("Items")
    if search then panel.search:SetText(search) end
    return true
end

function Wild.HideInboxBrowser()
    visibilityOverride = false
    UpdateVisibility()
end

function Wild.UpdateInboxBrowser()
    if not visit then return end
    visibilityOverride = nil
    UpdateVisibility()
end

function Wild.UpdateInboxBrowserSort()
    if IsBrowserVisible() then RenderGrid(true) end
end

--- Print a numbered letter in chat and select it for the take command.
function Wild.ReadInboxMessage(index)
    if not IsBrowserVisible() then return Warn("Open the Items tab in Wild Mail.") end
    local message = messages[index]
    if not message or not MatchesMessage(message) then return Warn("Enter a message number that matches the current search.") end
    if not Inbox.SameMessage(message, ReadCurrentMessage(index)) then
        RefreshInbox()
        return Warn("The inbox changed. Select a message again.")
    end

    -- Only the explicit read command calls GetInboxText, which marks the letter as read.
    commandMessage = message
    local text = GetInboxText(index)
    panel.status:SetText("")
    print(("|cff00ccffWild:|r Mail #%d from %s: %s"):format(index, EscapeText(message.sender), EscapeText(message.subject)))
    if text and text ~= "" then print(EscapeText(text)) end
    return true
end

--- Request one numbered attachment from the selected message, not a bulk take.
function Wild.TakeInboxAttachment(index, slot)
    if not IsBrowserVisible() or not commandMessage or commandMessage.index ~= index then
        return Warn("Use /wild inbox read <message> before taking a numbered attachment.")
    end
    return RequestAttachment(commandMessage, slot)
end

local events = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE",
    "ITEM_DATA_LOAD_RESULT", "TRIAL_STATUS_UPDATE", "PLAYER_REGEN_ENABLED",
    "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
}) do
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
        visit, visibilityOverride, commandMessage = nil, nil, nil
        selected, inboxRevision = {}, inboxRevision + 1
        messages, waitingItems, requestedItems, query = {}, {}, {}, nil
        loadedCount, totalCount = 0, 0
        UpdateVisibility()
        if panel then
            panel.search:SetText("")
            panel.status:SetText("")
            panel.bulkStatus = nil
            RenderGrid(true)
        end
    elseif event == "ADDON_LOADED" and argument == "Blizzard_MailFrame" then
        AttachToMailbox()
        UpdateVisibility()
    elseif event == "TRIAL_STATUS_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
        UpdateVisibility()
    elseif event == "ITEM_DATA_LOAD_RESULT" and success then
        if not nativeLayout or not IsMailboxOpen() then return end
        if waitingItems[argument] then RefreshInbox() end
        if not planItemRefreshPending then
            planItemRefreshPending = true
            C_Timer.After(0, function()
                planItemRefreshPending = nil
                Wild.UpdateMailRulePlan()
            end)
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED" then
        Wild.UpdateMailRulePlan()
    elseif event == "MAIL_INBOX_UPDATE" then
        if nativeLayout and IsMailboxOpen() then RefreshInbox() end
    end
end)
