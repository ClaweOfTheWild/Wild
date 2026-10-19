-- Run from the repository root with Lua 5.1: lua tests\ContainersTest.lua
local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result
end

local function NewEnvironment(saved, coreOnly)
    local state = {
        frames = {}, bags = { [0] = {}, [5] = {} }, uses = {}, timers = {},
        messages = {}, logs = {}, requested = {}, uncached = {}, now = 100, bagReads = 0,
    }
    local env = setmetatable({
        WildDB = saved,
        SlashCmdList = {},
        tremove = table.remove,
        Enum = { BagIndex = { ReagentBag = 5 } },
        wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end end,
        strtrim = function(text) return text:match("^%s*(.-)%s*$") end,
        print = function(message) state.messages[#state.messages + 1] = message end,
        GetTime = function() return state.now end,
        InCombatLockdown = function() return state.combat == true end,
        UnitIsDeadOrGhost = function() return state.dead == true end,
        GetCursorInfo = function() return state.cursor end,
        SpellIsTargeting = function() return state.targeting == true end,
        UnitCastingInfo = function() return state.casting end,
        UnitChannelInfo = function() return state.channeling end,
        GetNumLootItems = function() return state.lootCount or 0 end,
        C_Item = {
            GetItemInfo = function(itemID)
                if not state.uncached[itemID] then return "Container " .. itemID, "item:" .. itemID end
            end,
            GetItemIconByID = function() return 134400 end,
            IsItemDataCachedByID = function(itemID) return not state.uncached[itemID] end,
            RequestLoadItemDataByID = function(itemID)
                state.requested[itemID] = (state.requested[itemID] or 0) + 1
                if state.onRequest then state.onRequest(itemID) end
            end,
        },
        C_Container = {
            GetContainerNumSlots = function(bag) return state.bags[bag] and 8 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                state.bagReads = state.bagReads + 1
                return state.bags[bag] and state.bags[bag][slot]
            end,
            GetContainerItemCooldown = function(bag, slot)
                local item = state.bags[bag] and state.bags[bag][slot]
                if item and item.cooldown then return unpack(item.cooldown) end
                return 0, 0, 1
            end,
            UseContainerItem = function(bag, slot)
                local item = assert(state.bags[bag][slot])
                state.uses[#state.uses + 1] = { bag = bag, slot = slot, itemID = item.itemID }
                if state.onUse then state.onUse(bag, slot) end
            end,
        },
    }, { __index = _G })
    env._G = env
    env.C_Timer = {
        After = function() error("Container processing must not use delayed polling") end,
        NewTimer = function(delay, callback)
            local timer = { delay = delay, callback = callback }
            function timer:Cancel() self.cancelled = true end
            state.timers[#state.timers + 1] = timer
            return timer
        end,
    }
    env.CreateFrame = function()
        local frame = { events = {}, scripts = {}, shown = false }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        function frame:HookScript(event, callback)
            local previous = self.scripts[event]
            self.scripts[event] = function(...)
                if previous then previous(...) end
                callback(...)
            end
        end
        function frame:Show() self.shown = true end
        function frame:Hide()
            local wasShown = self.shown
            self.shown = false
            if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function frame:IsShown() return self.shown end
        state.frames[#state.frames + 1] = frame
        return frame
    end
    local Wild = {}
    local function Load(path) setfenv(assert(loadfile(path)), env)("Wild", Wild) end
    local function Fire(event, ...)
        local frames = { unpack(state.frames) }
        for _, frame in ipairs(frames) do
            if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    Load("Core.lua")
    Fire("ADDON_LOADED", "Wild")
    Wild.GetPlayerBags = function()
        return Wild.db.includeReagentBag ~= false and { 0, 5 } or { 0 }
    end
    Wild.Log = function(category, message)
        state.logs[#state.logs + 1] = category .. ": " .. message
    end
    if not coreOnly then
        Load("Containers.lua")
        Load("SlashCommands.lua")
    end
    local function Put(bag, slot, itemID, count, hasLoot)
        state.bags[bag] = state.bags[bag] or {}
        local item = {
            itemID = itemID, hyperlink = "item:" .. itemID, stackCount = count or 1,
            hasLoot = hasLoot ~= false, isLocked = false,
        }
        state.bags[bag][slot] = item
        return item
    end
    local function Timeout()
        local timers = { unpack(state.timers) }
        for _, timer in ipairs(timers) do
            if not timer.cancelled and not timer.fired then
                timer.fired = true
                timer.callback()
            end
        end
    end
    return Wild, state, Fire, Put, Timeout, env
end

local tests = {
    { "new containers default to not opening", function()
        local Wild = NewEnvironment(nil, true)
        Equal(Wild.db.containers.autoOpenNew, false)
        Equal(next(Wild.db.containers.items), nil)
        Equal(Wild.GetDefaultSetting("containers.autoOpenNew"), false)
    end },
    { "disabled discovery remembers unique loot containers without using other items", function()
        local Wild, state, Fire, Put = NewEnvironment()
        Put(0, 1, 200)
        Put(0, 2, 100, 3)
        Put(0, 3, 999, 1, false)
        Put(5, 1, 200)
        Fire("PLAYER_ENTERING_WORLD")
        Equal(Wild.db.containers.items[100], false)
        Equal(Wild.db.containers.items[200], false)
        Equal(Wild.db.containers.items[999], nil)
        Equal(#state.uses, 0)
        local items = Wild.GetContainers()
        Equal(#items, 2)
        Equal(items[1].itemID, 100)
        Equal(items[1].autoOpen, false)
        Equal(items[2].itemID, 200)
        items[1].autoOpen = true
        Equal(Wild.db.containers.items[100], false, "List results are not a second configuration store")
    end },
    { "the enabled default saves every discovery before opening one container", function()
        local Wild, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        Put(0, 1, 100)
        Put(5, 1, 200)
        state.onUse = function()
            Equal(Wild.db.containers.items[100], true)
            Equal(Wild.db.containers.items[200], true)
        end
        Fire("PLAYER_ENTERING_WORLD")
        Equal(#state.uses, 1)
        Equal(state.uses[1].itemID, 100)
    end },
    { "saved per-item choices override either discovery default", function()
        for _, default in ipairs({ false, true }) do
            local Wild, state, Fire, Put = NewEnvironment({
                containers = { autoOpenNew = default, items = { [100] = false, [200] = true } },
            })
            Put(0, 1, 100)
            Put(0, 2, 200)
            Fire("PLAYER_ENTERING_WORLD")
            Equal(Wild.db.containers.items[100], false)
            Equal(Wild.db.containers.items[200], true)
            Equal(#state.uses, 1)
            Equal(state.uses[1].itemID, 200)
        end
    end },
    { "changing the default affects only later discoveries", function()
        local Wild, state, Fire, Put = NewEnvironment()
        Put(0, 1, 100)
        Fire("PLAYER_ENTERING_WORLD")
        Wild.SetSetting("containers.autoOpenNew", true)
        Equal(Wild.db.containers.items[100], false)
        Equal(#state.uses, 0)
        Put(0, 2, 200)
        Fire("BAG_UPDATE_DELAYED")
        Equal(Wild.db.containers.items[200], true)
        Equal(state.uses[1].itemID, 200)
        Wild.SetSetting("containers.autoOpenNew", false)
        Put(0, 3, 300)
        Fire("BAG_UPDATE_DELAYED")
        Equal(Wild.db.containers.items[200], true)
        Equal(Wild.db.containers.items[300], false)
    end },
    { "an ID can be disabled before the container is ever received", function()
        local Wild, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        Equal(Wild.SetContainerAutoOpen("100", false), true)
        Equal(Wild.GetContainers()[1].itemID, 100)
        Fire("PLAYER_ENTERING_WORLD")
        Put(0, 1, 100)
        Fire("BAG_UPDATE_DELAYED")
        Equal(Wild.db.containers.items[100], false)
        Equal(#state.uses, 0)
    end },
    { "enabling a known item works while the discovery default remains off", function()
        local Wild, state, Fire, Put = NewEnvironment()
        Put(0, 1, 100)
        Fire("PLAYER_ENTERING_WORLD")
        Equal(Wild.SetContainerAutoOpen(100, true), true)
        Equal(#state.uses, 1)
        Equal(Wild.db.containers.autoOpenNew, false)
    end },
    { "generic per-ID setters use the same validation notifications and opener", function()
        local Wild, state, Fire, Put = NewEnvironment()
        Put(0, 1, 100)
        Fire("PLAYER_ENTERING_WORLD")
        Equal(Wild.SetSetting("containers.items.100", true), true)
        Equal(Wild.GetSetting("containers.items.100"), true)
        Equal(#state.uses, 1)
        Equal(Wild.SetSetting("containers.items.200", "off"), false)
        Equal(Wild.GetSetting("containers.items.200"), nil)
    end },
    { "resume events do not rescan bags when no container is enabled", function()
        local _, state, Fire, Put = NewEnvironment()
        Put(0, 1, 100)
        Fire("PLAYER_ENTERING_WORLD")
        state.bagReads = 0
        Fire("UNIT_SPELLCAST_STOP", "player")
        Fire("CURSOR_CHANGED")
        Fire("LOOT_CLOSED")
        Fire("ITEM_UNLOCKED", 0, 1)
        Fire("BAG_UPDATE_COOLDOWN")
        Equal(state.bagReads, 0)
        Fire("BAG_UPDATE_DELAYED")
        assert(state.bagReads > 0, "Bag changes still discover containers while opening is off")
    end },
    { "choices survive reload without being replaced by defaults", function()
        local Wild = NewEnvironment({ containers = { autoOpenNew = true, items = { [100] = false, [200] = true } } })
        local reloaded, state, Fire, Put = NewEnvironment(Copy(Wild.db))
        Put(0, 1, 100)
        Put(0, 2, 200)
        Fire("PLAYER_ENTERING_WORLD")
        Equal(reloaded.db.containers.items[100], false)
        Equal(reloaded.db.containers.items[200], true)
        Equal(state.uses[1].itemID, 200)
    end },
    { "invalid IDs and nonboolean choices are rejected with a warning", function()
        local Wild, state = NewEnvironment()
        for _, itemID in ipairs({ 0, -1, 1.5, math.huge, 2147483648, "", "invalid", {}, false }) do
            local before = #state.messages
            Equal(Wild.SetContainerAutoOpen(itemID, false), false)
            Equal(#state.messages, before + 1)
        end
        Equal(Wild.SetContainerAutoOpen(100, "off"), false)
        Equal(next(Wild.db.containers.items), nil)
    end },
    { "only the shared player-bag selection is scanned", function()
        local Wild, state, Fire, Put = NewEnvironment({ includeReagentBag = false })
        Put(0, 1, 100)
        Put(5, 1, 200)
        Put(12, 1, 300)
        Fire("PLAYER_ENTERING_WORLD")
        Equal(Wild.db.containers.items[100], false)
        Equal(Wild.db.containers.items[200], nil)
        Equal(Wild.db.containers.items[300], nil)
        Wild.SetSetting("includeReagentBag", true)
        Fire("BAG_UPDATE_DELAYED")
        Equal(Wild.db.containers.items[200], false)
        Equal(#state.uses, 0)
    end },
    { "combat still discovers containers and opening resumes after combat", function()
        local Wild, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        state.combat = true
        Put(0, 1, 100)
        Fire("PLAYER_ENTERING_WORLD")
        Equal(Wild.db.containers.items[100], true)
        Equal(#state.uses, 0)
        state.combat = false
        Fire("PLAYER_REGEN_ENABLED")
        Equal(#state.uses, 1)
    end },
    { "locked items are discovered and wait for their unlock event", function()
        local Wild, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        local item = Put(0, 1, 100)
        item.isLocked = true
        Fire("PLAYER_ENTERING_WORLD")
        Equal(Wild.db.containers.items[100], true)
        Equal(#state.uses, 0)
        item.isLocked = false
        Fire("ITEM_UNLOCKED", 0, 1)
        Equal(#state.uses, 1)
    end },
    { "item loading is requested once and discovery resumes on the completion event", function()
        local Wild, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        state.uncached[100] = true
        local item = Put(0, 1, 100, 1, false)
        Fire("PLAYER_ENTERING_WORLD")
        Fire("BAG_UPDATE_DELAYED")
        Equal(state.requested[100], 1)
        Equal(Wild.db.containers.items[100], nil)
        Equal(#state.uses, 0)
        state.uncached[100], item.hasLoot = nil, true
        Fire("ITEM_DATA_LOAD_RESULT", 100, true)
        Equal(Wild.db.containers.items[100], true)
        Equal(#state.uses, 1)
    end },
    { "synchronous item loading does not lose the event needed to discover a container", function()
        local Wild, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        state.uncached[100] = true
        Put(0, 1, 100, 1, false)
        state.onRequest = function(itemID)
            state.uncached[itemID] = nil
            Put(0, 1, itemID)
            Fire("ITEM_DATA_LOAD_RESULT", itemID, true)
        end
        Fire("PLAYER_ENTERING_WORLD")
        Equal(state.requested[100], 1)
        Equal(Wild.db.containers.items[100], true)
        Equal(#state.uses, 1)
    end },
    { "preconfigured IDs request missing names and preserve failed-load choices", function()
        local Wild, state, Fire = NewEnvironment()
        state.uncached[100] = true
        Wild.SetContainerAutoOpen(100, false)
        Equal(state.requested[100], 1)
        Fire("ITEM_DATA_LOAD_RESULT", 100, false)
        Equal(Wild.db.containers.items[100], false)
        assert(state.messages[#state.messages]:find("100", 1, true))
        Equal(#state.uses, 0)
    end },
    { "cooldowns wait for a cooldown update instead of polling", function()
        local _, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        local item = Put(0, 1, 100)
        item.cooldown = { 99, 10, 1 }
        Fire("PLAYER_ENTERING_WORLD")
        Equal(#state.uses, 0)
        item.cooldown = { 0, 0, 1 }
        Fire("BAG_UPDATE_COOLDOWN")
        Equal(#state.uses, 1)
    end },
    { "an outstanding request is not repeated on unrelated events", function()
        local _, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        Put(0, 1, 100, 2)
        Put(0, 2, 200)
        Fire("PLAYER_ENTERING_WORLD")
        Fire("BAG_UPDATE_DELAYED")
        Fire("BAG_UPDATE_COOLDOWN")
        Fire("ITEM_UNLOCKED", 0, 2)
        Equal(#state.uses, 1)
    end },
    { "stacked containers open one at a time after confirmed removal", function()
        local _, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        local item = Put(0, 1, 100, 2)
        Fire("PLAYER_ENTERING_WORLD")
        Equal(#state.uses, 1)
        item.stackCount = 1
        Fire("BAG_UPDATE_DELAYED")
        Equal(#state.uses, 2)
        state.bags[0][1] = nil
        Fire("BAG_UPDATE_DELAYED")
        Equal(#state.uses, 2)
    end },
    { "an active loot window prevents another open even after the item is consumed", function()
        local _, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        Put(0, 1, 100)
        Put(0, 2, 200)
        Fire("PLAYER_ENTERING_WORLD")
        Fire("LOOT_READY")
        Fire("LOOT_OPENED", true, true)
        state.bags[0][1] = nil
        Fire("BAG_UPDATE_DELAYED")
        Equal(#state.uses, 1)
        Fire("LOOT_CLOSED")
        Equal(#state.uses, 2)
        Equal(state.uses[2].itemID, 200)
    end },
    { "new nested containers inherit the current default", function()
        local Wild, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        Put(0, 1, 100)
        Fire("PLAYER_ENTERING_WORLD")
        Put(0, 1, 200)
        Fire("BAG_UPDATE_DELAYED")
        Equal(Wild.db.containers.items[200], true)
        Equal(#state.uses, 2)
        Equal(state.uses[2].itemID, 200)
    end },
    { "the bag slot is revalidated after discovery refreshes", function()
        local Wild, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        Put(0, 1, 100)
        Wild.RefreshNativeSettings = function()
            Put(0, 1, 999, 1, false)
        end
        Fire("PLAYER_ENTERING_WORLD")
        Equal(Wild.db.containers.items[100], true)
        Equal(#state.uses, 0)
    end },
    { "unconfirmed opens warn once and do not stall other containers", function()
        local Wild, state, Fire, Put, Timeout = NewEnvironment({ containers = { autoOpenNew = true } })
        Put(0, 1, 100)
        Put(0, 2, 200)
        Fire("PLAYER_ENTERING_WORLD")
        Timeout()
        Equal(#state.messages, 1)
        assert(state.messages[1]:find("100", 1, true))
        Equal(#state.uses, 2)
        Equal(state.uses[2].itemID, 200)
        state.bags[0][2] = nil
        Fire("BAG_UPDATE_DELAYED")
        Fire("BAG_UPDATE_DELAYED")
        Equal(#state.uses, 2)
        Wild.ScanContainers()
        Equal(#state.uses, 3)
        Equal(state.uses[3].itemID, 100)
    end },
    { "a player can leave a loot window open beyond the safety timeout", function()
        local _, state, Fire, Put, Timeout = NewEnvironment({ containers = { autoOpenNew = true } })
        Put(0, 1, 100)
        Put(0, 2, 200)
        Fire("PLAYER_ENTERING_WORLD")
        Fire("LOOT_OPENED", false, true)
        Timeout()
        Equal(#state.messages, 0)
        Equal(#state.uses, 1)
        Fire("LOOT_CLOSED")
        Equal(#state.uses, 1)
        state.bags[0][1] = nil
        Fire("BAG_UPDATE_DELAYED")
        Equal(#state.uses, 2)
        Equal(#state.messages, 0)
    end },
    { "contextual right-click windows never turn opening into a sale or transfer", function()
        for _, name in ipairs({
            "MerchantFrame", "BankFrame", "GuildBankFrame", "MailFrame", "TradeFrame",
            "AuctionHouseFrame", "ItemInteractionFrame", "ScrappingMachineFrame", "VoidStorageFrame",
            "WildDestroyFrame",
        }) do
            local Wild, state, Fire, Put, _, env = NewEnvironment({ containers = { autoOpenNew = true } })
            env[name] = env.CreateFrame()
            env[name]:Show()
            Put(0, 1, 100)
            Fire("PLAYER_ENTERING_WORLD")
            Equal(Wild.db.containers.items[100], true)
            Equal(#state.uses, 0, name .. " blocks item use")
            env[name]:Hide()
            Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 1)
            Equal(#state.uses, 1)
        end
    end },
    { "NPC interaction events block use even without a loaded Blizzard frame", function()
        local _, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        Fire("PLAYER_ENTERING_WORLD")
        Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 1)
        Put(0, 1, 100)
        Fire("BAG_UPDATE_DELAYED")
        Equal(#state.uses, 0)
        Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 1)
        Equal(#state.uses, 1)
    end },
    { "closing a blocking window resumes opening even when the close event precedes its hide", function()
        local _, state, Fire, Put, _, env = NewEnvironment({ containers = { autoOpenNew = true } })
        env.MerchantFrame = env.CreateFrame()
        env.MerchantFrame:Show()
        Put(0, 1, 100)
        Fire("PLAYER_ENTERING_WORLD")
        Fire("MERCHANT_CLOSED")
        Equal(#state.uses, 0)
        env.MerchantFrame:Hide()
        Equal(#state.uses, 1)
    end },
    { "casting and channeling defer opening until the player's stop event", function()
        for _, case in ipairs({
            { "casting", "UNIT_SPELLCAST_STOP" },
            { "channeling", "UNIT_SPELLCAST_CHANNEL_STOP" },
        }) do
            local Wild, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
            state[case[1]] = "A player spell"
            Put(0, 1, 100)
            Fire("PLAYER_ENTERING_WORLD")
            Equal(Wild.db.containers.items[100], true)
            Equal(#state.uses, 0)
            state[case[1]] = nil
            Fire(case[2], "party1")
            Equal(#state.uses, 0)
            Fire(case[2], "player")
            Equal(#state.uses, 1)
        end
    end },
    { "cursor targeting death and existing loot all defer opening", function()
        for _, field in ipairs({ "cursor", "targeting", "dead", "lootCount" }) do
            local _, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
            state[field] = field == "cursor" and "item" or field == "lootCount" and 1 or true
            Put(0, 1, 100)
            Fire("PLAYER_ENTERING_WORLD")
            Equal(#state.uses, 0, field .. " blocks item use")
            state[field] = nil
            Fire("BAG_UPDATE_DELAYED")
            Equal(#state.uses, 1)
        end
    end },
    { "synchronous bag events cannot reenter the opening scan", function()
        local _, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        Put(0, 1, 100, 2)
        state.onUse = function() Fire("BAG_UPDATE_DELAYED") end
        Fire("PLAYER_ENTERING_WORLD")
        Equal(#state.uses, 1)
    end },
    { "synchronous completion events drain containers without nesting item uses", function()
        local _, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        Put(0, 1, 100)
        Put(0, 2, 200)
        local using = false
        state.onUse = function(bag, slot)
            Equal(using, false)
            using = true
            state.bags[bag][slot] = nil
            Fire("BAG_UPDATE_DELAYED")
            using = false
        end
        Fire("PLAYER_ENTERING_WORLD")
        Equal(#state.uses, 2)
    end },
    { "an API error is surfaced without leaving the scan guard stuck", function()
        local _, state, Fire, Put, _, env = NewEnvironment({ containers = { autoOpenNew = true } })
        Put(0, 1, 100)
        local read = env.C_Container.GetContainerItemInfo
        env.C_Container.GetContainerItemInfo = function() error("Injected bag API failure") end
        local ok, reason = pcall(Fire, "PLAYER_ENTERING_WORLD")
        Equal(ok, false)
        assert(tostring(reason):find("Injected bag API failure", 1, true))
        env.C_Container.GetContainerItemInfo = read
        Fire("BAG_UPDATE_DELAYED")
        Equal(#state.uses, 1)
    end },
    { "disabling an item stops subsequent opens without losing its saved entry", function()
        local Wild, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        local item = Put(0, 1, 100, 2)
        Fire("PLAYER_ENTERING_WORLD")
        Wild.SetContainerAutoOpen(100, false)
        item.stackCount = 1
        Fire("BAG_UPDATE_DELAYED")
        Equal(#state.uses, 1)
        Equal(Wild.db.containers.items[100], false)
    end },
    { "sorting into an excluded reagent bag is not proof of opening", function()
        local _, state, Fire, Put, Timeout = NewEnvironment({
            includeReagentBag = false, containers = { autoOpenNew = true },
        })
        Put(0, 1, 100)
        Put(0, 2, 200)
        Fire("PLAYER_ENTERING_WORLD")
        state.bags[5][1], state.bags[0][1] = state.bags[0][1], nil
        Fire("BAG_UPDATE_DELAYED")
        Equal(#state.uses, 1)
        Timeout()
        Equal(#state.messages, 1)
        Equal(state.uses[2].itemID, 200)
    end },
    { "leaving the world cancels pending work until reentry", function()
        local _, state, Fire, Put, Timeout = NewEnvironment({ containers = { autoOpenNew = true } })
        Put(0, 1, 100, 2)
        Fire("PLAYER_ENTERING_WORLD")
        Fire("PLAYER_LEAVING_WORLD")
        state.bags[0][1].stackCount = 1
        Fire("BAG_UPDATE_DELAYED")
        Timeout()
        Equal(#state.uses, 1)
        Equal(#state.messages, 0)
        Fire("PLAYER_ENTERING_WORLD")
        Equal(#state.uses, 2)
    end },
    { "reset restores the safe default and prevents further opening", function()
        local Wild, state, Fire, Put = NewEnvironment({ containers = { autoOpenNew = true } })
        local item = Put(0, 1, 100, 2)
        Fire("PLAYER_ENTERING_WORLD")
        Wild.ResetSettings()
        item.stackCount = 1
        Fire("BAG_UPDATE_DELAYED")
        Equal(Wild.db.containers.autoOpenNew, false)
        Equal(Wild.db.containers.items[100], false)
        Equal(#state.uses, 1)
    end },
    { "slash commands configure defaults and individual IDs through the same store", function()
        local Wild, state = NewEnvironment()
        Wild.HandleSlashCommand("containers default on")
        Equal(Wild.db.containers.autoOpenNew, true)
        Wild.HandleSlashCommand("containers add 100")
        Equal(Wild.db.containers.items[100], false, "Manual additions start disabled even when discovery opens")
        Wild.HandleSlashCommand("containers add 200 on")
        Equal(Wild.db.containers.items[200], true)
        Wild.HandleSlashCommand("containers 100 on")
        Equal(Wild.db.containers.items[100], true)
        Wild.HandleSlashCommand("containers 200 off")
        Equal(Wild.db.containers.items[200], false)
        Wild.HandleSlashCommand("containers default off")
        Equal(Wild.db.containers.autoOpenNew, false)
        Wild.HandleSlashCommand("containers list")
        local output = table.concat(state.messages, "\n")
        assert(output:find("100", 1, true))
        assert(output:find("200", 1, true))
        local count = #Wild.GetContainers()
        Wild.HandleSlashCommand("containers add invalid")
        Equal(#Wild.GetContainers(), count)
        Wild.HandleSlashCommand("help")
        assert(table.concat(state.messages, "\n"):find("/wild containers", 1, true))
    end },
    { "the opener loads before slash commands and native settings", function()
        local file = assert(io.open("Wild.toc", "r"))
        local toc = file:read("*a")
        file:close()
        local containers = assert(toc:find("Containers.lua", 1, true))
        assert(containers < toc:find("SlashCommands.lua", 1, true))
        assert(containers < toc:find("NativeSettings.lua", 1, true))
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
assert(failures == 0, failures .. " container test(s) failed")
print(#tests .. " container tests passed")
