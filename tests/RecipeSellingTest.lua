-- Run from the repository root with Lua 5.1: lua tests\RecipeSellingTest.lua
local originalTrim = string.trim
string.trim = function(text) return text:match("^%s*(.-)%s*$") end

local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function AddRecipeSellIntent(Wild)
    local groups = {}
    for _, attr in ipairs({ "item.isRecipeKnown", "item.isRecipeForMissingProfession" }) do
        groups[#groups + 1] = {
            mode = "include",
            kind = "items",
            conditions = {
                { attr = "item.bind", op = "is", value = "soulbound" },
                { attr = attr, op = "is", value = true },
            },
        }
    end
    local intent = { enabled = true, action = "sell", groups = groups }
    Wild.db.intents[#Wild.db.intents + 1] = intent
    return intent
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

local function NewEnvironment()
    local Wild = { db = { intents = {}, advanced = { passDelay = 0, sellStartDelay = 0 } } }
    local state = {
        items = {}, bags = { [0] = {}, [5] = {} }, frames = {}, timers = {},
        professions = { [1] = 165, [2] = 393 }, professionIndices = { 1, 2 },
        sold = {}, destroyed = {}, logs = {}, merchantOpen = true, time = 10,
    }
    local function ItemID(source)
        if type(source) == "number" then return source end
        return tonumber(source:match("item:(%d+)"))
    end
    local function Tooltip(itemID)
        local item = state.items[itemID]
        if item.noTooltip then return nil end
        local lines = { { leftText = item.name or "Recipe" } }
        if item.tooltipBind then lines[#lines + 1] = { leftText = item.tooltipBind } end
        if item.known then lines[#lines + 1] = { leftText = "|cff00ff00Bereits bekannt|r" } end
        return { lines = lines }
    end
    local env = setmetatable({
        print = function(message) state.logs[#state.logs + 1] = message end,
        tremove = table.remove,
        SlashCmdList = {},
        strtrim = function(text) return text:match("^%s*(.-)%s*$") end,
        wipe = function(t) for key in pairs(t) do t[key] = nil end end,
        ITEM_SPELL_KNOWN = "Bereits bekannt",
        Enum = {
            BagIndex = { ReagentBag = 5 }, PlayerInteractionType = { Merchant = 5 },
            TooltipDataLineType = { SellPrice = 11 },
        },
        CreateFrame = function()
            local frame = { events = {}, scripts = {}, shown = false }
            function frame:Hide() self.shown = false end
            function frame:Show() self.shown = true end
            function frame:IsShown() return self.shown end
            function frame:RegisterEvent(event) self.events[event] = true end
            function frame:UnregisterEvent(event) self.events[event] = nil end
            function frame:RegisterAllEvents() end
            function frame:UnregisterAllEvents() self.events = {} end
            function frame:SetScript(event, callback) self.scripts[event] = callback end
            state.frames[#state.frames + 1] = frame
            return frame
        end,
        GetItemInfoInstant = function(source)
            local id = ItemID(source)
            local item = state.items[id]
            return id, nil, nil, nil, nil, item.classID, item.subclassID
        end,
        C_Item = {
            GetItemInfo = function(source)
                local id = ItemID(source)
                local item = state.items[id]
                return item.name or "Recipe", "item:" .. id, 3, 1, 1, nil, nil, 1, "",
                    nil, item.price or 100, item.classID, item.subclassID, item.bindType or 1
            end,
            RequestLoadItemDataByID = function() end,
        },
        C_TooltipInfo = {
            GetBagItem = function(bag, slot) return Tooltip(state.bags[bag][slot].itemID) end,
            GetHyperlink = function(link) return Tooltip(ItemID(link)) end,
            GetItemByID = Tooltip,
        },
        GetItemSpell = function() return "Learn recipe", 999 end,
        IsSpellKnown = function() return false end,
        IsPlayerSpell = function() return false end,
        GetProfessions = function() return unpack(state.professionIndices, 1, 5) end,
        GetProfessionInfo = function(index)
            return "Profession", nil, 1, 100, nil, nil, state.professions[index]
        end,
        GetAverageItemLevel = function() return 100, 100 end,
        UnitClass = function() return "Druid", "DRUID" end,
        UnitLevel = function() return 90 end,
        UnitName = function() return "Test" end,
        GetRealmName = function() return "Realm" end,
        GetInventoryItemLink = function() end,
        GetTime = function() return state.time end,
        GetMoneyString = function(amount) return tostring(amount) .. " copper" end,
        GetItemClassInfo = function(id) return id == 9 and "Recipes" or "Items" end,
        C_Timer = { After = function(_, callback) state.timers[#state.timers + 1] = callback end },
        MerchantFrame = { IsShown = function() return state.merchantOpen end },
        C_Container = {
            GetContainerNumSlots = function(bag) return #state.bags[bag] end,
            GetContainerItemInfo = function(bag, slot) return state.bags[bag][slot] end,
            UseContainerItem = function(bag, slot)
                state.sold[#state.sold + 1] = state.bags[bag][slot].itemID
                state.bags[bag][slot] = false
            end,
        },
        Item = {
            CreateFromItemID = function()
                return { IsItemDataCached = function() return true end }
            end,
        },
    }, { __index = _G })
    Wild.GetPlayerBags = function() return { 0, 5 } end
    Wild.QueueDestroyItems = function(items) state.destroyed = items end
    Wild.Log = function() end
    Wild.FEATURES = {}
    setfenv(assert(loadfile("Core.lua")), env)("Wild", Wild)
    setfenv(assert(loadfile("Conditions.lua")), env)("Wild", Wild)
    setfenv(assert(loadfile("Vendor.lua")), env)("Wild", Wild)
    setfenv(assert(loadfile("SlashCommands.lua")), env)("Wild", Wild)

    local function AddItem(itemID, item, bag)
        state.items[itemID] = item
        bag = bag or 0
        local slot = #state.bags[bag] + 1
        local info = { itemID = itemID, hyperlink = "item:" .. itemID, stackCount = 1,
            isBound = item.bindType == nil or item.bindType == 1, bag = bag, slot = slot }
        state.bags[bag][slot] = info
        return info
    end
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
    return Wild, state, AddItem, Fire, RunTimers, Tick, env
end

local tests = {
    { "recipe selling uses only ordinary intents with no separate toggle", function()
        local Wild = NewEnvironment()
        Equal(#Wild.db.intents, 0)
        Equal(Wild.IsRecipeSellingEnabled, nil)
        Equal(Wild.SetRecipeSellingEnabled, nil)
        local intent = AddRecipeSellIntent(Wild)
        Equal(Wild.ValidateIntent(intent), true)
        Equal(intent.recipeSelling, nil)
        Equal(#Wild.db.intents, 1)
    end },
    { "recipe condition states have readable labels under item types and subtypes", function()
        local Wild = NewEnvironment()
        for _, key in ipairs({ "item.isRecipeKnown", "item.isRecipeForMissingProfession" }) do
            local attr = Wild.ATTR_BY_KEY[key]
            assert(attr, "Recipe condition must be registered")
            Equal(attr.category, "Item types and subtypes")
            Equal(attr.subcategory, "Recipes")
        end
        Equal(Wild.GetConditionsSummary({ { attr = "item.isRecipeKnown", op = "is", value = true } }),
            "Recipe Knowledge is Already known")
        Equal(Wild.GetConditionsSummary({ { attr = "item.isRecipeKnown", op = "is", value = false } }),
            "Recipe Knowledge is Not yet known")
        Equal(Wild.GetConditionsSummary({ { attr = "item.isRecipeForMissingProfession", op = "is", value = true } }),
            "Recipe Profession is Unknown profession")
        Equal(Wild.GetConditionsSummary({ { attr = "item.isRecipeForMissingProfession", op = "is", value = false } }),
            "Recipe Profession is Known profession")
        Equal(Wild.GetConditionsSummary({ { attr = "item.isReagent", op = "is", value = false } }),
            "Is Crafting Reagent is No")
        local summary = Wild.GetIntentSummary(AddRecipeSellIntent(Wild))
        assert(summary:find("Recipes", 1, true))
        assert(summary:find("Recipe Knowledge is Already known", 1, true))
        assert(summary:find("Recipe Profession is Unknown profession", 1, true))
    end },
    { "condition picker nests recipe attributes and still exposes every other attribute", function()
        local Wild, state, _, _, _, _, env = NewEnvironment()
        local initializeMenu, entries, selected
        env.UIDropDownMenu_Initialize = function(_, callback) initializeMenu = callback end
        env.UIDropDownMenu_CreateInfo = function() return {} end
        env.UIDropDownMenu_AddButton = function(info, level)
            info.level = level
            entries[#entries + 1] = info
        end
        env.CloseDropDownMenus = function() end
        setfenv(assert(loadfile("Settings.lua")), env)("Wild", Wild)
        local loader = state.frames[#state.frames]
        local factory = GetUpvalue(loader.scripts.OnEvent, "CreateIntentRulesTab")
        local initialize = GetUpvalue(factory, "InitializeConditionAttributeDropdown")
        initialize({}, function(attr) selected = attr end)

        entries = {}
        initializeMenu(nil, 1)
        local seen = {}
        local itemTypeMenus = 0
        for _, entry in ipairs(entries) do
            Equal(entry.level, 1)
            if entry.menuList == "itemTypes" then
                itemTypeMenus = itemTypeMenus + 1
                Equal(entry.hasArrow, true)
            end
            if entry.value then seen[entry.value] = true end
        end
        Equal(itemTypeMenus, 1)
        for _, attr in ipairs(Wild.ATTRIBUTES) do
            Equal(seen[attr.key] == true, attr.category ~= "Item types and subtypes")
        end

        entries = {}
        initializeMenu(nil, 2, "itemTypes")
        Equal(#entries, 3)
        Equal(entries[1].value, "item.type")
        Equal(entries[2].value, "item.subtype")
        Equal(entries[3].text, "Recipes")
        Equal(entries[3].hasArrow, true)
        Equal(entries[3].menuList, "recipes")
        entries[1].func()
        Equal(selected.key, "item.type")

        entries = {}
        initializeMenu(nil, 3, "recipes")
        Equal(#entries, 2)
        Equal(entries[1].text, "Recipe Knowledge")
        Equal(entries[2].text, "Recipe Profession")
        for _, entry in ipairs(entries) do
            Equal(entry.level, 3)
            entry.func()
            Equal(selected, Wild.ATTR_BY_KEY[entry.value])
        end
    end },
    { "recipe states match only recipes including negative operators", function()
        local Wild, _, AddItem = NewEnvironment()
        local info = AddItem(1, { classID = 4, subclassID = 4 })
        for _, key in ipairs({ "item.isRecipeKnown", "item.isRecipeForMissingProfession" }) do
            for _, value in ipairs({ true, false }) do
                for _, op in ipairs({ "is", "is_not" }) do
                    Equal(Wild.EvaluateCondition({ attr = key, op = op, value = value },
                        1, info, Wild.BuildCharContext()), false)
                end
            end
        end
        info = AddItem(2, { classID = 9, subclassID = 1 })
        Equal(Wild.EvaluateCondition({ attr = "item.isRecipeKnown", op = "is", value = false },
            2, info, Wild.BuildCharContext()), true)
        Equal(Wild.EvaluateCondition({ attr = "item.isRecipeForMissingProfession", op = "is", value = false },
            2, info, Wild.BuildCharContext()), true)
    end },
    { "recipe conditions work with every item-matching action", function()
        local Wild, _, AddItem = NewEnvironment()
        local info = AddItem(1, { classID = 9, subclassID = 4 })
        local intent = AddRecipeSellIntent(Wild)
        intent.target = "warband"
        intent.source = "character"
        intent.recipient = "Alt"
        for _, action in ipairs({ "sell", "destroy", "deposit", "withdraw", "transfer", "mail" }) do
            intent.action = action
            Equal(Wild.ValidateIntent(intent), true)
            Equal(Wild.IntentMatchesItem(intent, 1, info, Wild.BuildCharContext()), true)
        end
    end },
    { "conditions within a group are AND while recipe include groups are OR", function()
        local Wild, _, AddItem = NewEnvironment()
        local info = AddItem(1, { classID = 9, subclassID = 1, known = true })
        local intent = AddRecipeSellIntent(Wild)
        Equal(Wild.IntentMatchesItem(intent, 1, info, Wild.BuildCharContext()), true)
        intent.groups = {
            { conditions = {
                { attr = "item.isRecipeKnown", op = "is", value = true },
                { attr = "item.isRecipeForMissingProfession", op = "is", value = true },
            } },
        }
        Equal(Wild.IntentMatchesItem(intent, 1, info, Wild.BuildCharContext()), false)
    end },
    { "obsolete recipe shortcut metadata is removed without changing saved intents", function()
        local Wild, state, _, _, _, _, env = NewEnvironment()
        local intent = AddRecipeSellIntent(Wild)
        intent.recipeSelling = true
        intent.enabled = false
        local groups = intent.groups
        env.WildDB = { intents = { intent } }
        local firstCoreFrame = #state.frames + 1
        setfenv(assert(loadfile("Core.lua")), env)("Wild", Wild)
        local loader = state.frames[firstCoreFrame]
        loader.scripts.OnEvent(loader, "ADDON_LOADED", "Wild")
        Equal(Wild.db.intents[1], intent)
        Equal(intent.recipeSelling, nil)
        Equal(intent.enabled, false)
        Equal(intent.groups, groups)
        Equal(Wild.ValidateIntent(intent), true)
    end },
    { "leatherworker and skinner sell soulbound blacksmithing recipes", function()
        local Wild, _, AddItem = NewEnvironment()
        local info = AddItem(1, { classID = 9, subclassID = 4 })
        AddRecipeSellIntent(Wild)
        Equal(Wild.IntentMatchesItem(Wild.db.intents[1], 1, info, Wild.BuildCharContext()), true)
    end },
    { "already learned soulbound recipes match even when the item spell is not known", function()
        local Wild, _, AddItem = NewEnvironment()
        local info = AddItem(1, { classID = 9, subclassID = 1, known = true })
        AddRecipeSellIntent(Wild)
        Equal(Wild.EvaluateCondition({ attr = "item.isKnown", op = "is", value = true },
            1, info, Wild.BuildCharContext()), true)
        Equal(Wild.IntentMatchesItem(Wild.db.intents[1], 1, info, Wild.BuildCharContext()), true)
    end },
    { "unlearned recipes for current professions are kept regardless of skill", function()
        local Wild, _, AddItem = NewEnvironment()
        local info = AddItem(1, { classID = 9, subclassID = 1 })
        AddRecipeSellIntent(Wild)
        Equal(Wild.IntentMatchesItem(Wild.db.intents[1], 1, info, Wild.BuildCharContext()), false)
    end },
    { "tradeable and warbound recipes are kept even if known or for another profession", function()
        for _, bindType in ipairs({ 0, 2, 3, 7, 8, 9 }) do
            local Wild, _, AddItem = NewEnvironment()
            local info = AddItem(1, { classID = 9, subclassID = 4, known = true, bindType = bindType })
            AddRecipeSellIntent(Wild)
            Equal(Wild.IntentMatchesItem(Wild.db.intents[1], 1, info, Wild.BuildCharContext()), false)
        end
    end },
    { "warbound tooltip overrides misleading bind-on-pickup item data", function()
        local Wild, _, AddItem = NewEnvironment()
        local info = AddItem(1, { classID = 9, subclassID = 4, tooltipBind = "Warbound" })
        AddRecipeSellIntent(Wild)
        local matched = Wild.IntentMatchesItem(Wild.db.intents[1], 1, info, Wild.BuildCharContext())
        Equal(matched, false)
    end },
    { "cooking and fishing are recognized even when primary profession slots are empty", function()
        local Wild, state, AddItem = NewEnvironment()
        state.professionIndices = { [4] = 4, [5] = 5 }
        state.professions = { [4] = 356, [5] = 185 }
        AddRecipeSellIntent(Wild)
        for _, subclassID in ipairs({ 5, 9 }) do
            local info = AddItem(subclassID, { classID = 9, subclassID = subclassID })
            Equal(Wild.IntentMatchesItem(Wild.db.intents[1], subclassID, info, Wild.BuildCharContext()), false)
        end
    end },
    { "a second primary profession is recognized when the first slot is empty", function()
        local Wild, state, AddItem = NewEnvironment()
        state.professionIndices = { [2] = 2 }
        state.professions = { [2] = 164 }
        local info = AddItem(1, { classID = 9, subclassID = 4 })
        AddRecipeSellIntent(Wild)
        Equal(Wild.IntentMatchesItem(Wild.db.intents[1], 1, info, Wild.BuildCharContext()), false)
    end },
    { "recipe profession mappings distinguish each crafting profession", function()
        local mappings = { [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185,
            [6] = 171, [8] = 333, [9] = 356, [10] = 755, [11] = 773 }
        local Wild, _, AddItem = NewEnvironment()
        for subclassID, skillLine in pairs(mappings) do
            AddItem(subclassID, { classID = 9, subclassID = subclassID })
            local condition = { attr = "item.isRecipeForMissingProfession", op = "is", value = true }
            Equal(Wild.EvaluateCondition(condition, subclassID, nil, { professions = {} }), true)
            Equal(Wild.EvaluateCondition(condition, subclassID, nil,
                { professions = { [skillLine] = true } }), false)
        end
    end },
    { "books, obsolete first-aid recipes, unknown subclasses, and non-recipes are not assumed unusable", function()
        local Wild, _, AddItem = NewEnvironment()
        AddRecipeSellIntent(Wild)
        for _, entry in ipairs({ { 9, 0 }, { 9, 7 }, { 9, 99 }, { 4, 4 } }) do
            local info = AddItem(1, { classID = entry[1], subclassID = entry[2] })
            Equal(Wild.IntentMatchesItem(Wild.db.intents[1], 1, info, Wild.BuildCharContext()), false)
        end
    end },
    { "missing recipe tooltip data does not count as learned", function()
        local Wild, _, AddItem = NewEnvironment()
        local info = AddItem(1, { classID = 9, subclassID = 1, noTooltip = true })
        AddRecipeSellIntent(Wild)
        Equal(Wild.IntentMatchesItem(Wild.db.intents[1], 1, info, Wild.BuildCharContext()), false)
        Equal(Wild.EvaluateCondition({ attr = "item.isKnown", op = "is", value = false },
            1, info, Wild.BuildCharContext()), false)
    end },
    { "recipe knowledge resolves from tooltip lines, links, and bare item IDs", function()
        local Wild, _, AddItem = NewEnvironment()
        AddItem(1, { classID = 9, subclassID = 1, known = true })
        for _, context in ipairs({
            { tooltipLines = { { leftText = "Bereits bekannt" } } },
            { tooltipLines = { { rightText = "  |cff00ff00Bereits bekannt|r  " } } },
            { hyperlink = "item:1" }, {},
        }) do
            Equal(Wild.IsRecipeKnown(1, context), true)
        end
    end },
    { "knowing a shared item-use spell does not mark an unlearned recipe as learned", function()
        local Wild, _, AddItem, _, _, _, env = NewEnvironment()
        local info = AddItem(1, { classID = 9, subclassID = 1 })
        env.IsSpellKnown = function() return true end
        env.IsPlayerSpell = function() return true end
        Equal(Wild.IsRecipeKnown(1, info), false)
    end },
    { "recipe tooltip collection status uses the same knowledge as sell conditions", function()
        local Wild, _, AddItem, _, _, _, env = NewEnvironment()
        setfenv(assert(loadfile("Tooltip.lua")), env)("Wild", Wild)
        local resolve
        for _, line in ipairs(Wild.TOOLTIP_LINES) do
            if line.key == "collectionStatus" then resolve = line.resolve end
        end
        assert(resolve, "Collection status resolver must be exposed")
        local info = AddItem(1, { classID = 9, subclassID = 1, known = true })
        Equal(resolve(1, info), "Recipe: |cff00ff00known|r")
        AddItem(1, { classID = 9, subclassID = 1 })
        Equal(resolve(1, info), "Recipe: |cffffff00unknown|r")
    end },
    { "ordinary recipe intents persist across addon reloads without duplicates", function()
        local Wild, _, _, _, _, _, env = NewEnvironment()
        local intent = AddRecipeSellIntent(Wild)
        setfenv(assert(loadfile("Vendor.lua")), env)("Wild", Wild)
        Equal(#Wild.db.intents, 1)
        Equal(Wild.db.intents[1], intent)
        Equal(Wild.ValidateIntent(intent), true)
    end },
    { "there is no recipe-specific slash command creating rules", function()
        local Wild, state = NewEnvironment()
        Wild.HandleSlashCommand("recipes on")
        Equal(#Wild.db.intents, 0)
        assert(state.logs[#state.logs]:find("Unknown command:", 1, true))
    end },
    { "merchant processing sells only matching recipes including the reagent bag and re-scans after bags update", function()
        local Wild, state, AddItem, Fire, RunTimers, Tick = NewEnvironment()
        AddItem(1, { classID = 9, subclassID = 4 })
        AddItem(2, { classID = 9, subclassID = 1, known = true }, 5)
        AddItem(3, { classID = 9, subclassID = 1 })
        AddItem(4, { classID = 9, subclassID = 4, bindType = 7 })
        AddItem(5, { classID = 9, subclassID = 4, price = 0 })
        AddRecipeSellIntent(Wild)
        Fire("MERCHANT_SHOW")
        RunTimers()
        Tick(); Tick(); Tick()
        Equal(#state.sold, 2)
        Equal(state.sold[1], 1)
        Equal(state.sold[2], 2)
        Equal(#state.destroyed, 0, "Recipes with no sell price must never be destroyed")
        AddItem(6, { classID = 9, subclassID = 4 })
        Tick()
        Equal(#state.sold, 2, "A second pass must wait for BAG_UPDATE_DELAYED")
        Fire("BAG_UPDATE_DELAYED")
        RunTimers()
        Tick(); Tick()
        Equal(#state.sold, 3)
        Equal(state.sold[3], 6)
    end },
    { "disabled recipe intent sells nothing at a merchant", function()
        local Wild, state, AddItem, Fire, RunTimers, Tick = NewEnvironment()
        AddItem(1, { classID = 9, subclassID = 4 })
        local intent = AddRecipeSellIntent(Wild)
        intent.enabled = false
        Fire("MERCHANT_SHOW")
        RunTimers()
        Tick()
        Equal(#state.sold, 0)
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
assert(failures == 0, failures .. " recipe selling test(s) failed")
print("All " .. #tests .. " recipe selling tests passed.")
