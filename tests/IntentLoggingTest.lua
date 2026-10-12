-- Run from the repository root with Lua 5.1: lua tests\IntentLoggingTest.lua
local LINK = "|cff1eff00|Hitem:1:0|h[Test Item]|h|r"
local OTHER_LINK = "|cff1eff00|Hitem:2:0|h[Other Item]|h|r"
local COUNT = " \195\151"

local function Equal(actual, expected)
    assert(actual == expected, "Expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function Item(count, itemID)
    return {
        itemID = itemID or 1, stackCount = count or 1,
        hyperlink = itemID == 2 and OTHER_LINK or LINK,
    }
end

local function NewEnvironment(...)
    local Wild = { db = {
        intents = {}, mail = { autoOpen = false }, advanced = {
            debug = false, ruleDelay = 0, passDelay = 0, bankStartDelay = 0,
            sellStartDelay = 0, sellInterval = 0, mailStartDelay = 0,
            mailBatchDelay = 0, guildBankStartDelay = 0, preloadTimeout = 3,
        },
    } }
    local state = {
        frames = {}, messages = {}, timers = {}, timeouts = {}, requests = {},
        bags = { [0] = {}, [5] = {}, [6] = {}, [12] = {}, guild = {} },
        money = 100000, bankMoney = 100000, merchantOpen = true,
        attachments = {}, sent = {}, cursor = nil,
    }
    local env = setmetatable({
        print = function(message) state.messages[#state.messages + 1] = message end,
        Enum = {
            BagIndex = { ReagentBag = 5, CharacterBankTab_1 = 6, AccountBankTab_1 = 12 },
            BankType = { Character = 0, Account = 2 }, PlayerInteractionType = {},
            TooltipDataLineType = { SellPrice = 11 },
        },
        BACKPACK_CONTAINER = 0, NUM_BAG_SLOTS = 0, ATTACHMENTS_MAX_SEND = 12,
        tremove = table.remove, SlashCmdList = {},
        strtrim = function(text) return text:match("^%s*(.-)%s*$") end,
        wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end end,
        GetTime = function() return 10 end,
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
        DepositMoney = function(_, amount)
            state.requests[#state.requests + 1] = { kind = "goldDeposit", count = amount }
        end,
        WithdrawMoney = function(_, amount)
            state.requests[#state.requests + 1] = { kind = "goldWithdraw", count = amount }
        end,
        FetchDepositedMoney = function() return state.bankMoney end,
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
    local function Fire(event)
        if event == "MAIL_SEND_SUCCESS" then state.attachments = {} end
        local frames = { unpack(state.frames) }
        for _, frame in ipairs(frames) do
            if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event) end
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
        local slots = state.bags[request.bag]
        local info = slots[request.slot]
        if info then
            local remaining = info.stackCount - count
            slots[request.slot] = remaining > 0 and Item(remaining, info.itemID) or nil
        end
        if request.kind == "destroy" then
            state.cursor = nil
        elseif request.kind ~= "sell" then
            local destination = state.bags[request.target]
            for slot = 1, 20 do
                local targetInfo = destination[slot]
                if not targetInfo or targetInfo.hyperlink == request.item.hyperlink then
                    destination[slot] = Item((targetInfo and targetInfo.stackCount or 0) + count, request.item.itemID)
                    break
                end
            end
        end
    end
    local function Tick()
        for _, frame in ipairs(state.frames) do
            if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 1) end
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
