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

local function ClampReputation(value)
    return math.min(LUMINARY_REPUTATION, math.max(0, value))
end

local function ValidateProgress(progress)
    if not IsTable(progress) then return "Reputation progress must contain all four factions." end
    for _, factionID in ipairs(FACTIONS) do
        if not IsInteger(progress[factionID], 0, LUMINARY_REPUTATION) then
            return "Reputation for " .. FACTION_NAMES[factionID] .. " must be an integer from 0 to 2500."
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
        local projected = ClampReputation(base[factionID] + count * FAVOR_REPUTATION)
        local gap = LUMINARY_REPUTATION - projected
        plan.favors[factionID] = count
        plan.projected[factionID] = projected
        plan.net[factionID] = projected - progress[factionID]
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
        base[factionID] = ClampReputation(progress[factionID] + offer.reputation[factionID])
    end
    base[invitedID] = ClampReputation(base[invitedID] + FORTIFY_REPUTATION)
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
    for _, factionID in ipairs(FACTIONS) do remaining = remaining + LUMINARY_REPUTATION - progress[factionID] end
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
