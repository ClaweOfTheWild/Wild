-- Wild: Quest automation (auto-accept, auto-hand-in, reward selection)
local ADDON_NAME, Wild = ...

local function GetConfig()
    return Wild.db and Wild.db.quests
end

-- ============================================================
-- Toggle key: hold modifier to temporarily invert automation
-- ============================================================
local TOGGLE_KEY_FUNCS = { [1] = function() return false end, [2] = IsAltKeyDown, [3] = IsControlKeyDown, [4] = IsShiftKeyDown }

local function IsAllowed(cfg)
    local keyHeld = TOGGLE_KEY_FUNCS[cfg.toggleKey or 1]()
    -- XOR: if enabled and key held → disabled; if disabled and key held → enabled
    -- But in Wild, the feature being enabled is the prerequisite for the event handler to run,
    -- so toggleKey simply inverts "should we act right now"
    return not keyHeld
end

-- ============================================================
-- Quest scope & trivial filtering
-- ============================================================
-- Classify the current quest from QUEST_DETAIL context
local function ShouldAcceptCurrentQuest(cfg)
    local questID = GetQuestID()
    -- Trivial check
    if not cfg.acceptTrivial and questID and C_QuestLog.IsQuestTrivial(questID) then return false end
    -- Type checks
    if QuestIsDaily() then return cfg.acceptDaily end
    if QuestIsWeekly() then return cfg.acceptWeekly end
    -- No API for "repeatable" on detail frame; daily/weekly covers most cases.
    -- Anything else is a normal quest.
    return cfg.acceptNormal
end

-- Classify a gossip-offered quest
local function ShouldAcceptGossipQuest(cfg, questInfo)
    if not cfg.acceptTrivial and questInfo.isTrivial then return false end
    if questInfo.frequency == Enum.QuestFrequency.Daily then return cfg.acceptDaily end
    if questInfo.frequency == Enum.QuestFrequency.Weekly then return cfg.acceptWeekly end
    if questInfo.isRepeatable then return cfg.acceptRepeatable end
    return cfg.acceptNormal
end

-- ============================================================
-- Reward selection: pick the item worth the most vendor gold.
-- Falls back to the first choice if prices are unavailable.
-- ============================================================
local function SelectBestReward()
    local numChoices = GetNumQuestChoices()
    if numChoices == 0 then return end

    -- If only one reward, just pick it
    if numChoices == 1 then
        GetQuestReward(1)
        return
    end

    local bestIndex, bestValue = 1, 0
    for i = 1, numChoices do
        local link = GetQuestItemLink("choice", i)
        if link then
            local itemID = tonumber(link:match("item:(%d+)"))
            local sellPrice = Wild.GetEffectiveSellPrice(itemID, { hyperlink = link })
            if sellPrice and sellPrice > bestValue then
                bestValue = sellPrice
                bestIndex = i
            end
        end
    end
    GetQuestReward(bestIndex)
end

-- ============================================================
-- Event handler
-- ============================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("QUEST_ACCEPT_CONFIRM")
frame:RegisterEvent("QUEST_GREETING")
frame:RegisterEvent("GOSSIP_SHOW")

frame:SetScript("OnEvent", function(self, event)
    local cfg = GetConfig()
    if not cfg then return end
    if not IsAllowed(cfg) then return end

    if event == "QUEST_DETAIL" then
        -- Auto-accept quest (including dailies, weeklies, repeatables)
        if cfg.autoAccept then
            if QuestGetAutoAccept and QuestGetAutoAccept() then
                -- Auto-accept quest (many dailies/repeatables): acknowledge and close
                if AcknowledgeAutoAcceptQuest then
                    AcknowledgeAutoAcceptQuest()
                end
                if QuestIsFromAreaTrigger and QuestIsFromAreaTrigger() then
                    CloseQuest()
                end
                return
            end
            if ShouldAcceptCurrentQuest(cfg) then
                AcceptQuest()
            end
        end

    elseif event == "QUEST_ACCEPT_CONFIRM" then
        -- Confirm quest acceptance (escort/repeatable quests that need extra confirmation)
        if cfg.autoAccept then
            ConfirmAcceptQuest()
        end

    elseif event == "GOSSIP_SHOW" then
        -- Gossip-based NPC interaction (Darkmoon Faire, daily hubs, etc.)
        -- First try to hand in completed quests, then accept available ones
        if cfg.autoHandIn then
            local activeQuests = C_GossipInfo.GetActiveQuests()
            for _, quest in ipairs(activeQuests) do
                if quest.isComplete then
                    C_GossipInfo.SelectActiveQuest(quest.questID)
                    return
                end
            end
        end
        if cfg.autoAccept then
            local availableQuests = C_GossipInfo.GetAvailableQuests()
            for _, quest in ipairs(availableQuests) do
                if ShouldAcceptGossipQuest(cfg, quest) then
                    C_GossipInfo.SelectAvailableQuest(quest.questID)
                    return
                end
            end
        end

    elseif event == "QUEST_GREETING" then
        -- NPC offers multiple quests (common at daily hubs)
        if cfg.autoHandIn then
            local active = GetNumActiveQuests()
            for i = active, 1, -1 do
                local _, isComplete = GetActiveTitle(i)
                if isComplete then
                    SelectActiveQuest(i)
                    return
                end
            end
        end
        if cfg.autoAccept then
            local available = GetNumAvailableQuests()
            for i = 1, available do
                local isTrivial, isDaily, isRepeatable = GetAvailableQuestInfo(i)
                if not cfg.acceptTrivial and isTrivial then
                    -- skip
                elseif isDaily and isDaily ~= 0 then
                    if cfg.acceptDaily then SelectAvailableQuest(i); return end
                elseif isRepeatable and isRepeatable ~= 0 then
                    if cfg.acceptRepeatable then SelectAvailableQuest(i); return end
                else
                    if cfg.acceptNormal then SelectAvailableQuest(i); return end
                end
            end
        end

    elseif event == "QUEST_PROGRESS" then
        -- Auto-hand-in: click Continue when objectives are complete
        if cfg.autoHandIn then
            if IsQuestCompletable() then
                CompleteQuest()
            end
        end

    elseif event == "QUEST_COMPLETE" then
        -- Auto-hand-in: complete the quest, selecting a reward if needed
        if cfg.autoHandIn then
            local numChoices = GetNumQuestChoices()
            if numChoices == 0 then
                -- No choice rewards, just finish
                GetQuestReward()
            elseif cfg.autoSelectReward then
                SelectBestReward()
            end
            -- If choices exist but autoSelectReward is off, leave the window open
        end
    end
end)
