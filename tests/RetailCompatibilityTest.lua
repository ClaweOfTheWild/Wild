-- Run from the repository root with Lua 5.1: lua tests\RetailCompatibilityTest.lua
-- Contracts: Gethe/wow-ui-source 12.1.5, build 70391.
-- Mail also uses the Forever 1.60.1 contract. Only the client boundary is simulated.
local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = Copy(child) end
    return copy
end

local function NewEnvironment(mode, saved, build)
    local link = "|cff0070dd|Hitem:100::::::::90:::::1:1001|h[Test armor]|h|r"
    local state = {
        link = link, queries = {}, bags = {}, equipment = {}, guild = {}, logs = {},
        classID = 4, subclassID = 2, equipLoc = "INVTYPE_HEAD",
        frames = {}, bankTypes = { [0] = true, [2] = true }, capacities = {},
        character = "Test", realm = "Realm", now = 123, guildTab = 1, inbox = {}, sent = {},
        tooltipText = {}, chat = {},
    }
    local Wild = {
        GetPlayerBags = function() return { 0, 5 } end,
        GetEffectiveSellPrice = function() return 100 end,
        Log = function(_, message) state.logs[#state.logs + 1] = message end,
    }
    local env = setmetatable({
        WOW_PROJECT_ID = mode == "forever" and 18 or 1,
        WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CAMELOT = 18,
        WildDB = saved,
        GetBuildInfo = function()
            if mode == "forever" then return "1.60.1", "70755", "", 16001 end
            if build then return "12.1.6", build, "", 120106 end
            return "12.1.5", "70391", "", 120105
        end,
        wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end end,
        Enum = {
            BagIndex = {
                Characterbanktab = -2, ReagentBag = 5,
                CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8,
                CharacterBankTab_4 = 9, CharacterBankTab_5 = 10, CharacterBankTab_6 = 11,
                AccountBankTab_1 = 12, AccountBankTab_2 = 13, AccountBankTab_3 = 14,
                AccountBankTab_4 = 15, AccountBankTab_5 = 16,
            },
            BankType = { Character = 0, Account = 2 },
            PlayerInteractionType = {},
            TooltipDataType = { Item = 0 },
        },
        BACKPACK_CONTAINER = 0, NUM_BAG_SLOTS = 0,
        SlashCmdList = {}, tremove = table.remove,
        print = function(message) state.chat[#state.chat + 1] = message end,
        strtrim = function(value) return value:match("^%s*(.-)%s*$") end,
        C_Bank = { CanViewBank = function(bankType) return state.bankTypes[bankType] end },
        C_Item = {
            GetItemInfo = function(source)
                assert(source == 100 or source == link, "Unexpected item query")
                return "Test armor", link, 3, 90, 1, "Armor", "Leather", 20,
                    state.equipLoc, 134400, 100, state.classID, state.subclassID, 1, 11
            end,
            GetItemIconByID = function() return 134400 end,
            GetItemNameByID = function(itemID) if itemID == 100 then return "Test armor" end end,
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
            GetContainerNumSlots = function(bag) return state.capacities[bag] or #(state.bags[bag] or {}) end,
            GetContainerItemInfo = function(bag, slot) return (state.bags[bag] or {})[slot] end,
        },
        C_Timer = { After = function(_, callback) callback() end },
        CreateFrame = function(_, name)
            local frame = { events = {} }
            function frame:RegisterEvent(event) self.events[event] = true end
            function frame:UnregisterEvent(event) self.events[event] = nil end
            function frame:SetScript(event, callback) self[event] = callback end
            function frame:Show() if name == "WildTooltipFrame" then state.tooltipShown = true end end
            function frame:CreateFontString()
                local fontString = {
                    SetText = function(_, text) state.tooltipText[text] = true end,
                    GetStringWidth = function() return 20 end,
                }
                return setmetatable(fontString, { __index = function() return function() end end })
            end
            setmetatable(frame, { __index = function(_, key)
                if key:match("^Set") or key == "Hide" or key == "ClearAllPoints" then return function() end end
            end })
            state.frames[#state.frames + 1] = frame
            return frame
        end,
        UnitName = function() return state.character end,
        GetUnitName = function() return state.character end,
        GetRealmName = function() return state.realm end,
        GetGuildInfo = function() return "Test Guild" end,
        GetProfessions = function() end,
        GetAverageItemLevel = function() return 144, 144 end,
        UnitClass = function() return "Druid", "DRUID" end,
        UnitLevel = function() return 90 end,
        GetInventoryItemID = function(_, slot) if state.equipment[slot] then return 100 end end,
        GetInventoryItemLink = function(_, slot) return state.equipment[slot] end,
        GetInventoryItemCount = function() return 1 end,
        IsSpellKnown = function(spellID) Equal(spellID, 700); return true end,
        IsPlayerSpell = function() return false end,
        GetNumGuildBankTabs = function() return 2 end,
        GetCurrentGuildBankTab = function() return state.guildTab end,
        GetGuildBankTabInfo = function() return "Tab", nil, true end,
        GetGuildBankItemInfo = function(tab, slot)
            local item = (state.guild[tab] or {})[slot]
            return item and 134400, item and item.stackCount, false
        end,
        GetGuildBankItemLink = function(tab, slot)
            local item = (state.guild[tab] or {})[slot]
            return item and item.hyperlink
        end,
        GetInboxNumItems = function() return #state.inbox, state.totalMail or #state.inbox end,
        GetInboxHeaderInfo = function(index)
            local mail = state.inbox[index]
            return nil, nil, "Sender", "Subject", 0, 0, mail.daysLeft, mail.attachmentCount
        end,
        GetInboxItem = function(index, slot)
            local item = state.inbox[index].items[slot]
            if item then return "Test armor", item.itemID, 134400, item.stackCount, 3 end
        end,
        GetInboxItemLink = function(index, slot)
            local item = state.inbox[index].items[slot]
            return item and item.hyperlink
        end,
        GetSendMailItem = function(slot)
            local item = state.sent[slot]
            if item then return "Test armor", item.itemID, 134400, item.stackCount, 3 end
        end,
        GetSendMailItemLink = function(slot) return state.sent[slot] and state.sent[slot].hyperlink end,
        SendMail = function() end,
        time = function() return state.now end,
        GameTooltip = { HookScript = function() end, GetOwner = function() end, GetWidth = function() return 200 end },
        TooltipDataProcessor = {
            AddTooltipPostCall = function(_, callback) state.itemTooltip = callback end,
        },
    }, { __index = _G })
    env.hooksecurefunc = function(name, callback)
        local original = assert(env[name])
        env[name] = function(...)
            original(...)
            callback(...)
        end
    end
    for _, name in ipairs({
        "GetItemInfoInstant", "GetDetailedItemLevelInfo", "GetItemClassInfo",
        "GetItemSubClassInfo", "GetItemSpell",
    }) do
        Equal(env[name], nil, "Removed item globals must not be supplied by the fixture")
    end
    for _, name in ipairs({ "Core.lua", "Conditions.lua", "CharacterData.lua", "Tooltip.lua", "SlashCommands.lua" }) do
        setfenv(assert(loadfile(name)), env)("Wild", Wild)
    end
    local function Item(count)
        return { itemID = 100, hyperlink = link, stackCount = count or 1, quality = 3 }
    end
    local function Fire(event, ...)
        for _, frame in ipairs({ unpack(state.frames) }) do
            if frame.events[event] and frame.OnEvent then frame:OnEvent(event, ...) end
        end
    end
    Fire("ADDON_LOADED", "Wild")
    return Wild, state, Item, Fire, env
end

local function GetCount(rows, location, owner)
    for _, row in ipairs(rows or {}) do
        if row.location == location and (row.character or row.guild) == owner then return row.count end
    end
    return 0
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
        local Wild, state, Item, Fire = NewEnvironment()
        state.bags[0], state.bags[5] = { Item(2) }, { Item(3) }
        state.bags[6], state.bags[12] = { Item(4) }, { Item(5) }
        Wild.SnapshotBags()
        Wild.SnapshotBank()
        Wild.SnapshotWarbandBank()
        Fire("GUILDBANKFRAME_OPENED")
        state.guild[1] = { Item(6) }
        Fire("GUILDBANKBAGSLOTS_CHANGED")
        local datastore = Wild.GetClientData().datastore
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
    { "inventory and confirmed mail stay with their client when the saved file is copied", function()
        local retail, state, Item, Fire, env = NewEnvironment()
        retail.SetSetting("includeReagentBag", false)
        retail.db.intents[1] = { action = "mail", recipient = "Alt-Realm" }
        state.bags[0], state.bags[12] = { Item(9) }, { Item(3) }
        retail.SnapshotBags()
        retail.SnapshotWarbandBank()
        Fire("MAIL_SHOW")
        state.sent = { Item(7) }
        env.SendMail("Alt", "Saved send", "")
        Fire("MAIL_SEND_SUCCESS")

        local forever, other, OtherItem, FireOther = NewEnvironment("forever", Copy(retail.db))
        Equal(forever.GetSetting("includeReagentBag"), false)
        Equal(forever.db.intents[1].recipient, "Alt-Realm")
        Equal(#forever.FindItems("armor"), 0)
        Equal(#forever.GetItemEntries(100, "bags", "Test-Realm"), 0)
        other.bags[0] = { OtherItem(2) }
        forever.SnapshotBags()
        Equal(forever.GetItemTotal(100), 2)

        other.character = "Alt"
        FireOther("MAIL_SHOW")
        FireOther("MAIL_INBOX_UPDATE")
        local reloaded = NewEnvironment("retail", Copy(forever.db), "70400")
        local total, _, sent = reloaded.GetItemTotal(100)
        Equal(total, 12, "Retail must retain its own counts across a patch and ignore Forever's")
        Equal(#sent, 1)
        Equal(sent[1].count, 7)

        forever.ResetSettings()
        Equal(forever.GetItemTotal(100), 0)
        local afterReset = NewEnvironment("retail", Copy(forever.db))
        Equal(afterReset.GetItemTotal(100), 12, "Reset on a different client must not remove Retail observations")
    end },
    { "untagged inventory and unknown data formats are preserved without being used", function()
        local item = { itemID = 100, name = "Test armor", count = 9 }
        local old = { characters = { ["Test-Realm"] = { bags = { item } } } }
        local future = { datastore = old }
        local Wild, state, Item = NewEnvironment("retail", {
            datastore = old, clientData = { retail = { [2] = future } },
        })
        Equal(#Wild.FindItems("armor"), 0)
        state.bags[0] = { Item(3) }
        Wild.SnapshotBags()
        Equal(Wild.GetItemTotal(100), 3)
        Equal(Wild.db.legacyClientData[1].datastore.characters["Test-Realm"].bags[1].count, 9)
        Wild.ResetSettings()
        Equal(Wild.db.clientData.retail[2], future)
        Equal(Wild.db.legacyClientData[1].datastore, old)
    end },
    { "inventory keeps alt bags, reagent bags excluded from rules, and equipped items", function()
        local Wild, state, Item, Fire = NewEnvironment()
        state.character = "Alt"
        state.bags[0] = { Item(2) }
        Wild.SnapshotBags()

        state.character = "Test"
        Wild.db.includeReagentBag = false
        state.bags[0], state.bags[5] = { Item(3), Item(4) }, { Item(5) }
        state.equipment[1] = state.link
        Fire("PLAYER_ENTERING_WORLD")
        local total, breakdown = Wild.GetItemTotal(100)
        Equal(total, 15)
        Equal(GetCount(breakdown, "bags", "Alt-Realm"), 2)
        Equal(GetCount(breakdown, "bags", "Test-Realm"), 7)
        Equal(GetCount(breakdown, "reagentBag", "Test-Realm"), 5)
        Equal(GetCount(breakdown, "equipped", "Test-Realm"), 1)

        state.equipment[1] = nil
        Fire("PLAYER_EQUIPMENT_CHANGED", 1, false)
        Equal(Wild.GetItemTotal(100), 14)
    end },
    { "bank tab changes save the new counts and closing the bank preserves its last view", function()
        local Wild, state, Item, Fire = NewEnvironment()
        state.capacities[6], state.capacities[12] = 2, 2
        state.bags[6], state.bags[12] = { Item(5) }, { Item(3) }
        Fire("BANKFRAME_OPENED")
        Equal(Wild.GetItemTotal(100), 8)

        state.bags[12] = { Item(6) }
        Fire("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", 1)
        state.bags[6] = {}
        Fire("BAG_UPDATE_DELAYED")
        Fire("BANKFRAME_CLOSED")
        state.bags[12] = {}
        Fire("BAG_UPDATE_DELAYED")
        local total, breakdown = Wild.GetItemTotal(100)
        Equal(total, 6)
        Equal(GetCount(breakdown, "warband"), 6)
    end },
    { "guild bank changes replace the visited tab without losing other saved tabs", function()
        local Wild, state, Item, Fire = NewEnvironment()
        state.guild[1] = { Item(5) }
        Fire("GUILDBANKFRAME_OPENED")
        Fire("GUILDBANKBAGSLOTS_CHANGED")
        state.guild[1], state.guild[2], state.guildTab = nil, { Item(2) }, 2
        Fire("GUILDBANKBAGSLOTS_CHANGED")
        Equal(Wild.GetItemTotal(100), 7)
        state.guildTab = 1
        Fire("GUILDBANKBAGSLOTS_CHANGED")
        Fire("GUILDBANKFRAME_CLOSED")
        state.guildTab = 2
        state.guild[2] = nil
        Fire("GUILDBANKBAGSLOTS_CHANGED")
        Equal(Wild.GetItemTotal(100), 2)
    end },
    { "name search finds all recorded copies even when some snapshots lack a name", function()
        local Wild, state = NewEnvironment()
        local datastore = Wild.GetClientData().datastore
        datastore.characters["Test-Realm"] = { bags = { { itemID = 100, count = 2, name = "?", link = state.link } } }
        datastore.characters["Alt-Realm"] = { bank = {
            { itemID = 100, count = 7 },
            { itemID = 1000, count = 4, name = "Other armor" },
        } }

        local results = Wild.FindItems("  ARMOR  ")
        Equal(#results, 2)
        Equal(results[1].itemID, 1000, "Sort name matches by their display names")
        local result = results[2]
        Equal(result.itemID, 100)
        Equal(result.name, "Test armor")
        Equal(result.link, state.link)
        Equal(result.total, 9)
        Equal(GetCount(result.breakdown, "bags", "Test-Realm"), 2)
        Equal(GetCount(result.breakdown, "bank", "Alt-Realm"), 7)
    end },
    { "a blank search lists every recorded item ID, including items without names", function()
        local Wild, state = NewEnvironment()
        local datastore = Wild.GetClientData().datastore
        datastore.characters["Test-Realm"] = { bags = {
            { itemID = 100, count = 2, name = "Test armor" },
            { itemID = 200, count = 1 },
        }, mail = { { itemID = 300, count = 4, name = "Expired item", expiresAt = state.now } } }
        datastore.characters["Alt-Realm"] = { bank = { { itemID = 100, count = 7 } } }
        datastore.sentMail["recipient-realm"] = {
            recipient = "Recipient-Realm",
            items = { { itemID = 400, count = 5, name = "Sent item", expiresAt = state.now + 1 } },
        }

        local results = Wild.FindItems(" \t ")
        Equal(#results, 3)
        Equal(#Wild.FindItems(), 3)
        local byID = {}
        for _, item in ipairs(results) do byID[item.itemID] = item end
        Equal(byID[100].total, 9)
        Equal(byID[200].total, 1)
        Equal(byID[300], nil)
        Equal(byID[400].total, 0)
        Equal(byID[400].sentMail[1].count, 5)
    end },
    { "ID search uses an exact ID in the API and in chat", function()
        local Wild, state, _, _, env = NewEnvironment()
        Wild.GetClientData().datastore.characters["Test-Realm"] = { bags = {
            { itemID = 100, name = "Test armor", count = 2, link = state.link },
            { itemID = 1000, name = "Other armor", count = 4 },
            { itemID = 101, name = "100 Token", count = 1 },
        } }

        local results = Wild.FindItems(" 00100 ")
        Equal(#results, 1)
        Equal(results[1].itemID, 100)
        Equal(Wild.FindItems(100)[1].total, 2)
        Equal(#Wild.FindItems("999"), 0)
        env.SlashCmdList.WILD("search 100")
        local chat = state.chat[#state.chat]
        assert(chat:find("|Hitem:100:", 1, true) and chat:find("2x total (2x Test-Realm bags)", 1, true), chat)
    end },
    { "only acknowledged sends appear, even for an unvisited recipient and after closing mail", function()
        local Wild, state, Item, Fire, env = NewEnvironment()
        Wild.db.tooltip.lines = { crossCharCount = "always" }
        Fire("MAIL_SHOW")
        state.sent = { Item(3) }
        env.SendMail("Alt", "Failed", "")
        Fire("MAIL_FAILED")
        Fire("MAIL_SEND_SUCCESS")
        Equal(#Wild.FindItems("armor"), 0)

        state.bags[0] = { Item(7) }
        Wild.SnapshotBags()
        state.sent = { Item(3), [12] = Item(4) }
        env.SendMail("Alt", "Sent", "")
        local total, _, sent = Wild.GetItemTotal(100)
        Equal(total, 7)
        Equal(#(sent or {}), 0)
        state.sent, state.bags[0] = {}, {}
        Fire("MAIL_CLOSED")
        Fire("MAIL_SEND_SUCCESS")
        Fire("MAIL_SEND_SUCCESS")
        total, _, sent = Wild.GetItemTotal(100)
        Equal(total, 0)
        Equal(#sent, 1)
        Equal(sent[1].recipient, "Alt-Realm")
        Equal(sent[1].count, 7)
        local results = Wild.FindItems("armor")
        Equal(#results, 1)
        Equal(results[1].sentMail[1].count, 7)
        env.SlashCmdList.WILD("find armor")
        assert(state.chat[#state.chat]:find("7x sent to Alt-Realm", 1, true))
        state.itemTooltip(env.GameTooltip, { hyperlink = state.link })
        Equal(state.tooltipShown, true)
        Equal(state.tooltipText["Sent Mail"], true)

        state.now = state.now + 30 * 86400
        Equal(#Wild.FindItems("armor"), 0)
    end },
    { "loaded inbox reconciles only its recipient and expires unclaimed attachments", function()
        local Wild, state, Item, Fire, env = NewEnvironment("forever")
        state.character, state.realm = "Test Family", "Test Realm"
        Fire("MAIL_SHOW")
        state.sent = { Item(4) }
        env.SendMail("Alt Family-TestRealm", "Local recipient", "")
        Fire("MAIL_SEND_SUCCESS")
        env.SendMail("Alt Family-OtherRealm", "Different recipient", "")
        Fire("MAIL_SEND_SUCCESS")
        Fire("MAIL_CLOSED")

        state.character = "Alt Family"
        Fire("MAIL_SHOW")
        state.totalMail = 1
        Fire("MAIL_INBOX_UPDATE")
        local _, _, sent = Wild.GetItemTotal(100)
        Equal(#(sent or {}), 2)

        local message = { items = { [12] = Item(4) }, attachmentCount = 1, daysLeft = 1 }
        state.inbox, state.totalMail = { message }, 2
        Fire("MAIL_INBOX_UPDATE")
        local total, breakdown
        total, breakdown, sent = Wild.GetItemTotal(100)
        Equal(total, 4)
        Equal(#sent, 2, "A partial inbox cannot account for every sent attachment")

        state.inbox, state.totalMail = { { items = {}, attachmentCount = 1, daysLeft = 1 } }, 1
        Fire("MAIL_INBOX_UPDATE")
        Equal(Wild.GetItemTotal(100), 4, "Missing attachment data must not replace the previous snapshot")

        state.inbox = { message }
        Fire("MAIL_INBOX_UPDATE")
        total, breakdown, sent = Wild.GetItemTotal(100)
        Equal(total, 4)
        Equal(GetCount(breakdown, "mail", "Alt Family-Test Realm"), 4)
        Equal(#sent, 1)
        Equal(sent[1].recipient, "Alt Family-OtherRealm")
        Fire("MAIL_CLOSED")
        state.now = state.now + 86401
        Equal(Wild.GetItemTotal(100), 0)
    end },
    { "item tooltips show mailbox counts when the client supplies only the item ID", function()
        local Wild, state, Item, Fire, env = NewEnvironment()
        Wild.db.tooltip.lines = { crossCharCount = "always" }
        Fire("MAIL_SHOW")
        state.inbox = { { items = { Item(6) }, attachmentCount = 1, daysLeft = 5 } }
        Fire("MAIL_INBOX_UPDATE")

        state.itemTooltip(env.GameTooltip, { id = 100 })
        Equal(state.tooltipShown, true)
        Equal(state.tooltipText.Mail, true)
        Equal(state.tooltipText["6"], true)

        state.inbox = {}
        Fire("MAIL_INBOX_UPDATE")
        Equal(Wild.GetItemTotal(100), 0)
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
