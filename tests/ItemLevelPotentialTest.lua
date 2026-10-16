-- Run from the repository root with Lua 5.1: lua tests\ItemLevelPotentialTest.lua
local MenuTestHelpers = dofile("tests\\MenuTestHelpers.lua")
local originalTrim = string.trim
string.trim = function(text) return text:match("^%s*(.-)%s*$") end

local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function GetUpvalue(callback, wanted)
    local index = 1
    while true do
        local name, value = debug.getupvalue(callback, index)
        assert(name, "Missing upvalue " .. wanted)
        if name == wanted then return value end
        index = index + 1
    end
end

local function PotentialCondition(op, offset)
    return { attr = "item.maxilvl", op = op or "<", ref = "char.slotilvl", offset = offset }
end

local function SellIntent()
    return {
        enabled = true, action = "sell",
        groups = { {
            mode = "include",
            conditions = {
                { attr = "item.bind", op = "is", value = "soulbound" },
                PotentialCondition(),
            },
        } },
    }
end

local function NewEnvironment()
    local Wild = { db = { intents = {}, advanced = { sellStartDelay = 0, passDelay = 0 } } }
    local state = {
        items = {}, links = {}, bags = { [0] = {}, [5] = {} }, equipped = {},
        frames = {}, timers = {}, sold = {}, messages = {}, requests = {}, upgradeQueries = {},
    }
    local function ItemID(source)
        return type(source) == "number" and source or tonumber(source:match("item:(%d+)"))
    end
    local function FindItem(source)
        return state.links[source] or state.items[ItemID(source)]
    end
    local function DefineItem(itemID, item)
        local link = item.link or ("item:" .. itemID)
        item.equipLoc = item.equipLoc or "INVTYPE_HEAD"
        state.items[itemID] = item
        state.links[link] = item
        return link
    end
    local function AddItem(itemID, item, bag)
        local link = DefineItem(itemID, item)
        bag = bag or 0
        local slot = #state.bags[bag] + 1
        local info = {
            itemID = itemID, hyperlink = link, stackCount = 1, bag = bag, slot = slot,
            isBound = item.bindType == nil or item.bindType == 1,
        }
        state.bags[bag][slot] = info
        return info
    end
    local function EquipItem(slot, itemID, item)
        state.equipped[slot] = DefineItem(itemID, item)
    end
    local function Tooltip(source)
        local item = FindItem(source)
        if not item then return nil end
        return { lines = { { leftText = "Item" } } }
    end
    local env = setmetatable({
        print = function(message) state.messages[#state.messages + 1] = message end,
        tremove = table.remove,
        wipe = function(t) for key in pairs(t) do t[key] = nil end end,
        CreateFrame = function()
            local frame = { scripts = {}, events = {}, shown = false }
            function frame:Hide() self.shown = false end
            function frame:Show() self.shown = true end
            function frame:IsShown() return self.shown end
            function frame:RegisterEvent(event) self.events[event] = true end
            function frame:UnregisterEvent(event) self.events[event] = nil end
            function frame:SetScript(event, callback) self.scripts[event] = callback end
            state.frames[#state.frames + 1] = frame
            return frame
        end,
        C_Item = {
            GetItemInfo = function(source)
                local item = FindItem(source)
                if not item or item.noInfo then return nil end
                return "Item", "item:" .. ItemID(source), 4, item.baseLevel or 1, 1,
                    nil, nil, 1, item.equipLoc, nil, 100, 4, 2, item.bindType or 1
            end,
            IsItemDataCachedByID = function(source)
                local item = FindItem(source)
                return item ~= nil and item.cached ~= false
            end,
            RequestLoadItemDataByID = function(source)
                state.requests[#state.requests + 1] = source
            end,
            GetItemUpgradeInfo = function(source)
                state.upgradeQueries[#state.upgradeQueries + 1] = source
                local item = FindItem(source)
                if item.upgradeInfo then return item.upgradeInfo end
                if item.maximum then
                    return {
                        currentLevel = 1, maxLevel = 6, maxItemLevel = item.maximum,
                        trackString = item.track or "Hero",
                    }
                end
            end,
            GetDetailedItemLevelInfo = function(link)
                local item = FindItem(link)
                return item and item.level
            end,
        },
        C_Container = {
            GetContainerNumSlots = function(bag) return #state.bags[bag] end,
            GetContainerItemInfo = function(bag, slot) return state.bags[bag][slot] end,
            GetContainerItemLink = function(bag, slot)
                local info = state.bags[bag][slot]
                return info and info.hyperlink
            end,
            UseContainerItem = function(bag, slot)
                state.sold[#state.sold + 1] = state.bags[bag][slot].itemID
                state.bags[bag][slot] = false
            end,
        },
        C_TooltipInfo = {
            GetHyperlink = Tooltip,
            GetBagItem = function(bag, slot)
                local info = state.bags[bag][slot]
                return info and Tooltip(info.hyperlink)
            end,
            GetInventoryItem = function(_, slot)
                local link = state.equipped[slot]
                return link and Tooltip(link)
            end,
        },
        GetInventoryItemLink = function(_, slot) return state.equipped[slot] end,
        GetAverageItemLevel = function() return 130, 130 end,
        GetProfessions = function() end,
        UnitClass = function() return "Druid", "DRUID" end,
        UnitLevel = function() return 90 end,
        GetTime = function() return 10 end,
        GetMoneyString = function(amount) return tostring(amount) .. " copper" end,
        C_Timer = {
            After = function(_, callback) state.timers[#state.timers + 1] = callback end,
            NewTimer = function() return { Cancel = function() end } end,
        },
        Item = {
            CreateFromItemID = function()
                return { IsItemDataCached = function() return true end }
            end,
        },
        MerchantFrame = { IsShown = function() return true end },
        Enum = { PlayerInteractionType = { Merchant = 5 } },
    }, { __index = _G })
    Wild.GetPlayerBags = function() return { 0, 5 } end
    Wild.GetEffectiveSellPrice = function() return 100 end
    Wild.Log = function(_, message) state.messages[#state.messages + 1] = message end
    Wild.Print = env.print
    Wild.QueueDestroyItems = function() error("This sell rule must not destroy items") end
    setfenv(assert(loadfile("Conditions.lua")), env)("Wild", Wild)

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
    return Wild, state, AddItem, EquipItem, env, Fire, RunTimers, Tick
end

local tests = {
    { "maximum item level is an opt-in numeric condition with a public resolver", function()
        local Wild = NewEnvironment()
        local attr = assert(Wild.ATTR_BY_KEY["item.maxilvl"], "Missing maximum item level attribute")
        Equal(attr.label, "Maximum Item Level")
        Equal(attr.category, "Item")
        Equal(attr.valueType, "number")
        Equal(attr.resolve, Wild.GetMaxItemLevel)
        Equal(type(Wild.GetMaxItemLevel), "function")
        Equal(#Wild.db.intents, 0)
        for _, op in ipairs(Wild.OPERATORS) do
            if op.key == "<" or op.key == "<=" or op.key == ">" or op.key == ">="
                or op.key == "=" or op.key == "!=" then
                Equal(op.forTypes[attr.valueType], true)
            end
        end
    end },
    { "Hero gear below the crafted equipped level even at its ceiling matches", function()
        local Wild, _, AddItem, EquipItem = NewEnvironment()
        EquipItem(1, 100, { level = 130 })
        local info = AddItem(1, { level = 110, maximum = 125 })
        Equal(Wild.GetMaxItemLevel(1, info), 125)
        Equal(Wild.IntentMatchesItem(SellIntent(), 1, info, Wild.BuildCharContext()), true)
    end },
    { "gear that can surpass equipped gear is kept despite its lower current level", function()
        local Wild, _, AddItem, EquipItem = NewEnvironment()
        EquipItem(1, 100, { level = 130 })
        local info = AddItem(1, { level = 110, maximum = 140 })
        Equal(Wild.EvaluateCondition(PotentialCondition(), 1, info, Wild.BuildCharContext()), false)
        Equal(Wild.EvaluateCondition({ attr = "item.ilvl", op = "<", ref = "char.slotilvl" },
            1, info, Wild.BuildCharContext()), true, "Existing current-level comparisons remain available")
    end },
    { "equal ceilings are kept by less-than and matched only by less-than-or-equal", function()
        local Wild, _, AddItem, EquipItem = NewEnvironment()
        EquipItem(1, 100, { level = 130 })
        local info = AddItem(1, { level = 110, maximum = 130 })
        local ctx = Wild.BuildCharContext()
        Equal(Wild.EvaluateCondition(PotentialCondition(), 1, info, ctx), false)
        Equal(Wild.EvaluateCondition(PotentialCondition("<="), 1, info, ctx), true)
    end },
    { "no-track gear uses its effective hyperlink level rather than the base template", function()
        local Wild, _, AddItem = NewEnvironment()
        local info = AddItem(1, { level = 128, baseLevel = 1 })
        Equal(Wild.GetMaxItemLevel(1, info), 128)
    end },
    { "full links distinguish upgrade ceilings for two copies of the same item ID", function()
        local Wild, state, AddItem = NewEnvironment()
        local first = AddItem(1, { level = 110, maximum = 125,
            link = "item:1:0:0:0:0:0:0:0:90:0:0:0:1:1001" })
        local second = AddItem(1, { level = 120, maximum = 140,
            link = "item:1:0:0:0:0:0:0:0:90:0:0:0:1:1002" })
        Equal(Wild.GetMaxItemLevel(1, first), 125)
        Equal(Wild.GetMaxItemLevel(1, second), 140)
        Equal(state.upgradeQueries[1], first.hyperlink)
        Equal(state.upgradeQueries[2], second.hyperlink)
    end },
    { "ceilings use native levels regardless of track names or already-completed upgrades", function()
        local Wild, _, AddItem = NewEnvironment()
        local info = AddItem(1, { level = 125, upgradeInfo = {
            currentLevel = 6, maxLevel = 6, maxItemLevel = 125, trackString = "Held",
        } })
        Equal(Wild.GetMaxItemLevel(1, info), 125)
    end },
    { "the bag link is resolved when only an exact container location is supplied", function()
        local Wild, _, AddItem = NewEnvironment()
        local info = AddItem(1, { level = 110, maximum = 125 }, 5)
        Equal(Wild.GetMaxItemLevel(1, { bag = info.bag, slot = info.slot }), 125)
        Equal(Wild.GetMaxItemLevel(1, nil), nil, "A bare ID must not lose instance bonus IDs")
        Equal(Wild.GetMaxItemLevel(1, {}), nil)
    end },
    { "uncached items request data and do not match any numeric operator", function()
        local Wild, state, AddItem, EquipItem = NewEnvironment()
        EquipItem(1, 100, { level = 130 })
        local info = AddItem(1, { level = 110, maximum = 125, cached = false })
        for _, op in ipairs({ "<", "<=", ">", ">=", "=", "!=" }) do
            Equal(Wild.EvaluateCondition(PotentialCondition(op), 1, info, Wild.BuildCharContext()), false)
        end
        Equal(state.requests[1], 1)
        state.items[1].cached = true
        Equal(Wild.EvaluateCondition(PotentialCondition(), 1, info, Wild.BuildCharContext()), true)
    end },
    { "missing metadata, item levels, and malformed upgrade ceilings fail closed", function()
        local Wild, _, AddItem, EquipItem = NewEnvironment()
        EquipItem(1, 100, { level = 130 })
        for index, item in ipairs({
            { level = 110, maximum = 125, noInfo = true },
            { maximum = 125 },
            { level = 0, maximum = 125 },
            { level = 110, upgradeInfo = { currentLevel = 1, maxLevel = 6 } },
            { level = 110, upgradeInfo = { maxItemLevel = 0 } },
            { level = 110, upgradeInfo = { maxItemLevel = 100 } },
            { level = 110, upgradeInfo = { maxItemLevel = "125" } },
        }) do
            local info = AddItem(index, item)
            Equal(Wild.GetMaxItemLevel(index, info), nil)
            Equal(Wild.EvaluateCondition(PotentialCondition(), index, info, Wild.BuildCharContext()), false)
        end
    end },
    { "missing upgrade APIs never fall back to the lower current level", function()
        local Wild, _, AddItem, EquipItem, env = NewEnvironment()
        EquipItem(1, 100, { level = 130 })
        local info = AddItem(1, { level = 110, maximum = 140 })
        env.C_Item.GetItemUpgradeInfo = nil
        Equal(Wild.GetMaxItemLevel(1, info), nil)
        Equal(Wild.EvaluateCondition(PotentialCondition(), 1, info, Wild.BuildCharContext()), false)
    end },
    { "non-equipment and unsupported equip locations never match", function()
        local Wild, _, AddItem, EquipItem = NewEnvironment()
        EquipItem(1, 100, { level = 130 })
        for index, loc in ipairs({ "", "INVTYPE_BAG", "INVTYPE_BODY", "INVTYPE_TABARD" }) do
            local info = AddItem(index, { level = 1, maximum = 125, equipLoc = loc })
            Equal(Wild.GetMaxItemLevel(index, info), nil)
            Equal(Wild.EvaluateCondition(PotentialCondition(), index, info, Wild.BuildCharContext()), false)
        end
    end },
    { "rings, trinkets, and one-handed weapons compare against the weaker slot", function()
        for _, pair in ipairs({
            { "INVTYPE_FINGER", 11, 12 }, { "INVTYPE_TRINKET", 13, 14 }, { "INVTYPE_WEAPON", 16, 17 },
        }) do
            local Wild, _, AddItem, EquipItem = NewEnvironment()
            EquipItem(pair[2], 100, { level = 130 })
            EquipItem(pair[3], 101, { level = 120 })
            local info = AddItem(1, { level = 110, maximum = 125, equipLoc = pair[1] })
            Equal(Wild.EvaluateCondition(PotentialCondition(), 1, info, Wild.BuildCharContext()), false)
            EquipItem(pair[3], 102, { level = 128 })
            Equal(Wild.EvaluateCondition(PotentialCondition(), 1, info, Wild.BuildCharContext()), true)
        end
    end },
    { "empty or unreadable compatible slots prevent automatic sales", function()
        for _, pair in ipairs({
            { "INVTYPE_FINGER", 11, 12 }, { "INVTYPE_TRINKET", 13, 14 }, { "INVTYPE_WEAPON", 16, 17 },
        }) do
            local Wild, _, AddItem, EquipItem = NewEnvironment()
            EquipItem(pair[2], 100, { level = 130 })
            local info = AddItem(1, { level = 110, maximum = 125, equipLoc = pair[1] })
            Equal(Wild.EvaluateCondition(PotentialCondition(), 1, info, Wild.BuildCharContext()), false)
            EquipItem(pair[3], 101, {})
            Equal(Wild.EvaluateCondition(PotentialCondition(), 1, info, Wild.BuildCharContext()), false)
            EquipItem(pair[3], 102, { level = 0 })
            Equal(Wild.EvaluateCondition(PotentialCondition(), 1, info, Wild.BuildCharContext()), false)
        end
    end },
    { "slot comparisons use freshly equipped current levels, not their upgrade ceilings", function()
        local Wild, _, AddItem, EquipItem = NewEnvironment()
        EquipItem(1, 100, { level = 120, maximum = 140 })
        local info = AddItem(1, { level = 110, maximum = 125 })
        Equal(Wild.EvaluateCondition(PotentialCondition(), 1, info, Wild.BuildCharContext()), false)
        EquipItem(1, 101, { level = 130 })
        Equal(Wild.EvaluateCondition(PotentialCondition(), 1, info, Wild.BuildCharContext()), true)
    end },
    { "fixed values, offsets, summaries, and debug output expose maximum item levels", function()
        local Wild, state, AddItem, EquipItem = NewEnvironment()
        EquipItem(1, 100, { level = 130 })
        local info = AddItem(1, { level = 110, maximum = 125 })
        Equal(Wild.EvaluateCondition({ attr = "item.maxilvl", op = "=", value = 125 },
            1, info, Wild.BuildCharContext()), true)
        Equal(Wild.EvaluateCondition(PotentialCondition("<", -5), 1, info, Wild.BuildCharContext()), false)
        Equal(Wild.GetConditionsSummary({ PotentialCondition() }), "Maximum Item Level < Equipped Slot iLvl")
        assert(Wild.GetIntentSummary(SellIntent()):find("Maximum Item Level < Equipped Slot iLvl", 1, true))
        Wild.db.advanced.debug = true
        Wild.EvaluateCondition(PotentialCondition(), 1, info, Wild.BuildCharContext())
        assert(state.messages[#state.messages]:find("Maximum Item Level: actual=125", 1, true))
    end },
    { "the existing attribute picker exposes the new condition", function()
        local Wild, state, _, _, env = NewEnvironment()
        local menu, selected
        env.MenuResponse = MenuTestHelpers.Response
        setfenv(assert(loadfile("Settings.lua")), env)("Wild", Wild)
        local factory = GetUpvalue(state.frames[#state.frames].scripts.OnEvent, "CreateIntentRulesTab")
        local initialize = GetUpvalue(factory, "InitializeConditionAttributeDropdown")
        local dropdown = { SetupMenu = function(_, callback) menu = callback end }
        initialize(dropdown, function(attr) selected = attr end)
        local root = MenuTestHelpers.NewDescription("Root")
        menu(dropdown, root)
        for _, entry in ipairs(root.children) do
            if entry.data and entry.data.key == "item.maxilvl" then
                Equal(entry.text, "Maximum Item Level")
                entry:Pick()
            end
        end
        Equal(selected, Wild.ATTR_BY_KEY["item.maxilvl"])
        assert(selected, "Maximum item level must appear in the settings picker")
    end },
    { "maximum item level conditions are valid for every item-matching action", function()
        local Wild = NewEnvironment()
        local intent = SellIntent()
        intent.target, intent.source, intent.recipient = "warband", "character", "Alt"
        for _, action in ipairs({ "sell", "destroy", "deposit", "withdraw", "transfer", "mail" }) do
            intent.action = action
            Equal(Wild.ValidateIntent(intent), true)
        end
    end },
    { "merchant processing sells only lower-potential soulbound gear and includes the reagent bag", function()
        local Wild, state, AddItem, EquipItem, env, Fire, RunTimers, Tick = NewEnvironment()
        EquipItem(1, 100, { level = 130 })
        AddItem(1, { level = 110, maximum = 125 })
        AddItem(2, { level = 110, maximum = 140 })
        AddItem(3, { level = 110, maximum = 130 })
        AddItem(4, { level = 120 })
        AddItem(5, { level = 110, upgradeInfo = { currentLevel = 1, maxLevel = 6 } })
        AddItem(6, { level = 1, equipLoc = "" })
        AddItem(7, { level = 110, maximum = 125 }, 5)
        AddItem(8, { level = 110, maximum = 125, bindType = 7 })
        AddItem(9, { level = 110, maximum = 125, bindType = 2 })
        Wild.db.intents[1] = SellIntent()
        setfenv(assert(loadfile("Vendor.lua")), env)("Wild", Wild)
        Fire("MERCHANT_SHOW")
        RunTimers()
        for _ = 1, 4 do Tick() end
        Equal(#state.sold, 3)
        Equal(state.sold[1], 1)
        Equal(state.sold[2], 4)
        Equal(state.sold[3], 7)
        Fire("BAG_UPDATE_DELAYED")
        RunTimers()
        Equal(#state.sold, 3, "The retry pass must find no remaining eligible items")
    end },
    { "no rule or a disabled rule sells nothing", function()
        for _, disabled in ipairs({ false, true }) do
            local Wild, state, AddItem, EquipItem, env, Fire, RunTimers, Tick = NewEnvironment()
            EquipItem(1, 100, { level = 130 })
            AddItem(1, { level = 110, maximum = 125 })
            if disabled then
                Wild.db.intents[1] = SellIntent()
                Wild.db.intents[1].enabled = false
            end
            setfenv(assert(loadfile("Vendor.lua")), env)("Wild", Wild)
            Fire("MERCHANT_SHOW")
            RunTimers()
            Tick()
            Equal(#state.sold, 0)
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
string.trim = originalTrim
assert(failures == 0, failures .. " item level potential test(s) failed")
print("All " .. #tests .. " item level potential tests passed.")
