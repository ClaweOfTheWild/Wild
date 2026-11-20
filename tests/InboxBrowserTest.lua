-- Run from the repository root with Lua 5.1: lua tests\InboxBrowserTest.lua
local function Equal(actual, expected)
    assert(actual == expected, "Expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function NewMailbox(saved, forever)
    local frames, timers, chat, reads, takes, nativeReply = {}, {}, {}, {}, {}, {}
    local state = { bulkCalls = 0, pending = false, itemLoads = {}, itemClasses = {} }
    local requests = {}
    local env = setmetatable({
        WildDB = saved, SlashCmdList = {}, tremove = table.remove,
        StaticPopupDialogs = {}, INBOXITEMS_TO_DISPLAY = 7,
        strtrim = function(value) return value:match("^%s*(.-)%s*$") end,
        print = function(line) chat[#chat + 1] = line end,
        IsShiftKeyDown = function() return false end,
        InCombatLockdown = function() return state.combat end,
        GetCursorInfo = function() return state.cursor end,
        GetBuildInfo = function() return "", "", "", forever and 16001 or 120105 end,
        WOW_PROJECT_ID = forever and 18 or 1, WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CAMELOT = 18,
        ATTACHMENTS_MAX_RECEIVE = 16,
        CONTAINER_SLOTS = forever and "%2$s [%1$d places]" or "%d Slot %s",
        Enum = { ItemClass = { Consumable = 0, Container = 1, Quiver = 11 } },
        ITEM_QUALITY_COLORS = {
            [0] = { r = 0.62, g = 0.62, b = 0.62 },
            [1] = { r = 1, g = 1, b = 1 },
            [3] = { r = 0, g = 0.44, b = 0.87 },
            [4] = { r = 0.64, g = 0.21, b = 0.93 },
        },
        C_Timer = {
            After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end,
            NewTimer = function(delay, callback)
                local timer = { delay = delay, callback = callback, Cancel = function(self) self.cancelled = true end }
                timers[#timers + 1] = timer
                return timer
            end,
        },
        C_Mail = { IsCommandPending = function() return state.pending end },
        C_Container = { CalculateTotalNumberOfFreeBagSlots = function() return state.freeSlots or 10 end },
        C_Item = { RequestLoadItemDataByID = function(itemID)
            state.itemLoads[#state.itemLoads + 1] = itemID
        end },
        AutoLootMailItem = function() state.bulkCalls = state.bulkCalls + 1 end,
        GetMoneyString = function(copper) return copper .. " copper" end,
        PlaySound = function() end,
        SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 },
    }, { __index = _G })
    env._G = env

    local methods = {}
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:GetParent() return self.parent end
    function methods:SetParent(parent)
        local wasVisible = self:IsVisible()
        self.parent = parent
        local visible = self:IsVisible()
        local script = self.scripts[visible and "OnShow" or "OnHide"]
        if visible ~= wasVisible and script then script(self) end
    end
    function methods:GetAlpha() return self.alpha or 1 end
    function methods:SetAlpha(alpha) self.alpha = alpha end
    function methods:SetIgnoreParentAlpha(ignore) self.ignoreParentAlpha = ignore end
    function methods:GetEffectiveAlpha()
        return self:GetAlpha() * (self.parent and not self.ignoreParentAlpha and self.parent:GetEffectiveAlpha() or 1)
    end
    function methods:GetFrameLevel() return self.level or 1 end
    function methods:SetFrameLevel(level) self.level = level end
    function methods:GetFrameStrata() return self.strata or "MEDIUM" end
    function methods:SetFrameStrata(strata) self.strata = strata end
    function methods:EnableMouse(enabled) self.mouseEnabled = enabled end
    function methods:IsMouseEnabled() return self.mouseEnabled or false end
    function methods:EnableMouseWheel(enabled) self.mouseWheelEnabled = enabled end
    function methods:IsMouseWheelEnabled() return self.mouseWheelEnabled or false end
    function methods:SetScript(event, script) self.scripts[event] = script end
    function methods:GetScript(event) return self.scripts[event] end
    function methods:HookScript(event, script)
        local original = self.scripts[event]
        self.scripts[event] = function(...)
            if original then original(...) end
            script(...)
        end
    end
    function methods:IsShown() return self.shown end
    function methods:IsVisible()
        return self.shown and (not self.parent or self.parent:IsVisible())
    end
    function methods:SetShown(shown)
        local visibility = {}
        for _, frame in ipairs(frames) do visibility[frame] = frame:IsVisible() end
        self.shown = shown
        for _, frame in ipairs({ unpack(frames) }) do
            local visible = frame:IsVisible()
            local event = visible and "OnShow" or "OnHide"
            if visible ~= visibility[frame] and frame.scripts[event] then frame.scripts[event](frame) end
        end
    end
    function methods:Show() self:SetShown(true) end
    function methods:Hide() self:SetShown(false) end
    function methods:SetEnabled(enabled) self.enabled = enabled end
    function methods:IsEnabled() return self.enabled end
    function methods:SetChecked(checked) self.checked = checked end
    function methods:GetChecked() return self.checked end
    function methods:SetText(text)
        self.text = text
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
    end
    function methods:GetText() return self.text or "" end
    function methods:Press()
        assert(self:IsVisible() and self.enabled and self.scripts.OnClick, "Button cannot be clicked")
        if self.scripts.OnMouseDown then self.scripts.OnMouseDown(self, "LeftButton") end
    end
    function methods:Release()
        if self.kind == "CheckButton" then self:SetChecked(not self:GetChecked()) end
        self.scripts.OnClick(self, "LeftButton")
    end
    function methods:Click()
        self:Press()
        if self:IsVisible() then self:Release() end
    end
    function methods:SetSize(width, height)
        if self.width == width and self.height == height then return end
        self.width, self.height = width, height
        if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, width, height) end
    end
    function methods:SetWidth(width) self:SetSize(width, self.height) end
    function methods:SetHeight(height) self:SetSize(self.width, height) end
    function methods:GetWidth() return self.width end
    function methods:GetHeight() return self.height end
    function methods:SetPoint(point, ...)
        self.anchors = self.anchors or {}
        local anchor = { point, ... }
        for index, previous in ipairs(self.anchors) do
            if previous[1] == point then self.anchors[index] = anchor; return end
        end
        self.anchors[#self.anchors + 1] = anchor
    end
    function methods:ClearAllPoints() self.anchors = nil end
    function methods:GetNumPoints() return self.anchors and #self.anchors or 0 end
    function methods:GetPoint(index) return unpack(self.anchors[index or 1]) end
    function methods:SetResizable(resizable) self.resizable = resizable end
    function methods:SetResizeBounds(minWidth, minHeight) self.minWidth, self.minHeight = minWidth, minHeight end
    function methods:StartSizing(point)
        assert(self.resizable, "The resize handle's parent must allow sizing")
        self.sizing = point
    end
    function methods:DragSize(width, height)
        assert(self.sizing, "Drag requires pressing the resize handle first")
        self:SetSize(math.max(self.minWidth, width), math.max(self.minHeight, height))
    end
    function methods:StopMovingOrSizing()
        self.sizing = nil
        self:ClearAllPoints()
    end
    function methods:SetScrollChild(child) self.scrollChild = child end
    function methods:GetVerticalScroll() return self.scroll or 0 end
    function methods:GetVerticalScrollRange() return math.max(0, self.scrollChild.height - self.height) end
    function methods:SetVerticalScroll(offset)
        self.scroll = offset
        if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self, offset) end
    end
    function methods:SetTexture(texture) self.texture = texture end
    function methods:SetBackdrop(backdrop) self.backdrop = backdrop end
    function methods:SetBackdropBorderColor(...) self.borderColor = { ... } end
    for _, method in ipairs({
        "SetAllPoints", "RegisterForClicks", "SetDontSavePosition", "UpdateScrollChildRect",
        "SetClampedToScreen", "SetBackdropColor",
        "SetJustifyH", "SetWordWrap", "SetTextColor", "SetAutoFocus", "ClearFocus",
        "SetNormalTexture", "SetPushedTexture", "SetHighlightTexture", "SetDesaturated",
        "LockHighlight", "UnlockHighlight",
    }) do
        methods[method] = function() end
    end
    env.CreateFrame = function(kind, _, parent)
        local frame = setmetatable({
            kind = kind, parent = parent, shown = true, enabled = true, events = {}, scripts = {},
        }, { __index = methods })
        frames[#frames + 1] = frame
        return frame
    end
    function methods:CreateFontString() return env.CreateFrame("FontString", nil, self) end
    function methods:CreateTexture() return env.CreateFrame("Texture", nil, self) end

    local tooltip = { lines = {} }
    function tooltip:SetOwner(owner)
        self.owner, self.index, self.slot, self.lines = owner, nil, nil, {}
    end
    function tooltip:IsOwned(owner) return self.owner == owner end
    function tooltip:SetInboxItem(index, slot) self.index, self.slot = index, slot end
    function tooltip:SetText(text) self.lines = { text } end
    function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tooltip:Show() self.shown = true end
    function tooltip:Hide() self.owner, self.shown = nil, false end
    env.GameTooltip = tooltip

    env.MailFrame = env.CreateFrame("Frame")
    env.MailFrame:SetSize(338, 424)
    env.MailFrame:EnableMouse(true)
    env.MailFrame:EnableMouseWheel(true)
    env.MailFrame:SetScript("OnMouseWheel", function(_, delta) state.inboxWheel = delta end)
    env.MailFrame.CloseButton = env.CreateFrame("Button", nil, env.MailFrame)
    env.MailFrameTab1 = env.CreateFrame("Button", nil, env.MailFrame)
    env.MailFrameTab2 = env.CreateFrame("Button", nil, env.MailFrame)
    env.InboxFrame = env.CreateFrame("Frame", nil, env.MailFrame)
    env.InboxFrame:SetPoint("TOPLEFT", env.MailFrame, "TOPLEFT")
    env.OpenAllMail = env.CreateFrame("Button", nil, env.InboxFrame)
    env.OpenAllMail:SetText("Native Open All")
    env.InboxFrame.pageNum = 1
    if forever then
        env.InputUtil = { IsGamepadUIEnabled = function() return state.gamepad end }
        local footer = { isShown = false }
        footer.HideAndDeactivateBindings = function(self) self.isShown = false end
        footer.ShowAndActivateBindings = function(self) self.isShown = true end
        env.InboxFrame.gamepadFooter = footer
        env.InboxFrame.FocusGamepad = function() footer:ShowAndActivateBindings() end
    end
    for row = 1, env.INBOXITEMS_TO_DISPLAY do
        local name = "MailItem" .. row
        env[name] = env.CreateFrame("Frame", nil, env.InboxFrame)
        env[name .. "Button"] = env.CreateFrame("Button", nil, env[name])
    end
    env.SendMailFrame = env.CreateFrame("Frame", nil, env.MailFrame)
    env.SendMailFrame:SetPoint("TOPLEFT", env.MailFrame, "TOPLEFT")
    if forever then
        env.InboxFrame:SetPoint("BOTTOMRIGHT", env.MailFrame, "BOTTOMRIGHT")
        env.SendMailFrame:SetPoint("BOTTOMRIGHT", env.MailFrame, "BOTTOMRIGHT")
    end
    env.SendMailFrame:Hide()
    env.OpenMailFrame = env.CreateFrame("Frame")
    env.OpenMailFrame:SetSize(338, 424)
    env.OpenMailFrame:SetPoint("TOPLEFT", env.MailFrame, "TOPRIGHT", 6, 0)
    env.OpenMailFrame:SetScript("OnHide", function() env.InboxFrame.openMailID = nil end)
    env.MailFrame:SetScript("OnHide", function() env.OpenMailFrame:Hide() end)
    env.MailFrame:Hide()
    env.OpenMailFrame:Hide()
    env.MailFrameTab_OnClick = function(_, tab)
        env.InboxFrame:SetShown(tab == 1)
        env.SendMailFrame:SetShown(tab == 2)
        if tab == 1 then
            if forever then
                env.InboxFrame:Update()
                if state.gamepad then env.InboxFrame:FocusGamepad() end
            else
                env.InboxFrame_Update()
            end
        end
    end
    env.MailFrame_Show = function()
        env.MailFrame:Show()
        env.MailFrameTab_OnClick(nil, 1)
    end
    local showNativeMailbox = env.MailFrame_Show
    env.GameLimitedMode_IsActive = function() return state.trial or false end
    local nativeEvents = env.CreateFrame("Frame")
    nativeEvents:RegisterEvent("TRIAL_STATUS_UPDATE")
    nativeEvents:SetScript("OnEvent", function() env.MailFrameTab2:SetShown(not state.trial) end)
    env.hooksecurefunc = function(owner, name, callback)
        if type(owner) == "string" then owner, name, callback = env, owner, name end
        local original = assert(owner[name])
        owner[name] = function(...)
            original(...)
            callback(...)
        end
    end

    local function Item(itemID, name, count)
        return {
            id = itemID, name = name, count = count, quality = 1,
            link = "|Hitem:" .. itemID .. "|h[" .. name .. "]|h",
        }
    end
    state.inbox = {
        { sender = "Beekeeper", subject = "Supplies", body = "Here are the supplies.", money = 70,
            slots = { [1] = Item(100, "Wax", 4), [4] = Item(101, "Honey Cake", 2) } },
        { sender = "Courier", subject = "Private note", body = "Unread letter.", slots = {} },
        { sender = "Merchant", subject = "Special delivery", cod = 100000,
            slots = { [2] = Item(102, "Honey Cake: Deluxe", 1) } },
        { sender = "Scribe", subject = "100% complete", slots = {} },
    }

    env.GetInboxNumItems = function() return #state.inbox, state.total or #state.inbox end
    local function UpdateNativeList()
        for row = 1, env.INBOXITEMS_TO_DISPLAY do
            local button = env["MailItem" .. row .. "Button"]
            button.index = (env.InboxFrame.pageNum - 1) * env.INBOXITEMS_TO_DISPLAY + row
            button:SetShown(button.index <= #state.inbox)
        end
    end
    if forever then env.InboxFrame.Update = UpdateNativeList else env.InboxFrame_Update = UpdateNativeList end
    env.GetInboxHeaderInfo = function(index)
        local message = state.inbox[index]
        if not message or message.unavailable then return end
        local count = 0
        for _ in pairs(message.slots) do count = count + 1 end
        return nil, 1, message.sender, message.subject, message.money or 0, message.cod or 0,
            15, count > 0 and count or nil, message.wasRead, message.wasReturned, nil, nil, message.isGM
    end
    env.HasInboxItem = function(index, slot) return state.inbox[index].slots[slot] ~= nil end
    env.GetInboxItem = function(index, slot)
        local item = state.inbox[index].slots[slot]
        if item then return item.name, item.id, 70000 + item.id, item.count, item.quality end
    end
    env.GetInboxItemLink = function(index, slot)
        local item = state.inbox[index].slots[slot]
        return item and item.link
    end
    env.C_Item.GetItemInfoInstant = function(itemID)
        return itemID, nil, nil, nil, nil, state.itemClasses[itemID] or env.Enum.ItemClass.Consumable
    end
    env.C_TooltipInfo = { GetInboxItem = function(index, slot)
        local item = state.inbox[index].slots[slot]
        if item.tooltip then
            local lines = {}
            for _, text in ipairs(item.tooltip) do lines[#lines + 1] = { leftText = text } end
            return { lines = lines }
        end
    end }
    env.GetInboxText = function(index)
        reads[#reads + 1] = index
        state.inbox[index].wasRead = true
        return state.inbox[index].body
    end
    env.InboxItemCanDelete = function(index)
        local message = state.inbox[index]
        if message.legacyReturnable then return nil end
        return not message.returnable
    end
    local function Request(action, index, slot)
        assert(not state.pending, "Only one native mail command may be pending")
        requests[#requests + 1] = { action = action, index = index, slot = slot, message = state.inbox[index] }
        state.pending = true
    end
    env.TakeInboxItem = function(index, slot)
        takes[#takes + 1] = { index = index, slot = slot }
        Request("item", index, slot)
    end
    env.TakeInboxMoney = function(index) Request("money", index) end
    env.DeleteInboxItem = function(index) Request("delete", index) end
    env.ReturnInboxItem = function(index) Request("return", index) end

    local Wild = {}
    local function Load(path) setfenv(assert(loadfile(path)), env)("Wild", Wild) end
    local function Fire(event, ...)
        if event == "MAIL_INBOX_UPDATE" then
            if forever then env.InboxFrame:Update() else env.InboxFrame_Update() end
        end
        for _, frame in ipairs({ unpack(frames) }) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    local function Acknowledge(autoRemove, keepPending)
        local request = assert(requests[#requests])
        local message = request.message
        if request.action == "item" then
            message.slots[request.slot] = nil
        elseif request.action == "money" then
            message.money = 0
        end
        if autoRemove or request.action == "return" or request.action == "delete" then
            table.remove(state.inbox, request.index)
            if state.total then state.total = state.total - 1 end
        end
        state.pending = not not keepPending
        Fire("MAIL_INBOX_UPDATE")
    end
    local function Open(eventFirst)
        if eventFirst then Fire("MAIL_SHOW") end
        showNativeMailbox()
        if not eventFirst then Fire("MAIL_SHOW") end
        Fire("MAIL_INBOX_UPDATE")
    end
    local function Close()
        env.MailFrame:Hide()
        Fire("MAIL_CLOSED")
    end
    env.HideUIPanel = function(frame)
        if frame == env.MailFrame then Close() else frame:Hide() end
    end
    local function FindButton(text)
        for _, frame in ipairs(frames) do
            if frame.kind == "Button" and frame:IsVisible() and frame:GetText() == text then return frame end
        end
    end
    local function HasText(text)
        for _, frame in ipairs(frames) do
            if frame:IsVisible() and frame:GetText():find(text, 1, true) then return true end
        end
        return false
    end
    local function HasChildText(parent, text)
        for _, child in ipairs(frames) do
            if child.parent == parent and child:GetText() == text then return true end
        end
        return false
    end
    local function IconLabels(icon)
        local labels = {}
        for _, child in ipairs(frames) do
            if child.kind == "FontString" and child.parent == icon and child:IsVisible() and child:GetText() ~= "" then
                labels[#labels + 1] = child:GetText()
            end
        end
        table.sort(labels)
        return table.concat(labels, ", ")
    end
    local function IconBorder(icon)
        local color = icon.borderColor
        if icon:IsVisible() and icon.backdrop and icon.backdrop.edgeFile and color and color[4] > 0 then
            return table.concat(color, ", ")
        end
    end
    local function RunTimers(matches)
        local queued = timers
        timers = {}
        for _, timer in ipairs(queued) do
            if not timer.cancelled then
                if matches(timer.delay) then timer.callback() else timers[#timers + 1] = timer end
            end
        end
    end
    local function HidePopup(which)
        local popup = state.popup
        if popup and popup.which == which then
            state.popup = nil
            local dialog = env.StaticPopupDialogs[which]
            if dialog.OnHide then dialog.OnHide(popup, popup.data) end
        end
    end
    env.StaticPopup_Show = function(which, text, _, data)
        local popup = { which = which, text = text, data = data }
        state.popup = popup
        return popup
    end
    env.StaticPopup_Hide = HidePopup
    local function AnswerPopup(accept)
        local popup = assert(state.popup, "Expected a confirmation")
        local definition = assert(env.StaticPopupDialogs[popup.which])
        local handler = accept and definition.OnAccept or not accept and definition.OnCancel
        if handler then handler(popup, popup.data) end
        HidePopup(popup.which)
    end
    local function Selection(row)
        for _, frame in ipairs(frames) do
            if frame.kind == "CheckButton" and frame.parent == env["MailItem" .. row] and frame:IsVisible() then
                return frame
            end
        end
    end
    local function FindIcon(itemID, stackCount)
        for _, texture in ipairs(frames) do
            if texture.kind == "Texture" and texture.texture == 70000 + itemID
                and texture.parent.kind == "Button" and texture:IsVisible()
                and (not stackCount or HasChildText(texture.parent, tostring(stackCount))) then
                return texture.parent
            end
        end
    end
    local function VisibleScroll()
        for _, frame in ipairs(frames) do
            if frame.kind == "ScrollFrame" and frame:IsVisible() then
                return frame
            end
        end
        error("No visible scroll area")
    end
    local function ScrollGrid(toEnd)
        local scroll = VisibleScroll()
        scroll:SetVerticalScroll(toEnd and scroll:GetVerticalScrollRange() or 0)
    end
    local function ResizeHandle()
        for _, frame in ipairs(frames) do
            if frame.kind == "Button" and frame:IsVisible() and frame.scripts.OnMouseDown
                and frame.scripts.OnMouseUp and frame:GetPoint() == "BOTTOMRIGHT" then
                return frame
            end
        end
        error("No visible corner resize handle")
    end

    Load("Core.lua")
    Load("Conditions.lua")
    Load("Mail.lua")
    Load("InboxBulk.lua")
    Load("InboxBrowser.lua")
    Load("SlashCommands.lua")
    Fire("ADDON_LOADED", "Wild")

    return {
        state = state, env = env, wild = Wild, open = Open, close = Close, fire = Fire, hasText = HasText,
        reads = reads, takes = takes, chat = chat, command = env.SlashCmdList.WILD,
        runBulkTimer = function() RunTimers(function(delay) return delay == 0.5 or delay == 0.35 end) end,
        advance = function() RunTimers(function(delay) return delay < 0.35 end) end,
        expire = function() RunTimers(function(delay) return delay >= 1 end) end,
        requests = requests, ack = Acknowledge, answer = AnswerPopup, selection = Selection,
        page = function(page)
            env.InboxFrame.pageNum = page
            if forever then env.InboxFrame:Update() else env.InboxFrame_Update() end
        end,
        findIcon = FindIcon, iconLabels = IconLabels, iconBorder = IconBorder,
        scrollGrid = ScrollGrid, tooltip = tooltip, item = Item,
        resizeHandle = ResizeHandle, visibleScroll = VisibleScroll, button = FindButton, nativeReply = nativeReply,
        reply = function()
            env.MailFrameTab_OnClick(nil, 2)
            nativeReply.id = env.InboxFrame.openMailID
        end,
    }
end

local function AssertIconOrder(mail, ...)
    local previousX, previousY
    for _, itemID in ipairs({ ... }) do
        local icon = assert(mail.findIcon(itemID), "Missing icon for " .. itemID)
        local _, _, _, x, y = icon:GetPoint()
        assert(not previousY or y < previousY or (y == previousY and x > previousX),
            "Icon for " .. itemID .. " is out of order")
        previousX, previousY = x, y
    end
end

for _, forever in ipairs({ false, true }) do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } }, forever)
    local bag = mail.item(110, "Linen Bag", 1)
    local quiver = mail.item(111, "Leather Quiver", 1)
    local slots = mail.state.inbox[1].slots
    local bagSize = forever and "Sac [10 places]" or "10 Slot Bag"
    slots[1], slots[8] = bag, quiver
    mail.state.itemClasses[110] = mail.env.Enum.ItemClass.Container
    mail.state.itemClasses[111] = mail.env.Enum.ItemClass.Quiver
    bag.tooltip = { "Linen Bag", "Item Level 5", "|cffffffff" .. bagSize .. "|r" }
    slots[4].tooltip = { bagSize }

    mail.open()
    Equal(mail.iconLabels(assert(mail.findIcon(110))), "10")
    Equal(mail.iconLabels(assert(mail.findIcon(101))), "2")
    Equal(mail.iconLabels(assert(mail.findIcon(111))), "")
    Equal(mail.state.itemLoads[1], 111, "Request missing capacity data even when the item link is ready")
    assert(not mail.tooltip.shown, "Capacity labels do not open the hover tooltip")

    mail.command("inbox search honey cake")
    Equal(mail.iconLabels(assert(mail.findIcon(101))), "2", "A recycled icon must not retain its bag capacity")
    assert(not mail.findIcon(110))

    mail.command("inbox search leather quiver")
    quiver.tooltip = { forever and "Carquois [16 places]" or "16 Slot Quiver" }
    mail.fire("ITEM_DATA_LOAD_RESULT", 111, true)
    Equal(mail.iconLabels(assert(mail.findIcon(111))), "16", "The badge appears when the item data arrives")
    assert(not mail.findIcon(110), "Loading bag data does not clear the active search")

    mail.command("inbox search")
    Equal(mail.iconLabels(assert(mail.findIcon(110))), "10")
    Equal(mail.iconLabels(assert(mail.findIcon(111))), "16")
    Equal(#mail.reads, 0)
    assert(mail.findIcon(110)):Click()
    Equal(mail.takes[1].index, 1)
    Equal(mail.takes[1].slot, 1)
end

for _, forever in ipairs({ false, true }) do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } }, forever)
    local slots = mail.state.inbox[1].slots
    slots[1].quality, slots[4].quality = 3, -1
    slots[8] = mail.item(112, "Torn Cloth", 1)
    slots[8].quality = 0

    mail.open()
    Equal(mail.iconBorder(assert(mail.findIcon(100))), "0, 0.44, 0.87, 1")
    Equal(mail.iconBorder(assert(mail.findIcon(112))), "0.62, 0.62, 0.62, 1")
    Equal(mail.iconBorder(assert(mail.findIcon(102))), "1, 1, 1, 1")
    Equal(mail.state.itemLoads[1], 101)

    mail.command("inbox select 1 on")
    mail.command("inbox search honey cake")
    Equal(mail.iconBorder(assert(mail.findIcon(101))), nil)
    Equal(#mail.state.itemLoads, 1)

    slots[4].quality = 4
    mail.fire("ITEM_DATA_LOAD_RESULT", 101, true)
    local icon = assert(mail.findIcon(101))
    Equal(mail.iconBorder(icon), "0.64, 0.21, 0.93, 1")
    Equal(mail.iconLabels(icon), "2")
    assert(not mail.findIcon(100), "Loading quality does not clear the active search")
    assert(mail.button("Open selected"), "Loading quality does not clear the mail selection")
end

for _, forever in ipairs({ false, true }) do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } }, forever)
    mail.open(true)
    assert(mail.button("Items") and mail.findIcon(100),
        "Wild mounts even when WoW calls the show function it saved before hooks were installed")
end

do
    local mail = NewMailbox()
    mail.open()
    local env = mail.env
    env.InboxFrame.openMailID = 2
    env.OpenMailFrame:Show()
    mail.command("inbox on")
    assert(env.OpenMailFrame:IsVisible(), "Enabling Wild Mail must keep the current letter open")
    Equal(env.InboxFrame.openMailID, 2)
    assert(not env.InboxFrame:IsVisible())
end

for _, forever in ipairs({ false, true }) do
    local mail = NewMailbox(nil, forever)
    mail.state.total = 7
    mail.open()
    assert(not mail.findIcon(100) and not mail.hasText("Browse Mail"),
        "The disabled grid must not add a mailbox button")
    assert(mail.wild.SetSetting("mail.showInboxBrowser", true))
    assert(mail.hasText("4 of 7"), "Show how much mail WoW has loaded")
    assert(mail.findIcon(100) and mail.findIcon(101) and mail.findIcon(102),
        "Show attachments from several messages together without opening a letter")
    assert(mail.button("List") and mail.button("Items") and mail.button("Send"), "The mailbox has three top tabs")
    for _, page in ipairs({ "List", "Send", "Items" }) do
        assert(mail.button(page)):Click()
        assert(not mail.button("/"), page .. " has no command icon")
    end
    assert(not mail.hasText("Private note"), "The grid does not list letters without attachments")
    local cake = assert(mail.findIcon(101, 2), "The icon shows the stack count")
    cake.scripts.OnEnter(cake)
    Equal(mail.tooltip.shown, true)
    Equal(mail.tooltip.index, 1)
    Equal(mail.tooltip.slot, 4)
    cake.scripts.OnLeave(cake)
    Equal(mail.tooltip.shown, false)

    mail.command("inbox search hOnEy CaKe")
    assert(mail.findIcon(101) and mail.findIcon(102) and not mail.findIcon(100),
        "Item-name search shows only matching stacks")
    mail.command("inbox search BEeKeeper")
    assert(mail.findIcon(100) and mail.findIcon(101) and not mail.findIcon(102),
        "Sender search includes the matching sender's attachments")
    mail.command("inbox search supplies")
    assert(mail.findIcon(100) and mail.findIcon(101) and not mail.findIcon(102),
        "Subject search includes the matching message's attachments")
    mail.command("inbox search 100%")
    assert(mail.hasText("No matching attachments"))
    Equal(#mail.reads, 0)
    assert(mail.button("Send")):Click()
    assert(not mail.hasText("No matching attachments"), "Send Mail must not show the inbox browser")
    assert(mail.button("Items")):Click()
    assert(mail.hasText("No matching attachments"), "Returning to Inbox keeps the filter for the visit")
    mail.command("inbox hide")
    assert(not mail.hasText("No matching attachments"), "The hide command applies only to the current visit")
    mail.close()
    mail.open()
    assert(mail.findIcon(100) and mail.findIcon(102), "Each visit starts with an unfiltered grid")
    mail.command("inbox off")
    assert(not mail.findIcon(100) and not mail.hasText("Browse Mail"),
        "Turning the setting off must immediately hide the grid without adding a button")
    mail.close()
    mail.open()
    assert(not mail.findIcon(100) and not mail.hasText("Browse Mail"),
        "The disabled setting must persist into the next visit")
end

for _, forever in ipairs({ false, true }) do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } }, forever)
    local env = mail.env
    local processed = 0
    mail.wild.RunMailIntents = function() processed = processed + 1; return true end
    mail.open()
    Equal(env.MailFrame:GetAlpha(), 0)
    assert(not env.MailFrameTab1:IsShown() and not env.MailFrameTab2:IsShown(),
        "Native tabs must not remain clickable behind the Wild mailbox")
    assert(mail.findIcon(100) and not env.InboxFrame:IsVisible() and not env.SendMailFrame:IsVisible(),
        "Only Items is visible when Wild opens")
    assert(mail.button("List")):Click()
    assert(env.InboxFrame:IsVisible() and env.InboxFrame:GetEffectiveAlpha() > 0 and not mail.findIcon(100),
        "List shows the native list inside Wild's window")
    local window = mail.resizeHandle():GetParent()
    window:GetScript("OnMouseWheel")(window, -1)
    Equal(mail.state.inboxWheel, -1)
    env.InboxFrame.openMailID = 1
    env.OpenMailFrame:Show()
    assert(env.OpenMailFrame:GetParent() ~= nil and env.OpenMailFrame:GetEffectiveAlpha() > 0,
        "Opening a letter shows it inside the same window")
    assert(not env.InboxFrame:IsVisible(), "The native inbox does not sit behind the open letter")
    mail.reply()
    assert(env.SendMailFrame:IsVisible() and env.SendMailFrame:GetEffectiveAlpha() > 0,
        "A native reply opens the Send tab")
    Equal(mail.nativeReply.id, 1)
    assert(env.OpenMailFrame:IsShown() and env.OpenMailFrame:GetEffectiveAlpha() == 0,
        "Switching to Send must not close the letter before the native reply is prepared")
    assert(mail.button("Process rules")):Click()
    mail.command("mail run")
    Equal(processed, 2)
    mail.close()
    mail.open(true)
    assert(mail.findIcon(100) and not env.SendMailFrame:IsVisible(),
        "Reopening after Send starts on Items even if Wild receives MAIL_SHOW before Blizzard")

    assert(mail.button("List")):Click()
    env.InboxFrame.openMailID = 2
    env.OpenMailFrame:Show()
    mail.command("inbox off")
    Equal(env.InboxFrame.openMailID, 2)
    assert(env.OpenMailFrame:IsVisible(), "Restoring the native window does not close an open letter")
    if forever then
        local point, parent, relativePoint = env.InboxFrame:GetPoint(2)
        Equal(point, "BOTTOMRIGHT")
        Equal(parent, env.MailFrame)
        Equal(relativePoint, "BOTTOMRIGHT")
    end
    env.OpenMailFrame:Hide()
    env.MailFrameTab_OnClick(nil, 2)
    mail.command("inbox on")
    assert(mail.button("Process rules"))
    assert(mail.button("Process rules")):Click()
    Equal(processed, 3)

    mail.command("inbox off")
    Equal(env.MailFrame:GetAlpha(), 1)
    Equal(env.InboxFrame:GetParent(), env.MailFrame)
    Equal(env.SendMailFrame:GetParent(), env.MailFrame)
    Equal(env.OpenMailFrame:GetParent(), nil)
    Equal(env.MailFrame:IsMouseWheelEnabled(), true)
    assert(env.MailFrameTab1:IsShown() and env.MailFrameTab2:IsShown() and not mail.button("Process rules"))
    assert(env.SendMailFrame:IsVisible(), "Disabling Wild keeps the native Send tab open")
end

do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } })
    mail.state.trial = true
    mail.env.MailFrameTab2:Hide()
    mail.open()
    assert(mail.env.InboxFrame:IsVisible() and not mail.button("Send"),
        "Trial accounts use the native restricted mailbox")
    mail.state.trial = false
    mail.fire("TRIAL_STATUS_UPDATE")
    assert(mail.button("Send"))
    mail.command("inbox off")
    assert(mail.env.MailFrameTab2:IsShown(), "Restoring the native UI respects the current account restriction")
end

for _, forever in ipairs({ false, true }) do
    local mail = NewMailbox(nil, forever)
    mail.state.inbox = {
        { sender = "Zane", slots = {
            [2] = mail.item(110, "Zinc Ore", 5),
            [4] = mail.item(111, "amber Ore", 2),
            [8] = mail.item(112, "Amber Ore", 2),
        } },
        { sender = "alden", slots = {
            [3] = mail.item(120, "Brass Ore", 7),
            [5] = mail.item(121, "Silk", 5),
        } },
        { sender = "Bran", slots = { [12] = mail.item(130, "Tin Ore", 8) } },
    }

    mail.open()
    mail.command("inbox search ore")
    AssertIconOrder(mail, 110, 111, 112, 120, 130)
    local first = assert(mail.findIcon(110))
    first:Press()
    mail.command("inbox sort NAME")
    first:Release()
    AssertIconOrder(mail, 111, 112, 120, 130, 110)
    assert(not mail.findIcon(121), "Changing sort order keeps the search and the visit's show override")
    Equal(#mail.takes, 0)

    assert(mail.wild.SetSetting("mail.inboxSort", "sender"))
    AssertIconOrder(mail, 120, 130, 110, 111, 112)
    mail.command("inbox sort size")
    AssertIconOrder(mail, 130, 120, 110, 111, 112)

    local brass = assert(mail.findIcon(120))
    brass.scripts.OnEnter(brass)
    Equal(mail.tooltip.index, 2)
    Equal(mail.tooltip.slot, 3)
    brass:Click()
    Equal(#mail.takes, 1)
    Equal(mail.takes[1].index, 2)
    Equal(mail.takes[1].slot, 3)
    Equal(#mail.reads, 0)

    mail.command("inbox on")
    mail.command("inbox hide")
    mail.command("inbox sort inbox")
    assert(not mail.findIcon(110), "Changing sort order must not show a manually hidden grid")
    mail.close()
    mail.command("inbox sort size")
    mail.open()
    AssertIconOrder(mail, 130, 120, 110, 121, 111, 112)
    mail.command("inbox sort inbox")
    AssertIconOrder(mail, 110, 111, 112, 120, 121, 130)
end

do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } })
    mail.state.inbox[2].slots[5] = mail.item(103, "Potion", 3)
    mail.state.inbox[2].slots[7] = mail.item(101, "Honey Cake", 5)
    mail.open()
    assert(mail.findIcon(101, 5), "Identical items in different mail remain separate stacks")
    assert(mail.findIcon(101, 2)):Click()
    assert(mail.findIcon(103)):Click()
    Equal(#mail.takes, 1)
    Equal(mail.takes[1].index, 1)
    Equal(mail.takes[1].slot, 4)
    Equal(#mail.reads, 0)

    mail.state.inbox[1].slots[4] = nil
    mail.state.pending = false
    mail.fire("MAIL_INBOX_UPDATE")
    assert(not mail.findIcon(101, 2) and mail.findIcon(101, 5) and mail.findIcon(100),
        "Only the collected stack disappears")
    assert(mail.findIcon(102)):Click()
    Equal(#mail.takes, 1)
    assert(mail.hasText("C.O.D."))
    assert(mail.findIcon(103)):Click()
    Equal(#mail.takes, 2)
    Equal(mail.takes[2].index, 2)
    Equal(mail.takes[2].slot, 5)
    Equal(#mail.reads, 0)
end

do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } })
    mail.open()
    local wax = assert(mail.findIcon(100))
    wax:Press()
    mail.state.inbox[1].slots[1] = nil
    mail.fire("MAIL_INBOX_UPDATE")
    wax:Release()
    Equal(#mail.takes, 0)

    local cake = assert(mail.findIcon(101))
    mail.state.inbox[1].slots[4].link = "|Hitem:101:2|h[Honey Cake]|h"
    cake:Click()
    Equal(#mail.takes, 0)
end

do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } })
    for index = 5, 14 do
        local slots = {}
        for slot = 1, 16 do
            slots[slot] = mail.item(index * 16 + slot, "Mail item " .. slot, 1)
        end
        mail.state.inbox[index] = { sender = "Courier", subject = "Package", slots = slots }
    end
    mail.open()
    local first = assert(mail.findIcon(100))
    first:Press()
    mail.scrollGrid(true)
    mail.scrollGrid(false)
    first:Release()
    Equal(#mail.takes, 0)

    assert(not mail.findIcon(240))
    local grip = mail.resizeHandle()
    local window, scroll = grip:GetParent(), mail.visibleScroll()
    local initialWidth, initialHeight = scroll:GetWidth(), scroll:GetHeight()
    local movedIcon = assert(mail.findIcon(89))
    local _, _, _, _, initialY = movedIcon:GetPoint()
    grip.scripts.OnMouseDown(grip, "LeftButton")
    Equal(window.sizing, "BOTTOMRIGHT")
    movedIcon:Press()
    window:DragSize(320, 270)
    movedIcon:Release()
    Equal(#mail.takes, 0)
    assert(scroll:GetWidth() < initialWidth and scroll:GetHeight() < initialHeight,
        "The viewport follows both window dimensions")
    local _, _, _, _, narrowY = assert(mail.findIcon(89)):GetPoint()
    assert(narrowY < initialY, "Narrowing the pane wraps icons to a lower row")

    mail.scrollGrid(true)
    assert(mail.findIcon(240), "The last stack is reachable after narrowing the pane")
    window:DragSize(750, 660)
    local _, _, _, _, wideY = assert(mail.findIcon(89)):GetPoint()
    Equal(wideY, initialY)
    Equal(scroll:GetVerticalScroll(), 0)
    grip.scripts.OnMouseUp(grip, "LeftButton")
    Equal(window.sizing, nil)
    local anchor, relative, relativePoint = window:GetPoint()
    Equal(anchor, "TOPLEFT")
    Equal(relative, mail.env.MailFrame)
    Equal(relativePoint, "TOPLEFT")

    assert(mail.findIcon(240)):Click()
    Equal(#mail.takes, 1)
    Equal(mail.takes[1].index, 14)
    Equal(mail.takes[1].slot, 16)
    mail.command("inbox search wax")
    assert(mail.findIcon(100) and not mail.findIcon(240), "Search returns to the first matching row")
    grip.scripts.OnMouseDown(grip, "LeftButton")
    window:DragSize(1, 1)
    assert(mail.findIcon(100) and not mail.findIcon(101), "Resizing keeps the search filter active")
    mail.close()
    Equal(window.sizing, nil)
end

do
    local mail = NewMailbox()
    mail.open()
    mail.command("inbox search honey cake")
    mail.command("inbox read 1")
    assert(table.concat(mail.chat, "\n"):find("Here are the supplies.", 1, true))
    assert(mail.findIcon(101) and mail.findIcon(102) and not mail.findIcon(100),
        "The read command does not switch the grid to a letter view")
    mail.command("inbox take 1 4")
    mail.command("inbox take 1 4")
    Equal(#mail.takes, 1)
    Equal(mail.takes[1].index, 1)
    Equal(mail.takes[1].slot, 4)
    mail.state.inbox[1].slots[4] = nil
    mail.state.pending = false
    mail.fire("MAIL_INBOX_UPDATE")
    assert(not mail.findIcon(101) and mail.findIcon(102))
    mail.command("inbox read 3")
    mail.command("inbox take 3 2")
    assert(mail.hasText("C.O.D."), "Explain why the player must use WoW's C.O.D. confirmation")
    Equal(#mail.takes, 1)
end

do
    local mail = NewMailbox()
    mail.open()
    mail.command("inbox show")
    mail.command("inbox read 1")
    -- The index still exists, but an attachment moved before the next update.
    mail.state.inbox[1].slots[4].link = "|Hitem:101:2|h[Honey Cake]|h"
    mail.command("inbox take 1 4")
    Equal(#mail.takes, 0)
    mail.command("inbox read 1")
    mail.state.pending = true
    mail.command("inbox take 1 4")
    Equal(#mail.takes, 0)
    mail.state.pending = false
    mail.state.combat = true
    mail.command("inbox take 1 4")
    Equal(#mail.takes, 0)
    mail.state.combat = false
    mail.state.cursor = "item"
    mail.command("inbox take 1 4")
    Equal(#mail.takes, 0)
    mail.state.cursor = nil
    mail.command("inbox take 2 4")
    Equal(#mail.takes, 0)
    mail.command("inbox take 1 4")
    Equal(#mail.takes, 1)
    Equal(mail.takes[1].slot, 4)
    mail.close()
    mail.command("inbox take 1 4")
    Equal(#mail.takes, 1)
end

do
    local mail = NewMailbox({ mail = { inboxSort = "name" } })
    local attachment = mail.state.inbox[1].slots[4]
    local name, link = attachment.name, attachment.link
    attachment.name, attachment.link = nil, nil
    mail.open()
    mail.command("inbox show")
    AssertIconOrder(mail, 102, 100, 101)
    local unloaded = assert(mail.findIcon(101))
    unloaded.scripts.OnEnter(unloaded)
    Equal(mail.tooltip.lines[1], "Attachment not ready")
    mail.command("inbox read 1")
    mail.command("inbox take 1 4")
    Equal(#mail.takes, 0)
    Equal(#mail.state.itemLoads, 1)
    Equal(mail.state.itemLoads[1], 101)

    mail.command("inbox search honey cake")
    assert(not mail.findIcon(101))
    attachment.name, attachment.link = name, link
    mail.fire("ITEM_DATA_LOAD_RESULT", 101, true)
    assert(mail.findIcon(101), "Loaded item names update an existing search")
    AssertIconOrder(mail, 101, 102)
    Equal(#mail.reads, 1)
end

do
    local mail = NewMailbox({ mail = { autoOpen = true } })
    mail.open()
    mail.command("inbox on")
    assert(mail.findIcon(100), "Enabling the setting shows the grid during the current visit")
    mail.command("inbox off")
    mail.runBulkTimer()
    Equal(mail.state.bulkCalls, 0)
    mail.close()
    mail.open()
    mail.runBulkTimer()
    Equal(mail.state.bulkCalls, 1)
    mail.close()
    mail.command("inbox on")
    mail.open()
    mail.runBulkTimer()
    assert(mail.findIcon(100), "The saved setting opens the grid")
    Equal(mail.state.bulkCalls, 1)
    Equal(mail.wild.GetSetting("mail.autoOpen"), true)
end

for _, forever in ipairs({ false, true }) do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } }, forever)
    for index = 5, 9 do
        mail.state.inbox[index] = { sender = "Courier " .. index, slots = { [3] = mail.item(index, "Supply", 1) } }
    end
    mail.state.total = 12
    mail.open(true)
    assert(mail.button("Open all mail") and mail.button("Return all mail") and mail.button("Delete all empty mail"))
    assert(not mail.selection(1) and not mail.button("Native Open All"))
    assert(mail.button("List")):Click()
    assert(not mail.button("Native Open All"), "The native button would ignore Wild's selection")
    if forever then
        mail.state.gamepad = true
        mail.env.InboxFrame:FocusGamepad()
        assert(not mail.env.InboxFrame.gamepadFooter.isShown, "A controller shortcut must not bypass selection")
        mail.state.gamepad = false
    end
    assert(mail.selection(1)):Click()
    mail.page(2)
    assert(not assert(mail.selection(1)):GetChecked(), "A recycled row must not inherit the previous page's check")
    assert(mail.selection(2)):Click()
    assert(not mail.selection(3), "Unoccupied native rows do not show checkboxes")
    mail.page(1)
    assert(assert(mail.selection(1)):GetChecked(), "Selection persists between native pages")
    assert(mail.button("Open selected") and mail.button("Return selected") and mail.button("Delete selected empty"))
    assert(mail.button("Items")):Click()
    mail.command("inbox search no matches")
    assert(mail.button("Open selected")):Click()
    assert(not mail.env.MailItem1Button:IsEnabled(), "Native row actions cannot race the batch")
    Equal(mail.requests[1].index, 9)
    Equal(mail.requests[1].slot, 3)
    mail.fire("MAIL_SUCCESS")
    mail.fire("MAIL_INBOX_UPDATE")
    mail.advance()
    Equal(#mail.requests, 1, "An unrelated event must not advance a bulk request")
    mail.ack(true, true)
    mail.advance()
    Equal(#mail.requests, 1, "An inbox update cannot advance while WoW is still processing the command")
    mail.state.pending = false
    mail.advance()
    Equal(mail.requests[2].index, 1)
    Equal(mail.requests[2].action, "money")
    mail.ack()
    mail.advance()
    Equal(mail.requests[3].index, 1)
    Equal(mail.requests[3].slot, 1)
    mail.ack()
    mail.advance()
    Equal(mail.requests[4].index, 1)
    Equal(mail.requests[4].slot, 4)
    mail.ack()
    mail.advance()
    Equal(#mail.requests, 4)
    assert(mail.env.MailItem1Button:IsEnabled(), "Native rows are restored when the batch finishes")
    Equal(mail.state.inbox[3].cod, 100000)
    assert(mail.state.inbox[8].slots[3], "Unselected mail on the other page stays untouched")
    Equal(#mail.reads, 0)
    mail.command("inbox off")
    assert(mail.button("Native Open All") and not mail.selection(1), "Restore the standard Inbox actions")
end

do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } }, true)
    mail.state.gamepad = true
    mail.env.OpenAllMail:Hide()
    mail.open(true)
    assert(mail.button("List")):Click()
    assert(not mail.env.InboxFrame.gamepadFooter.isShown)
    mail.command("inbox off")
    assert(mail.env.InboxFrame.gamepadFooter.isShown, "The native controller bindings return when Wild is disabled")
    assert(not mail.button("Native Open All"), "The native mouse button stays hidden in controller mode")
end

do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } })
    local inbox = mail.state.inbox
    inbox[1].returnable = true
    inbox[3].legacyReturnable = true
    inbox[4].isGM = true
    inbox[4].returnable = true
    mail.open()
    assert(mail.button("List")):Click()
    mail.command("inbox select 3 on")
    assert(mail.selection(3):GetChecked())
    assert(mail.button("Return selected")):Click()
    assert(mail.state.popup.text:find("1 selected", 1, true))
    Equal(#mail.requests, 0)
    mail.answer(false)
    Equal(#mail.requests, 0)
    assert(mail.button("Return selected")):Click()
    mail.answer(true)
    Equal(mail.requests[1].action, "return")
    Equal(mail.requests[1].message, inbox[3], "Returns do not pay C.O.D. or collect the contents")
    mail.ack()
    mail.advance()
    Equal(#mail.requests, 1)
    assert(inbox[1].slots[1] and inbox[1].money == 70)
    assert(mail.button("Return all mail")):Click()
    assert(mail.state.popup.text:find("all loaded", 1, true))
    mail.answer(true)
    Equal(mail.requests[2].message, inbox[1])
    mail.ack()
    mail.advance()
    Equal(#mail.requests, 2, "Native delete-only and GM mail cannot be bulk returned")
    Equal(#mail.reads, 0)
end

do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } })
    mail.state.inbox[1].returnable = true
    mail.state.inbox[3].returnable = true
    mail.state.total = 5
    mail.open()
    assert(mail.button("Return all mail")):Click()
    mail.answer(true)
    Equal(mail.requests[1].index, 3)
    mail.ack()
    table.insert(mail.state.inbox, { sender = "Refill", slots = {}, returnable = true })
    mail.fire("MAIL_INBOX_UPDATE")
    mail.advance()
    Equal(#mail.requests, 1, "A newly loaded letter cannot enter an already confirmed batch")
    assert(mail.hasText("Stopped the batch."))
end

do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } })
    local inbox = mail.state.inbox
    inbox[4].wasRead = true
    inbox[5] = { sender = "Banker", money = 10, slots = {} }
    inbox[6] = { sender = "GM", isGM = true, slots = {} }
    inbox[7] = { sender = "Merchant", returnable = true, slots = {} }
    local unread = inbox[2]
    mail.open()
    mail.command("inbox keepunread on")
    assert(mail.button("Delete all empty mail")):Click()
    Equal(#mail.requests, 0)
    mail.answer(true)
    Equal(mail.requests[1].index, 4)
    mail.ack()
    mail.advance()
    Equal(#mail.requests, 1)
    mail.command("inbox keepunread off")
    mail.command("inbox delete all")
    assert(mail.state.popup.text:find("unread", 1, true) and mail.state.popup.text:find("text", 1, true))
    mail.answer(true)
    Equal(mail.requests[2].message, unread)
    mail.ack()
    mail.advance()
    Equal(#mail.requests, 2, "Keep mail with attachments, gold, C.O.D., GM mail, and native return-only letters")
    Equal(#mail.reads, 0, "Bulk deletion never needs to open a letter")
end

do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } })
    mail.open()
    assert(mail.button("List")):Click()
    assert(mail.selection(2)):Click()
    local delete = assert(mail.button("Delete selected empty"))
    delete:Press()
    table.remove(mail.state.inbox, 1)
    mail.fire("MAIL_INBOX_UPDATE")
    delete:Release()
    Equal(mail.state.popup, nil, "A click that started with a selection cannot switch to all mail on release")
    mail.command("inbox delete selected")
    Equal(mail.state.popup, nil, "An explicitly selected-only command never falls back to all")
    assert(mail.button("Delete all empty mail")):Click()
    table.insert(mail.state.inbox, 1, { sender = "New mail", slots = {} })
    mail.answer(true)
    Equal(#mail.requests, 0, "A preview cannot authorize deletion after inbox indexes change")
    assert(mail.button("Delete all empty mail")):Click()
    mail.close()
    Equal(mail.state.popup, nil, "Closing the mailbox dismisses its confirmation")
end

do
    local mail = NewMailbox({ mail = { showInboxBrowser = true } })
    mail.state.inbox[5] = { sender = "Another", money = 2, slots = {} }
    mail.open()
    mail.state.pending = true
    assert(mail.button("Open all mail")):Click()
    Equal(#mail.requests, 0)
    mail.state.pending = false
    assert(mail.button("Open all mail")):Click()
    Equal(#mail.requests, 1)
    local started, _, reason = mail.wild.RunMailIntents()
    Equal(started, false)
    Equal(reason, "inbox_bulk_active")
    mail.ack()
    assert(mail.findIcon(100)):Click()
    Equal(#mail.requests, 1, "The grid cannot take a stack between bulk requests")
    mail.fire("MAIL_FAILED")
    mail.advance()
    Equal(#mail.requests, 1, "An inbox failure stops the batch")
    mail.command("inbox open")
    Equal(#mail.requests, 2)
    mail.state.pending = false
    mail.expire()
    mail.fire("MAIL_INBOX_UPDATE")
    mail.advance()
    Equal(#mail.requests, 2, "An unconfirmed request cannot advance the batch")
    mail.command("inbox open")
    Equal(#mail.requests, 3)
    mail.close()
    mail.ack()
    mail.open()
    mail.advance()
    Equal(#mail.requests, 3, "Late updates after close cannot resume a batch")
end

print("Inbox browser fixtures passed (Retail and Forever)")
