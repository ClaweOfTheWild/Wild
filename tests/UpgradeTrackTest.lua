-- Run from the repository root with Lua 5.1: lua tests\UpgradeTrackTest.lua
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

local function NewEnvironment()
    local Wild = { db = { intents = {} } }
    local state = { frames = {}, items = {} }
    local methods = {}
    for _, name in ipairs({
        "SetPoint", "SetWidth", "SetHeight", "SetSize", "SetScrollChild",
        "HookScript", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
        "SetJustifyH", "SetAutoFocus", "SetMaxLetters", "SetFontObject",
        "SetNumeric", "SetScale", "Hide", "RegisterEvent",
    }) do
        methods[name] = function() end
    end
    function methods:SetText(text) self.text = text end
    function methods:GetText() return self.text end
    function methods:GetWidth() return 520 end
    function methods:SetScript(event, callback) self.scripts[event] = callback end
    function methods:CreateFontString()
        return setmetatable({ scripts = {} }, { __index = methods })
    end
    local function Tooltip()
        local lines = { { leftText = "Item" } }
        if state.track then
            lines[#lines + 1] = { leftText = "|cff00ff00Upgrade Level: " .. state.track .. " 1/6|r" }
        end
        return { lines = lines }
    end
    local env = setmetatable({
        CreateFrame = function(kind, name)
            local frame = setmetatable({ name = name, scripts = {} }, { __index = methods })
            if kind == "CheckButton" then frame.Text = frame:CreateFontString() end
            state.frames[#state.frames + 1] = frame
            return frame
        end,
        C_Item = {
            GetItemInfo = function(itemID)
                if type(itemID) == "string" then itemID = tonumber(itemID:match("item:(%d+)")) end
                return "Item", "item:" .. itemID, 3, 100, 1, nil, nil, 1, "",
                    nil, 100, 4, 2, state.items[itemID]
            end,
        },
        C_TooltipInfo = { GetBagItem = Tooltip, GetHyperlink = Tooltip },
        C_Timer = { After = function() end },
        hooksecurefunc = function() end,
        UIDropDownMenu_SetWidth = function() end,
        UIDropDownMenu_SetText = function(frame, text) frame.text = text end,
        UIDropDownMenu_CreateInfo = function() return {} end,
        CloseDropDownMenus = function() state.closed = true end,
    }, { __index = _G })
    setfenv(assert(loadfile("Conditions.lua")), env)("Wild", Wild)
    return Wild, state, env
end

local function SoulboundNoTrackIntent()
    return {
        enabled = true, action = "sell",
        groups = { {
            mode = "include",
            conditions = {
                { attr = "item.bind", op = "is", value = "soulbound" },
                { attr = "item.upgradeTrack", op = "=", value = 0 },
            },
        } },
    }
end

local tests = {
    { "upgrade track dropdown offers None first and preserves every ranked track", function()
        local Wild, state, env = NewEnvironment()
        local menu, dropdown
        local stop = {}
        env.UIDropDownMenu_Initialize = function(frame, callback)
            if frame.name == "WildIntentCondTrackDD" then
                dropdown, menu = frame, callback
                -- Stop UI construction once the real dropdown callback is registered.
                error(stop)
            end
        end
        setfenv(assert(loadfile("Settings.lua")), env)("Wild", Wild)
        local loader = state.frames[#state.frames]
        local factory = GetUpvalue(loader.scripts.OnEvent, "CreateIntentRulesTab")
        local success, reason = pcall(factory)
        Equal(success, false)
        Equal(reason, stop, "UI must reach the upgrade track dropdown")

        local entries = {}
        env.UIDropDownMenu_AddButton = function(info) entries[#entries + 1] = info end
        menu()
        Equal(#entries, 7)
        for index, entry in ipairs(entries) do
            Equal(entry.value, index - 1)
            Equal(entry.text, Wild.UPGRADE_TRACK_NAMES[index - 1])
            entry.func({ value = entry.value, GetText = function() return entry.text end })
            local editorState = GetUpvalue(entry.func, "condEditorState")
            Equal(editorState.value, index - 1)
            Equal(dropdown.text, entry.text)
            Equal(state.closed, true)
        end
    end },
    { "soulbound items without an upgrade track match the combined include group", function()
        local Wild, state = NewEnvironment()
        state.items[1] = 1
        local intent = SoulboundNoTrackIntent()
        Equal(Wild.IntentMatchesItem(intent, 1, nil, {}), true)
        Equal(Wild.IntentMatchesItem(intent, 1, { bag = 0, slot = 1, hyperlink = "item:1" }, {}), true)
        Equal(Wild.GetConditionsSummary(intent.groups[1].conditions),
            "Bind Type is Soulbound, Upgrade Track = None")
    end },
    { "ranked gear never matches the no-track rule", function()
        local Wild, state = NewEnvironment()
        state.items[1] = 1
        for rank = 1, 6 do
            state.track = Wild.UPGRADE_TRACK_NAMES[rank]
            for _, info in ipairs({
                { bag = 0, slot = 1 }, { hyperlink = "item:1" },
            }) do
                Equal(Wild.EvaluateCondition({ attr = "item.upgradeTrack", op = "=", value = rank },
                    1, info, {}), true)
                Equal(Wild.IntentMatchesItem(SoulboundNoTrackIntent(), 1, info, {}), false)
            end
        end
    end },
    { "unbound, BoE, and warbound items without a track do not match", function()
        local Wild, state = NewEnvironment()
        for _, bindType in ipairs({ 0, 2, 3, 7, 8, 9 }) do
            state.items[1] = bindType
            Equal(Wild.IntentMatchesItem(SoulboundNoTrackIntent(), 1, nil, {}), false)
        end
    end },
    { "zero is a valid saved condition for every item-matching action", function()
        local Wild = NewEnvironment()
        local intent = SoulboundNoTrackIntent()
        intent.target = "warband"
        intent.source = "character"
        intent.recipient = "Alt"
        for _, action in ipairs({ "sell", "destroy", "deposit", "withdraw", "transfer", "mail" }) do
            intent.action = action
            Equal(Wild.ValidateIntent(intent), true)
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
assert(failures == 0, failures .. " upgrade track test(s) failed")
print("All " .. #tests .. " upgrade track tests passed.")
