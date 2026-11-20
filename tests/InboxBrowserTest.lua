-- Run from the repository root with Lua 5.1: lua tests\InboxBrowserTest.lua
local function Equal(actual, expected)
    assert(actual == expected, "Expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function NewMailbox(saved, forever)
    local frames, timers, chat, reads, takes = {}, {}, {}, {}, {}
    local state = { bulkCalls = 0, pending = false, itemLoads = {} }
    local env = setmetatable({
        WildDB = saved, SlashCmdList = {}, tremove = table.remove,
        strtrim = function(value) return value:match("^%s*(.-)%s*$") end,
        print = function(line) chat[#chat + 1] = line end,
        IsShiftKeyDown = function() return false end,
        InCombatLockdown = function() return state.combat end,
        GetCursorInfo = function() return state.cursor end,
        GetBuildInfo = function() return "", "", "", forever and 16001 or 120105 end,
        WOW_PROJECT_ID = forever and 160 or 1, WOW_PROJECT_MAINLINE = 1,
        ATTACHMENTS_MAX_RECEIVE = 16,
        C_Timer = {
            After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end,
        },
        C_Mail = { IsCommandPending = function() return state.pending end },
        C_Item = { RequestLoadItemDataByID = function(itemID)
            state.itemLoads[#state.itemLoads + 1] = itemID
        end },
        AutoLootMailItem = function() state.bulkCalls = state.bulkCalls + 1 end,
        DeleteInboxItem = function() error("Browsing must not delete mail") end,
        TakeInboxMoney = function() error("An attachment action must not take gold") end,
        GetMoneyString = function(copper) return copper .. " copper" end,
    }, { __index = _G })
    env._G = env

    local methods = {}
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:GetParent() return self.parent end
    function methods:SetScript(event, script) self.scripts[event] = script end
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
        if self.shown == shown then return end
        self.shown = shown
        local event = shown and "OnShow" or "OnHide"
        if self.scripts[event] then self.scripts[event](self) end
    end
    function methods:Show() self:SetShown(true) end
    function methods:Hide() self:SetShown(false) end
    function methods:SetEnabled(enabled) self.enabled = enabled end
    function methods:SetText(text)
        self.text = text
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
    end
    function methods:GetText() return self.text or "" end
    function methods:GetStringHeight() return 14 end
    function methods:Click()
        assert(self:IsVisible() and self.enabled and self.scripts.OnClick, "Button cannot be clicked")
        self.scripts.OnClick(self)
    end
    for _, method in ipairs({
        "SetSize", "SetHeight", "SetWidth", "SetPoint", "ClearAllPoints", "SetVerticalScroll",
        "EnableMouse", "SetClampedToScreen", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
        "SetJustifyH", "SetWordWrap", "SetTextColor", "SetScrollChild", "SetAutoFocus", "ClearFocus",
        "SetHighlightTexture", "SetTexture",
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

    env.MailFrame = env.CreateFrame("Frame")
    env.InboxFrame = env.CreateFrame("Frame", nil, env.MailFrame)
    env.OpenMailFrame = env.CreateFrame("Frame")
    env.MailFrame:Hide()
    env.OpenMailFrame:Hide()

    local function Item(itemID, name, count)
        return {
            id = itemID, name = name, count = count,
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
    env.GetInboxHeaderInfo = function(index)
        local message = state.inbox[index]
        if not message or message.unavailable then return end
        local count = 0
        for _ in pairs(message.slots) do count = count + 1 end
        return nil, 1, message.sender, message.subject, message.money or 0, message.cod or 0,
            15, count > 0 and count or nil, message.wasRead
    end
    env.HasInboxItem = function(index, slot) return state.inbox[index].slots[slot] ~= nil end
    env.GetInboxItem = function(index, slot)
        local item = state.inbox[index].slots[slot]
        if item then return item.name, item.id, 123, item.count end
    end
    env.GetInboxItemLink = function(index, slot)
        local item = state.inbox[index].slots[slot]
        return item and item.link
    end
    env.GetInboxText = function(index)
        reads[#reads + 1] = index
        state.inbox[index].wasRead = true
        return state.inbox[index].body
    end
    env.TakeInboxItem = function(index, slot)
        takes[#takes + 1] = { index = index, slot = slot }
        state.pending = true
    end

    local Wild = {}
    local function Load(path) setfenv(assert(loadfile(path)), env)("Wild", Wild) end
    local function Fire(event, ...)
        for _, frame in ipairs({ unpack(frames) }) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    local function Open()
        env.MailFrame:Show()
        Fire("MAIL_SHOW")
        Fire("MAIL_INBOX_UPDATE")
    end
    local function Close()
        env.MailFrame:Hide()
        Fire("MAIL_CLOSED")
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
    local function Click(text, childText, siblingText)
        for _, frame in ipairs(frames) do
            if frame.kind == "Button" and frame:IsVisible()
                and (frame:GetText() == text or HasChildText(frame, text))
                and (not childText or HasChildText(frame, childText))
                and (not siblingText or HasChildText(frame.parent, siblingText)) then
                frame:Click()
                return
            end
        end
        error("No visible button labeled " .. text)
    end
    local function RunBulkTimer()
        local queued = timers
        timers = {}
        for _, timer in ipairs(queued) do
            if timer.delay == 0.5 or timer.delay == 0.35 then timer.callback() end
        end
    end

    Load("Core.lua")
    Load("Conditions.lua")
    Load("Mail.lua")
    Load("InboxBrowser.lua")
    Load("SlashCommands.lua")
    Fire("ADDON_LOADED", "Wild")

    return {
        state = state, env = env, wild = Wild, open = Open, close = Close, fire = Fire, hasText = HasText,
        click = Click, reads = reads, takes = takes, command = env.SlashCmdList.WILD, runBulkTimer = RunBulkTimer,
    }
end

for _, forever in ipairs({ false, true }) do
    local mail = NewMailbox(nil, forever)
    mail.state.total = 7
    mail.open()
    assert(not mail.hasText("Private note"), "The browser must start closed")
    mail.click("Browse Mail")
    assert(mail.hasText("4 of 7"), "Show how much mail WoW has loaded")
    assert(mail.hasText("Private note"), "Include messages with no attachments")
    Equal(#mail.reads, 0)
    mail.command("inbox search hOnEy CaKe")
    assert(mail.hasText("Supplies") and mail.hasText("Special delivery"))
    assert(not mail.hasText("Private note"))
    Equal(#mail.reads, 0)
    mail.click("#1  Supplies", "Beekeeper")
    assert(mail.hasText("Here are the supplies.") and mail.hasText("70 copper"))
    assert(mail.hasText("Wax") and mail.hasText("Honey Cake"))
    Equal(#mail.reads, 1)
    Equal(mail.reads[1], 1)
    assert(not mail.state.inbox[2].wasRead)

    mail.command("inbox search 100%")
    assert(mail.hasText("100% complete") and not mail.hasText("Special delivery"))
    mail.command("inbox search BEeKeeper")
    assert(mail.hasText("Supplies") and not mail.hasText("Special delivery"))
    mail.command("inbox search nonexistent")
    assert(mail.hasText("No matching messages"))
    mail.env.InboxFrame:Hide()
    assert(not mail.hasText("No matching messages"), "Send Mail must not show the inbox browser")
    mail.env.InboxFrame:Show()
    assert(mail.hasText("No matching messages"), "Returning to Inbox keeps the filter for the visit")
    mail.env.OpenMailFrame:Show()
    assert(not mail.hasText("No matching messages"), "An open native letter must not be covered by the browser")
    mail.env.OpenMailFrame:Hide()
    mail.close()
    mail.open()
    mail.click("Browse Mail")
    assert(mail.hasText("Private note"), "A new visit starts without the old search")
end

do
    local mail = NewMailbox()
    mail.open()
    mail.command("inbox search honey cake")
    mail.command("inbox read 1")
    mail.click("Take", nil, "#4  Honey Cake x2")
    mail.command("inbox take 1 1")
    Equal(#mail.takes, 1)
    Equal(mail.takes[1].index, 1)
    Equal(mail.takes[1].slot, 4)
    mail.state.inbox[1].slots[4] = nil
    mail.state.pending = false
    mail.fire("MAIL_INBOX_UPDATE")
    assert(not mail.hasText("Supplies") and mail.hasText("Special delivery"))
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
    local mail = NewMailbox()
    local attachment = mail.state.inbox[1].slots[4]
    local name, link = attachment.name, attachment.link
    attachment.name, attachment.link = nil, nil
    mail.open()
    mail.command("inbox show")
    mail.command("inbox read 1")
    assert(mail.hasText("Some attachments are not ready"))
    mail.command("inbox take 1 4")
    Equal(#mail.takes, 0)
    Equal(#mail.state.itemLoads, 1)
    Equal(mail.state.itemLoads[1], 101)

    mail.command("inbox search honey cake")
    assert(not mail.hasText("Supplies"))
    attachment.name, attachment.link = name, link
    mail.fire("ITEM_DATA_LOAD_RESULT", 101, true)
    assert(mail.hasText("Supplies"), "Loaded item names update an existing search")
    Equal(#mail.reads, 1)
end

do
    local mail = NewMailbox({ mail = { autoOpen = true } })
    mail.open()
    mail.click("Browse Mail")
    mail.command("inbox hide")
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
    assert(mail.hasText("Private note"), "The saved setting opens the browser")
    Equal(mail.state.bulkCalls, 1)
    Equal(mail.wild.GetSetting("mail.autoOpen"), true)
end

print("Inbox browser fixtures passed (Retail and Forever)")
