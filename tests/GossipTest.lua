-- Run from the repository root with Lua 5.1: lua tests\GossipTest.lua
local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local DARKMOON_GUID = "Creature-0-1-2-3-54334-0000000001"
local DARKMOON_OPTION = { name = "Take me to the faire staging area.", gossipOptionID = 42 }

local function NewEnvironment()
    local cfg = { darkmoonTeleport = true, skipIfQuest = true, toggleKey = 1 }
    local Wild = { db = { gossip = cfg } }
    local state = {
        options = {}, activeQuests = {}, availableQuests = {}, selections = {},
        guidReads = 0, splits = 0, hiddenPopups = {}, modifierHeld = false,
    }
    state.secret = setmetatable({}, {
        __tostring = function() error("String conversion on a secret GUID") end,
    })
    state.guid = state.secret
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    local env = setmetatable({
        CreateFrame = function() return frame end,
        UnitGUID = function(unit)
            Equal(unit, "npc")
            state.guidReads = state.guidReads + 1
            return state.guid
        end,
        issecretvalue = function(value) return rawequal(value, state.secret) end,
        strsplit = function(separator, value)
            state.splits = state.splits + 1
            if rawequal(value, state.secret) then
                error("String conversion on a secret GUID")
            end
            Equal(separator, "-")
            local parts = {}
            for part in value:gmatch("[^-]+") do parts[#parts + 1] = part end
            return unpack(parts)
        end,
        IsAltKeyDown = function() return state.modifierHeld end,
        IsControlKeyDown = function() return state.modifierHeld end,
        IsShiftKeyDown = function() return state.modifierHeld end,
        StaticPopup_Hide = function(name)
            state.hiddenPopups[#state.hiddenPopups + 1] = name
        end,
        C_GossipInfo = {
            GetOptions = function() return state.options end,
            GetActiveQuests = function() return state.activeQuests end,
            GetAvailableQuests = function() return state.availableQuests end,
            SelectOption = function(...)
                state.selections[#state.selections + 1] = { ... }
            end,
        },
    }, { __index = _G })
    local function Load()
        setfenv(assert(loadfile("Gossip.lua")), env)("Wild", Wild)
    end
    Load()
    local function Fire(event, ...)
        assert(frame.events[event], "Gossip handler must register " .. event)
        frame.scripts.OnEvent(frame, event, ...)
    end
    return cfg, state, Fire, env, Load
end

local tests = {
    { "secret NPC GUID still allows a single quest-related gossip option", function()
        local cfg, state, Fire = NewEnvironment()
        cfg.autoSelectSingle = true
        state.options = { { name = "Quest dialog", type = "quest", gossipOptionID = 10 } }
        Fire("GOSSIP_SHOW")
        Equal(state.splits, 0, "Secret GUID must never reach strsplit")
        Equal(#state.selections, 1)
        Equal(state.selections[1][1], 10)
    end },
    { "secret NPC GUID still allows quest selection among multiple options", function()
        local cfg, state, Fire = NewEnvironment()
        cfg.autoSelectQuest = true
        state.options = {
            { name = "Tell me about this place.", type = "gossip", gossipOptionID = 9 },
            { name = "I am ready.", type = "quest", gossipOptionID = 10 },
        }
        Fire("GOSSIP_SHOW")
        Equal(state.splits, 0)
        Equal(#state.selections, 1)
        Equal(state.selections[1][1], 10)
    end },
    { "secret NPC GUID never auto-confirms or hides a cost dialog", function()
        local _, state, Fire = NewEnvironment()
        Fire("GOSSIP_CONFIRM", 42)
        Equal(state.splits, 0)
        Equal(#state.selections, 0)
        Equal(#state.hiddenPopups, 0)
    end },
    { "secret NPC GUID does not enable Darkmoon selection by option text alone", function()
        local _, state, Fire = NewEnvironment()
        state.options = { DARKMOON_OPTION }
        Fire("GOSSIP_SHOW")
        Equal(state.splits, 0)
        Equal(#state.selections, 0)
    end },
    { "readable Darkmoon GUID retains teleport selection priority", function()
        local cfg, state, Fire = NewEnvironment()
        cfg.autoSelectQuest = true
        state.guid = DARKMOON_GUID
        state.options = {
            { name = "Quest dialog", type = "quest", gossipOptionID = 10 },
            DARKMOON_OPTION,
        }
        Fire("GOSSIP_SHOW")
        Equal(state.splits, 1)
        Equal(#state.selections, 1)
        Equal(state.selections[1][1], 42)
    end },
    { "readable Darkmoon GUID retains cost confirmation", function()
        local _, state, Fire = NewEnvironment()
        state.guid = DARKMOON_GUID
        Fire("GOSSIP_CONFIRM", 42)
        Equal(#state.selections, 1)
        Equal(state.selections[1][1], 42)
        Equal(state.selections[1][2], "")
        Equal(state.selections[1][3], true)
        Equal(#state.hiddenPopups, 1)
        Equal(state.hiddenPopups[1], "GOSSIP_CONFIRM")
    end },
    { "other NPCs do not trigger Darkmoon selection or confirmation", function()
        local _, state, Fire = NewEnvironment()
        state.guid = "Creature-0-1-2-3-12345-0000000001"
        state.options = { DARKMOON_OPTION }
        Fire("GOSSIP_SHOW")
        Fire("GOSSIP_CONFIRM", 42)
        Equal(#state.selections, 0)
        Equal(#state.hiddenPopups, 0)
    end },
    { "missing NPC GUID still allows single-option automation", function()
        local cfg, state, Fire = NewEnvironment()
        cfg.autoSelectSingle = true
        state.guid = nil
        state.options = { { name = "Continue.", gossipOptionID = 10 } }
        Fire("GOSSIP_SHOW")
        Fire("GOSSIP_CONFIRM", 42)
        Equal(state.splits, 0)
        Equal(#state.selections, 1)
        Equal(state.selections[1][1], 10)
        Equal(#state.hiddenPopups, 0)
    end },
    { "secret NPC GUID does not bypass the quest safeguard", function()
        for _, questList in ipairs({ "activeQuests", "availableQuests" }) do
            local cfg, state, Fire = NewEnvironment()
            cfg.autoSelectSingle = true
            state[questList] = { { questID = 1 } }
            state.options = { { name = "Continue.", gossipOptionID = 10 } }
            Fire("GOSSIP_SHOW")
            Equal(state.splits, 0)
            Equal(#state.selections, 0)
        end
    end },
    { "Darkmoon automation resumes when the NPC GUID becomes readable", function()
        local _, state, Fire = NewEnvironment()
        state.options = { DARKMOON_OPTION }
        for _ = 1, 3 do
            Fire("GOSSIP_SHOW")
            Fire("GOSSIP_CONFIRM", 42)
        end
        Equal(state.splits, 0)
        Equal(#state.selections, 0)
        state.guid = DARKMOON_GUID
        Fire("GOSSIP_SHOW")
        Fire("GOSSIP_CONFIRM", 42)
        Equal(state.splits, 2)
        Equal(#state.selections, 2)
        Equal(state.selections[1][1], 42)
        Equal(state.selections[2][3], true)
    end },
    { "disabled Darkmoon automation does not inspect the NPC GUID", function()
        local cfg, state, Fire = NewEnvironment()
        cfg.darkmoonTeleport = false
        cfg.autoSelectSingle = true
        state.options = { { name = "Continue.", gossipOptionID = 10 } }
        Fire("GOSSIP_SHOW")
        Fire("GOSSIP_CONFIRM", 42)
        Equal(state.guidReads, 0)
        Equal(#state.selections, 1)
        Equal(state.selections[1][1], 10)
    end },
    { "modifier bypass still prevents gossip automation", function()
        local cfg, state, Fire = NewEnvironment()
        cfg.toggleKey = 4
        cfg.autoSelectSingle = true
        state.modifierHeld = true
        state.options = { DARKMOON_OPTION }
        Fire("GOSSIP_SHOW")
        Fire("GOSSIP_CONFIRM", 42)
        Equal(state.guidReads, 0)
        Equal(#state.selections, 0)
    end },
    { "readable GUID works when the secret-value API is unavailable", function()
        local _, state, Fire, env, Load = NewEnvironment()
        env.issecretvalue = nil
        Load()
        state.guid = DARKMOON_GUID
        state.options = { DARKMOON_OPTION }
        Fire("GOSSIP_SHOW")
        Fire("GOSSIP_CONFIRM", 42)
        Equal(#state.selections, 2)
        Equal(state.selections[1][1], 42)
        Equal(state.selections[2][3], true)
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
assert(failures == 0, failures .. " of " .. #tests .. " gossip tests failed")
print(#tests .. " gossip tests passed")
