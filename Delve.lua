-- Wild: Delve auto-select power
local ADDON_NAME, Wild = ...

-- ============================================================
-- Auto-select Delve power when a PlayerChoice appears inside
-- a Delve instance (difficulty ID 208). Picks the first option
-- automatically so you skip the interaction window entirely.
-- ============================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_CHOICE_UPDATE")
frame:SetScript("OnEvent", function(self, event)
    if not Wild.db or not Wild.db.delveAutoSelectPower then return end

    -- Only act inside a Delve (instance difficulty 208)
    local _, _, difficultyID = GetInstanceInfo()
    if difficultyID ~= 208 then return end

    local choiceInfo = C_PlayerChoice.GetCurrentPlayerChoiceInfo()
    if not choiceInfo or not choiceInfo.options or #choiceInfo.options == 0 then return end

    -- Select the first available option's first button
    local firstOption = choiceInfo.options[1]
    if not firstOption or not firstOption.buttons or #firstOption.buttons == 0 then return end

    local buttonID = firstOption.buttons[1].id
    C_PlayerChoice.SendPlayerChoiceResponse(buttonID)

    -- Hide the choice frame if it appeared
    if PlayerChoiceFrame and PlayerChoiceFrame:IsShown() then
        PlayerChoiceFrame:Hide()
    end
end)
