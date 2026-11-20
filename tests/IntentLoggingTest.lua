-- Run from the repository root with Lua 5.1: lua tests\IntentLoggingTest.lua
-- WoW mail controls are simulated; these tests do not establish live server behavior.
local LINK = "|cff1eff00|Hitem:1:0|h[Test Item]|h|r"
local OTHER_LINK = "|cff1eff00|Hitem:2:0|h[Other Item]|h|r"
local THIRD_LINK = "|cff1eff00|Hitem:3:0|h[Third Item]|h|r"
local COUNT = " \195\151"

local function Equal(actual, expected)
    assert(actual == expected, "Expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function Item(count, itemID)
    return {
        itemID = itemID or 1, stackCount = count or 1,
        hyperlink = itemID == 2 and OTHER_LINK or itemID == 3 and THIRD_LINK or LINK,
    }
end

local function FillBag(state, bag)
    for slot = 1, 20 do state.bags[bag][slot] = Item(200) end
end

local function ActionEntries(Wild, action)
    local entries = {}
    for _, entry in ipairs(Wild.GetLogEntries()) do
        if entry.kind == "action" and entry.action == action then entries[#entries + 1] = entry end
    end
    return entries
end

local function NewEnvironment(...)
    local Wild = { db = {
        intents = {}, mail = { autoOpen = false }, advanced = {
            debug = false, ruleDelay = 0, passDelay = 0, bankStartDelay = 0,
            sellStartDelay = 0, sellInterval = 0, mailStartDelay = 0,
            mailBatchDelay = 0, guildBankStartDelay = 0, destroyStartDelay = 0, preloadTimeout = 3,
        },
    } }
    local state = {
        frames = {}, messages = {}, timers = {}, timeouts = {}, requests = {},
        bags = { [0] = {}, [5] = {}, [6] = {}, [12] = {}, guild = {} },
        money = 100000, bankMoney = 100000, merchantOpen = true,
        attachments = {}, sent = {}, cursor = nil, inboxCount = 0,
        bankTypes = { [0] = true, [2] = true }, guildBankOpen = true,
        time = 10, modifiers = {},
    }
    local env = setmetatable({
        print = function(message) state.messages[#state.messages + 1] = message end,
        Enum = {
            BagIndex = { ReagentBag = 5, CharacterBankTab_1 = 6, AccountBankTab_1 = 12 },
            BankType = { Character = 0, Account = 2 },
            PlayerInteractionType = { Merchant = 5, Banker = 8, GuildBanker = 10, AccountBanker = 67 },
            TooltipDataLineType = { SellPrice = 11 },
        },
        BACKPACK_CONTAINER = 0, NUM_BAG_SLOTS = 0, ATTACHMENTS_MAX_SEND = 12,
        tremove = table.remove, SlashCmdList = {},
        strtrim = function(text) return text:match("^%s*(.-)%s*$") end,
        wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end end,
        GetTime = function() return state.time end,
        IsShiftKeyDown = function() return state.modifiers.SHIFT end,
        IsControlKeyDown = function() return state.modifiers.CTRL end,
        IsAltKeyDown = function() return state.modifiers.ALT end,
        date = function() return "2026-10-11 12:00:00" end,
        GetMoney = function() return state.money end,
        GetMoneyString = function(amount) return amount .. " copper" end,
        MerchantFrame = { IsShown = function() return state.merchantOpen end },
        StaticPopup_Visible = function(which)
            return state.deletePopup and which == "DELETE_GOOD_ITEM" and 1 or nil
        end,
        GetNumGuildBankTabs = function() return 1 end,
        GetGuildBankTabInfo = function() return "Test", nil, true end,
        GetGuildBankItemInfo = function(_, slot)
            local info = state.bags.guild[slot]
            return 134400, info and info.stackCount
        end,
        GetGuildBankItemLink = function(_, slot)
            local info = state.bags.guild[slot]
            return info and info.hyperlink
        end,
        GetGuildBankMoney = function() return state.bankMoney end,
        C_Item = {
            GetItemIconByID = function() return 134400 end,
            GetItemInfo = function() return "Test Item", LINK, 2, 1, 1, nil, nil, 200, "", 134400, 100 end,
        },
        Item = { CreateFromItemID = function()
            return { IsItemDataCached = function() return true end }
        end },
    }, { __index = _G })
    env.C_Timer = {
        After = function(_, callback) state.timers[#state.timers + 1] = callback end,
        NewTimer = function(_, callback)
            local timer = { callback = callback }
            function timer:Cancel() self.cancelled = true end
            state.timeouts[#state.timeouts + 1] = timer
            return timer
        end,
    }
    local function Request(kind, bag, slot, count, target)
        local info = state.bags[bag][slot]
        local request = {
            kind = kind, bag = bag, slot = slot, target = target,
            item = info, count = count or (info and info.stackCount),
        }
        state.requests[#state.requests + 1] = request
        return request
    end
    env.GetCursorInfo = function()
        local cursor = state.cursor
        if cursor then return "item", cursor.item.itemID, cursor.item.hyperlink end
    end
    env.ClearCursor = function()
        local cursor = state.cursor
        if cursor and cursor.removed then
            state.bags[cursor.bag][cursor.slot] = cursor.item
        end
        state.cursor = nil
    end
    env.C_Container = {
        GetContainerNumSlots = function() return 20 end,
        GetContainerItemInfo = function(bag, slot) return state.bags[bag][slot] end,
        UseContainerItem = function(bag, slot, _, bankType)
            local kind = state.selling and "sell" or (bag == 0 or bag == 5) and "deposit" or "withdraw"
            Request(kind, bag, slot, nil, kind == "deposit" and (bankType == 2 and 12 or 6) or 0)
        end,
        SplitContainerItem = function(bag, slot, count)
            state.cursor = { bag = bag, slot = slot, count = count, item = state.bags[bag][slot] }
        end,
        PickupContainerItem = function(bag, slot)
            if state.cursor then
                local cursor = state.cursor
                Request("move", cursor.bag, cursor.slot, cursor.count, bag)
                state.cursor = nil
            else
                local info = state.bags[bag][slot]
                if info and not info.isLocked then
                    state.cursor = { bag = bag, slot = slot, item = info }
                    if state.removeOnPickup then
                        state.bags[bag][slot] = nil
                        state.cursor.removed = true
                    end
                end
            end
        end,
    }
    env.AutoStoreGuildBankItem = function(_, slot) Request("withdraw", "guild", slot, nil, 0) end
    env.DeleteCursorItem = function()
        if state.cursor then
            if state.askForDeleteConfirmation then state.deletePopup = true end
            local cursor = state.cursor
            state.requests[#state.requests + 1] = {
                kind = "destroy", bag = cursor.bag, slot = cursor.slot,
                item = cursor.item, count = cursor.item.stackCount,
            }
        end
    end
    env.C_Bank = {
        CanUseBank = function(bankType) return state.bankTypes[bankType] == true end,
        DepositMoney = function(_, amount)
            state.requests[#state.requests + 1] = { kind = "goldDeposit", count = amount }
        end,
        WithdrawMoney = function(_, amount)
            state.requests[#state.requests + 1] = { kind = "goldWithdraw", count = amount }
        end,
        FetchDepositedMoney = function() return state.bankMoney end,
    }
    env.C_PlayerInteractionManager = {
        IsInteractingWithNpcOfType = function() return state.guildBankOpen end,
    }
    env.DepositGuildBankMoney = function(amount) env.C_Bank.DepositMoney(2, amount) end
    env.WithdrawGuildBankMoney = function(amount) env.C_Bank.WithdrawMoney(2, amount) end
    env.ClickSendMailItemButton = function(index)
        if not state.cursor or state.refuseAttachment then return end
        local cursor = state.cursor
        state.attachments[index] = cursor.item
        state.bags[cursor.bag][cursor.slot] = nil
        state.cursor = nil
    end
    env.GetSendMailItem = function(index)
        local info = state.attachments[index]
        if info then return "Test Item", info.itemID, 134400, info.stackCount, 2 end
    end
    env.GetSendMailItemLink = function(index)
        local info = state.attachments[index]
        return info and info.hyperlink
    end
    env.GetInboxNumItems = function() return state.inboxCount end
    env.AutoLootMailItem = function() state.inboxCount = state.inboxCount - 1 end
    local function MailEditBox()
        local editBox = { text = "" }
        function editBox:SetText(text) self.text = text end
        function editBox:GetText() return self.text end
        return editBox
    end
    env.SendMailNameEditBox = MailEditBox()
    env.SendMailSubjectEditBox = MailEditBox()
    env.SendMailBodyEditBox = MailEditBox()
    env.SendMailFrame = { IsShown = function() return state.mailTab == 2 end }
    env.MailFrameTab_OnClick = function(_, tabID)
        state.mailTab = tabID
        env.SendMailFrame.sendMode = tabID == 2 and "send" or nil
    end
    env.SendMail = function(recipient, subject)
        state.sent[#state.sent + 1] = recipient
        state.subject = subject
    end
    env.CreateFrame = function(frameType)
        local frame = { events = {}, scripts = {}, shown = false, frameType = frameType }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:RegisterAllEvents() end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        for _, method in ipairs({
            "SetSize", "SetPoint", "SetFrameStrata", "SetFrameLevel", "SetBackdrop",
            "SetBackdropColor", "SetBackdropBorderColor", "EnableMouse", "SetMovable",
            "SetClampedToScreen", "SetHeight", "RegisterForDrag", "SetWidth", "SetText",
            "SetColorTexture",
        }) do frame[method] = function() end end
        function frame:CreateFontString() return env.CreateFrame() end
        function frame:CreateTexture() return env.CreateFrame() end
        state.frames[#state.frames + 1] = frame
        return frame
    end
    local function Load(file) setfenv(assert(loadfile(file)), env)("Wild", Wild) end
    Load("Core.lua")
    Load("Log.lua")
    Load("Conditions.lua")
    Wild.BuildCharContext = function() return {} end
    Wild.ValidateIntent = function() return true end
    Wild.IntentMatchesActor = function() return true end
    Wild.IntentMatchesItem = function(intent, itemID)
        return not intent.itemID or intent.itemID == itemID
    end
    Wild.GetIntentSummary = function() return "Test rule" end
    Wild.GetIntentGoldTarget = function(intent) return intent.gold or 0 end
    Wild.GetItemGroups = function(intent) return intent.groups or {} end
    Wild.SubIntentForGroup = function(intent) return intent end
    Wild.GetEffectiveSellPrice = function() return 100 end
    Wild.CountMatchingInBags = function(intent)
        local total = 0
        for _, bag in ipairs(Wild.GetPlayerBags()) do
            for _, info in pairs(state.bags[bag]) do
                if Wild.IntentMatchesItem(intent, info.itemID) then total = total + info.stackCount end
            end
        end
        return total
    end
    for _, file in ipairs({ ... }) do Load(file) end
    local function Fire(event, ...)
        if event == "MAIL_SEND_SUCCESS" then state.attachments = {} end
        local frames = { unpack(state.frames) }
        for _, frame in ipairs(frames) do
            if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    local function RunTimers()
        local timers = state.timers
        state.timers = {}
        for _, callback in ipairs(timers) do callback() end
    end
    local function RunTimeouts()
        local timers = state.timeouts
        state.timeouts = {}
        for _, timer in ipairs(timers) do
            if not timer.cancelled then timer.callback() end
        end
    end
    local function Apply(index, count)
        local request = state.requests[index]
        count = count or request.count
        if request.kind == "goldDeposit" or request.kind == "goldWithdraw" then
            local delta = request.kind == "goldDeposit" and -count or count
            state.money, state.bankMoney = state.money + delta, state.bankMoney - delta
            return
        end
        if request.kind ~= "destroy" and request.kind ~= "sell" then
            local destination = state.bags[request.target]
            local maxStack = select(8, env.C_Item.GetItemInfo(request.item.itemID))
            local remaining = count
            for slot = 1, 20 do
                local targetInfo = destination[slot]
                if targetInfo and targetInfo.hyperlink == request.item.hyperlink then
                    local moved = math.min(remaining, maxStack - targetInfo.stackCount)
                    destination[slot] = Item(targetInfo.stackCount + moved, request.item.itemID)
                    remaining = remaining - moved
                end
            end
            for slot = 1, 20 do
                if not destination[slot] and remaining > 0 then
                    local moved = math.min(remaining, maxStack)
                    destination[slot] = Item(moved, request.item.itemID)
                    remaining = remaining - moved
                end
            end
            count = count - remaining
        end
        local slots = state.bags[request.bag]
        local info = slots[request.slot]
        if info then
            local remaining = info.stackCount - count
            slots[request.slot] = remaining > 0 and Item(remaining, info.itemID) or nil
        end
        if request.kind == "destroy" then state.cursor = nil end
        return count
    end
    local function Tick(elapsed)
        for _, frame in ipairs(state.frames) do
            if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, elapsed or 1) end
        end
    end
    local function ClickDestroy()
        for _, frame in ipairs(state.frames) do
            if frame.frameType == "Button" and frame.scripts.OnClick then
                frame.scripts.OnClick()
                return
            end
        end
        error("Missing destroy button")
    end
    local function Messages(fragment)
        local matches = {}
        for _, message in ipairs(state.messages) do
            if message:find(fragment, 1, true) then matches[#matches + 1] = message end
        end
        return matches
    end
    return Wild, state, Fire, RunTimers, RunTimeouts, Apply, Tick, ClickDestroy, Messages, env
end

local tests = {
    { "item variants and repeated events cannot inflate confirmed counts or prices", function()
        local Wild = NewEnvironment()
        local variant = LINK:gsub("item:1:0", "item:1:99")
        local source, target = { [LINK] = 5 }, {}
        local batch = Wild.CreateItemActionBatch(function() return source end, function() return target end)
        Wild.RecordItemAction(batch, { itemID = 1, link = LINK }, 5, 100)
        source, target = {}, { [variant] = 5 }
        local entries, complete = Wild.ConfirmItemActionBatch(batch)
        Equal(#entries, 0)
        Equal(complete, false)
        target = { [LINK] = 2, [variant] = 3 }
        entries, complete = Wild.ConfirmItemActionBatch(batch)
        Equal(entries[1].count, 2)
        Equal(entries[1].copper, 200)
        Equal(complete, false)
        local results = {}
        Wild.MergeItemActionEntries(results, entries)
        entries = Wild.ConfirmItemActionBatch(batch)
        Equal(#entries, 0)
        target = { [LINK] = 5 }
        entries, complete = Wild.ConfirmItemActionBatch(batch)
        Equal(entries[1].count, 3)
        Equal(complete, true)
        Wild.MergeItemActionEntries(results, entries)
        Equal(#results, 1)
        Equal(results[1].count, 5)
        Equal(results[1].copper, 500)
    end },
    { "moving an item into an excluded reagent bag does not prove it was removed", function()
        local Wild, state = NewEnvironment("Bank.lua")
        Wild.db.includeReagentBag = false
        state.bags[0][1] = Item(4)
        local batch = Wild.CreateItemActionBatch(Wild.CapturePlayerItemCounts)
        Wild.RecordItemAction(batch, state.bags[0][1], 4)
        state.bags[0][1], state.bags[5][1] = nil, Item(4)
        local entries, complete = Wild.ConfirmItemActionBatch(batch)
        Equal(#entries, 0)
        Equal(complete, false)
        Equal(#Wild.GetPlayerBags(), 1)
    end },
    { "bank requests and unrelated bag updates do not report completed deposits", function()
        local Wild, state, Fire, RunTimers, _, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[0][1] = Item(5)
        Wild.db.advanced.debug = true
        Wild.db.intents = { { action = "deposit", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        Equal(#state.messages, 0)
        assert(Wild.GetLogCount() > 0)
        Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#state.messages, 0)
        Equal(#state.requests, 1)
        Apply(1)
        Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Deposited "), 1)
        assert(Messages("Deposited ")[1]:find(COUNT .. "5 to Warband bank.", 1, true))
        Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Deposited "), 1)
    end },
    { "unavailable bank targets are skipped without blocking accessible rules", function()
        local Wild, state = NewEnvironment("Bank.lua")
        state.bankTypes[2], state.guildBankOpen = false, false
        state.bags[0][1] = Item(4)
        Wild.db.intents = {
            { action = "deposit", target = "warband", groups = { {} } },
            { action = "deposit", target = "character", groups = { {} } },
        }
        Equal(Wild.RunBankIntents(), true)
        Equal(#state.requests, 1)
        Equal(state.requests[1].target, 6)
    end },
    { "transfers do not withdraw when the destination bank is unavailable", function()
        local Wild, state = NewEnvironment("Bank.lua")
        state.bankTypes[2], state.guildBankOpen = false, false
        state.bags[6][1] = Item(4)
        Wild.db.intents = {
            { action = "transfer", source = "character", target = "warband", groups = { {} } },
        }
        Wild.RunBankIntents()
        Equal(#state.requests, 0)
    end },
    { "manual bank commands report a closed bank without claiming execution", function()
        local Wild, state, _, _, _, _, _, _, _, env = NewEnvironment("Bank.lua", "SlashCommands.lua")
        state.bankTypes[0], state.bankTypes[2], state.guildBankOpen = false, false, false
        Equal(Wild.RunBankIntents(), false)
        env.SlashCmdList.WILD("bank run")
        assert(state.messages[#state.messages]:find("Open an accessible bank", 1, true))
        Equal(#state.requests, 0)
    end },
    { "bank validation needs both source removal and destination receipt", function()
        local Wild, state, Fire, RunTimers, _, _, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[0][1] = Item(4)
        Wild.db.intents = { { action = "deposit", target = "character", groups = { {} } } }
        Wild.RunBankIntents()
        state.bags[0][1] = nil
        Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Deposited "), 0)
        state.bags[6][1] = Item(4)
        Fire("PLAYERBANKSLOTS_CHANGED"); RunTimers()
        Equal(#Messages("Deposited "), 1)
    end },
    { "bank results retain the actual destination when a pending rule is edited", function()
        local Wild, state, Fire, RunTimers, _, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[0][1] = Item(2)
        local intent = { action = "deposit", target = "warband", groups = { {} } }
        Wild.db.intents = { intent }
        Wild.RunBankIntents()
        intent.target = "character"
        Apply(1); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Deposited "), 1)
        assert(Messages("Deposited ")[1]:find("to Warband bank.", 1, true))
        Equal(#Messages("to Character bank."), 0)
    end },
    { "partial bank results are counted once and failed remainder is not claimed", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[0][1] = Item(8)
        Wild.db.intents = { { action = "deposit", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        Apply(1, 3)
        Fire("BAG_UPDATE_DELAYED"); Fire("BAG_UPDATE_DELAYED")
        RunTimers()
        RunTimeouts()
        Equal(#Messages("Deposited "), 1)
        assert(Messages("Deposited ")[1]:find(COUNT .. "3", 1, true))
        Equal(#Messages("confirmed"), 1)
        Equal(#state.requests, 2)
    end },
    { "partial bank passes retry remaining items and combine only confirmed quantities", function()
        local Wild, state, Fire, RunTimers, _, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[0][1] = Item(8)
        Wild.db.intents = { { action = "deposit", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        Apply(1, 3); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Deposited "), 0)
        Equal(state.requests[2].count, 5)
        Apply(2); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Deposited "), 1)
        assert(Messages("Deposited ")[1]:find(COUNT .. "8", 1, true))
    end },
    { "full banks skip refused deposit rules and fill stacks for later rules", function()
        for target, bag in pairs({ character = 6, warband = 12 }) do
            local Wild, state, Fire, RunTimers, RunTimeouts, Apply, _, _, Messages = NewEnvironment("Bank.lua")
            FillBag(state, bag)
            state.bags[bag][20] = Item(198, 2)
            state.bags[0][1], state.bags[0][2] = Item(5), Item(5, 2)
            Wild.db.intents = {
                { action = "deposit", target = target, itemID = 1, groups = { {} } },
                { action = "deposit", target = target, itemID = 2, groups = { {} } },
            }
            Wild.RunBankIntents()
            Equal(Apply(1), 0)
            Fire("BAG_UPDATE_DELAYED"); RunTimeouts(); RunTimers()
            Equal(#state.requests, 2)
            Equal(Apply(2), 2)
            Fire("BAG_UPDATE_DELAYED"); RunTimers()
            Equal(Apply(3), 0)
            RunTimeouts(); RunTimers()
            Equal(#state.requests, 3)
            Equal(state.bags[bag][20].stackCount, 200)
            Equal(state.bags[0][1].stackCount, 5)
            Equal(state.bags[0][2].stackCount, 3)
            Equal(#Messages("Deposited "), 1)
            assert(Messages("Deposited ")[1]:find(COUNT .. "2", 1, true))
            Equal(#Messages("skipped remaining items"), 2)
        end
    end },
    { "full banks try later stacks in the same rule before advancing to the next rule", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        FillBag(state, 12)
        state.bags[12][20] = Item(198, 2)
        state.bags[0][1], state.bags[0][2] = Item(5), Item(5, 2)
        Wild.db.intents = {
            { action = "deposit", target = "warband", groups = { {} } },
            { action = "deposit", target = "character", itemID = 1, groups = { {} } },
        }
        Wild.RunBankIntents()
        Equal(#state.requests, 2)
        Equal(Apply(1), 0)
        Equal(Apply(2), 2)
        Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#state.requests, 4)
        Equal(Apply(3), 0)
        Equal(Apply(4), 0)
        RunTimeouts(); RunTimers()
        Equal(#state.requests, 5)
        Equal(Apply(5), 5)
        Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Deposited "), 2)
        assert(Messages("Deposited ")[1]:find(COUNT .. "2 to Warband bank.", 1, true))
        assert(Messages("Deposited ")[2]:find(COUNT .. "5 to Character bank.", 1, true))
        Equal(state.bags[0][2].stackCount, 3)
    end },
    { "unconfirmed removal or receipt still stops before later bank rules", function()
        for _, removed in ipairs({ true, false }) do
            local Wild, state, Fire, RunTimers, RunTimeouts, _, _, _, Messages = NewEnvironment("Bank.lua")
            state.bags[0][1], state.bags[0][2] = Item(4), Item(2, 2)
            Wild.db.intents = {
                { action = "deposit", target = "warband", itemID = 1, groups = { {} } },
                { action = "deposit", target = "warband", itemID = 2, groups = { {} } },
            }
            Wild.RunBankIntents()
            if removed then state.bags[0][1] = nil
            else state.bags[12][1] = Item(4) end
            Fire("BAG_UPDATE_DELAYED"); RunTimeouts(); RunTimers()
            Equal(#state.requests, 1)
            Equal(#Messages("Deposited "), 0)
            Equal(#Messages("stopped intent processing"), 1)
        end
    end },
    { "an occupied cursor still stops before later bank rules", function()
        local Wild, state, _, RunTimers, RunTimeouts, _, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[0][1], state.bags[0][2] = Item(4), Item(2, 2)
        Wild.db.intents = {
            { action = "deposit", target = "warband", itemID = 1, groups = { {} } },
            { action = "deposit", target = "warband", itemID = 2, groups = { {} } },
        }
        Wild.RunBankIntents()
        state.cursor = { item = Item(4), bag = 0, slot = 1 }
        RunTimeouts(); RunTimers()
        Equal(#state.requests, 1)
        Equal(#Messages("stopped intent processing"), 1)
    end },
    { "late bank receipts during the settle delay are included exactly once", function()
        local Wild, state, Fire, RunTimers, _, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[0][1] = Item(8)
        Wild.db.intents = { { action = "deposit", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        Apply(1, 3); Fire("BAG_UPDATE_DELAYED")
        Apply(1, 5); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#state.requests, 1)
        Equal(#Messages("Deposited "), 1)
        assert(Messages("Deposited ")[1]:find(COUNT .. "8", 1, true))
    end },
    { "multiple stacks and reagent bags produce one completed bank result per item", function()
        local Wild, state, Fire, RunTimers, _, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[0][1], state.bags[5][1] = Item(2), Item(3)
        Wild.db.intents = { { action = "deposit", target = "warband", groups = { {}, {} } } }
        Wild.RunBankIntents()
        Apply(1); Apply(2)
        Fire("BAG_UPDATE_DELAYED")
        -- The overlapping include group requested the same stacks, not extra items.
        RunTimers()
        Equal(#Messages("Deposited "), 1)
        assert(Messages("Deposited ")[1]:find(COUNT .. "5", 1, true))
    end },
    { "withdrawals from every bank wait for validated movement", function()
        for target, bag in pairs({ character = 6, warband = 12, guild = "guild" }) do
            local Wild, state, Fire, RunTimers, _, Apply, _, _, Messages = NewEnvironment("Bank.lua")
            state.bags[bag][1] = Item(2)
            Wild.db.intents = { { action = "withdraw", target = target, groups = { {} } } }
            Wild.RunBankIntents()
            Equal(#state.messages, 0)
            Fire("BAG_UPDATE_DELAYED")
            Equal(#Messages("Withdrew "), 0)
            Apply(1)
            Fire("BAG_UPDATE_DELAYED"); RunTimers()
            Equal(#Messages("Withdrew "), 1)
        end
    end },
    { "full bags skip refused withdrawals and fill stacks for later bank rules", function()
        for target, bag in pairs({ character = 6, warband = 12, guild = "guild" }) do
            local Wild, state, Fire, RunTimers, RunTimeouts, Apply, _, _, Messages = NewEnvironment("Bank.lua")
            FillBag(state, 0); FillBag(state, 5)
            state.bags[0][20] = Item(198, 2)
            state.bags[bag][1], state.bags[bag][2] = Item(5), Item(5, 2)
            Wild.db.intents = {
                { action = "withdraw", target = target, itemID = 1, groups = { {} } },
                { action = "withdraw", target = target, itemID = 2, groups = { {} } },
            }
            Wild.RunBankIntents()
            Equal(Apply(1), 0)
            RunTimeouts(); RunTimers()
            Equal(#state.requests, 2)
            Equal(Apply(2), 2)
            Fire("BAG_UPDATE_DELAYED"); RunTimers()
            Equal(Apply(3), 0)
            RunTimeouts(); RunTimers()
            Equal(#state.requests, 3)
            Equal(state.bags[0][20].stackCount, 200)
            Equal(state.bags[bag][1].stackCount, 5)
            Equal(state.bags[bag][2].stackCount, 3)
            Equal(#Messages("Withdrew "), 1)
            assert(Messages("Withdrew ")[1]:find(COUNT .. "2", 1, true))
        end
    end },
    { "withdrawal receipts in an excluded reagent bag are still observed without enabling its rules", function()
        local Wild, state, Fire, RunTimers, _, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        Wild.db.includeReagentBag = false
        state.bags[12][1] = Item(3)
        Wild.db.intents = { { action = "withdraw", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        state.requests[1].target = 5
        Apply(1); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Withdrew "), 1)
        Equal(#Wild.GetPlayerBags(), 1)
    end },
    { "transfers report only after both phases are validated", function()
        local Wild, state, Fire, RunTimers, _, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[6][1] = Item(3)
        state.bags[0][1] = Item(4, 2)
        Wild.db.intents = { { action = "transfer", source = "character", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        Equal(#state.messages, 0)
        Fire("BAG_UPDATE_DELAYED")
        Equal(#state.requests, 1)
        Apply(1); Fire("BAG_UPDATE_DELAYED")
        Equal(#Messages("Transferred "), 0)
        Equal(#state.requests, 2)
        Equal(state.requests[2].item.itemID, 1)
        Equal(state.requests[2].count, 3)
        Apply(2); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Transferred "), 1)
        Equal(#Messages("Withdrew "), 0)
        Equal(#Messages("Deposited "), 0)
    end },
    { "a refused transfer deposit reports a withdrawal, never a transfer", function()
        local Wild, state, Fire, _, RunTimeouts, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[6][1] = Item(3)
        Wild.db.intents = { { action = "transfer", source = "character", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        Apply(1); Fire("BAG_UPDATE_DELAYED")
        RunTimeouts()
        Equal(#Messages("Transferred "), 0)
        Equal(#Messages("Withdrew "), 1)
        Equal(#Messages("confirmed"), 1)
    end },
    { "a transfer with no eligible deposit continues to later bank rules", function()
        local Wild, state, Fire, RunTimers, _, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[6][1], state.bags[0][1] = Item(3), Item(2, 2)
        local intent = { action = "transfer", source = "character", target = "warband", itemID = 1, groups = { {} } }
        Wild.db.intents = {
            intent,
            { action = "deposit", target = "warband", itemID = 2, groups = { {} } },
        }
        Wild.RunBankIntents()
        Apply(1)
        intent.itemID = 2
        Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#state.requests, 2)
        Equal(state.requests[2].kind, "deposit")
        Equal(state.requests[2].item.itemID, 2)
        Apply(2); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Transferred "), 0)
        Equal(#Messages("Withdrew "), 1)
        assert(Messages("Withdrew ")[1]:find(COUNT .. "3 from Character bank.", 1, true))
        Equal(#Messages("Deposited "), 1)
        Equal(#Messages("skipped remaining items"), 1)
    end },
    { "partial transfer deposits retry only the remaining withdrawn quantity", function()
        local Wild, state, Fire, RunTimers, _, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[6][1] = Item(5)
        state.bags[0][1] = Item(8)
        Wild.db.intents = { { action = "transfer", source = "character", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        Apply(1); Fire("BAG_UPDATE_DELAYED")
        Equal(state.requests[2].count, 5)
        Apply(2, 2); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Transferred "), 0)
        Equal(state.requests[3].count, 3)
        Apply(3); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Transferred "), 1)
        assert(Messages("Transferred ")[1]:find(COUNT .. "5", 1, true))
        Equal(state.bags[0][1].stackCount, 8)
        Equal(#Messages("Withdrew "), 0)
    end },
    { "full transfer targets still receive stackable items from later rules", function()
        for _, banks in ipairs({
            { source = "character", sourceBag = 6, target = "warband", targetBag = 12 },
            { source = "warband", sourceBag = 12, target = "character", targetBag = 6 },
        }) do
            local Wild, state, Fire, RunTimers, RunTimeouts, Apply, _, _, Messages = NewEnvironment("Bank.lua")
            FillBag(state, banks.targetBag)
            state.bags[banks.targetBag][20] = Item(198, 2)
            state.bags[banks.sourceBag][1], state.bags[banks.sourceBag][2] = Item(5), Item(5, 2)
            Wild.db.intents = {
                { action = "transfer", source = banks.source, target = banks.target, itemID = 1, groups = { {} } },
                { action = "transfer", source = banks.source, target = banks.target, itemID = 2, groups = { {} } },
            }
            Wild.RunBankIntents()
            Equal(Apply(1), 5)
            Fire("BAG_UPDATE_DELAYED")
            Equal(Apply(2), 0)
            RunTimeouts(); RunTimers()
            Equal(#state.requests, 3)
            Equal(Apply(3), 5)
            Fire("BAG_UPDATE_DELAYED")
            Equal(Apply(4), 2)
            Fire("BAG_UPDATE_DELAYED"); RunTimers()
            Equal(Apply(5), 0)
            RunTimeouts(); RunTimers()
            Equal(#state.requests, 5)
            Equal(state.bags[banks.targetBag][20].stackCount, 200)
            Equal(state.bags[0][1].stackCount, 5)
            Equal(state.bags[0][2].stackCount, 3)
            Equal(#Messages("Transferred "), 1)
            assert(Messages("Transferred ")[1]:find(COUNT .. "2", 1, true))
            Equal(#Messages("Withdrew "), 2)
            assert(Messages("Withdrew ")[1]:find(COUNT .. "5", 1, true))
            assert(Messages("Withdrew ")[2]:find(COUNT .. "3", 1, true))
            Equal(#Messages("Deposited "), 0)
        end
    end },
    { "gold-only hold rules wait for matching player and bank balances", function()
        for _, target in ipairs({ "warband", "guild" }) do
            local Wild, state, Fire, RunTimers, _, Apply, _, _, Messages = NewEnvironment("Bank.lua")
            Wild.db.intents = { { action = "hold", target = target, gold = 5 } }
            Wild.RunBankIntents()
            Equal(#state.messages, 0)
            Fire("PLAYER_MONEY")
            Equal(#state.messages, 0)
            Apply(1); Fire(target == "guild" and "GUILDBANK_UPDATE_MONEY" or "ACCOUNT_MONEY")
            RunTimers()
            Equal(#Messages("Deposited 50000 copper"), 1)
        end
    end },
    { "unconfirmed gold still stops before later bank rules", function()
        local Wild, state, _, RunTimers, RunTimeouts, _, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[0][1] = Item(2)
        Wild.db.intents = {
            { action = "hold", target = "warband", gold = 5 },
            { action = "deposit", target = "warband", groups = { {} } },
        }
        Wild.RunBankIntents()
        RunTimeouts(); RunTimers()
        Equal(#state.requests, 1)
        Equal(#Messages("Deposited "), 0)
        Equal(#Messages("stopped intent processing"), 1)
    end },
    { "closed banks discard unconfirmed requests and scheduled retries", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, _, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[0][1] = Item()
        Wild.db.intents = { { action = "deposit", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        Fire("BANKFRAME_CLOSED")
        RunTimers(); RunTimeouts(); Fire("BAG_UPDATE_DELAYED")
        Equal(#Messages("Deposited "), 0)
        Equal(#state.requests, 1)
    end },
    { "closing a bank before its start delay cannot start a new queue", function()
        for _, event in ipairs({ "BANKFRAME_OPENED", "GUILDBANKFRAME_OPENED" }) do
            local Wild, state, Fire, RunTimers, RunTimeouts = NewEnvironment("Bank.lua")
            state.bags[0][1], state.bags.guild[1] = Item(), Item()
            Wild.db.intents = {
                { action = "deposit", target = "warband", groups = { {} } },
                { action = "withdraw", target = "guild", groups = { {} } },
            }
            Fire(event); Fire("BANKFRAME_CLOSED")
            RunTimers(); RunTimeouts(); RunTimers()
            Equal(#state.requests, 0)
        end
    end },
    { "the selected key skips intent rules for one interaction, even if an open event repeats after release", function()
        local interactions = {
            { "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "Banker", "SHIFT", "deposit", "character" },
            { "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "AccountBanker", "ALT", "deposit", "warband", modernFirst = true },
            { "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GuildBanker", "CTRL", "withdraw", "guild", modernFirst = true },
            { "MERCHANT_SHOW", "MERCHANT_CLOSED", "Merchant", "SHIFT", "sell", modernFirst = true },
            { "MAIL_SHOW", "MAIL_CLOSED", nil, "ALT", "mail" },
        }
        for _, interaction in ipairs(interactions) do
            local open, close, interactionName, key, action, target = unpack(interaction, 1, 6)
            local Wild, state, Fire, RunTimers, _, _, Tick, ClickDestroy, _, env =
                NewEnvironment("Bank.lua", "Inventory.lua", "Vendor.lua", "Mail.lua")
            local interactionType = env.Enum.PlayerInteractionType[interactionName]
            local modernOpen = "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
            local modernClose = "PLAYER_INTERACTION_MANAGER_FRAME_HIDE"
            Wild.SetSetting("intentBypassModifier", key)
            Wild.db.intents = {
                { action = action, target = target, recipient = "Alt-Realm", groups = { {} }, itemID = 1 },
                { action = "destroy", groups = { {} }, itemID = 2 },
            }
            state.bags[0][1], state.bags[0][2], state.bags.guild[1] = Item(), Item(1, 2), Item()
            state.selling = action == "sell"

            state.modifiers[key] = true
            if interaction.modernFirst then Fire(modernOpen, interactionType) else Fire(open) end
            state.modifiers[key] = false
            state.time = state.time + 2
            if interactionType and not interaction.modernFirst then Fire(modernOpen, interactionType) else Fire(open) end
            RunTimers(); RunTimers(); Tick(); ClickDestroy()
            Equal(#state.requests, 0)
            Equal(#state.sent, 0)

            if interaction.modernFirst then Fire(modernClose, interactionType) else Fire(close) end
            state.modifiers[key == "SHIFT" and "CTRL" or "SHIFT"] = true
            Fire(open)
            state.modifiers[key] = true
            RunTimers(); RunTimers(); Tick()
            if action == "mail" then
                Equal(state.sent[1], "Alt-Realm")
            else
                Equal(#state.requests, 1)
                Equal(state.requests[1].kind, action)
                ClickDestroy()
                Equal(#state.requests, 2)
                Equal(state.requests[2].kind, "destroy")
            end
        end
    end },
    { "closing a normal vendor visit cancels pending automatic rules before a bypassed visit", function()
        local Wild, state, Fire, RunTimers, _, _, Tick, ClickDestroy = NewEnvironment("Inventory.lua", "Vendor.lua")
        Wild.SetSetting("intentBypassModifier", "SHIFT")
        Wild.db.intents = {
            { action = "sell", groups = { {} }, itemID = 1 },
            { action = "destroy", groups = { {} }, itemID = 2 },
        }
        state.bags[0][1], state.bags[0][2] = Item(), Item(1, 2)
        state.selling = true
        Fire("MERCHANT_SHOW")
        Fire("MERCHANT_CLOSED")
        state.modifiers.SHIFT = true
        Fire("MERCHANT_SHOW")
        RunTimers(); RunTimers(); Tick(); ClickDestroy()
        Equal(#state.requests, 0)
    end },
    { "an intent bypass leaves independent automation, loot triggers, and manual bank rules available", function()
        local Wild, state, Fire, RunTimers, _, _, _, ClickDestroy, _, env =
            NewEnvironment("Bank.lua", "Inventory.lua", "Vendor.lua", "SlashCommands.lua")
        Wild.SetSetting("intentBypassModifier", "SHIFT")
        Wild.db.intents = {
            { action = "deposit", target = "character", groups = { {} }, itemID = 1 },
            { action = "destroy", groups = { {} }, itemID = 2 },
        }
        Wild.db.bankWarband = { enabled = true, depositWarbound = true }
        Wild.db.vendorAutoRepair = true
        local deposits, repairs = 0, 0
        env.C_Bank.AutoDepositItemsIntoBank = function() deposits = deposits + 1 end
        env.CanMerchantRepair = function() return true end
        env.GetRepairAllCost = function() return 10, true end
        env.RepairAllItems = function() repairs = repairs + 1 end
        state.bags[0][1], state.bags[0][2] = Item(), Item(1, 2)
        state.modifiers.SHIFT = true
        Fire("MERCHANT_SHOW"); Fire("MERCHANT_CLOSED")
        Fire("BANKFRAME_OPENED")
        RunTimers(); RunTimers()
        Equal(deposits, 1)
        Equal(repairs, 1)
        Equal(#state.requests, 0)
        env.SlashCmdList.WILD("bank run")
        Equal(state.requests[1].kind, "deposit")
        Fire("LOOT_CLOSED")
        RunTimers(); ClickDestroy()
        Equal(state.requests[2].kind, "destroy")
    end },
    { "holding the configured key at mailbox open skips inbox collection for that visit", function()
        for _, key in ipairs({ "SHIFT", "CTRL", "ALT" }) do
            local Wild, state, Fire, RunTimers = NewEnvironment("Mail.lua")
            Wild.SetSetting("intentBypassModifier", key)
            Wild.db.mail.autoOpen = true
            state.inboxCount = 2
            state.modifiers[key] = true
            Fire("MAIL_SHOW")
            state.modifiers[key] = false
            Fire("MAIL_SHOW")
            RunTimers(); RunTimers()
            Equal(state.inboxCount, 2)

            Fire("MAIL_CLOSED")
            state.modifiers[key == "SHIFT" and "CTRL" or "SHIFT"] = true
            Fire("MAIL_SHOW")
            RunTimers(); RunTimers()
            Equal(state.inboxCount, 0)
        end
    end },
    { "None lets inbox collection run with a modifier held", function()
        local Wild, state, Fire, RunTimers = NewEnvironment("Mail.lua")
        Wild.SetSetting("intentBypassModifier", "NONE")
        Wild.db.mail.autoOpen = true
        state.inboxCount = 1
        state.modifiers.SHIFT = true
        Fire("MAIL_SHOW")
        RunTimers()
        Equal(state.inboxCount, 0)
    end },
    { "inbox collection from a closed mailbox cannot continue in a bypassed visit", function()
        local Wild, state, Fire, RunTimers = NewEnvironment("Mail.lua")
        Wild.SetSetting("intentBypassModifier", "SHIFT")
        Wild.db.mail.autoOpen = true
        state.inboxCount = 2
        Fire("MAIL_SHOW")
        RunTimers()
        Equal(state.inboxCount, 1)

        Fire("MAIL_CLOSED")
        state.modifiers.SHIFT = true
        Fire("MAIL_SHOW")
        RunTimers()
        Equal(state.inboxCount, 1)
    end },
    { "vendor requests are not sales until the matching item count decreases", function()
        local Wild, state, Fire, RunTimers, _, Apply, Tick, _, Messages = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1] = Item(4)
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers()
        Tick(); Tick()
        Equal(#Messages("Sold "), 0)
        Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Sold "), 0)
        Apply(1); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Sold "), 1)
        assert(Messages("Sold ")[1]:find(COUNT .. "4 for 400 copper", 1, true))
        Equal(#Messages("Auto-sold 4 item(s) for 400 copper."), 1)
    end },
    { "vendor updates arriving before the batch ends are retained and stacks are combined", function()
        local Wild, state, Fire, RunTimers, _, Apply, Tick, _, Messages = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1], state.bags[0][2] = Item(2), Item(3)
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers()
        Tick(); Apply(1); Fire("BAG_UPDATE_DELAYED")
        Tick(); Apply(2); Fire("BAG_UPDATE_DELAYED")
        Tick(); RunTimers()
        Equal(#Messages("Sold "), 1)
        assert(Messages("Sold ")[1]:find(COUNT .. "5 for 500 copper", 1, true))
    end },
    { "partial vendor passes retry unsold quantities without inflating money totals", function()
        local Wild, state, Fire, RunTimers, _, Apply, Tick, _, Messages = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1] = Item(4)
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers()
        Tick(); Tick()
        Apply(1, 2); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Sold "), 0)
        Tick(); Tick()
        Equal(state.requests[2].count, 2)
        Apply(2); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Sold "), 1)
        assert(Messages("Sold ")[1]:find(COUNT .. "4 for 400 copper", 1, true))
    end },
    { "vendor timeouts and changed bag slots never claim an unconfirmed sale", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, _, Tick, _, Messages = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1] = Item()
        Wild.db.intents = { { action = "sell", itemID = 1, groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers()
        state.bags[0][1] = Item(1, 2)
        Tick(); Tick(); RunTimers(); RunTimeouts()
        Equal(#state.requests, 0)
        Equal(#Messages("Sold "), 0)
        Equal(#Messages("Auto-sold "), 0)
    end },
    { "refused vendor sales produce a warning instead of inflated totals", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, _, Tick, _, Messages = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1] = Item(4)
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers()
        Tick(); Tick(); RunTimeouts()
        Equal(#Messages("Sold "), 0)
        Equal(#Messages("Auto-sold "), 0)
        Equal(#Messages("confirmed"), 1)
        Equal(#state.requests, 1)
    end },
    { "mail logs actual stack counts only on MAIL_SEND_SUCCESS", function()
        local Wild, state, Fire, RunTimers, _, _, _, _, Messages = NewEnvironment("Bank.lua", "Mail.lua")
        state.bags[0][1], state.bags[0][2] = Item(2), Item(3)
        Wild.db.intents = { { action = "mail", recipient = "Alt-Realm", groups = { {} } } }
        Fire("MAIL_SHOW"); RunTimers(); RunTimers()
        Equal(#state.sent, 1)
        Equal(state.subject, "Wild: 5 item(s)")
        Equal(#state.messages, 0)
        Fire("BAG_UPDATE_DELAYED")
        Equal(#Messages("Mailed "), 0)
        Fire("MAIL_SEND_SUCCESS"); RunTimers()
        Equal(#Messages("Mailed "), 1)
        assert(Messages("Mailed ")[1]:find(COUNT .. "5 to Alt-Realm.", 1, true))
        Equal(#Messages("Mail complete: 5 item(s)"), 1)
    end },
    { "mail prepares the native send tab and preserves full recipient names in both clients", function()
        for _, case in ipairs({
            { forever = true, recipient = "Alt Family" },
            { forever = true, recipient = "Alt Family-Realm", reply = true },
            { forever = false, recipient = "Alt-Realm" },
        }) do
            local Wild, state, Fire, RunTimers, _, _, _, _, _, env = NewEnvironment("Bank.lua", "Mail.lua")
            Wild.isForever, Wild.isRetail = case.forever, not case.forever
            state.bags[0][1] = Item(3)
            local intent = { action = "mail", recipient = case.recipient, groups = { {} } }
            Wild.db.intents = { intent }
            env.SendMailSubjectEditBox:SetText("Old subject")
            env.SendMailBodyEditBox:SetText("Old body")
            if case.reply then
                state.mailTab = 2
                env.SendMailFrame.sendMode = "reply"
            end
            local send = env.SendMail
            env.SendMail = function(recipient, subject, body)
                Equal(state.mailTab, 2)
                Equal(env.SendMailFrame.sendMode, "send")
                Equal(env.SendMailNameEditBox:GetText(), case.recipient)
                Equal(env.SendMailSubjectEditBox:GetText(), "Wild: 3 item(s)")
                Equal(env.SendMailBodyEditBox:GetText(), "")
                Equal(recipient, case.recipient)
                Equal(subject, env.SendMailSubjectEditBox:GetText())
                Equal(body, env.SendMailBodyEditBox:GetText())
                send(recipient, subject)
            end
            Fire("MAIL_SHOW"); RunTimers(); RunTimers()
            Equal(#state.sent, 1)
            Equal(intent.recipient, case.recipient)
            Equal(#ActionEntries(Wild, "mail"), 0)
            Fire("MAIL_SEND_SUCCESS")
            Equal(ActionEntries(Wild, "mail")[1].recipient, case.recipient)
        end
    end },
    { "each mail batch restores native fields after the client clears them", function()
        local Wild, state, Fire, RunTimers, _, _, _, _, _, env = NewEnvironment("Bank.lua", "Mail.lua")
        for slot = 1, 13 do state.bags[0][slot] = Item(2) end
        Wild.db.intents = { { action = "mail", recipient = "Alt Family", groups = { {} } } }
        local send = env.SendMail
        env.SendMail = function(recipient, subject, body)
            Equal(state.mailTab, 2)
            Equal(env.SendMailNameEditBox:GetText(), "Alt Family")
            Equal(env.SendMailSubjectEditBox:GetText(), subject)
            Equal(env.SendMailBodyEditBox:GetText(), body)
            send(recipient, subject)
        end
        Fire("MAIL_SHOW"); RunTimers(); RunTimers()
        Equal(#state.sent, 1)
        Fire("MAIL_SEND_SUCCESS")
        env.SendMailNameEditBox:SetText("")
        env.SendMailSubjectEditBox:SetText("")
        env.SendMailBodyEditBox:SetText("")
        env.MailFrameTab_OnClick(nil, 1)
        RunTimers()
        Equal(#state.sent, 2)
        Equal(state.subject, "Wild: 2 item(s)")
    end },
    { "missing native mail controls stop the queue before moving items", function()
        local Wild, state, Fire, RunTimers, _, _, _, _, Messages, env = NewEnvironment("Bank.lua", "Mail.lua")
        state.bags[0][1] = Item(3)
        Wild.db.intents = { { action = "mail", recipient = "Alt Family", groups = { {} } } }
        env.SendMailNameEditBox = nil
        Fire("MAIL_SHOW"); RunTimers(); RunTimers()
        Equal(#state.sent, 0)
        Equal(state.bags[0][1].stackCount, 3)
        Equal(next(state.attachments), nil)
        Equal(#ActionEntries(Wild, "mail"), 0)
        Equal(#Messages("Mail send controls are unavailable"), 1)
    end },
    { "failed or refused mail produces no success log and cannot resume later", function()
        for _, refuse in ipairs({ false, true }) do
            local Wild, state, Fire, RunTimers, RunTimeouts, _, _, _, Messages = NewEnvironment("Bank.lua", "Mail.lua")
            state.bags[0][1] = Item(2)
            state.refuseAttachment = refuse
            Wild.db.intents = { { action = "mail", recipient = "Alt-Realm", groups = { {} } } }
            Fire("MAIL_SHOW"); RunTimers(); RunTimers()
            Fire("MAIL_FAILED"); Fire("MAIL_SEND_SUCCESS"); Fire("BAG_UPDATE_DELAYED")
            RunTimers(); RunTimeouts()
            Equal(#Messages("Mailed "), 0)
            Equal(#Messages("Mail complete:"), 0)
            Equal(#state.sent, refuse and 0 or 1)
        end
    end },
    { "closed mailboxes cancel delayed sends and ignore later success events", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, _, _, _, Messages = NewEnvironment("Bank.lua", "Mail.lua")
        state.bags[0][1] = Item(2)
        Wild.db.intents = { { action = "mail", recipient = "Alt-Realm", groups = { {} } } }
        Fire("MAIL_SHOW"); RunTimers()
        Fire("MAIL_CLOSED"); RunTimers(); RunTimeouts()
        Fire("MAIL_SEND_SUCCESS")
        Equal(#state.sent, 0)
        Equal(#Messages("Mailed "), 0)
    end },
    { "a late mail success is reported after closing without sending another queued batch", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, _, _, _, Messages = NewEnvironment("Bank.lua", "Mail.lua")
        for slot = 1, 13 do state.bags[0][slot] = Item(2) end
        Wild.db.intents = { { action = "mail", recipient = "Alt-Realm", groups = { {} } } }
        Fire("MAIL_SHOW"); RunTimers(); RunTimers()
        Equal(#state.sent, 1)
        Fire("MAIL_CLOSED"); Fire("MAIL_SEND_SUCCESS")
        RunTimers(); RunTimeouts()
        Equal(#state.sent, 1)
        Equal(#Messages("Mailed "), 1)
        assert(Messages("Mailed ")[1]:find(COUNT .. "24 to Alt-Realm.", 1, true))
        Equal(#Messages("Mail complete:"), 0)
    end },
    { "destroy requests wait for bag removal and an empty cursor before logging", function()
        local Wild, state, Fire, _, _, Apply, _, ClickDestroy, Messages = NewEnvironment("Bank.lua", "Inventory.lua")
        state.bags[0][1] = Item(7)
        local completed
        Wild.QueueDestroyItems({ { itemID = 1, bag = 0, slot = 1, link = LINK, count = 7 } },
            function(count) completed = count end)
        ClickDestroy(); ClickDestroy()
        Equal(#state.requests, 1)
        Equal(#Messages("Destroyed "), 0)
        Equal(completed, nil)
        Fire("BAG_UPDATE_DELAYED")
        Equal(#Messages("Destroyed "), 0)
        Apply(1); Fire("BAG_UPDATE_DELAYED")
        Equal(#Messages("Destroyed "), 1)
        assert(Messages("Destroyed ")[1]:find(COUNT .. "7", 1, true))
        Equal(completed, 7)
        Fire("BAG_UPDATE_DELAYED")
        Equal(#Messages("Destroyed "), 1)
    end },
    { "moving an item onto the cursor does not prove it was destroyed", function()
        local Wild, state, Fire, _, RunTimeouts, _, _, ClickDestroy, Messages = NewEnvironment("Bank.lua", "Inventory.lua")
        state.bags[0][1] = Item(2)
        state.removeOnPickup = true
        Wild.QueueDestroyItems({ { itemID = 1, bag = 0, slot = 1, link = LINK, count = 2 } })
        ClickDestroy(); Fire("BAG_UPDATE_DELAYED"); RunTimeouts()
        Equal(#Messages("Destroyed "), 0)
        Equal(state.bags[0][1].stackCount, 2)
        Equal(#Messages("confirmed"), 1)
    end },
    { "typed destroy popups remain pending until the player confirms deletion", function()
        local Wild, state, Fire, _, RunTimeouts, Apply, _, ClickDestroy, Messages = NewEnvironment("Bank.lua", "Inventory.lua")
        state.bags[0][1] = Item(2)
        state.removeOnPickup, state.askForDeleteConfirmation = true, true
        local completed
        Wild.QueueDestroyItems({ { itemID = 1, bag = 0, slot = 1, link = LINK, count = 2 } },
            function(count) completed = count end)
        ClickDestroy(); RunTimeouts()
        Equal(#state.messages, 0)
        Equal(completed, nil)
        assert(state.cursor, "A safety timeout must not cancel the player's typed confirmation")
        state.deletePopup = false
        Apply(1); Fire("BAG_UPDATE_DELAYED")
        Equal(completed, 2)
        Equal(#Messages("Destroyed "), 1)
    end },
    { "canceling a typed destroy popup does not count its picked-up item as deleted", function()
        local Wild, state, Fire, _, RunTimeouts, _, _, ClickDestroy, Messages, env = NewEnvironment("Bank.lua", "Inventory.lua")
        state.bags[0][1] = Item(2)
        state.removeOnPickup, state.askForDeleteConfirmation = true, true
        Wild.QueueDestroyItems({ { itemID = 1, bag = 0, slot = 1, link = LINK, count = 2 } })
        ClickDestroy(); RunTimeouts()
        state.deletePopup = false
        env.ClearCursor()
        Fire("BAG_UPDATE_DELAYED")
        Equal(#Messages("Destroyed "), 0)
        Equal(state.bags[0][1].stackCount, 2)
        Equal(#Messages("confirmed"), 1)
    end },
    { "a late vendor confirmation survives a partially completed batch", function()
        local Wild, state, Fire, RunTimers, _, Apply, Tick, _, Messages = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1], state.bags[0][2] = Item(2), Item(3, 2)
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers()
        Tick(); Apply(1); Fire("BAG_UPDATE_DELAYED")
        Tick(); Fire("BAG_UPDATE_DELAYED"); Tick(); RunTimers()
        Apply(2); Fire("BAG_UPDATE_DELAYED")
        Tick(); Tick(); RunTimers()
        Equal(#Messages("Sold "), 2)
        Equal(#Messages("Auto-sold 5 item(s) for 500 copper."), 1)
        Equal(#state.requests, 2)
    end },
    { "vendor confirmations are saved before a later refused item ends the run", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, Apply, Tick, _, Messages = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1], state.bags[0][2] = Item(2), Item(3, 2)
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers()
        Tick(); Apply(1); Fire("BAG_UPDATE_DELAYED")
        local entries = ActionEntries(Wild, "sell")
        Equal(#entries, 1)
        Equal(entries[1].itemID, 1)
        Equal(entries[1].count, 2)
        Equal(entries[1].copper, 200)
        Equal(entries[1].status, "confirmed")
        Tick(); Tick(); RunTimeouts(); RunTimers()
        Tick(); Tick(); RunTimeouts(); RunTimers()
        Equal(#Messages("Sold "), 1)
        Equal(#Messages("Auto-sold 2 item(s) for 200 copper."), 1)
        Equal(#ActionEntries(Wild, "sell"), 1)
    end },
    { "retrying one item does not discard late confirmations for other item variants", function()
        local Wild, state, Fire, RunTimers, _, Apply, Tick, _, Messages = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1], state.bags[0][2], state.bags[0][3] = Item(2), Item(3, 2), Item(4, 3)
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers()
        Tick(); Apply(1); Fire("BAG_UPDATE_DELAYED")
        Tick(); Tick(); Fire("BAG_UPDATE_DELAYED"); Tick(); RunTimers()
        Tick()
        Equal(#state.requests, 4)
        Apply(3); Fire("BAG_UPDATE_DELAYED")
        Apply(2); Fire("BAG_UPDATE_DELAYED")
        Tick(); Tick(); RunTimers()
        Equal(#Messages("Sold "), 3)
        Equal(#Messages("Auto-sold 9 item(s) for 900 copper."), 1)
        Equal(#state.requests, 4)
        local total = 0
        for _, entry in ipairs(ActionEntries(Wild, "sell")) do total = total + entry.count end
        Equal(total, 9)
    end },
    { "vendor requests retain the configured rate without waiting between items", function()
        local Wild, state, Fire, RunTimers, _, _, Tick = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1], state.bags[0][2] = Item(2), Item(3, 2)
        Wild.db.advanced.sellInterval = 0.2
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers()
        Tick(0.01)
        Equal(#state.requests, 1)
        Tick(0.1)
        Equal(#state.requests, 1)
        Tick(0.1)
        Equal(#state.requests, 2)
    end },
    { "synchronous bank completion does not wait for a confirmation timeout", function()
        local Wild, state, Fire, RunTimers, _, Apply, _, _, Messages, env = NewEnvironment("Bank.lua")
        state.bags[0][1] = Item(3)
        Wild.db.intents = { { action = "deposit", target = "warband", groups = { {} } } }
        local use = env.C_Container.UseContainerItem
        env.C_Container.UseContainerItem = function(...)
            use(...)
            Apply(#state.requests)
            Fire("BAG_UPDATE_DELAYED")
        end
        Wild.RunBankIntents(); RunTimers()
        Equal(#Messages("Deposited "), 1)
        Equal(#state.requests, 1)
    end },
    { "confirmed bank results and the exact refused remainder are saved without debug mode", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, Apply = NewEnvironment("Bank.lua")
        state.bags[0][1] = Item(8)
        Wild.db.intents = { { action = "deposit", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        Apply(1, 3); Fire("BAG_UPDATE_DELAYED")
        local entries = ActionEntries(Wild, "deposit")
        Equal(#entries, 1)
        Equal(entries[1].count, 3)
        Equal(entries[1].source, "bags")
        Equal(entries[1].target, "warband")
        RunTimers(); RunTimeouts()
        Equal(#ActionEntries(Wild, "deposit"), 1)
        local failures = {}
        for _, entry in ipairs(Wild.GetLogEntries()) do
            if entry.kind == "warning" and entry.itemID == 1 then failures[#failures + 1] = entry end
        end
        Equal(#failures, 1)
        Equal(failures[1].action, "deposit")
        Equal(failures[1].unconfirmedCount, 5)
        Equal(failures[1].target, "warband")
        Equal(failures[1].status, "unconfirmed")
    end },
    { "transfer history separates completed transfers from withdrawals left in bags", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, Apply = NewEnvironment("Bank.lua")
        state.bags[6][1] = Item(5)
        Wild.db.intents = { { action = "transfer", source = "character", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        Apply(1); Fire("BAG_UPDATE_DELAYED")
        Equal(#ActionEntries(Wild, "withdraw"), 0)
        Apply(2, 2); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        RunTimeouts()
        local transfers, withdrawals = ActionEntries(Wild, "transfer"), ActionEntries(Wild, "withdraw")
        Equal(#transfers, 1)
        Equal(transfers[1].count, 2)
        Equal(transfers[1].source, "character")
        Equal(transfers[1].target, "warband")
        Equal(#withdrawals, 1)
        Equal(withdrawals[1].count, 3)
        Equal(withdrawals[1].source, "character")
        Equal(withdrawals[1].target, "bags")
    end },
    { "failed mail retains the summary and history of earlier successful batches", function()
        local Wild, state, Fire, RunTimers, _, _, _, _, Messages = NewEnvironment("Bank.lua", "Mail.lua")
        for slot = 1, 13 do state.bags[0][slot] = Item(2) end
        Wild.db.intents = { { action = "mail", recipient = "Alt-Realm", groups = { {} } } }
        Fire("MAIL_SHOW"); RunTimers(); RunTimers()
        Fire("BAG_UPDATE_DELAYED"); Fire("MAIL_SEND_SUCCESS"); RunTimers()
        Equal(#state.sent, 2)
        Fire("MAIL_FAILED"); RunTimers()
        Equal(#Messages("Mail stopped: 24 item(s) sent"), 1)
        Equal(#Messages("Mail complete:"), 0)
        local entries = ActionEntries(Wild, "mail")
        Equal(#entries, 1)
        Equal(entries[1].count, 24)
        Equal(entries[1].recipient, "Alt-Realm")
    end },
    { "a mail timeout preserves the pending acknowledgment without resuming the queue", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, _, _, _, Messages = NewEnvironment("Bank.lua", "Mail.lua")
        for slot = 1, 13 do state.bags[0][slot] = Item(2) end
        Wild.db.intents = { { action = "mail", recipient = "Alt-Realm", groups = { {} } } }
        Fire("MAIL_SHOW"); RunTimers(); RunTimers(); RunTimeouts()
        Equal(#Messages("Mailed "), 0)
        Fire("MAIL_SEND_SUCCESS"); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Mailed "), 1)
        Equal(#Messages("Mail stopped: 24 item(s) sent"), 1)
        Equal(#Messages("Mail complete:"), 0)
        Equal(#state.sent, 1)
        Equal(ActionEntries(Wild, "mail")[1].count, 24)
    end },
    { "mail checks all attachment slots before preparing an automated send", function()
        local Wild, state, Fire, RunTimers, _, _, _, _, Messages = NewEnvironment("Bank.lua", "Mail.lua")
        state.bags[0][1], state.attachments[2] = Item(2), Item(3, 2)
        Wild.db.intents = { { action = "mail", recipient = "Alt-Realm", groups = { {} } } }
        Fire("MAIL_SHOW"); RunTimers(); RunTimers()
        Equal(#state.sent, 0)
        Equal(state.bags[0][1].stackCount, 2)
        Equal(state.attachments[2].stackCount, 3)
        Equal(#Messages("Mailed "), 0)
        Equal(#Messages("already occupied"), 1)
    end },
    { "destroy confirmations are saved while another item still awaits a click", function()
        local Wild, state, Fire, _, _, Apply, _, ClickDestroy = NewEnvironment("Bank.lua", "Inventory.lua")
        state.bags[0][1], state.bags[0][2] = Item(2), Item(3, 2)
        Wild.QueueDestroyItems({
            { itemID = 1, bag = 0, slot = 1, link = LINK, count = 2 },
            { itemID = 2, bag = 0, slot = 2, link = OTHER_LINK, count = 3 },
        })
        ClickDestroy(); Apply(1); Fire("BAG_UPDATE_DELAYED")
        local entries = ActionEntries(Wild, "destroy")
        Equal(#entries, 1)
        Equal(entries[1].itemID, 1)
        Equal(entries[1].count, 2)
        Fire("BAG_UPDATE_DELAYED")
        Equal(#ActionEntries(Wild, "destroy"), 1)
    end },
    { "saved action records do not change when the original result changes", function()
        local Wild = NewEnvironment()
        local result = { key = LINK, link = LINK, itemID = 1, count = 3, copper = 300 }
        Wild.LogAction("Vendor", "sell", result)
        result.count, result.copper = 99, 9900
        local entries = ActionEntries(Wild, "sell")
        Equal(#entries, 1)
        Equal(entries[1].count, 3)
        Equal(entries[1].copper, 300)
        assert(not entries[1].m:find("|T", 1, true))
        Equal(#Wild.GetLogEntries("vendor"), 1)
        Wild.ClearLog()
        Equal(Wild.GetLogCount(), 0)
    end },
    { "the shared action log retains its bounded chronological order", function()
        local Wild = NewEnvironment()
        for count = 1, 5002 do
            Wild.LogAction("Inventory", "destroy", { key = LINK, link = LINK, itemID = 1, count = count })
        end
        local entries = Wild.GetLogEntries()
        Equal(#entries, 5000)
        Equal(entries[1].count, 3)
        Equal(entries[#entries].count, 5002)
    end },
    { "native errors are saved for active processors without claiming an item failed or printing twice", function()
        for _, case in ipairs({
            { source = "Bank", files = { "Bank.lua" } },
            { source = "Vendor", files = { "Bank.lua", "Vendor.lua" }, event = "MERCHANT_SHOW" },
            { source = "Mail", files = { "Bank.lua", "Mail.lua" }, event = "MAIL_SHOW" },
            { source = "Inventory", files = { "Bank.lua", "Inventory.lua" } },
        }) do
            local Wild, state, Fire, RunTimers, _, _, _, ClickDestroy, Messages = NewEnvironment(unpack(case.files))
            Fire("UI_ERROR_MESSAGE", 777, "Example client error")
            Equal(Wild.GetLogCount(), 0)
            state.bags[0][1] = Item(3)
            state.selling = case.source == "Vendor"
            Wild.db.intents = {
                { action = "deposit", target = "warband", groups = { {} } },
                { action = "sell", groups = { {} } },
                { action = "mail", recipient = "Alt-Realm", groups = { {} } },
            }
            if case.source == "Bank" then
                Wild.RunBankIntents()
            elseif case.source == "Inventory" then
                Wild.QueueDestroyItems({ { itemID = 1, bag = 0, slot = 1, link = LINK, count = 3 } })
                ClickDestroy()
            else
                Fire(case.event); RunTimers(); RunTimers()
            end
            Fire("UI_ERROR_MESSAGE", 777, "Example client error")
            local entries = Wild.GetLogEntries("client_error")
            Equal(#entries, 1)
            Equal(entries[1].s, case.source)
            Equal(entries[1].errorType, 777)
            Equal(entries[1].m, "Example client error")
            Equal(entries[1].itemID, nil)
            Equal(#Messages("Example client error"), 0)
        end
    end },
    { "failed mail records the actual unsent attachment quantities and recipient", function()
        local Wild, state, Fire, RunTimers = NewEnvironment("Bank.lua", "Mail.lua")
        state.bags[0][1] = Item(3)
        local intent = { action = "mail", recipient = "Alt-Realm", groups = { {} } }
        Wild.db.intents = { intent }
        Fire("MAIL_SHOW"); RunTimers(); RunTimers()
        intent.recipient = "Different-Realm"
        Fire("MAIL_FAILED")
        Equal(#ActionEntries(Wild, "mail"), 0)
        local found = false
        for _, entry in ipairs(Wild.GetLogEntries()) do
            if entry.itemID == 1 and entry.reason == "mail_failed" then
                Equal(entry.kind, "warning")
                Equal(entry.status, "failed")
                Equal(entry.unconfirmedCount, 3)
                Equal(entry.recipient, "Alt-Realm")
                found = true
            end
        end
        assert(found, "The unsent attachments must remain in the failure history")
    end },
    { "an unconfirmed gold request saves its remaining copper without a success record", function()
        local Wild, _, _, _, RunTimeouts = NewEnvironment("Bank.lua")
        Wild.db.intents = { { action = "hold", target = "warband", gold = 5 } }
        Wild.RunBankIntents(); RunTimeouts()
        Equal(#ActionEntries(Wild, "deposit"), 0)
        local found = 0
        for _, entry in ipairs(Wild.GetLogEntries()) do
            if entry.unconfirmedCopper then
                Equal(entry.status, "unconfirmed")
                Equal(entry.unconfirmedCopper, 50000)
                Equal(entry.target, "warband")
                Equal(entry.reason, "confirmation_timeout")
                found = found + 1
            end
        end
        Equal(found, 1)
    end },
    { "a failed deletion flushes earlier confirmed chat results without recounting them on retry", function()
        local Wild, state, Fire, _, RunTimeouts, Apply, _, ClickDestroy, Messages = NewEnvironment("Bank.lua", "Inventory.lua")
        state.bags[0][1], state.bags[0][2] = Item(2), Item(3, 2)
        local completed
        Wild.QueueDestroyItems({
            { itemID = 1, bag = 0, slot = 1, link = LINK, count = 2 },
            { itemID = 2, bag = 0, slot = 2, link = OTHER_LINK, count = 3 },
        }, function(count) completed = count end)
        ClickDestroy(); Apply(1); Fire("BAG_UPDATE_DELAYED")
        ClickDestroy(); RunTimeouts()
        Equal(#Messages("Destroyed "), 1)
        Equal(completed, nil)
        ClickDestroy(); Apply(3); Fire("BAG_UPDATE_DELAYED")
        Equal(#Messages("Destroyed "), 2)
        Equal(completed, 5)
        Equal(#ActionEntries(Wild, "destroy"), 2)
    end },
    { "action replay formats money at display time without changing saved evidence", function()
        local Wild, _, _, _, _, _, _, _, Messages, env = NewEnvironment("SlashCommands.lua")
        Wild.LogAction("Vendor", "sell", { itemID = 1, link = LINK, count = 3, copper = 300 })
        env.GetMoneyString = function(amount) return "localized:" .. amount end
        env.SlashCmdList.WILD("log show sell")
        Equal(#Messages("Sold "), 1)
        Equal(#Messages("localized:300"), 1)
        Equal(ActionEntries(Wild, "sell")[1].copper, 300)
        assert(not ActionEntries(Wild, "sell")[1].m:find("localized:", 1, true))
    end },
    { "successful destroy stacks remain grouped until the queue finishes", function()
        local Wild, state, Fire, _, _, Apply, _, ClickDestroy, Messages = NewEnvironment("Bank.lua", "Inventory.lua")
        state.bags[0][1], state.bags[0][2] = Item(2), Item(3)
        Wild.QueueDestroyItems({
            { itemID = 1, bag = 0, slot = 1, link = LINK, count = 2 },
            { itemID = 1, bag = 0, slot = 2, link = LINK, count = 3 },
        })
        ClickDestroy(); Apply(1); Fire("BAG_UPDATE_DELAYED")
        Equal(#Messages("Destroyed "), 0)
        ClickDestroy(); Apply(2); Fire("BAG_UPDATE_DELAYED")
        Equal(#Messages("Destroyed "), 1)
        assert(Messages("Destroyed ")[1]:find(COUNT .. "5", 1, true))
    end },
    { "mixed vendor failures and event orders preserve every applied quantity and copper total", function()
        for scenario = 1, 12 do
            local Wild, state, Fire, RunTimers, RunTimeouts, Apply, Tick, _, Messages = NewEnvironment("Bank.lua", "Vendor.lua")
            state.selling = true
            state.bags[0][1], state.bags[0][2], state.bags[0][3] = Item(2), Item(3, 2), Item(4, 3)
            Wild.db.intents = { { action = "sell", groups = { {} } } }
            local expected = { 0, 0, 0 }
            local seed = scenario
            local function Next(limit)
                seed = (seed * 25173 + 13849) % 65536
                return seed % limit + 1
            end
            Fire("MERCHANT_SHOW"); RunTimers()
            for step = 1, 60 do
                Tick()
                if #state.requests > 0 then
                    local index = Next(#state.requests)
                    local request = state.requests[index]
                    local info = state.bags[request.bag][request.slot]
                    if info and info.itemID == request.item.itemID and info.itemID ~= scenario % 4 then
                        local count = Next(info.stackCount)
                        Apply(index, count)
                        expected[info.itemID] = expected[info.itemID] + count
                    end
                end
                if Next(3) ~= 1 then Fire("BAG_UPDATE_DELAYED") end
                if step % 2 == 0 then RunTimers() end
            end
            Fire("BAG_UPDATE_DELAYED"); RunTimers()
            for _ = 1, 5 do Tick(); Tick(); Tick(); Tick(); RunTimeouts(); RunTimers() end
            local actual, copper = { 0, 0, 0 }, 0
            for _, entry in ipairs(ActionEntries(Wild, "sell")) do
                actual[entry.itemID] = actual[entry.itemID] + entry.count
                copper = copper + entry.copper
            end
            for itemID = 1, 3 do Equal(actual[itemID], expected[itemID]) end
            local total = expected[1] + expected[2] + expected[3]
            Equal(copper, total * 100)
            Equal(#Messages("Auto-sold " .. total .. " item(s) for " .. (total * 100) .. " copper."), total > 0 and 1 or 0)
        end
    end },
    { "late withdrawals join the active transfer instead of disappearing between phases", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[6][1], state.bags[6][2] = Item(2), Item(3, 2)
        Wild.db.intents = { { action = "transfer", source = "character", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        Apply(1); Fire("BAG_UPDATE_DELAYED"); RunTimeouts()
        Equal(#state.requests, 3)
        Apply(2); Fire("BAG_UPDATE_DELAYED")
        Apply(3); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#state.requests, 4)
        Equal(state.requests[4].item.itemID, 2)
        Equal(state.requests[4].count, 3)
        Apply(4); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Transferred "), 2)
        Equal(#Messages("Withdrew "), 0)
        local total = 0
        for _, entry in ipairs(ActionEntries(Wild, "transfer")) do total = total + entry.count end
        Equal(total, 5)
    end },
    { "depositing a partial withdrawal does not hide a later receipt of the same variant", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, Apply, _, _, Messages = NewEnvironment("Bank.lua")
        state.bags[6][1] = Item(5)
        Wild.db.intents = { { action = "transfer", source = "character", target = "warband", groups = { {} } } }
        Wild.RunBankIntents()
        Apply(1, 2); Fire("BAG_UPDATE_DELAYED"); RunTimeouts()
        Equal(state.requests[2].count, 2)
        Apply(2); Fire("BAG_UPDATE_DELAYED")
        Apply(1, 3); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#state.requests, 3)
        Equal(state.requests[3].kind, "deposit")
        Equal(state.requests[3].count, 3)
        Apply(3); Fire("BAG_UPDATE_DELAYED"); RunTimers()
        Equal(#Messages("Transferred "), 1)
        assert(Messages("Transferred ")[1]:find(COUNT .. "5", 1, true))
        Equal(#Messages("Withdrew "), 0)
        Equal(state.bags[12][1].stackCount, 5)
    end },
    { "skipped vendor slots retain their item and reason without debug or repeated warning records", function()
        local Wild, state, Fire, RunTimers, _, _, Tick = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1] = Item(3)
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers()
        state.bags[0][1].isLocked = true
        Tick(); Tick(); RunTimers(); Tick()
        Fire("MERCHANT_CLOSED")
        Equal(#state.requests, 0)
        Equal(#ActionEntries(Wild, "sell"), 0)
        local entries = Wild.GetLogEntries("item_locked")
        Equal(#entries, 1)
        Equal(entries[1].itemID, 1)
        Equal(entries[1].status, "skipped")
        Equal(entries[1].unconfirmedCount, 3)
    end },
    { "a changed locked slot is not reported as the original item being locked", function()
        for _, case in ipairs({
            { file = "Vendor.lua", event = "MERCHANT_SHOW", action = "sell" },
            { file = "Mail.lua", event = "MAIL_SHOW", action = "mail", recipient = "Alt-Realm" },
        }) do
            local Wild, state, Fire, RunTimers, _, _, Tick = NewEnvironment("Bank.lua", case.file)
            state.bags[0][1] = Item(3)
            Wild.db.intents = { { action = case.action, recipient = case.recipient, groups = { {} } } }
            Fire(case.event); RunTimers()
            state.bags[0][1] = Item(7, 2)
            state.bags[0][1].isLocked = true
            Tick(); RunTimers()
            local entries = Wild.GetLogEntries("slot_changed")
            Equal(#entries, 1)
            Equal(entries[1].itemID, 1)
            Equal(entries[1].status, "skipped")
            Equal(#Wild.GetLogEntries("item_locked"), 0)
        end
    end },
    { "pending vendor sales cannot also be confirmed as hardware deletions", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, Apply, Tick, ClickDestroy, Messages = NewEnvironment("Bank.lua", "Inventory.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1] = Item(3)
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Wild.QueueDestroyItems({ { itemID = 1, bag = 0, slot = 1, link = LINK, count = 3 } })
        Fire("MERCHANT_SHOW"); RunTimers(); Tick(); Tick()
        ClickDestroy()
        Equal(#state.requests, 1)
        RunTimeouts()
        ClickDestroy()
        Equal(#state.requests, 2)
        Equal(state.requests[2].kind, "destroy")
        Apply(2); Fire("BAG_UPDATE_DELAYED")
        Equal(#Messages("Sold "), 0)
        Equal(#ActionEntries(Wild, "sell"), 0)
        Equal(ActionEntries(Wild, "destroy")[1].count, 3)
    end },
    { "a pending hardware deletion cannot also start a vendor sale", function()
        local Wild, state, Fire, RunTimers, _, Apply, Tick, ClickDestroy = NewEnvironment("Bank.lua", "Inventory.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1] = Item(3)
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Wild.QueueDestroyItems({ { itemID = 1, bag = 0, slot = 1, link = LINK, count = 3 } })
        ClickDestroy()
        state.cursor = nil
        Fire("MERCHANT_SHOW"); RunTimers(); Tick()
        Equal(#state.requests, 1)
        Apply(1); Fire("BAG_UPDATE_DELAYED")
        Tick(); Tick(); RunTimers()
        Equal(#ActionEntries(Wild, "sell"), 0)
        Equal(ActionEntries(Wild, "destroy")[1].count, 3)
    end },
    { "vendor requests wait for an occupied cursor without discarding the queued item", function()
        local Wild, state, Fire, RunTimers, _, Apply, Tick = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1] = Item(3)
        state.cursor = { item = Item(1, 2), bag = 0, slot = 2 }
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers(); Tick()
        Equal(#state.requests, 0)
        state.cursor = nil
        Tick()
        Equal(#state.requests, 1)
        Apply(1); Fire("BAG_UPDATE_DELAYED")
        Tick(); RunTimers()
        Equal(ActionEntries(Wild, "sell")[1].count, 3)
    end },
    { "moving a requested sale onto the cursor is not confirmation of a sale", function()
        local Wild, state, Fire, RunTimers, RunTimeouts, _, Tick, _, Messages, env = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1] = Item(3)
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers(); Tick(); Tick()
        local item = state.bags[0][1]
        state.bags[0][1] = nil
        state.cursor = { item = item, bag = 0, slot = 1, removed = true }
        Fire("BAG_UPDATE_DELAYED")
        Equal(#ActionEntries(Wild, "sell"), 0)
        env.ClearCursor(); Fire("BAG_UPDATE_DELAYED"); RunTimeouts()
        Equal(#Messages("Sold "), 0)
        Equal(state.bags[0][1].stackCount, 3)
    end },
}

local failures = 0
for _, test in ipairs(tests) do
    local passed, message = pcall(test[2])
    if passed then
        print("PASS: " .. test[1])
    else
        failures = failures + 1
        print("FAIL: " .. test[1] .. ": " .. tostring(message))
    end
end
assert(failures == 0, failures .. " intent logging test(s) failed")
print("All " .. #tests .. " intent logging tests passed.")
