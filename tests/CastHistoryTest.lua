-- Run from the repository root with Lua 5.1: lua tests\CastHistoryTest.lua
local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function NewEnvironment(enabled)
    local state = {
        frames = {}, items = {}, bags = { [0] = {}, [5] = {} }, equipment = {},
        actions = {}, uses = {}, hooks = {}, requests = {}, time = 10, actionReads = 0,
    }
    local methods = {}
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:RegisterUnitEvent(event, unit)
        self.events[event] = true
        self.units[event] = unit
    end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:SetScript(event, callback) self.scripts[event] = callback end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:GetPoint() return unpack(self.point) end
    function methods:ClearAllPoints() self.point = nil end
    function methods:GetFrameLevel() return 10 end
    function methods:SetSize(width, height) self.width, self.height = width, height end
    function methods:SetWidth(width) self.width = width end
    function methods:SetText(text) self.text = text end
    function methods:SetTexture(texture) self.texture = texture end
    function methods:Show() self.shown = true end
    function methods:Hide() self.shown = false end
    function methods:SetShown(shown) self.shown = shown end
    for _, name in ipairs({
        "SetFrameStrata", "SetFrameLevel", "SetClampedToScreen", "SetMovable",
        "RegisterForDrag", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
        "SetJustifyH", "SetWordWrap", "SetFont", "SetColorTexture", "SetTexCoord",
        "EnableMouse", "SetAlpha", "StartMoving", "StopMovingOrSizing",
    }) do
        methods[name] = function() end
    end
    function methods:CreateFontString() return setmetatable({}, { __index = methods }) end
    function methods:CreateTexture() return setmetatable({}, { __index = methods }) end

    local env = setmetatable({
        UIParent = {},
        GameFontHighlightSmall = { GetFont = function() return "Font", 12, "" end },
        GetTime = function() return state.time end,
        issecretvalue = function(value) return value == state.secret end,
        GetSpellBaseCooldown = function() return 0, 1500 end,
        C_Spell = {
            GetSpellCooldown = function() return { duration = 1.5, modRate = 1 } end,
            GetSpellInfo = function(id) return { name = "Spell " .. id, iconID = id } end,
        },
    }, { __index = _G })
    env._G = env
    env.CreateFrame = function(kind, name, parent, template)
        assert(not template or not template:find("Secure") and not template:find("ActionButton"),
            "Cast history must not create secure action frames")
        local frame = setmetatable({
            frameType = kind, name = name, parent = parent, template = template,
            events = {}, units = {}, scripts = {}, shown = true,
        }, { __index = methods })
        state.frames[#state.frames + 1] = frame
        if name then env[name] = frame end
        return frame
    end
    env.GetInventoryItemID = function(unit, slot)
        Equal(unit, "player")
        return state.equipment[slot]
    end
    env.C_Container = {
        GetContainerNumSlots = function(bag) return #state.bags[bag] end,
        GetContainerItemID = function(bag, slot) return state.bags[bag][slot] end,
        UseContainerItem = function() end,
    }
    env.C_Item = {
        GetItemInfo = function(id)
            local item = assert(state.items[id], "Unknown item " .. tostring(id))
            if item.cached == false then return nil end
            return "Item " .. id, nil, nil, nil, nil, nil, nil, nil, nil, id
        end,
        GetItemSpell = function(id)
            local item = assert(state.items[id])
            return "Item spell", item.spellID
        end,
        RequestLoadItemDataByID = function(id) state.requests[#state.requests + 1] = id end,
        GetItemInfoInstant = function(id) return id end,
        UseItemByName = function() end,
    }
    env.UseInventoryItem = function() end
    local function Fire(event, ...)
        local frames = { unpack(state.frames) }
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    env.UseAction = function(slot)
        state.uses[#state.uses + 1] = slot
        Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. #state.uses, state.actions[slot])
    end
    state.originalUseAction = env.UseAction
    env.GetActionInfo = function(slot)
        state.actionReads = state.actionReads + 1
        return "spell", state.actions[slot]
    end
    env.ExtraActionButton1 = { Click = function() env.UseAction(169) end }
    env.hooksecurefunc = function(object, name, callback)
        if type(object) == "string" then
            callback, name, object = name, object, env
        end
        state.hooks[name] = callback
        local original = assert(object[name])
        object[name] = function(...)
            original(...)
            callback(...)
        end
    end
    local Wild = {
        db = { castHistory = { enabled = enabled, locked = true } },
        GetPlayerBags = function() return { 0, 5 } end,
        NotifySettingsChanged = function() end,
    }
    setfenv(assert(loadfile("CastHistory.lua")), env)("Wild", Wild)
    local function AddItem(id, spellID, bag, slot)
        state.items[id] = { spellID = spellID }
        if bag ~= nil then state.bags[bag][slot or 1] = id end
    end
    local function Latest()
        local found
        for _, frame in ipairs(state.frames) do
            if frame.icon and frame.shown and frame.age == 0 then found = frame end
        end
        return found
    end
    return Wild, state, env, Fire, AddItem, Latest
end

local tests = {
    { "startup leaves native action dispatch untouched with cast history on or off", function()
        for _, enabled in ipairs({ false, true }) do
            local Wild, state, env, Fire = NewEnvironment(enabled)
            state.actions[169] = 9001
            Fire("ADDON_LOADED", "Wild")
            Equal(state.hooks.UseAction, nil)
            Equal(env.UseAction, state.originalUseAction)
            env.ExtraActionButton1:Click()
            Equal(#state.uses, 1)
            Equal(state.uses[1], 169)
            Equal(state.actionReads, 0)
            Wild.SetCastHistoryEnabled(not enabled)
            Equal(state.hooks.UseAction, nil)
            Equal(env.UseAction, state.originalUseAction)
        end
    end },
    { "action-bar item casts resolve from bag reagent-bag and equipped caches", function()
        local _, state, env, Fire, AddItem, Latest = NewEnvironment(true)
        AddItem(101, 8001, 0)
        AddItem(102, 8002, 5)
        AddItem(103, 8003)
        state.equipment[13] = 103
        Fire("ADDON_LOADED", "Wild")
        for slot, id in ipairs({ 101, 102, 103 }) do
            state.actions[slot] = state.items[id].spellID
            env.UseAction(slot)
            local entry = assert(Latest())
            Equal(entry.kind, "item")
            Equal(entry.id, id)
            Equal(entry.displayName, "Item " .. id)
            Equal(entry.icon.texture, id)
        end
        Equal(state.actionReads, 0)
    end },
    { "normal spells and the extra action remain ordinary successful cast entries", function()
        local _, state, env, Fire, _, Latest = NewEnvironment(true)
        Fire("ADDON_LOADED", "Wild")
        state.actions[169] = 9001
        env.ExtraActionButton1:Click()
        local entry = assert(Latest())
        Equal(entry.kind, "spell")
        Equal(entry.id, 9001)
        Equal(entry.displayName, "Spell 9001")
        Fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "Other", 9002)
        Equal(Latest(), entry)
        Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 9001)
        Equal(Latest(), entry)
    end },
    { "bag equipment and item-load events keep the item cache current", function()
        local _, state, env, Fire, AddItem, Latest = NewEnvironment(true)
        AddItem(101, 8001, 0)
        Fire("ADDON_LOADED", "Wild")
        AddItem(102, 8002, 5)
        state.items[102].cached = false
        Fire("BAG_UPDATE_DELAYED")
        Equal(state.requests[1], 102)
        state.items[102].cached = true
        Fire("ITEM_DATA_LOAD_RESULT", 102, true)
        state.actions[1] = 8002
        env.UseAction(1)
        Equal(assert(Latest()).id, 102)
        AddItem(103, 8003)
        state.equipment[13] = 103
        Fire("PLAYER_EQUIPMENT_CHANGED")
        state.actions[2] = 8003
        env.UseAction(2)
        Equal(assert(Latest()).id, 103)
    end },
    { "sent item casts survive consumption of the last stack before success", function()
        local _, state, env, Fire, AddItem, Latest = NewEnvironment(true)
        AddItem(101, 8001, 0)
        Fire("ADDON_LOADED", "Wild")
        Fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-1", 8001)
        state.bags[0][1] = nil
        Fire("BAG_UPDATE_DELAYED")
        state.actions[1] = 8001
        env.UseAction(1)
        local entry = assert(Latest())
        Equal(entry.kind, "item")
        Equal(entry.id, 101)
    end },
    { "sent casts preserve the exact pending bag item when items share a spell", function()
        local _, state, env, Fire, AddItem, Latest = NewEnvironment(true)
        AddItem(101, 8001, 0)
        AddItem(102, 8001)
        state.equipment[13] = 102
        Fire("ADDON_LOADED", "Wild")
        env.C_Container.UseContainerItem(0, 1)
        Fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-1", 8001)
        Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 8001)
        Equal(assert(Latest()).id, 101)
    end },
    { "sent casts replace expired pending metadata before a consumed item leaves the cache", function()
        local _, state, env, Fire, AddItem, Latest = NewEnvironment(true)
        AddItem(101, 8001, 0)
        AddItem(102, 8001)
        state.equipment[13] = 102
        Fire("ADDON_LOADED", "Wild")
        env.C_Container.UseContainerItem(0, 1)
        state.time = 41
        Fire("PLAYER_EQUIPMENT_CHANGED", 13)
        Fire("UNIT_SPELLCAST_SENT", "player", "", "New", 8001)
        state.bags[0][1], state.equipment[13] = nil, nil
        Fire("BAG_UPDATE_DELAYED")
        Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "New", 8001)
        Equal(assert(Latest()).kind, "item")
        Equal(Latest().id, 102)
    end },
    { "disabled other-unit and secret sent events do not prepare item data", function()
        for _, mode in ipairs({ "disabled", "otherUnit", "secret" }) do
            local _, state, _, Fire, AddItem = NewEnvironment(mode ~= "disabled")
            AddItem(101, 8001, 0)
            Fire("ADDON_LOADED", "Wild")
            state.items[101].cached = false
            state.secret = {}
            Fire("UNIT_SPELLCAST_SENT", mode == "otherUnit" and "pet" or "player", "", "Attempt",
                mode == "secret" and state.secret or 8001)
            Equal(#state.requests, 0)
        end
    end },
    { "failed and interrupted item casts discard pending data", function()
        for _, event in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
            local _, state, _, Fire, AddItem, Latest = NewEnvironment(true)
            AddItem(101, 8001, 0)
            Fire("ADDON_LOADED", "Wild")
            Fire("UNIT_SPELLCAST_SENT", "player", "", "Attempt", 8001)
            state.bags[0][1] = nil
            Fire("BAG_UPDATE_DELAYED")
            Fire(event, "player", "Attempt", 8001)
            Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Other", 8001)
            Equal(assert(Latest()).kind, "spell")
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
assert(failures == 0, failures .. " cast history test(s) failed")
