-- Run from the repository root with Lua 5.1: lua tests\SoireePlannerTest.lua
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

local function Same(actual, expected)
    Equal(type(actual), type(expected))
    if type(expected) ~= "table" then return Equal(actual, expected) end
    for key, value in pairs(expected) do Same(actual[key], value) end
    for key in pairs(actual) do assert(expected[key] ~= nil, "Unexpected key " .. tostring(key)) end
end

local FACTIONS = { 2711, 2712, 2713, 2714 }
local function Progress(magisters, knights, farstriders, shades)
    return { [2711] = magisters, [2712] = knights, [2713] = farstriders, [2714] = shades }
end

local function Offers()
    local offers = {}
    for _, factionID in ipairs(FACTIONS) do
        offers[factionID] = { reputation = Progress(0, 0, 0, 0), bonusFavors = 0 }
    end
    return offers
end

local Wild = {}
local secret = {}
local env = setmetatable({
    issecretvalue = function(value) return rawequal(value, secret) end,
    CreateFrame = function()
        return { RegisterEvent = function() end, SetScript = function() end }
    end,
}, { __index = _G })
setfenv(assert(loadfile("Soiree.lua")), env)("Wild", Wild)

local tests = {
    { "a snapshot accounts for gains losses Fortify and the extra Favor", function()
        local progress = Progress(2500, 1600, 1100, 1100)
        local offers = Offers()
        offers[2711].reputation = Progress(100, 75, 0, -75)
        offers[2712] = { reputation = Progress(75, 100, 0, -75), bonusFavors = 1 }
        offers[2713].reputation = Progress(75, -75, 100, 0)
        offers[2714].reputation = Progress(-75, 75, 0, 100)
        local plan = assert(Wild.CalculateSoireeRecommendation(progress, offers))
        Equal(plan.inviteFactionID, 2712)
        Equal(plan.totalFavors, 4)
        Same(plan.favors, Progress(0, 0, 2, 2))
        Same(plan.projected, Progress(2500, 2000, 1300, 1225))
        Same(plan.net, Progress(0, 400, 200, 125))
        Equal(plan.gain, 725)
        Equal(plan.remaining, 2975)
        Equal(plan.weeks, nil, "Future invitation offers are unknown")
    end },
    { "Fortify is credited to the invited faction without overflowing Luminary", function()
        local plan = assert(Wild.CalculateSoireeRecommendation(Progress(2400, 0, 0, 0), Offers()))
        Equal(plan.inviteFactionID, 2712)
        Equal(plan.projected[2711], 2400)
        Equal(plan.projected[2712], 300)
        Equal(plan.favors[2711], 0)
        Equal(plan.gain, 600)
    end },
    { "an extra Favor does not outweigh a larger invitation penalty", function()
        local offers = Offers()
        offers[2711] = { reputation = Progress(0, -600, 0, 0), bonusFavors = 1 }
        local plan = assert(Wild.CalculateSoireeRecommendation(Progress(1000, 1000, 1000, 1000), offers))
        Equal(plan.inviteFactionID, 2712)
        Equal(plan.totalFavors, 3)
        Equal(plan.gain, 600)
    end },
    { "reputation losses stop at zero before Fortify and Favor rewards", function()
        local offers = Offers()
        offers[2711].reputation[2711] = -75
        local plan = assert(Wild.CalculateSoireeRecommendation(Progress(0, 1000, 1000, 1000), offers))
        Equal(plan.inviteFactionID, 2711)
        Equal(plan.projected[2711], 600)
        Equal(plan.gain, 600)
    end },
    { "losses to a completed track are recovered instead of ignored", function()
        local offers = Offers()
        for _, factionID in ipairs({ 2711, 2713, 2714 }) do
            offers[factionID].reputation = Progress(-500, -500, -500, -500)
        end
        offers[2712].reputation = Progress(-100, 100, 0, 0)
        local plan = assert(Wild.CalculateSoireeRecommendation(Progress(2500, 2450, 2450, 2450), offers))
        Equal(plan.inviteFactionID, 2712)
        Same(plan.favors, Progress(1, 0, 1, 1))
        Same(plan.projected, Progress(2500, 2500, 2500, 2500))
        Equal(plan.remaining, 0)
        Equal(plan.gain, 150)
    end },
    { "equal useful gains favor balanced remaining gaps", function()
        local plan = assert(Wild.CalculateSoireeRecommendation(Progress(1000, 1000, 1000, 1000), Offers()))
        Equal(plan.inviteFactionID, 2711)
        Same(plan.favors, Progress(0, 1, 1, 1))
        Same(plan.tiedInvites, FACTIONS)
        Equal(plan.gain, 600)
    end },
    { "unused Favors are retained when every track can be completed without them", function()
        local plan = assert(Wild.CalculateSoireeRecommendation(Progress(2490, 2500, 2500, 2500), Offers()))
        Equal(plan.inviteFactionID, 2711)
        Equal(plan.usedFavors, 0)
        Equal(plan.unusedFavors, 3)
        Same(plan.favors, Progress(0, 0, 0, 0))
        Equal(plan.gain, 10)
        Equal(plan.remaining, 0)
    end },
    { "already completed progress needs no invitation or preview data", function()
        local progress = Progress(2500, 2500, 2500, 2500)
        local plan = assert(Wild.CalculateSoireeRecommendation(progress))
        Equal(plan.complete, true)
        Equal(plan.inviteFactionID, nil)
        Equal(plan.remaining, 0)
        Same(plan.projected, progress)
    end },
    { "all four current previews are required including explicit zero effects", function()
        local progress = Progress(0, 0, 0, 0)
        for _, change in ipairs({
            function(offers) offers[2714] = nil end,
            function(offers) offers[2712].bonusFavors = nil end,
            function(offers) offers[2711].reputation[2713] = nil end,
            function(offers) offers[2713].reputation = nil end,
        }) do
            local offers = Offers()
            change(offers)
            local plan, reason = Wild.CalculateSoireeRecommendation(progress, offers)
            Equal(plan, nil)
            assert(type(reason) == "string" and #reason > 0, "Incomplete input needs a diagnostic")
        end
    end },
    { "invalid secret fractional and non-finite inputs fail with a reason", function()
        for _, value in ipairs({ -1, 2501, "100", 0.5, math.huge, secret, false }) do
            local progress = Progress(0, 0, 0, 0)
            progress[2711] = value
            local plan, reason = Wild.CalculateSoireeRecommendation(progress, Offers())
            Equal(plan, nil)
            assert(reason)
        end
        local progress = Progress(0, 0, 0, 0)
        progress[2712] = 0 / 0
        Equal(Wild.CalculateSoireeRecommendation(progress, Offers()), nil)
        for _, value in ipairs({ -1, 2, 0.5, "1", secret }) do
            local offers = Offers()
            offers[2711].bonusFavors = value
            Equal(Wild.CalculateSoireeRecommendation(Progress(0, 0, 0, 0), offers), nil)
        end
        for _, value in ipairs({ -2501, 2501, math.huge, "75", 0.5, secret }) do
            local offers = Offers()
            offers[2713].reputation[2714] = value
            Equal(Wild.CalculateSoireeRecommendation(Progress(0, 0, 0, 0), offers), nil)
        end
        for _, value in ipairs({ false, 1, "progress", secret }) do
            local plan, reason = Wild.CalculateSoireeRecommendation(value, Offers())
            Equal(plan, nil)
            assert(reason)
        end
    end },
    { "input tables are not mutated and ties are deterministic", function()
        local progress, offers = Progress(200, 400, 600, 800), Offers()
        local originalProgress, originalOffers = Copy(progress), Copy(offers)
        local first = assert(Wild.CalculateSoireeRecommendation(progress, offers))
        for _ = 1, 3 do Same(Wild.CalculateSoireeRecommendation(progress, offers), first) end
        Same(progress, originalProgress)
        Same(offers, originalOffers)
    end },
    { "useful reputation is maximal against an independent marginal-gain oracle", function()
        local seed = 31
        local function Random(limit)
            seed = (seed * 16807) % 2147483647
            return seed % limit
        end
        for _ = 1, 64 do
            local progress, offers, before = {}, Offers(), 0
            for _, factionID in ipairs(FACTIONS) do
                progress[factionID] = Random(2501)
                before = before + progress[factionID]
                offers[factionID].bonusFavors = Random(2)
                for _, targetID in ipairs(FACTIONS) do
                    offers[factionID].reputation[targetID] = (Random(11) - 5) * 25
                end
            end
            local maximum = -math.huge
            for _, invitedID in ipairs(FACTIONS) do
                local offer, projected = offers[invitedID], {}
                for _, factionID in ipairs(FACTIONS) do
                    projected[factionID] = math.min(2500,
                        math.max(0, progress[factionID] + offer.reputation[factionID]))
                end
                projected[invitedID] = math.min(2500, projected[invitedID] + 300)
                for _ = 1, 3 + offer.bonusFavors do
                    local target, gain = nil, 0
                    for _, factionID in ipairs(FACTIONS) do
                        local marginal = math.min(100, 2500 - projected[factionID])
                        if marginal > gain then target, gain = factionID, marginal end
                    end
                    if target then projected[target] = projected[target] + gain end
                end
                local total = 0
                for _, factionID in ipairs(FACTIONS) do total = total + projected[factionID] end
                maximum = math.max(maximum, total - before)
            end
            local plan = assert(Wild.CalculateSoireeRecommendation(progress, offers))
            Equal(plan.gain, maximum, "A different Favor allocation earns more useful reputation")
            assert(plan.usedFavors <= plan.totalFavors)
            for _, factionID in ipairs(FACTIONS) do
                assert(plan.projected[factionID] >= 0 and plan.projected[factionID] <= 2500)
            end
        end
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
assert(failures == 0, failures .. " Soiree planner test(s) failed")
print(#tests .. " Soiree planner tests passed")
