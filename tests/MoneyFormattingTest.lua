-- Run from the repository root with Lua 5.1: lua tests\MoneyFormattingTest.lua
local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function NewEnvironment()
    local Wild = {
        db = {
            intents = {}, advanced = { sellStartDelay = 0, passDelay = 0 },
            vendorAutoRepair = false,
        },
    }
    local state = {
        frames = {}, messages = {}, logs = {}, timers = {}, calls = {},
        colorblind = false, symbols = { "g", "s", "c" },
        price = 225839, money = 500000, bankMoney = 500000, items = {},
        slotPrices = {}, hyperlinkPrices = {}, linkPrices = {}, sold = {}, destroyed = {},
    }
    local env = setmetatable({
        Enum = {
            BagIndex = {}, BankType = { Account = 2 }, PlayerInteractionType = {},
            TooltipDataLineType = { SellPrice = 11 },
        },
        BACKPACK_CONTAINER = 0, NUM_BAG_SLOTS = 0,
        tremove = table.remove,
        print = function(message) state.messages[#state.messages + 1] = message end,
        wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end end,
        GetTime = function() return 10 end,
        UnitClass = function() return "Druid", "DRUID" end,
        UnitLevel = function() return 90 end,
        UnitName = function() return "Test" end,
        GetRealmName = function() return "Realm" end,
        GetAverageItemLevel = function() return 100, 100 end,
        GetInventoryItemLink = function() end,
        GetProfessions = function() end,
        GetMoney = function() return state.money end,
        CanMerchantRepair = function() return true end,
        GetRepairAllCost = function() return state.price, true end,
        RepairAllItems = function(guild) state.repaired = guild and "guild" or "personal" end,
        IsInGuild = function() return true end,
        CanGuildBankRepair = function() return true end,
        MerchantFrame = { IsShown = function() return true end },
        C_Timer = { After = function(_, callback) state.timers[#state.timers + 1] = callback end },
        C_Item = { GetItemInfo = function(source)
            local price = state.linkPrices[source]
            if price == nil then price = state.price end
            return "Item", "item:1", 3, 1, 1, nil, nil, 1, "", nil, price
        end },
        C_TooltipInfo = {
            GetBagItem = function(_, slot)
                local price = state.slotPrices[slot]
                if price ~= nil then return { lines = { { type = 11, price = price } } } end
            end,
            GetHyperlink = function(link)
                local price = state.hyperlinkPrices[link]
                if price ~= nil then return { lines = { { type = 11, price = price } } } end
            end,
        },
        C_Container = {
            GetContainerNumSlots = function() return #state.items end,
            GetContainerItemInfo = function(_, slot) return state.items[slot] end,
            UseContainerItem = function(_, slot)
                local info = state.items[slot]
                local amount = state.slotPrices[slot]
                if amount == nil then amount = state.price * (info.stackCount or 1) end
                state.money = state.money + amount
                state.sold[#state.sold + 1] = info.itemID
                state.items[slot] = false
            end,
        },
        Item = { CreateFromItemID = function()
            return { IsItemDataCached = function() return true end }
        end },
        C_Bank = {
            DepositMoney = function(_, amount) state.deposited = amount end,
            WithdrawMoney = function(_, amount) state.withdrawn = amount end,
            FetchDepositedMoney = function() return state.bankMoney end,
        },
        GetGuildBankMoney = function() return state.bankMoney end,
        DepositGuildBankMoney = function(amount) state.deposited = amount end,
        WithdrawGuildBankMoney = function(amount) state.withdrawn = amount end,
        GetNumGuildBankTabs = function() return 0 end,
    }, { __index = _G })
    env.CreateFrame = function()
        local frame = { events = {}, scripts = {}, shown = false }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        state.frames[#state.frames + 1] = frame
        return frame
    end
    -- Simulate the native formatter's setting and localization behavior.
    env.GetMoneyString = function(amount, separateThousands, checkGoldThreshold, showZeroAsGold)
        state.calls[#state.calls + 1] = {
            amount = amount, separateThousands = separateThousands,
            checkGoldThreshold = checkGoldThreshold, showZeroAsGold = showZeroAsGold,
        }
        local values = { math.floor(amount / 10000), math.floor(amount % 10000 / 100), amount % 100 }
        local names = { "Gold", "Silver", "Copper" }
        local parts = {}
        for i, value in ipairs(values) do
            if value > 0 or (i == 3 and #parts == 0) then
                local number = tostring(value)
                if i == 1 and separateThousands and value >= 1000 then
                    number = number:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                end
                local unit = state.colorblind and state.symbols[i]
                    or ("|TInterface\\MoneyFrame\\UI-" .. names[i] .. "Icon:0:0|t")
                parts[#parts + 1] = number .. unit
            end
        end
        return table.concat(parts, " ")
    end
    Wild.Log = function(_, message) state.logs[#state.logs + 1] = message end
    Wild.QueueDestroyItems = function(items) state.destroyed = items end
    setfenv(assert(loadfile("Core.lua")), env)("Wild", Wild)
    setfenv(assert(loadfile("Conditions.lua")), env)("Wild", Wild)
    setfenv(assert(loadfile("Bank.lua")), env)("Wild", Wild)
    setfenv(assert(loadfile("Vendor.lua")), env)("Wild", Wild)
    setfenv(assert(loadfile("Tooltip.lua")), env)("Wild", Wild)

    local function Fire(event)
        for _, frame in ipairs(state.frames) do
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
    local function HasMessage(fragment, messages)
        for _, message in ipairs(messages or state.messages) do
            if message:find(fragment, 1, true) then return true end
        end
        error("Missing message: " .. fragment)
    end
    return Wild, state, env, Fire, RunTimers, Tick, HasMessage
end

local tests = {
    { "money uses Blizzard's formatter without suppressing copper", function()
        local Wild, state, env = NewEnvironment()
        for _, amount in ipairs({ 0, 1, 63, 100, 863, 10000, 225839, 12345678901 }) do
            Equal(Wild.FormatGold(amount), env.GetMoneyString(amount, true))
            local call = state.calls[#state.calls - 1]
            Equal(call.amount, amount)
            Equal(call.separateThousands, true)
            Equal(call.checkGoldThreshold, nil)
            Equal(call.showZeroAsGold, nil)
        end
    end },
    { "icons match the screenshot without zero gold or silver", function()
        local Wild = NewEnvironment()
        Equal(Wild.FormatGold(225839),
            "22|TInterface\\MoneyFrame\\UI-GoldIcon:0:0|t " ..
            "58|TInterface\\MoneyFrame\\UI-SilverIcon:0:0|t " ..
            "39|TInterface\\MoneyFrame\\UI-CopperIcon:0:0|t")
        Equal(Wild.FormatGold(63), "63|TInterface\\MoneyFrame\\UI-CopperIcon:0:0|t")
        Equal(Wild.FormatGold(0), "0|TInterface\\MoneyFrame\\UI-CopperIcon:0:0|t")
    end },
    { "changing colorblind mode and localized symbols affects the next display", function()
        local Wild, state = NewEnvironment()
        assert(Wild.FormatGold(225839):find("|T", 1, true))
        state.colorblind = true
        Equal(Wild.FormatGold(225839), "22g 58s 39c")
        state.symbols = { " gold", " silver", " copper" }
        Equal(Wild.FormatGold(225839), "22 gold 58 silver 39 copper")
        state.colorblind = false
        assert(Wild.FormatGold(225839):find("|T", 1, true))
    end },
    { "hold rule summaries format gold amounts without changing stored units", function()
        local Wild, state, env = NewEnvironment()
        local intent = { action = "hold", target = "warband", groups = { { kind = "gold", gold = 1234 } } }
        for _, colorblind in ipairs({ false, true }) do
            state.colorblind = colorblind
            local summary = Wild.GetIntentSummary(intent)
            assert(summary:find(env.GetMoneyString(12340000, true), 1, true))
            Equal(intent.groups[1].gold, 1234)
        end
    end },
    { "sell price tooltips use the shared formatter and keep unavailable prices readable", function()
        local Wild, state, env = NewEnvironment()
        local resolve
        for _, line in ipairs(Wild.TOOLTIP_LINES) do
            if line.key == "sellPrice" then resolve = line.resolve end
        end
        for _, colorblind in ipairs({ false, true }) do
            state.colorblind = colorblind
            Equal(resolve(1), "Sell Price: " .. env.GetMoneyString(state.price, true))
        end
        state.price = 0
        Equal(resolve(1), "Sell Price: None")
        state.price = nil
        Equal(resolve(1), "Sell Price: None")
    end },
    { "sell price condition values and debug output format money but keep copper inputs", function()
        local Wild, state, env = NewEnvironment()
        local cond = { attr = "item.sellprice", op = ">=", value = 225839 }
        local attr = Wild.ATTR_BY_KEY[cond.attr]
        Wild.db.advanced.debug = true
        for _, colorblind in ipairs({ false, true }) do
            state.colorblind = colorblind
            local money = env.GetMoneyString(cond.value, true)
            Equal(Wild.FormatConditionValue(cond, attr), money)
            assert(Wild.GetConditionsSummary({ cond }):find(money, 1, true))
            Equal(Wild.EvaluateCondition(cond, 1, nil, {}), true)
            assert(state.logs[#state.logs]:find("actual=" .. money, 1, true))
            assert(state.logs[#state.logs]:find("expected >= " .. money, 1, true))
            Equal(cond.value, 225839)
        end
    end },
    { "ordinary numeric conditions and incomplete price values keep their existing formatting", function()
        local Wild = NewEnvironment()
        Equal(Wild.FormatConditionValue({ value = 42 }, Wild.ATTR_BY_KEY["char.level"]), "42")
        local priceAttr = Wild.ATTR_BY_KEY["item.sellprice"]
        Equal(Wild.FormatConditionValue({}, priceAttr), "?")
        Equal(Wild.FormatConditionValue({ value = -1 }, priceAttr), "-1")
    end },
    { "vendor sale lines and totals format stack values in both modes", function()
        for _, colorblind in ipairs({ false, true }) do
            local Wild, state, env, Fire, RunTimers, Tick, HasMessage = NewEnvironment()
            state.colorblind = colorblind
            state.items = { { itemID = 1, hyperlink = "item:1", stackCount = 2 } }
            Wild.db.intents = { { action = "sell", groups = {
                { kind = "items", conditions = { { attr = "item.id", op = "=", value = 1 } } },
            } } }
            Fire("MERCHANT_SHOW")
            RunTimers()
            Tick(); Tick()
            Fire("BAG_UPDATE_DELAYED")
            RunTimers()
            local money = env.GetMoneyString(state.price * 2, true)
            HasMessage("Sold item:1 \195\1512 for " .. money)
            HasMessage("Auto-sold 2 item(s) for " .. money .. ".")
        end
    end },
    { "the screenshot item uses its 86 silver 97 copper tooltip price instead of 33 copper", function()
        for _, colorblind in ipairs({ false, true }) do
            local Wild, state, env, Fire, RunTimers, Tick, HasMessage = NewEnvironment()
            state.colorblind, state.price = colorblind, 33
            state.items = { { itemID = 1, hyperlink = "item:1", stackCount = 1 } }
            state.slotPrices[1] = 8697
            Wild.db.intents = { { action = "sell", groups = {
                { kind = "items", conditions = { { attr = "item.id", op = "=", value = 1 } } },
            } } }
            Equal(Wild.GetEffectiveSellPrice(1, { bag = 0, slot = 1, stackCount = 1 }), 8697)
            Fire("MERCHANT_SHOW")
            RunTimers()
            Tick(); Tick()
            Fire("BAG_UPDATE_DELAYED")
            RunTimers()
            local money = env.GetMoneyString(8697, true)
            Equal(state.money - 500000, 8697)
            HasMessage("Sold item:1 \195\1511 for " .. money)
            HasMessage("Auto-sold 1 item(s) for " .. money .. ".")
        end
    end },
    { "stack tooltip prices are divided once and sale totals match the gold received", function()
        local Wild, state, env, Fire, RunTimers, Tick, HasMessage = NewEnvironment()
        state.price = 33
        state.items = {
            { itemID = 1, hyperlink = "item:1", stackCount = 2 },
            { itemID = 1, hyperlink = "item:1", stackCount = 3 },
        }
        state.slotPrices[1], state.slotPrices[2] = 8697 * 2, 12345 * 3
        Equal(Wild.GetEffectiveSellPrice(1, { bag = 0, slot = 1, stackCount = 2 }), 8697)
        Equal(Wild.GetEffectiveSellPrice(1, { bag = 0, slot = 2 }), 12345)
        Wild.db.intents = { { action = "sell", groups = {
            { kind = "items", conditions = { { attr = "item.id", op = "=", value = 1 } } },
        } } }
        Fire("MERCHANT_SHOW")
        RunTimers()
        Tick(); Tick(); Tick()
        Fire("BAG_UPDATE_DELAYED")
        RunTimers()
        Equal(state.money - 500000, 8697 * 2 + 12345 * 3)
        HasMessage("Sold item:1 \195\1512 for " .. env.GetMoneyString(8697 * 2, true))
        HasMessage("Sold item:1 \195\1513 for " .. env.GetMoneyString(12345 * 3, true))
        HasMessage("Auto-sold 5 item(s) for " .. env.GetMoneyString(state.money - 500000, true) .. ".")
    end },
    { "effective vendor prices also drive sell-price rules and tooltips", function()
        local Wild, state, env = NewEnvironment()
        state.price = 33
        state.items = { { itemID = 1, hyperlink = "item:1", stackCount = 2, bag = 0, slot = 1 } }
        state.slotPrices[1] = 8697 * 2
        local info = state.items[1]
        Equal(Wild.EvaluateCondition({ attr = "item.sellprice", op = ">=", value = 8000 }, 1, info, {}), true)
        Equal(Wild.EvaluateCondition({ attr = "item.sellprice", op = ">", value = 9000 }, 1, info, {}), false)
        for _, line in ipairs(Wild.TOOLTIP_LINES) do
            if line.key == "sellPrice" then
                Equal(line.resolve(1, info), "Sell Price: " .. env.GetMoneyString(8697, true))
            end
        end
    end },
    { "hyperlink tooltip and item-info fallbacks preserve item variants", function()
        local Wild, state, env = NewEnvironment()
        state.price = 33
        local info = { hyperlink = "item:1:variant", stackCount = 5 }
        state.hyperlinkPrices[info.hyperlink] = 8697
        Equal(Wild.GetEffectiveSellPrice(1, info), 8697)
        state.hyperlinkPrices[info.hyperlink] = nil
        state.linkPrices[info.hyperlink] = 8697
        Equal(Wild.GetEffectiveSellPrice(1, info), 8697)
        env.C_TooltipInfo = nil
        Equal(Wild.GetEffectiveSellPrice(1, info), 8697)
        Equal(Wild.GetEffectiveSellPrice(1), 33)
    end },
    { "a tooltip price of zero is authoritative rather than falling back to the base price", function()
        local Wild, state = NewEnvironment()
        state.items = { { itemID = 1, hyperlink = "item:1", stackCount = 2 } }
        state.slotPrices[1] = 0
        Equal(Wild.GetEffectiveSellPrice(1, { bag = 0, slot = 1, stackCount = 2 }), 0)
        state.hyperlinkPrices["item:1"] = 0
        Equal(Wild.GetEffectiveSellPrice(1, { hyperlink = "item:1" }), 0)
    end },
    { "a sellable tooltip price is not sent for destruction when the base price is zero", function()
        local Wild, state, env, Fire, RunTimers, Tick, HasMessage = NewEnvironment()
        state.price = 0
        state.items = { { itemID = 1, hyperlink = "item:1", stackCount = 1 } }
        state.slotPrices[1] = 8697
        Wild.db.intents = { { action = "sell", destroyUnsellable = true, groups = {
            { kind = "items", conditions = { { attr = "item.id", op = "=", value = 1 } } },
        } } }
        Fire("MERCHANT_SHOW")
        RunTimers()
        Tick(); Tick()
        Fire("BAG_UPDATE_DELAYED")
        RunTimers()
        Equal(#state.sold, 1)
        Equal(#state.destroyed, 0)
        HasMessage("Auto-sold 1 item(s) for " .. env.GetMoneyString(8697, true) .. ".")
    end },
    { "personal and guild repair messages use the shared money formatter", function()
        for _, colorblind in ipairs({ false, true }) do
            for _, guild in ipairs({ false, true }) do
                local Wild, state, env, Fire, _, _, HasMessage = NewEnvironment()
                state.colorblind = colorblind
                Wild.db.vendorAutoRepair = true
                Wild.db.vendorRepairUseGuild = guild
                Fire("MERCHANT_SHOW")
                Equal(state.repaired, guild and "guild" or "personal")
                HasMessage("Repaired all items for " .. env.GetMoneyString(state.price, true))
            end
        end
    end },
    { "bank deposit, withdrawal, and debug amounts follow colorblind mode", function()
        for _, colorblind in ipairs({ false, true }) do
            for _, target in ipairs({ "warband", "guild" }) do
                for _, balance in ipairs({ 100000, 500000 }) do
                    local Wild, state, env, _, _, _, HasMessage = NewEnvironment()
                    state.colorblind, state.money = colorblind, balance
                    Wild.db.intents = { { action = "hold", target = target,
                        groups = { { kind = "gold", gold = 25 } } } }
                    Wild.RunBankIntents()
                    local delta = math.abs(balance - 250000)
                    local verb = balance > 250000 and "Deposited " or "Withdrew "
                    Equal(state.deposited or state.withdrawn, delta)
                    HasMessage(verb .. env.GetMoneyString(delta, true) .. ".")
                    HasMessage("Hold phase 1: goldTarget=" .. env.GetMoneyString(250000, true), state.logs)
                    HasMessage("Gold sync: target=" .. env.GetMoneyString(250000, true), state.logs)
                end
            end
        end
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
assert(failures == 0, failures .. " money formatting test(s) failed")
print("All " .. #tests .. " money formatting tests passed.")
