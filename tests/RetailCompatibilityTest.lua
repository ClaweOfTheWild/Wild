-- Run from the repository root with Lua 5.1: lua tests\RetailCompatibilityTest.lua
-- Contracts: Gethe/wow-ui-source 12.1.5, build 70391.
local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function NewEnvironment()
    local link = "|cff0070dd|Hitem:100::::::::90:::::1:1001|h[Test armor]|h|r"
    local state = {
        link = link, queries = {}, bags = {}, equipment = {}, guild = {}, logs = {},
        classID = 4, subclassID = 2, equipLoc = "INVTYPE_HEAD",
    }
    local Wild = {
        db = { intents = {}, advanced = {} },
        GetPlayerBags = function() return { 0, 5 } end,
        GetEffectiveSellPrice = function() return 100 end,
        Log = function(_, message) state.logs[#state.logs + 1] = message end,
    }
    local env = setmetatable({
        Enum = {
            BagIndex = {
                Characterbanktab = -2, ReagentBag = 5,
                CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8,
                CharacterBankTab_4 = 9, CharacterBankTab_5 = 10, CharacterBankTab_6 = 11,
                AccountBankTab_1 = 12, AccountBankTab_2 = 13, AccountBankTab_3 = 14,
                AccountBankTab_4 = 15, AccountBankTab_5 = 16,
            },
            PlayerInteractionType = {},
        },
        C_Item = {
            GetItemInfo = function(source)
                assert(source == 100 or source == link, "Unexpected item query")
                return "Test armor", link, 3, 90, 1, "Armor", "Leather", 20,
                    state.equipLoc, 134400, 100, state.classID, state.subclassID, 1, 11
            end,
            GetItemInfoInstant = function(source)
                Equal(source, 100)
                return 100, "Armor", "Leather", state.equipLoc, 134400,
                    state.classID, state.subclassID
            end,
            GetDetailedItemLevelInfo = function(source)
                Equal(source, link, "Detailed item levels must preserve the full hyperlink")
                state.queries[#state.queries + 1] = source
                return 144, false, 90
            end,
            GetItemClassInfo = function(classID)
                Equal(classID, 4)
                return "Armor"
            end,
            GetItemSubClassInfo = function(classID, subclassID)
                Equal(classID, 4)
                Equal(subclassID, 2)
                return "Leather", false
            end,
            GetItemSpell = function(source)
                Equal(source, 100)
                return "Learn spell", 700
            end,
            IsItemDataCachedByID = function(source) Equal(source, link); return true end,
            GetItemUpgradeInfo = function(source) Equal(source, link); return { maxItemLevel = 150 } end,
        },
        C_Container = {
            GetContainerNumSlots = function(bag) return #(state.bags[bag] or {}) end,
            GetContainerItemInfo = function(bag, slot) return state.bags[bag][slot] end,
        },
        CreateFrame = function()
            local frame = {}
            function frame:RegisterEvent() end
            function frame:UnregisterEvent() end
            function frame:SetScript() end
            return frame
        end,
        UnitName = function() return "Test" end,
        GetRealmName = function() return "Realm" end,
        GetGuildInfo = function() return "Test Guild" end,
        GetProfessions = function() end,
        GetAverageItemLevel = function() return 144, 144 end,
        UnitClass = function() return "Druid", "DRUID" end,
        UnitLevel = function() return 90 end,
        GetInventoryItemLink = function(_, slot) return state.equipment[slot] end,
        IsSpellKnown = function(spellID) Equal(spellID, 700); return true end,
        IsPlayerSpell = function() return false end,
        GetNumGuildBankTabs = function() return 1 end,
        GetGuildBankTabInfo = function() return "Tab", nil, true end,
        GetGuildBankItemInfo = function(_, slot)
            return 134400, state.guild[slot] and state.guild[slot].stackCount or 0, false
        end,
        GetGuildBankItemLink = function(_, slot)
            return state.guild[slot] and state.guild[slot].hyperlink
        end,
        time = function() return 123 end,
    }, { __index = _G })
    for _, name in ipairs({
        "GetItemInfoInstant", "GetDetailedItemLevelInfo", "GetItemClassInfo",
        "GetItemSubClassInfo", "GetItemSpell",
    }) do
        Equal(env[name], nil, "Removed item globals must not be supplied by the fixture")
    end
    for _, name in ipairs({ "Conditions.lua", "CharacterData.lua", "Tooltip.lua" }) do
        setfenv(assert(loadfile(name)), env)("Wild", Wild)
    end
    local function Item(count)
        return { itemID = 100, hyperlink = link, stackCount = count or 1, quality = 3 }
    end
    return Wild, state, Item
end

local tests = {
    { "the addon declares the installed Retail 12.1.5 interface", function()
        local file = assert(io.open("Wild.toc", "r"))
        local toc = file:read("*a")
        file:close()
        Equal(toc:match("## Interface:%s*(%d+)"), "120105")
    end },
    { "item classification uses current item APIs without deprecation fallbacks", function()
        local Wild, state = NewEnvironment()
        Equal(Wild.ATTR_BY_KEY["item.type"].resolve(100), 4)
        Equal(Wild.ATTR_BY_KEY["item.subtype"].resolve(100), 4002)
        Equal(Wild.ATTR_BY_KEY["item.isWrongArmorType"].resolve(100, nil, { classFile = "DRUID" }), false)
        Equal(Wild.ATTR_BY_KEY["item.isPet"].resolve(100), false)
        state.classID, state.subclassID = 15, 2
        Equal(Wild.ATTR_BY_KEY["item.isPet"].resolve(100), true)
        state.classID, state.subclassID = 9, 4
        Equal(Wild.ATTR_BY_KEY["item.isRecipeForMissingProfession"].resolve(100, nil, { professions = {} }), true)
    end },
    { "spell-teaching collection conditions use the namespaced item-spell API", function()
        local Wild, state = NewEnvironment()
        state.classID, state.subclassID, state.equipLoc = 15, 0, ""
        Equal(Wild.ATTR_BY_KEY["item.isKnown"].resolve(100), true)
    end },
    { "equipment comparisons preserve effective hyperlink levels and upgrade ceilings", function()
        local Wild, state = NewEnvironment()
        state.equipment[1] = state.link
        Equal(Wild.ATTR_BY_KEY["item.ilvl"].resolve(100, { hyperlink = state.link }), 144)
        Equal(Wild.GetMaxItemLevel(100, { hyperlink = state.link }), 150)
        Equal(Wild.BuildCharContext().slotIlvls[1], 144)
        Equal(#state.queries, 3)
    end },
    { "rule values summaries and debug output retain item class and subclass names", function()
        local Wild, state = NewEnvironment()
        Equal(Wild.FormatConditionValue({ value = 4 }, Wild.ATTR_BY_KEY["item.type"]), "Armor")
        Equal(Wild.FormatConditionValue({ value = 4002 }, Wild.ATTR_BY_KEY["item.subtype"]), "Armor > Leather")
        local intent = {
            action = "sell", groups = { { mode = "include",
                conditions = {
                    { attr = "item.type", op = "is", value = 4 },
                    { attr = "item.subtype", op = "is", value = 4002 },
                },
            } },
        }
        local summary = Wild.GetIntentSummary(intent)
        assert(summary:find("Leather", 1, true), summary)
        Wild.db.advanced.debug = true
        Equal(Wild.IntentMatchesItem(intent, 100, nil, Wild.BuildCharContext()), true)
        local log = table.concat(state.logs, "\n")
        assert(log:find("Item Type: actual=Armor", 1, true), log)
        assert(log:find("Item Subtype: actual=Armor > Leather", 1, true), log)
    end },
    { "tooltips retain class names and actual upgraded item levels", function()
        local Wild, state = NewEnvironment()
        local lines = {}
        for _, line in ipairs(Wild.TOOLTIP_LINES) do lines[line.key] = line end
        assert(lines.itemType.resolve(100):find("Armor > Leather", 1, true))
        Equal(lines.itemLevel.resolve(100, { hyperlink = state.link }), "iLvl: 144")
    end },
    { "bag character warband and guild snapshots retain effective item levels", function()
        local Wild, state, Item = NewEnvironment()
        state.bags[0], state.bags[5] = { Item(2) }, { Item(3) }
        state.bags[6], state.bags[12], state.guild = { Item(4) }, { Item(5) }, { Item(6) }
        Wild.SnapshotBags()
        Wild.SnapshotBank()
        Wild.SnapshotWarbandBank()
        Wild.SnapshotGuildBank()
        local datastore = Wild.db.datastore
        local character = datastore.characters["Test-Realm"]
        Equal(#character.bags, 2)
        Equal(character.bags[2].bag, 5)
        for _, record in ipairs({
            character.bags[1], character.bags[2], character.bank[1],
            datastore.warband.bank[1], datastore.guilds["Test Guild-Realm"].bank[1],
        }) do
            Equal(record.ilvl, 144)
            Equal(record.link, state.link)
        end
        Equal(character.bank[1].count, 4)
        Equal(datastore.warband.bank[1].count, 5)
        Equal(datastore.guilds["Test Guild-Realm"].bank[1].count, 6)
        Equal(#state.queries, 5)
    end },
}

local failures = 0
for _, test in ipairs(tests) do
    local ok, reason = pcall(test[2])
    if ok then
        print("PASS: " .. test[1])
    else
        failures = failures + 1
        print("FAIL: " .. test[1] .. ": " .. tostring(reason))
    end
end
assert(failures == 0, failures .. " Retail compatibility test(s) failed")
print(#tests .. " Retail compatibility tests passed")
