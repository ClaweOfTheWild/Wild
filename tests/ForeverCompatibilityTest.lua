-- Run with Lua 5.1: lua tests\ForeverCompatibilityTest.lua
-- WoW is unavailable outside the client. These doubles exercise Wild, not the live APIs.
-- Contracts: Gethe/wow-ui-source 17ed2c3, Forever 1.60.1 build 70755.
local LINK = "|cff1eff00|Hitem:100|h[Test item]|h|r"

local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function Contains(values, expected)
    for _, value in ipairs(values) do
        if value == expected then return true end
    end
    return false
end

local function NewEnvironment(mode)
    local state = {
        frames = {}, bags = {}, reads = {}, messages = {}, surname = "Family",
        timers = {}, requests = {}, bankTypes = { [0] = true, [2] = false },
    }
    local bagIndex = { Backpack = 0, ReagentBag = 5, Characterbanktab = -2 }
    local characterTabs, accountOffset, accountTabs = 6, 11, 5
    if mode == "forever" then
        bagIndex.Keyring = -1
        characterTabs, accountOffset, accountTabs = 9, 14, 9
    end
    for index = 1, characterTabs do bagIndex["CharacterBankTab_" .. index] = index + 5 end
    for index = 1, accountTabs do bagIndex["AccountBankTab_" .. index] = index + accountOffset end

    local env = setmetatable({
        WOW_PROJECT_ID = mode == "forever" and 18 or 1,
        WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CAMELOT = 18,
        BACKPACK_CONTAINER = 0, NUM_BAG_SLOTS = 4,
        Enum = {
            BagIndex = bagIndex, BankType = { Character = 0, Account = 2 },
            PlayerInteractionType = { Banker = 5, GuildBanker = 10, AccountBanker = 68 },
            TooltipDataLineType = { SellPrice = 11 },
        },
        SlashCmdList = {}, tremove = table.remove,
        wipe = function(value) for key in pairs(value) do value[key] = nil end end,
        strtrim = function(value) return value:match("^%s*(.-)%s*$") end,
        print = function(message) state.messages[#state.messages + 1] = message end,
        GetTime = function() return 100 end,
        date = function() return "2026-11-04 12:00:00" end,
        time = function() return 100 end,
        UnitName = function() return "Test" end,
        GetUnitName = function() return "Test " .. state.surname end,
        GetRealmName = function() return "Realm" end,
        UnitClass = function() return "Druid", "DRUID" end,
        UnitRace = function() return "Night Elf", "NightElf" end,
        UnitFactionGroup = function() return "Alliance" end,
        UnitLevel = function() return 60 end,
        GetAverageItemLevel = function() return 100, 100 end,
        GetProfessions = function() end,
        GetGuildInfo = function() return "Test Guild" end,
        GetInventoryItemLink = function() end,
        GetCursorInfo = function() end,
        GetMoney = function() return 10000 end,
        GetMoneyString = function(value) return value .. " copper" end,
        C_Item = {
            GetItemInfo = function()
                return "Test item", LINK, 2, 100, 1, "Armor", "Cloth", 20,
                    "INVTYPE_HEAD", 134400, 100, 4, 1, 1, 0
            end,
            GetItemIconByID = function() return 134400 end,
            GetDetailedItemLevelInfo = function() return 100 end,
            IsItemDataCachedByID = function() return true end,
        },
        C_Container = {
            GetContainerNumSlots = function(bag)
                state.reads[bag] = true
                return #(state.bags[bag] or {})
            end,
            GetContainerItemInfo = function(bag, slot) return (state.bags[bag] or {})[slot] end,
            UseContainerItem = function(bag, slot, _, bankType)
                state.requests[#state.requests + 1] = { bag = bag, slot = slot, bankType = bankType }
            end,
        },
        C_Timer = {
            After = function(_, callback) state.timers[#state.timers + 1] = callback end,
            NewTimer = function() return { Cancel = function() end } end,
        },
        C_Bank = {
            CanViewBank = function(bankType) return state.bankTypes[bankType] == true end,
            CanUseBank = function(bankType) return state.bankTypes[bankType] == true end,
        },
        C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function() return false end },
    }, { __index = _G })
    if mode == "unknown" then
        env.WOW_PROJECT_ID, env.WOW_PROJECT_MAINLINE, env.WOW_PROJECT_CAMELOT = nil, nil, nil
    end
    env.CreateFrame = function()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        function frame:Show() end
        function frame:Hide() end
        state.frames[#state.frames + 1] = frame
        return frame
    end
    local Wild = {}
    local function Load(path) setfenv(assert(loadfile(path)), env)("Wild", Wild) end
    local function Fire(event, ...)
        for _, frame in ipairs({ unpack(state.frames) }) do
            if frame.events[event] and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end
    Load("Core.lua")
    Fire("ADDON_LOADED", "Wild")
    Load("Log.lua")
    Wild.UpdateSoireeAdvisor = function() end
    Load("Bank.lua")
    Load("CharacterData.lua")
    Load("Conditions.lua")
    Load("SlashCommands.lua")
    local function Put(bag, count)
        state.bags[bag] = { { itemID = 100, hyperlink = LINK, stackCount = count } }
    end
    return Wild, state, env, Put, Fire, Load
end

local tests = {
    { "client detection distinguishes Forever from Retail and missing constants", function()
        for _, mode in ipairs({ "retail", "forever", "unknown" }) do
            local Wild = NewEnvironment(mode)
            Equal(Wild.isForever, mode == "forever")
            Equal(Wild.GetClientMode(), mode == "unknown" and "unsupported" or mode)
        end
    end },
    { "Forever character snapshots include the base bank and all eight bank bags", function()
        local Wild, state, _, Put = NewEnvironment("forever")
        for _, bag in ipairs({ 6, 12, 13, 14 }) do Put(bag, bag == 6 and 1 or bag - 10) end
        Wild.SnapshotBank()
        local snapshot = Wild.GetClientData().datastore.characters[Wild.GetCharKey()].bank
        local count = 0
        for _, item in ipairs(snapshot) do count = count + item.count end
        Equal(count, 10)
        Equal(#snapshot, 4)
        for _, bag in ipairs({ 12, 13, 14 }) do Equal(state.reads[bag], true) end
        Equal(state.reads[-2], nil, "The bank bag equipment index is not a storage container")
    end },
    { "shared bank enumeration follows each client's enum rather than Retail offsets", function()
        for _, mode in ipairs({ "retail", "forever" }) do
            local Wild = NewEnvironment(mode)
            local character = Wild.GetCharacterBankBags()
            local account = Wild.GetAccountBankBags()
            Equal(#character, mode == "forever" and 9 or 6)
            Equal(character[1], 6)
            Equal(character[#character], mode == "forever" and 14 or 11)
            Equal(account[1], mode == "forever" and 15 or 12)
            Equal(account[#account], mode == "forever" and 23 or 16)
        end
    end },
    { "keyring contents count as possession without becoming automation selections", function()
        local Wild, _, _, Put = NewEnvironment("forever")
        Put(0, 2)
        Put(5, 3)
        Put(-1, 5)
        Wild.db.includeReagentBag = false
        Equal(Contains(Wild.GetPlayerBags(), -1), false)
        Equal(Contains(Wild.GetPlayerBags(), 5), false)
        Equal(Wild.CapturePlayerItemCounts()[LINK], 10)
    end },
    { "moving an item into the keyring is not confirmed as item removal", function()
        local Wild, state, _, Put = NewEnvironment("forever")
        Put(0, 5)
        local batch = Wild.CreateItemActionBatch(Wild.CapturePlayerItemCounts)
        Wild.RecordItemAction(batch, state.bags[0][1], 5)
        state.bags[0] = {}
        Put(-1, 5)
        local results, complete = Wild.ConfirmItemActionBatch(batch)
        Equal(#results, 0)
        Equal(complete, false)
    end },
    { "read-only Forever inventory snapshots include the keyring", function()
        local Wild, _, _, Put = NewEnvironment("forever")
        Put(-1, 5)
        Wild.SnapshotBags()
        local snapshot = Wild.GetClientData().datastore.characters[Wild.GetCharKey()].bags
        Equal(#snapshot, 1)
        Equal(snapshot[1].bag, -1)
        Equal(snapshot[1].count, 5)
    end },
    { "inaccessible banks do not replace saved snapshots with empty data", function()
        local Wild, state = NewEnvironment("forever")
        local previous = { { itemID = 100, count = 7 } }
        local datastore = Wild.GetClientData().datastore
        datastore.warband.bank = previous
        datastore.warband.updated = 77
        Wild.SnapshotWarbandBank()
        Equal(datastore.warband.bank, previous)
        Equal(datastore.warband.updated, 77)
        state.bankTypes[0] = false
        local character = { bank = previous, bankUpdated = 77 }
        datastore.characters[Wild.GetCharKey()] = character
        Wild.SnapshotBank()
        Equal(character.bank, previous)
        Equal(character.bankUpdated, 77)
    end },
    { "accessible Forever account snapshots follow all exposed account container IDs", function()
        local Wild, state, _, Put = NewEnvironment("forever")
        state.bankTypes[2] = true
        Put(23, 7)
        Wild.SnapshotWarbandBank()
        local bank = Wild.GetClientData().datastore.warband.bank
        Equal(#bank, 1)
        Equal(bank[1].bag, 23)
        Equal(bank[1].count, 7)
    end },
    { "Forever actor matching and inventory keys preserve first and last names", function()
        local Wild, state = NewEnvironment("forever")
        Equal(Wild.GetCharKey(), "Test Family-Realm")
        Wild.CollectCurrentCharacter()
        Equal(Wild.db.actors.characters["Test Family-Realm"].name, "Test Family")
        Equal(Wild.IntentMatchesActor({ actors = { { value = "Test Family-Realm" } } }), true)
        Equal(Wild.IntentMatchesActor({ actors = { { value = "Test Other-Realm" } } }), false)
        state.surname = "Other"
        Wild.CollectCurrentCharacter()
        assert(Wild.db.actors.characters["Test Family-Realm"])
        assert(Wild.db.actors.characters["Test Other-Realm"])
    end },
    { "Retail character names and actor keys keep their existing format", function()
        local Wild = NewEnvironment("retail")
        Equal(Wild.GetCharKey(), "Test-Realm")
        Wild.CollectCurrentCharacter()
        Equal(Wild.db.actors.characters["Test-Realm"].name, "Test")
    end },
    { "unavailable helpers do not execute or overwrite saved choices in Forever", function()
        local Wild, state, env = NewEnvironment("forever")
        Wild.db.soiree.enabled = true
        Equal(Wild.IsFeatureEnabled("delve"), false)
        Equal(Wild.IsFeatureEnabled("soiree"), false)
        Equal(Wild.SetFeatureEnabled("soiree", true), false)
        Equal(Wild.SetSetting("lfg.keystoneButtons", true), false)
        Equal(Wild.db.soiree.enabled, true)
        Equal(Wild.db.lfg.keystoneButtons, true)
        env.SlashCmdList.WILD("delve on")
        assert(state.messages[#state.messages]:find("not available", 1, true))
        Equal(Wild.db.delveAutoSelectPower, true)
    end },
    { "Retail feature availability and explicit disable operations are preserved", function()
        local Wild = NewEnvironment("retail")
        Equal(Wild.IsFeatureAvailable("delve"), true)
        Equal(Wild.SetFeatureEnabled("delve", true), true)
        Equal(Wild.IsFeatureEnabled("delve"), true)
        Wild = NewEnvironment("forever")
        Equal(Wild.SetFeatureEnabled("delve", false), true)
        Equal(Wild.db.delveAutoSelectPower, false)
    end },
    { "Forever retains the native group finder without Retail hooks or background jobs", function()
        local Wild, state, env, _, _, Load = NewEnvironment("forever")
        local frames, timers = #state.frames, #state.timers
        env.hooksecurefunc = function() error("Forever must not install Retail hooks") end
        env.C_ChatInfo = {
            RegisterAddonMessagePrefix = function() error("Forever must not start keystone traffic") end,
        }
        env.C_Timer.NewTicker = function() error("Forever must not start the Mythic+ reply ticker") end
        Load("LFG.lua")
        Load("AutoReply.lua")
        Load("Delve.lua")
        Load("Soiree.lua")
        Equal(#state.frames, frames)
        Equal(#state.timers, timers)
        Equal(Wild.IsFeatureEnabled("lfg"), false)
        Equal(Wild.SetFeatureEnabled("lfg", true), false)
        Equal(Wild.ShowSoireeAdvisor(), false)
        local progress, reason = Wild.GetSoireeProgress()
        Equal(progress, nil)
        assert(reason:find("not available", 1, true))
        Equal(type(Wild.CalculateSoireeRecommendation), "function")
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
assert(failures == 0, failures .. " Forever compatibility test(s) failed")
print(#tests .. " Forever compatibility tests passed")
