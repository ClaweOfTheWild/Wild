-- Wild: Gossip automation (auto-select single option, skip quest/delve dialogs, Darkmoon Faire teleport)
local ADDON_NAME, Wild = ...

local DARKMOON_MAGE_NPC_ID = 54334
local DARKMOON_TELEPORT_TEXT = "Take me to the faire staging area."

local function GetConfig()
    return Wild.db and Wild.db.gossip
end

-- ============================================================
-- Toggle key: hold modifier to temporarily bypass automation
-- ============================================================
local TOGGLE_KEY_FUNCS = { [1] = function() return false end, [2] = IsAltKeyDown, [3] = IsControlKeyDown, [4] = IsShiftKeyDown }

local function IsAllowed(cfg)
    local keyHeld = TOGGLE_KEY_FUNCS[cfg.toggleKey or 1]()
    return not keyHeld
end

-- ============================================================
-- NPC ID helper (extract from GUID)
-- ============================================================
local function GetTargetNpcID()
    local guid = UnitGUID("npc")
    if not guid then return nil end
    local _, _, _, _, _, npcID = strsplit("-", guid)
    return tonumber(npcID)
end

-- ============================================================
-- Check if a gossip option matches the Darkmoon Faire teleport
-- ============================================================
local function FindDarkmoonTeleportOption(options)
    for _, opt in ipairs(options) do
        local name = opt.name or ""
        if name == DARKMOON_TELEPORT_TEXT then
            return opt
        end
    end
    return nil
end

-- ============================================================
-- Check gossip option type helpers
-- ============================================================
local QUEST_OPTION_TYPES = {
    ["gossip-quest"]  = true,
    ["quest"]         = true,
}
local DELVE_OPTION_TYPES = {
    ["delve"]         = true,
    ["gossip-delve"]  = true,
}

local function FindOptionByType(options, typeSet)
    for _, opt in ipairs(options) do
        local optType = opt.type and tostring(opt.type):lower() or ""
        if typeSet[optType] then return opt end
    end
    return nil
end

local function FindOptionByNamePattern(options, pattern)
    for _, opt in ipairs(options) do
        local name = opt.name or ""
        if name:lower():find(pattern) then return opt end
    end
    return nil
end

local function FindSkipOption(options)
    return FindOptionByNamePattern(options, "skip")
end

-- ============================================================
-- GOSSIP_SHOW handler
-- ============================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("GOSSIP_CONFIRM")

frame:SetScript("OnEvent", function(self, event, ...)
    local cfg = GetConfig()
    if not cfg then return end
    if not IsAllowed(cfg) then return end

    if event == "GOSSIP_CONFIRM" then
        -- Auto-confirm Darkmoon Faire teleport cost dialog (25 copper)
        if cfg.darkmoonTeleport and GetTargetNpcID() == DARKMOON_MAGE_NPC_ID then
            local gossipID = ...
            C_GossipInfo.SelectOption(gossipID, "", true)
            StaticPopup_Hide("GOSSIP_CONFIRM")
        end
        return
    end

    -- event == "GOSSIP_SHOW"
    local options = C_GossipInfo.GetOptions()
    if not options then return end

    local activeQuests = C_GossipInfo.GetActiveQuests()
    local availableQuests = C_GossipInfo.GetAvailableQuests()
    local hasQuests = (activeQuests and #activeQuests > 0) or (availableQuests and #availableQuests > 0)

    -- Darkmoon teleport: auto-select if talking to the Mystic Mage (NPC 54334)
    if cfg.darkmoonTeleport and GetTargetNpcID() == DARKMOON_MAGE_NPC_ID then
        local dmOpt = FindDarkmoonTeleportOption(options)
        if dmOpt then
            C_GossipInfo.SelectOption(dmOpt.gossipOptionID)
            return
        end
    end

    -- Auto-skip: select any option whose name contains "skip"
    if cfg.autoSkip then
        local skipOpt = FindSkipOption(options)
        if skipOpt then
            C_GossipInfo.SelectOption(skipOpt.gossipOptionID)
            return
        end
    end

    -- Auto-select quest-typed gossip option
    if cfg.autoSelectQuest then
        local questOpt = FindOptionByType(options, QUEST_OPTION_TYPES)
            or FindOptionByNamePattern(options, "quest")
        if questOpt then
            C_GossipInfo.SelectOption(questOpt.gossipOptionID)
            return
        end
    end

    -- Auto-select delve-typed gossip option
    if cfg.autoSelectDelve then
        local delveOpt = FindOptionByType(options, DELVE_OPTION_TYPES)
            or FindOptionByNamePattern(options, "delve")
        if delveOpt then
            C_GossipInfo.SelectOption(delveOpt.gossipOptionID)
            return
        end
    end

    -- Auto-select single gossip option
    if cfg.autoSelectSingle then
        -- Skip if there are quest dialogs and skipIfQuest is enabled
        if cfg.skipIfQuest and hasQuests then
            return
        end

        if #options == 1 then
            C_GossipInfo.SelectOption(options[1].gossipOptionID)
            return
        end
    end
end)
