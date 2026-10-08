-- Run from the repository root with Lua 5.1: lua tests\ItemChatIconsTest.lua
local LINK = "|cffa335ee|Hitem:1::::::::90:::::1:12345::::|h[Test Item]|h|r"
local HYPERLINK = LINK:sub(11, -3)
local ICON = "|T134400:0:0|t "
local COUNT = " \195\151"

local function Equal(actual, expected)
    assert(actual == expected, "Expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function NewEnvironment(...)
    local Wild = { db = {
        intents = {}, advanced = {
            debug = false, ruleDelay = 0, passDelay = 0, sellStartDelay = 0,
            mailStartDelay = 0, mailBatchDelay = 0,
        },
        mail = { autoOpen = false },
    } }
    local state = {
        frames = {}, timers = {}, messages = {}, iconRequests = {},
        icons = { [1] = 134400, [2] = "Interface\\Icons\\INV_Misc_Herb_01" },
        bags = { [0] = {}, [6] = {}, [12] = {}, [20] = {} },
    }
    local env = setmetatable({
        print = function(...)
            Equal(select("#", ...), 1)
            state.messages[#state.messages + 1] = ...
        end,
        Enum = {
            BagIndex = { CharacterBankTab_1 = 6, AccountBankTab_1 = 12 },
            BankType = { Account = 2 }, PlayerInteractionType = {},
            TooltipDataLineType = { SellPrice = 11 },
        },
        BACKPACK_CONTAINER = 0, NUM_BAG_SLOTS = 0,
        tremove = table.remove, SlashCmdList = {},
        strtrim = function(text) return text:match("^%s*(.-)%s*$") end,
        wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end end,
        GetTime = function() return 10 end,
        date = function() return "2026-01-01 00:00:00" end,
        GetMoneyString = function(amount) return amount .. " copper" end,
        GetCursorInfo = function() end,
        ClearCursor = function() end,
        DeleteCursorItem = function()
            local cursor = state.cursor
            state.bags[cursor.bag][cursor.slot] = nil
        end,
        MerchantFrame = { IsShown = function() return true end },
        C_Timer = { After = function(_, callback) state.timers[#state.timers + 1] = callback end },
        C_Item = {
            GetItemIconByID = function(itemID)
                state.iconRequests[#state.iconRequests + 1] = itemID
                return state.icons[itemID]
            end,
            GetItemInfo = function() return "Test Item", LINK, 4, 1, 1, nil, nil, 20, "", 134400, 100 end,
        },
        Item = { CreateFromItemID = function()
            return { IsItemDataCached = function() return true end }
        end },
        GetNumGuildBankTabs = function() return 1 end,
        GetGuildBankTabInfo = function() return "Test", nil, true end,
        GetGuildBankItemInfo = function(_, slot)
            local info = state.bags[20][slot]
            return 134400, info and info.stackCount
        end,
        GetGuildBankItemLink = function(_, slot)
            local info = state.bags[20][slot]
            return info and info.hyperlink
        end,
        AutoStoreGuildBankItem = function(_, slot)
            state.bags[0][1], state.bags[20][slot] = state.bags[20][slot], nil
        end,
        ClickSendMailItemButton = function() end,
        SendMail = function(recipient) state.recipient = recipient end,
    }, { __index = _G })
    env.C_Container = {
        GetContainerNumSlots = function() return 2 end,
        GetContainerItemInfo = function(bag, slot) return state.bags[bag][slot] end,
        UseContainerItem = function(bag, slot, _, bankType)
            local info = state.bags[bag][slot]
            state.bags[bag][slot] = nil
            if state.selling then return end
            local destination = bag == 0 and (bankType == 2 and 12 or 6) or 0
            local slots = state.bags[destination]
            slots[slots[1] and 2 or 1] = info
        end,
        PickupContainerItem = function(bag, slot) state.cursor = { bag = bag, slot = slot } end,
    }
    env.CreateFrame = function(frameType)
        local frame = { events = {}, scripts = {}, shown = false, frameType = frameType }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:RegisterAllEvents() end
        function frame:UnregisterAllEvents() self.events = {} end
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
    Wild.IntentMatchesItem = function() return true end
    Wild.GetIntentSummary = function() return "Rule for " .. LINK end
    Wild.GetIntentGoldTarget = function() return 0 end
    Wild.GetItemGroups = function(intent) return intent.groups end
    Wild.SubIntentForGroup = function(intent) return intent end
    Wild.CountMatchingInBags = function()
        local count = 0
        for _, info in pairs(state.bags[0]) do count = count + info.stackCount end
        return count
    end
    for _, file in ipairs({ ... }) do Load(file) end
    local function Fire(event)
        local frames = { unpack(state.frames) }
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event) end
        end
    end
    local function RunTimers()
        local timers = state.timers
        state.timers = {}
        for _, callback in ipairs(timers) do callback() end
    end
    local function Tick()
        for _, frame in ipairs(state.frames) do
            if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 1) end
        end
    end
    local function HasIcon(fragment)
        for _, message in ipairs(state.messages) do
            if message:find(fragment, 1, true) then
                assert(message:find(ICON .. HYPERLINK, 1, true), "Missing item icon: " .. message)
                assert(not message:find("\226\134", 1, true), "Unsupported bank arrow: " .. message)
                assert(not message:find("\226\156\137", 1, true), "Unsupported mail symbol: " .. message)
                return
            end
        end
        error("Missing message: " .. fragment)
    end
    return Wild, state, env, Fire, RunTimers, Tick, HasIcon
end

local function Item(count)
    return { itemID = 1, hyperlink = LINK, stackCount = count or 1 }
end

local tests = {
    { "item icons sit immediately before intact hyperlinks, including quality atlases", function()
        local Wild, state = NewEnvironment()
        local quality = "|A:Professions-ChatIcon-Quality-Tier3:17:15::1|a"
        local link = LINK:gsub("Test Item", "Test Item " .. quality)
        Wild.Print("Sold " .. link .. COUNT .. "5.")
        Equal(state.messages[1], "Sold |cffa335ee" .. ICON .. link:sub(11) .. COUNT .. "5.")
        Equal(state.iconRequests[1], 1)
    end },
    { "every item link gets its own numeric or path texture", function()
        local Wild, state = NewEnvironment()
        local other = "|Hitem:2:0|h[Herb]|h"
        Wild.Print(LINK .. " and " .. other .. " then " .. LINK)
        Equal(state.messages[1], "|cffa335ee" .. ICON .. HYPERLINK .. "|r and " ..
            "|TInterface\\Icons\\INV_Misc_Herb_01:0:0|t " .. other .. " then |cffa335ee" .. ICON .. HYPERLINK .. "|r")
        Equal(#state.iconRequests, 3)
    end },
    { "unavailable item icons use a real question-mark texture without delaying chat", function()
        local Wild, state = NewEnvironment()
        state.icons[1] = nil
        Wild.Print(LINK)
        Equal(state.messages[1], "|cffa335ee|TInterface\\Icons\\INV_Misc_QuestionMark:0:0|t " .. HYPERLINK .. "|r")
        Equal(#state.timers, 0)
        state.icons[1] = 134400
        Wild.Print(LINK)
        Equal(state.messages[2], "|cffa335ee" .. ICON .. HYPERLINK .. "|r")
    end },
    { "plain text, other links and native money textures remain unchanged", function()
        local Wild, state = NewEnvironment()
        for _, message in ipairs({
            "", "Wild: Repaired for 1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0|t.",
            "|Hquest:1|h[Quest]|h", "|Hcurrency:1|h[Currency]|h",
            "|Hbattlepet:1|h[Pet]|h", "item:1", "|Hitem:1|h[Incomplete",
        }) do
            Wild.Print(message)
            Equal(state.messages[#state.messages], message)
        end
        Equal(#state.iconRequests, 0)
    end },
    { "debug chat gets icons without changing saved messages or bypassing its toggle", function()
        local Wild, state, _, _, _, _, HasIcon = NewEnvironment()
        local message = "Matched " .. LINK
        Wild.Log("Rules", message)
        Equal(#state.messages, 0)
        Wild.db.advanced.debug = true
        Wild.Log("Rules", message)
        Equal(Wild.GetLogEntries()[1].m, message)
        HasIcon("Matched ")
    end },
    { "bank deposits and their rule summaries both have item icons", function()
        for _, target in ipairs({ "character", "warband" }) do
            local Wild, state, _, _, RunTimers, _, HasIcon = NewEnvironment("Bank.lua")
            state.bags[0][1] = Item(5)
            Wild.db.intents = { { action = "deposit", target = target, groups = { {} } } }
            Wild.RunBankIntents(); RunTimers()
            HasIcon(COUNT .. "5")
            HasIcon("Deposited 5 item(s).")
        end
    end },
    { "character, warband and guild withdrawals have item icons", function()
        for target, bag in pairs({ character = 6, warband = 12, guild = 20 }) do
            local Wild, state, _, _, RunTimers, _, HasIcon = NewEnvironment("Bank.lua")
            state.bags[bag][1] = Item(2)
            Wild.db.intents = { { action = "withdraw", target = target, groups = { {} } } }
            Wild.RunBankIntents(); RunTimers()
            HasIcon(COUNT .. "2")
            HasIcon("Withdrew 2 item(s).")
        end
    end },
    { "both bank transfer phases log item icons", function()
        local Wild, state, _, Fire, RunTimers, _, HasIcon = NewEnvironment("Bank.lua")
        state.bags[6][1] = Item(3)
        Wild.db.intents = { { action = "transfer", source = "character", target = "warband", groups = { {} } } }
        Wild.RunBankIntents(); RunTimers()
        HasIcon("Withdrew ")
        Fire("BAG_UPDATE_DELAYED")
        HasIcon("Deposited ")
        HasIcon("Transferred 3 item(s).")
    end },
    { "hold rules show icons for deposits and withdrawals", function()
        for _, withdraw in ipairs({ false, true }) do
            local Wild, state, _, _, RunTimers, _, HasIcon = NewEnvironment("Bank.lua")
            if withdraw then
                state.bags[12][1] = Item()
            else
                state.bags[0][1], state.bags[0][2] = Item(), Item()
            end
            Wild.db.intents = { { action = "hold", target = "warband", groups = { { count = 1 } } } }
            Wild.RunBankIntents(); RunTimers()
            HasIcon(COUNT .. "1")
            HasIcon("to reach 1 on character.")
        end
    end },
    { "vendor sales show item icons while preserving amounts and totals", function()
        local Wild, state, _, Fire, RunTimers, Tick, HasIcon = NewEnvironment("Bank.lua", "Vendor.lua")
        state.selling = true
        state.bags[0][1] = Item(2)
        Wild.db.intents = { { action = "sell", groups = { {} } } }
        Fire("MERCHANT_SHOW"); RunTimers()
        Tick(); Tick()
        Fire("BAG_UPDATE_DELAYED"); RunTimers()
        HasIcon("Sold ")
        assert(state.messages[#state.messages]:find("Auto-sold 2 item(s) for 200 copper.", 1, true))
    end },
    { "mail attachment logs have icons rather than unsupported envelope glyphs", function()
        local Wild, state, _, Fire, RunTimers, _, HasIcon = NewEnvironment("Bank.lua", "Mail.lua")
        state.bags[0][1] = Item(4)
        Wild.db.intents = { { action = "mail", recipient = "Test-Realm", groups = { {} } } }
        Fire("MAIL_SHOW"); RunTimers(); RunTimers()
        HasIcon(COUNT .. "4")
        Equal(state.recipient, "Test-Realm")
    end },
    { "destroy logs have an item icon", function()
        local Wild, state, _, _, _, _, HasIcon = NewEnvironment("Inventory.lua")
        state.bags[0][1] = Item()
        Wild.QueueDestroyItems({ { itemID = 1, bag = 0, slot = 1, link = LINK, count = 1 } })
        for _, frame in ipairs(state.frames) do
            if frame.frameType == "Button" and frame.scripts.OnClick then
                frame.scripts.OnClick()
                break
            end
        end
        HasIcon("Destroyed ")
    end },
    { "slash item searches, bank rule listings and trace replay have icons", function()
        local Wild, state, env, _, _, _, HasIcon = NewEnvironment("SlashCommands.lua")
        Wild.FindItems = function() return { { link = LINK, total = 3, breakdown = {} } } end
        Wild.FormatItemBreakdown = function() return "Test-Realm" end
        env.SlashCmdList.WILD("find Test")
        HasIcon("3x total")
        Wild.db.intents = { { action = "deposit", target = "warband" } }
        env.SlashCmdList.WILD("bank rules")
        HasIcon("Rule for ")
        Wild.db.eventTrace = { "Matched " .. LINK }
        env.SlashCmdList.WILD("trace show")
        HasIcon("Matched ")
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
assert(failures == 0, failures .. " item chat icon test(s) failed")
print("All " .. #tests .. " item chat icon tests passed.")
