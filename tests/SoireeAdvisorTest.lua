-- Run from the repository root with Lua 5.1: lua tests\SoireeAdvisorTest.lua
local function Equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") ..
        ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local FACTIONS = { 2711, 2712, 2713, 2714 }
local NAMES = { [2711] = "Magisters", [2712] = "Blood Knights", [2713] = "Farstriders", [2714] = "Shades of the Row" }

local function NewEnvironment(saved)
    local state = { frames = {}, messages = {}, reads = 0, combat = false, reputations = {}, names = {} }
    local env = setmetatable({
        WildDB = saved, SlashCmdList = {}, tremove = table.remove,
        strtrim = function(value) return value:match("^%s*(.-)%s*$") end,
        wipe = function(value) for key in pairs(value) do value[key] = nil end end,
        print = function(message) state.messages[#state.messages + 1] = message end,
        InCombatLockdown = function() return state.combat end,
        IsShiftKeyDown = function() return false end,
        SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 },
        PlaySound = function() end,
        C_Timer = { After = function() error("The advisor must not poll or delay its work") end },
    }, { __index = _G })
    env._G = env
    local secret = setmetatable({}, { __tostring = function() error("Secret value was formatted") end })
    state.secret = secret
    env.issecretvalue = function(value) return rawequal(value, secret) end
    env.strsplit = function(delimiter, value)
        assert(not rawequal(value, secret), "A secret GUID must not be parsed")
        local parts = {}
        for part in value:gmatch("[^" .. delimiter .. "]+") do parts[#parts + 1] = part end
        return unpack(parts)
    end
    local methods = {}
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:SetScript(event, callback) self.scripts[event] = callback end
    function methods:GetScript(event) return self.scripts[event] end
    function methods:HookScript(event, callback)
        local previous = self.scripts[event]
        self.scripts[event] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:SetSize(width, height) self.width, self.height = width, height end
    function methods:SetWidth(width) self.width = width end
    function methods:SetHeight(height) self.height = height end
    function methods:SetText(text)
        self.text = text
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
    end
    function methods:GetText() return self.text or "" end
    function methods:UserText(text)
        self.text = text
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, true) end
    end
    function methods:SetFocus() state.focus = self end
    function methods:ClearFocus() if state.focus == self then state.focus = nil end end
    function methods:HighlightText() self.highlighted = true end
    function methods:GetParent() return self.parent end
    function methods:IsShown() return self.shown end
    function methods:Show()
        local changed = not self.shown
        self.shown = true
        if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function methods:Hide()
        local changed = self.shown
        self.shown = false
        if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:Click() if self.scripts.OnClick then self.scripts.OnClick(self) end end
    function methods:SetAttribute() error("The advisor must not use secure attributes") end
    for _, name in ipairs({
        "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag",
        "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetJustifyH", "SetJustifyV",
        "SetTextColor", "SetAutoFocus", "SetMaxLetters", "SetTextInsets", "StartMoving", "StopMovingOrSizing",
    }) do methods[name] = function() end end
    function methods:CreateFontString()
        return setmetatable({ scripts = {}, shown = true }, { __index = methods })
    end
    env.CreateFrame = function(kind, name, parent, template)
        assert(not template or not template:find("Secure"), "The advisor must use ordinary addon frames")
        local frame = setmetatable({
            kind = kind, name = name, parent = parent, template = template,
            events = {}, scripts = {}, shown = true,
        }, { __index = methods })
        state.frames[#state.frames + 1] = frame
        return frame
    end
    env.UIParent = env.CreateFrame("Frame")
    state.selector = env.CreateFrame("Frame")
    state.selector:Hide()
    env.PlayerChoiceFrame = state.selector
    for _, factionID in ipairs(FACTIONS) do
        state.reputations[factionID] = { friendshipFactionID = factionID, standing = 1000, maxRep = 2500 }
        state.names[factionID] = NAMES[factionID]
    end
    env.C_GossipInfo = {
        GetFriendshipReputation = function(factionID)
            state.reads = state.reads + 1
            return state.reputations[factionID]
        end,
        SelectOption = function() error("The advisor must not select gossip") end,
    }
    env.C_Reputation = { GetFactionDataByID = function(factionID) return { name = state.names[factionID] } end }
    env.C_PlayerChoice = {
        GetCurrentPlayerChoiceInfo = function() return state.choice end,
        SendPlayerChoiceResponse = function() error("The advisor must never send an invitation") end,
    }
    env.AcceptQuest = function() error("The advisor must not accept a quest") end
    env.GetQuestReward = function() error("The advisor must not spend or claim anything") end
    local Wild = {}
    local function Load(path) setfenv(assert(loadfile(path)), env)("Wild", Wild) end
    local function Fire(event, ...)
        local frames = { unpack(state.frames) }
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    local function Advisor()
        for _, frame in ipairs(state.frames) do
            if frame.template == "BackdropTemplate" then return frame end
        end
    end
    local function Open(npcID)
        state.choice = {
            choiceID = 12345, objectGUID = "Creature-0-1-2-3-" .. (npcID or 240832) .. "-0000000001",
            options = {},
        }
        for index = 1, 4 do
            state.choice.options[index] = {
                id = 900 + index, header = "Localized guest " .. index,
                subHeader = "Not an English faction name", description = "Untrusted +9999 weekly text",
                rewardInfo = { repRewards = {}, itemRewards = {}, currencyRewards = {} },
            }
        end
        state.selector:Show()
        Fire("PLAYER_CHOICE_UPDATE")
    end
    local function Fill()
        local frame = assert(Advisor())
        for _, factionID in ipairs(FACTIONS) do
            local row = frame.inputs[factionID]
            for _, targetID in ipairs(FACTIONS) do row.reputation[targetID]:UserText("0") end
            row.bonusFavors:UserText("0")
        end
        return frame
    end
    Load("Core.lua")
    Fire("ADDON_LOADED", "Wild")
    Load("Soiree.lua")
    Load("SlashCommands.lua")
    Fire("ADDON_LOADED", "Wild")
    return Wild, state, env, Fire, Open, Advisor, Fill
end

local tests = {
    { "disabled by default with no helper reputation reads or polling", function()
        local Wild, state, _, Fire, Open, Advisor = NewEnvironment()
        Equal(Wild.GetSetting("soiree.enabled"), false)
        Equal(Wild.IsFeatureEnabled("soiree"), false)
        Open()
        Fire("UPDATE_FACTION")
        Equal(Advisor(), nil)
        Equal(state.reads, 0)
        for _, frame in ipairs(state.frames) do Equal(frame.scripts.OnUpdate, nil) end
    end },
    { "only Saltheril's four-option selector opens the opt-in helper", function()
        local Wild, state, _, Fire, Open, Advisor = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        Open(123)
        Equal(Advisor(), nil)
        Open()
        local frame = assert(Advisor())
        Equal(frame:IsShown(), true)
        Equal(frame.name, nil, "The helper does not introduce a global frame")
        Equal(frame.calculate:GetText(), "Calculate from these previews")
        for _, row in pairs(frame.inputs) do
            for _, field in pairs(row.reputation) do Equal(field:GetText(), "") end
            Equal(row.bonusFavors:GetText(), "")
        end
        state.choice.options[4] = nil
        Fire("PLAYER_CHOICE_UPDATE")
        Equal(frame:IsShown(), false)
    end },
    { "a secret selector GUID is not parsed and explicit show reports the problem", function()
        local Wild, state, _, Fire, Open, Advisor = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        Open(123)
        state.choice.objectGUID = state.secret
        Fire("PLAYER_CHOICE_UPDATE")
        Equal(Advisor(), nil)
        Equal(Wild.ShowSoireeAdvisor(), false)
        assert(state.messages[#state.messages]:find("selector", 1, true))
    end },
    { "manual show works without enabling automatic display", function()
        local Wild, _, _, _, Open, Advisor = NewEnvironment()
        Equal(Wild.ShowSoireeAdvisor(), false)
        Open()
        Wild.HandleSlashCommand("soiree show")
        Equal(Advisor():IsShown(), true)
        Equal(Wild.IsFeatureEnabled("soiree"), false)
        Wild.HandleSlashCommand("soiree hide")
        Equal(Advisor():IsShown(), false)
    end },
    { "all current previews are required before displaying an invitation recommendation", function()
        local Wild, _, _, _, Open, Advisor, Fill = NewEnvironment()
        Wild.HandleSlashCommand("soiree on")
        Open()
        local frame = assert(Advisor())
        frame.calculate:Click()
        assert(frame.result:GetText():find("Invitation for Magisters", 1, true))
        Fill()
        frame.inputs[2714].reputation[2711]:UserText("")
        frame.calculate:Click()
        assert(frame.result:GetText():find("Shades of the Row", 1, true))
        assert(not frame.result:GetText():find("Suggested invite", 1, true))
    end },
    { "entered previews combine with live progress and render the suggested Favor allocation", function()
        local Wild, state, _, _, Open, Advisor, Fill = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        state.reputations[2711].standing = 2500
        state.reputations[2712].standing = 1600
        state.reputations[2713].standing = 1100
        state.reputations[2714].standing = 1100
        Open()
        local frame = Fill()
        local row = frame.inputs[2712]
        row.reputation[2711]:UserText("+75")
        row.reputation[2712]:UserText("+100")
        row.reputation[2714]:UserText("-75")
        row.bonusFavors:UserText("1")
        frame.calculate:Click()
        assert(frame.result:GetText():find("Suggested invite: Blood Knights", 1, true))
        assert(frame.result:GetText():find("+725", 1, true))
        assert(frame.progressLabels[2713]:GetText():find("2 Favors", 1, true))
        assert(frame.progressLabels[2714]:GetText():find("2 Favors", 1, true))
        assert(frame.progressLabels[2711]:GetText():find("(+0)", 1, true))
        Equal(Advisor(), frame)
        Equal(Wild.db.soiree.offers, nil, "Preview data must not persist in saved variables")
    end },
    { "editing a preview immediately invalidates the displayed recommendation", function()
        local Wild, _, _, _, Open, _, Fill = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        local frame = Fill()
        frame.calculate:Click()
        assert(frame.result:GetText():find("Suggested invite", 1, true))
        frame.inputs[2712].bonusFavors:UserText("1")
        assert(not frame.result:GetText():find("Suggested invite", 1, true))
        assert(frame.result:GetText():find("Calculate", 1, true))
    end },
    { "reputation refreshes preserve focused draft fields and update confirmed projections", function()
        local Wild, state, _, Fire, Open, _, Fill = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        local frame = Fill()
        frame.calculate:Click()
        local field = frame.inputs[2711].reputation[2712]
        field:UserText("-")
        field:SetFocus()
        Fire("UPDATE_FACTION")
        Equal(field:GetText(), "-")
        Equal(state.focus, field)
        field:UserText("0")
        frame.calculate:Click()
        state.reputations[2711].standing = 1100
        Fire("UPDATE_FACTION")
        assert(frame.progressLabels[2711]:GetText():find("1100", 1, true))
    end },
    { "selector refresh and close discard every entered preview", function()
        local Wild, state, _, Fire, Open, Advisor, Fill = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        local frame = Fill()
        frame.calculate:Click()
        Fire("PLAYER_CHOICE_UPDATE")
        Equal(frame.inputs[2711].bonusFavors:GetText(), "")
        Fill()
        state.choice = nil
        Fire("PLAYER_CHOICE_CLOSE")
        Equal(frame:IsShown(), false)
        Open()
        Equal(Advisor(), frame)
        Equal(frame.inputs[2714].reputation[2714]:GetText(), "")
    end },
    { "native selector hiding also closes the helper without waiting for a server event", function()
        local Wild, state, _, _, Open, Advisor = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        state.selector:Hide()
        Equal(Advisor():IsShown(), false)
        Equal(Wild.ShowSoireeAdvisor(), false, "Cached choice data does not prove the selector is open")
    end },
    { "native OnShow handles the update arriving before Blizzard shows the selector", function()
        local Wild, state, _, Fire, Open, Advisor = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        Open(123)
        state.choice.objectGUID = "Creature-0-1-2-3-240832-0000000001"
        state.selector:Hide()
        Fire("PLAYER_CHOICE_UPDATE")
        Equal(Advisor(), nil)
        state.selector:Show()
        Equal(Advisor():IsShown(), true)
    end },
    { "load-on-demand selector hooks are attached without loading Blizzard UI", function()
        local Wild, state, env, Fire, Open, Advisor = NewEnvironment()
        env.PlayerChoiceFrame = nil
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        env.PlayerChoiceFrame = state.selector
        Fire("ADDON_LOADED", "Blizzard_PlayerChoice")
        state.selector:Hide()
        Equal(Advisor():IsShown(), false)
    end },
    { "unknown reputation is never treated as zero and recovers on a faction update", function()
        local Wild, state, _, Fire, Open, _, Fill = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        state.reputations[2713] = nil
        Open()
        local frame = Fill()
        frame.calculate:Click()
        assert(frame.result:GetText():find("Farstriders", 1, true))
        assert(not frame.result:GetText():find("Suggested invite", 1, true))
        state.reputations[2713] = { friendshipFactionID = 2713, standing = 1000, maxRep = 2500 }
        Fire("UPDATE_FACTION")
        frame.calculate:Click()
        assert(frame.result:GetText():find("Suggested invite", 1, true))
    end },
    { "secret reputation and unsupported scales block the recommendation explicitly", function()
        local Wild, state, _, _, Open, _, Fill = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        local frame = Fill()
        state.reputations[2711].standing = state.secret
        frame.calculate:Click()
        assert(not frame.result:GetText():find("Suggested invite", 1, true))
        state.reputations[2711].standing = 1000
        state.reputations[2711].maxRep = 3000
        frame.calculate:Click()
        assert(frame.result:GetText():find("scale", 1, true))
    end },
    { "all Luminary progress reports completion without asking for invitation previews", function()
        local Wild, state, _, _, Open, Advisor = NewEnvironment()
        for _, factionID in ipairs(FACTIONS) do state.reputations[factionID].standing = 2500 end
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        assert(Advisor().result:GetText():find("All four", 1, true))
        assert(not Advisor().result:GetText():find("Suggested invite", 1, true))
    end },
    { "unused Favors are explained when Fortify alone finishes the last track", function()
        local Wild, state, _, _, Open, _, Fill = NewEnvironment()
        for _, factionID in ipairs(FACTIONS) do state.reputations[factionID].standing = 2500 end
        state.reputations[2711].standing = 2490
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        local frame = Fill()
        frame.calculate:Click()
        assert(frame.result:GetText():find("3 Favors unused", 1, true))
    end },
    { "tab cycles through all preview fields without changing or submitting them", function()
        local Wild, state, _, _, Open, Advisor = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        local fields = {}
        for _, frame in ipairs(state.frames) do
            if frame.kind == "EditBox" then fields[#fields + 1] = frame end
        end
        Equal(#fields, 20)
        for index, field in ipairs(fields) do
            field.scripts.OnTabPressed(field)
            Equal(state.focus, fields[index % #fields + 1])
            Equal(field:GetText(), "")
        end
        Wild.HideSoireeAdvisor()
        Equal(state.focus, nil, "Hidden preview inputs cannot retain keyboard focus")
        Equal(Advisor():IsShown(), false)
    end },
    { "missing supported APIs report an explicit unavailable state", function()
        local Wild, _, env, _, Open, _, Fill = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        local frame = Fill()
        env.C_GossipInfo.GetFriendshipReputation = nil
        frame.calculate:Click()
        assert(frame.result:GetText():find("API is unavailable", 1, true))
        env.C_PlayerChoice.GetCurrentPlayerChoiceInfo = nil
        Equal(Wild.ShowSoireeAdvisor(), false)
    end },
    { "combat prevents creating the helper and hides an existing one", function()
        local Wild, state, _, Fire, Open, Advisor = NewEnvironment()
        state.combat = true
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        Equal(Advisor(), nil)
        Equal(Wild.ShowSoireeAdvisor(), false)
        state.combat = false
        Fire("PLAYER_REGEN_ENABLED")
        Equal(Advisor():IsShown(), true)
        state.combat = true
        Fire("PLAYER_REGEN_DISABLED")
        Equal(Advisor():IsShown(), false)
    end },
    { "setters disabling reset zoning and quest completion clear the helper", function()
        for _, close in ipairs({
            function(Wild) Wild.SetSetting("soiree.enabled", false) end,
            function(Wild) Wild.SetFeatureEnabled("soiree", false) end,
            function(Wild) Wild.ResetSettings() end,
            function(_, Fire) Fire("PLAYER_LEAVING_WORLD") end,
            function(_, Fire) Fire("QUEST_TURNED_IN", 89289) end,
            function(_, Fire) Fire("QUEST_TURNED_IN", 91629) end,
        }) do
            local Wild, _, _, Fire, Open, Advisor, Fill = NewEnvironment()
            Wild.SetFeatureEnabled("soiree", true)
            Open()
            Fill()
            close(Wild, Fire)
            Equal(Advisor():IsShown(), false)
        end
    end },
    { "faction names come from localized API data not invitation prose", function()
        local Wild, state, _, _, Open, Advisor, Fill = NewEnvironment()
        state.names[2711] = "Localized faction 2711"
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        local frame = Fill()
        frame.calculate:Click()
        assert(frame.result:GetText():find("Localized faction 2711", 1, true))
        assert(not frame.result:GetText():find("9999", 1, true))
        Equal(Advisor():IsShown(), true)
    end },
    { "an unrelated selector cannot reuse previously entered Soiree previews", function()
        local Wild, _, _, _, Open, Advisor, Fill = NewEnvironment()
        Wild.SetFeatureEnabled("soiree", true)
        Open()
        local frame = Fill()
        frame.calculate:Click()
        Open(999)
        Equal(Advisor():IsShown(), false)
        Equal(Wild.ShowSoireeAdvisor(), false)
    end },
    { "the TOC loads the advisor before slash commands and native settings", function()
        local file = assert(io.open("Wild.toc", "r"))
        local toc = file:read("*a")
        file:close()
        local advisor = assert(toc:find("Soiree.lua", 1, true))
        assert(advisor < toc:find("SlashCommands.lua", 1, true))
        assert(advisor < toc:find("NativeSettings.lua", 1, true))
        assert(advisor < toc:find("Settings.lua", 1, true))
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
assert(failures == 0, failures .. " Soiree advisor test(s) failed")
print(#tests .. " Soiree advisor tests passed")
