-- Wild: Saltheril's Soiree reputation advisor
local ADDON_NAME, Wild = ...

local FACTIONS = { 2711, 2712, 2713, 2714 }
local FACTION_NAMES = {
    [2711] = "Magisters",
    [2712] = "Blood Knights",
    [2713] = "Farstriders",
    [2714] = "Shades of the Row",
}
local LUMINARY_REPUTATION = 2500
local FORTIFY_REPUTATION = 300
local FAVOR_REPUTATION = 100
local BASE_FAVORS = 3
local SALTHERIL_NPC_ID = 240832
local MAX_INTEGER = 2147483647

local function IsPublic(value)
    return not (issecretvalue and issecretvalue(value))
end

local function IsInteger(value, minimum, maximum)
    return IsPublic(value) and type(value) == "number" and value == value and
        value >= minimum and value <= maximum and value % 1 == 0
end

local function IsTable(value)
    return IsPublic(value) and type(value) == "table"
end

local function ClampToLuminary(value)
    return math.min(LUMINARY_REPUTATION, math.max(0, value))
end

local function ValidateProgress(progress)
    if not IsTable(progress) then return "Reputation progress must contain all four factions." end
    for _, factionID in ipairs(FACTIONS) do
        if not IsInteger(progress[factionID], 0, MAX_INTEGER) then
            return "Reputation for " .. FACTION_NAMES[factionID] ..
                " must be an integer from 0 to 2147483647."
        end
    end
end

local function ValidateOffers(offers)
    if not IsTable(offers) then return "Enter all four current invitation previews." end
    for _, factionID in ipairs(FACTIONS) do
        local offer = offers[factionID]
        local prefix = "Invitation for " .. FACTION_NAMES[factionID] .. ": "
        if not IsTable(offer) or not IsTable(offer.reputation) then
            return prefix .. "enter all four reputation changes, including zero for unlisted factions."
        end
        if not IsInteger(offer.bonusFavors, 0, 1) then
            return prefix .. "bonus Favors must be 0 or 1."
        end
        for _, targetID in ipairs(FACTIONS) do
            if not IsInteger(offer.reputation[targetID], -LUMINARY_REPUTATION, LUMINARY_REPUTATION) then
                return prefix .. "enter a whole-number change from -2500 to 2500 for " ..
                    FACTION_NAMES[targetID] .. "."
            end
        end
    end
end

local function BuildPlan(progress, invitedID, base, allocation, totalFavors)
    local plan = {
        inviteFactionID = invitedID, projected = {}, favors = {}, net = {}, gaps = {},
        totalFavors = totalFavors, usedFavors = 0, remaining = 0, gain = 0,
    }
    for _, factionID in ipairs(FACTIONS) do
        local count = allocation[factionID]
        local projected = ClampToLuminary(base[factionID] + count * FAVOR_REPUTATION)
        local gap = LUMINARY_REPUTATION - projected
        plan.favors[factionID] = count
        plan.projected[factionID] = projected
        plan.net[factionID] = projected - ClampToLuminary(progress[factionID])
        plan.usedFavors = plan.usedFavors + count
        plan.remaining = plan.remaining + gap
        plan.gain = plan.gain + plan.net[factionID]
        plan.gaps[#plan.gaps + 1] = gap
    end
    table.sort(plan.gaps, function(left, right) return left > right end)
    plan.unusedFavors = totalFavors - plan.usedFavors
    return plan
end

local function ComparePlans(left, right)
    if left.remaining ~= right.remaining then return left.remaining < right.remaining and -1 or 1 end
    for index = 1, #FACTIONS do
        if left.gaps[index] ~= right.gaps[index] then
            return left.gaps[index] < right.gaps[index] and -1 or 1
        end
    end
    if left.usedFavors ~= right.usedFavors then return left.usedFavors < right.usedFavors and -1 or 1 end
    return 0
end

local function PlanInvitation(progress, invitedID, offer)
    local base, allocation = {}, {}
    for _, factionID in ipairs(FACTIONS) do
        -- Apply losses to the actual standing before capping useful progress at Luminary.
        base[factionID] = ClampToLuminary(progress[factionID] + offer.reputation[factionID])
    end
    base[invitedID] = ClampToLuminary(base[invitedID] + FORTIFY_REPUTATION)
    local totalFavors = BASE_FAVORS + offer.bonusFavors
    local best
    local function Allocate(index, remaining)
        if index > #FACTIONS then
            local plan = BuildPlan(progress, invitedID, base, allocation, totalFavors)
            if not best or ComparePlans(plan, best) < 0 then best = plan end
            return
        end
        local factionID = FACTIONS[index]
        for count = 0, remaining do
            allocation[factionID] = count
            Allocate(index + 1, remaining - count)
        end
    end
    Allocate(1, totalFavors)
    return best
end

-- Pure calculator: progress and offers are keyed by faction ID; returns a plan or nil, reason.
function Wild.CalculateSoireeRecommendation(progress, offers)
    local reason = ValidateProgress(progress)
    if reason then return nil, reason end
    local remaining = 0
    for _, factionID in ipairs(FACTIONS) do
        remaining = remaining + LUMINARY_REPUTATION - ClampToLuminary(progress[factionID])
    end
    if remaining == 0 then
        local allocation = {}
        for _, factionID in ipairs(FACTIONS) do allocation[factionID] = 0 end
        local plan = BuildPlan(progress, nil, progress, allocation, 0)
        plan.complete, plan.gaps, plan.tiedInvites = true, nil, {}
        return plan
    end
    reason = ValidateOffers(offers)
    if reason then return nil, reason end
    local best, tiedInvites
    for _, factionID in ipairs(FACTIONS) do
        local plan = PlanInvitation(progress, factionID, offers[factionID])
        local comparison = best and ComparePlans(plan, best) or -1
        if comparison < 0 then
            best, tiedInvites = plan, { factionID }
        elseif comparison == 0 then
            tiedInvites[#tiedInvites + 1] = factionID
        end
    end
    best.gaps = nil
    best.tiedInvites = tiedInvites
    return best
end

-- Returns current absolute friendship standings, or nil, reason when any track is unavailable.
function Wild.GetSoireeProgress()
    if not C_GossipInfo or not C_GossipInfo.GetFriendshipReputation then
        return nil, "The friendship reputation API is unavailable."
    end
    local progress = {}
    for _, factionID in ipairs(FACTIONS) do
        local reputation = C_GossipInfo.GetFriendshipReputation(factionID)
        if not IsTable(reputation) or not IsInteger(reputation.friendshipFactionID, 1, MAX_INTEGER) or
            not IsInteger(reputation.standing, 0, MAX_INTEGER) then
            return nil, "Reputation for " .. FACTION_NAMES[factionID] ..
                " is unavailable. Unlock the Soiree and try again after reputation data loads."
        end
        if not IsInteger(reputation.maxRep, LUMINARY_REPUTATION, MAX_INTEGER) then
            return nil, "The reputation scale for " .. FACTION_NAMES[factionID] ..
                " is unsupported; no recommendation can be calculated."
        end
        if reputation.standing > reputation.maxRep then
            return nil, "Reputation for " .. FACTION_NAMES[factionID] ..
                " exceeds the reported maximum; no recommendation can be calculated."
        end
        progress[factionID] = reputation.standing
    end
    return progress
end

local helper
local activeChoiceID
local confirmedOffers
local hookedSelector

local function IsEnabled()
    return Wild.db and Wild.db.soiree and Wild.db.soiree.enabled == true
end

local function GetFactionName(factionID)
    local faction = C_Reputation and C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(factionID)
    if IsTable(faction) and IsPublic(faction.name) and type(faction.name) == "string" and faction.name ~= "" then
        return faction.name
    end
    return FACTION_NAMES[factionID]
end

local function GetSelector()
    if not C_PlayerChoice or not C_PlayerChoice.GetCurrentPlayerChoiceInfo then
        return nil, "The invitation selector API is unavailable."
    end
    local choice = C_PlayerChoice.GetCurrentPlayerChoiceInfo()
    if not IsTable(choice) then return nil, "Open Saltheril's weekly invitation selector first." end
    if not _G.PlayerChoiceFrame or not _G.PlayerChoiceFrame:IsShown() then
        return nil, "Open Saltheril's weekly invitation selector first."
    end
    if not IsPublic(choice.objectGUID) or type(choice.objectGUID) ~= "string" then
        return nil, "The invitation selector identity is unavailable."
    end
    local kind, _, _, _, _, npcID = strsplit("-", choice.objectGUID)
    if kind ~= "Creature" or tonumber(npcID) ~= SALTHERIL_NPC_ID or not IsTable(choice.options) or
        #choice.options ~= #FACTIONS or not IsInteger(choice.choiceID, 1, MAX_INTEGER) then
        return nil, "Open Saltheril's four-invitation selector first."
    end
    return choice
end

local function CloseSession()
    activeChoiceID, confirmedOffers = nil, nil
    if helper then helper:Hide() end
end

local function HookSelector()
    local selector = _G.PlayerChoiceFrame
    if not selector or selector == hookedSelector then return end
    selector:HookScript("OnHide", CloseSession)
    selector:HookScript("OnShow", function()
        if IsEnabled() then Wild.UpdateSoireeAdvisor() end
    end)
    hookedSelector = selector
end

local function RefreshAdvisor()
    local progress, reason = Wild.GetSoireeProgress()
    if not progress then
        helper.result:SetText("|cffff6600" .. reason .. "|r")
        for _, factionID in ipairs(FACTIONS) do
            helper.progressLabels[factionID]:SetText(GetFactionName(factionID) .. ": unavailable")
        end
        return
    end
    local plan
    if confirmedOffers then
        plan, reason = Wild.CalculateSoireeRecommendation(progress, confirmedOffers)
    else
        local remaining = 0
        for _, factionID in ipairs(FACTIONS) do
            remaining = remaining + LUMINARY_REPUTATION - ClampToLuminary(progress[factionID])
        end
        if remaining == 0 then plan = Wild.CalculateSoireeRecommendation(progress) end
    end
    if plan and plan.complete then
        helper.result:SetText("|cff44ff44All four factions are Luminary. No invitation is needed for this goal.|r")
    elseif plan then
        local tied = #plan.tiedInvites > 1 and " (tied best)" or ""
        local text = string.format(
            "Suggested invite: %s%s\nFortify: +300 with that faction. %d base Favors + %d bonus.\n" ..
            "Useful net gain: %+d reputation. Total remaining: %d.",
            GetFactionName(plan.inviteFactionID), tied, BASE_FAVORS, plan.totalFavors - BASE_FAVORS,
            plan.gain, plan.remaining)
        if plan.unusedFavors > 0 then
            text = text .. string.format("\n%d Favor%s unused; no further reputation is needed.",
                plan.unusedFavors, plan.unusedFavors == 1 and "" or "s")
        end
        helper.result:SetText(text)
    elseif reason then
        helper.result:SetText("|cffff6600" .. reason .. "|r")
    else
        helper.result:SetText("Manual preview mode: enter all four current offers, then Calculate. " ..
            "Weekly effects are not inferred from description text.")
    end
    for _, factionID in ipairs(FACTIONS) do
        local name = GetFactionName(factionID)
        if plan and not plan.complete then
            local count = plan.favors[factionID]
            helper.progressLabels[factionID]:SetText(string.format(
                "%s: %d -> %d / 2500 (%+d); %d Favor%s",
                name, ClampToLuminary(progress[factionID]), plan.projected[factionID], plan.net[factionID],
                count, count == 1 and "" or "s"))
        else
            helper.progressLabels[factionID]:SetText(name .. ": " .. ClampToLuminary(progress[factionID]) .. " / 2500")
        end
    end
end

local function CalculateFromPreviews()
    if InCombatLockdown() then CloseSession(); return end
    local choice, reason = GetSelector()
    if not choice or choice.choiceID ~= activeChoiceID then
        CloseSession()
        Wild.Print("|cffff6600Wild:|r " .. (reason or "The invitation selector changed. Reopen the advisor."))
        return
    end
    local offers = {}
    for _, factionID in ipairs(FACTIONS) do
        local row = helper.inputs[factionID]
        local offer = { reputation = {}, bonusFavors = tonumber(row.bonusFavors:GetText()) }
        for _, targetID in ipairs(FACTIONS) do
            offer.reputation[targetID] = tonumber(row.reputation[targetID]:GetText())
        end
        offers[factionID] = offer
    end
    local progress
    progress, reason = Wild.GetSoireeProgress()
    if progress then
        local plan
        plan, reason = Wild.CalculateSoireeRecommendation(progress, offers)
        if plan then
            confirmedOffers = offers
            RefreshAdvisor()
            return
        end
    end
    confirmedOffers = nil
    RefreshAdvisor()
    helper.result:SetText("|cffff6600" .. reason .. "|r")
end

local function CreateHelper()
    if helper then return helper end
    helper = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    helper:SetSize(752, 520)
    helper:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -70)
    helper:SetFrameStrata("DIALOG")
    helper:SetClampedToScreen(true)
    helper:SetMovable(true)
    helper:EnableMouse(true)
    helper:RegisterForDrag("LeftButton")
    helper:SetScript("OnDragStart", helper.StartMoving)
    helper:SetScript("OnDragStop", helper.StopMovingOrSizing)
    helper:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    })
    helper:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
    helper:SetBackdropBorderColor(0.25, 0.25, 0.3, 1)
    helper.inputs, helper.progressLabels = {}, {}
    helper:SetScript("OnHide", function()
        activeChoiceID, confirmedOffers = nil, nil
        for _, row in pairs(helper.inputs) do
            for _, field in pairs(row.reputation) do field:ClearFocus() end
            row.bonusFavors:ClearFocus()
        end
    end)

    local function Label(text, x, y, width, template)
        local label = helper:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", x, y)
        label:SetWidth(width)
        label:SetJustifyH("LEFT")
        label:SetText(text)
        return label
    end
    Label("Wild: Saltheril's Soiree Advisor", 16, -16, 680, "GameFontNormalLarge")
    Label("Copy each invitation's signed reputation changes. Enter 0 for every unlisted faction.\n" ..
        "Bonus Favors: 0 or 1 (do not include the 3 base Favors). Drag this window to see the previews.",
        16, -48, 712)
    local close = CreateFrame("Button", nil, helper, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    Label("Invite", 16, -102, 130, "GameFontNormal")
    for index, factionID in ipairs(FACTIONS) do
        Label(GetFactionName(factionID), 152 + (index - 1) * 114, -98, 104, "GameFontNormalSmall")
    end
    Label("Bonus\nFavors", 640, -98, 80, "GameFontNormalSmall")

    local fields = {}
    local function Input(x, y)
        local field = CreateFrame("EditBox", nil, helper, "InputBoxTemplate")
        field:SetSize(78, 24)
        field:SetPoint("TOPLEFT", x, y)
        field:SetAutoFocus(false)
        field:SetMaxLetters(6)
        field:SetScript("OnTextChanged", function(_, userInput)
            if userInput then
                confirmedOffers = nil
                RefreshAdvisor()
            end
        end)
        field:SetScript("OnEnterPressed", field.ClearFocus)
        field:SetScript("OnEscapePressed", field.ClearFocus)
        fields[#fields + 1] = field
        return field
    end
    for index, factionID in ipairs(FACTIONS) do
        local y = -134 - (index - 1) * 32
        Label(GetFactionName(factionID), 16, y - 3, 130)
        local row = { reputation = {} }
        for column, targetID in ipairs(FACTIONS) do
            row.reputation[targetID] = Input(164 + (column - 1) * 114, y)
        end
        row.bonusFavors = Input(640, y)
        helper.inputs[factionID] = row
    end
    for index, field in ipairs(fields) do
        field:SetScript("OnTabPressed", function()
            local nextIndex = ((index - 1 + (IsShiftKeyDown() and -1 or 1)) % #fields) + 1
            fields[nextIndex]:SetFocus()
            fields[nextIndex]:HighlightText()
        end)
    end
    helper.calculate = CreateFrame("Button", nil, helper, "UIPanelButtonTemplate")
    helper.calculate:SetSize(230, 24)
    helper.calculate:SetPoint("TOPLEFT", 16, -274)
    helper.calculate:SetText("Calculate from these previews")
    helper.calculate:SetScript("OnClick", CalculateFromPreviews)
    helper.result = Label("", 16, -312, 712, "GameFontHighlight")
    for index, factionID in ipairs(FACTIONS) do
        helper.progressLabels[factionID] = Label("", 16, -382 - (index - 1) * 20, 712)
    end
    Label("Base quest rewards only: Fortify +300; each completed Favor quest +100. " ..
        "Advice never selects or spends. Future weeks and reputation bonuses are not predicted.",
        16, -480, 712)
    helper:Hide()
    return helper
end

local function OpenAdvisor()
    if InCombatLockdown() then
        CloseSession()
        return false, "Open the Soiree advisor outside combat."
    end
    local choice, reason = GetSelector()
    if not choice then CloseSession(); return false, reason end
    local frame = CreateHelper()
    HookSelector()
    if activeChoiceID ~= choice.choiceID or not frame:IsShown() then
        confirmedOffers = nil
        for _, row in pairs(frame.inputs) do
            for _, field in pairs(row.reputation) do field:SetText("") end
            row.bonusFavors:SetText("")
        end
    end
    activeChoiceID = choice.choiceID
    frame:Show()
    RefreshAdvisor()
    return true
end

-- Explicit display does not enable automatic display; a current selector is still required.
function Wild.ShowSoireeAdvisor()
    local shown, reason = OpenAdvisor()
    if not shown then Wild.Print("|cffff6600Wild:|r " .. reason) end
    return shown
end

function Wild.HideSoireeAdvisor()
    CloseSession()
end

function Wild.UpdateSoireeAdvisor()
    if IsEnabled() then
        HookSelector()
        OpenAdvisor()
    else
        CloseSession()
    end
end

local frame = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_CHOICE_UPDATE", "PLAYER_CHOICE_CLOSE", "UPDATE_FACTION",
    "PLAYER_LEAVING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "QUEST_TURNED_IN",
}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, argument)
    if event == "ADDON_LOADED" then
        if argument == ADDON_NAME then
            Wild.UpdateSoireeAdvisor()
        elseif argument == "Blizzard_PlayerChoice" and (IsEnabled() or (helper and helper:IsShown())) then
            HookSelector()
            if IsEnabled() then OpenAdvisor() end
        end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then
        Wild.UpdateSoireeAdvisor()
    elseif event == "PLAYER_CHOICE_UPDATE" then
        local show = IsEnabled() or (helper and helper:IsShown())
        CloseSession()
        if show then HookSelector(); OpenAdvisor() end
    elseif event == "PLAYER_CHOICE_CLOSE" or event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_REGEN_DISABLED" then
        CloseSession()
    elseif event == "QUEST_TURNED_IN" then
        if IsPublic(argument) and (argument == 89289 or argument == 91629) then CloseSession() end
    elseif event == "UPDATE_FACTION" and helper and helper:IsShown() then
        local choice = GetSelector()
        if choice and choice.choiceID == activeChoiceID then RefreshAdvisor() else CloseSession() end
    end
end)
