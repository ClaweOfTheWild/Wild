-- Wild: Auto-reply to whispers while in Mythic+ keystones
local ADDON_NAME, Wild = ...

local recentReplies = {}    -- throttle: sender → timestamp of last auto-reply
local REPLY_COOLDOWN = 60   -- seconds before re-replying to the same person

local function GetConfig()
    return Wild.db and Wild.db.autoReply
end

-- ============================================================
-- Detect whether we are inside a Mythic+ keystone
-- ============================================================
local function IsInMythicPlus()
    local _, _, difficultyID = GetInstanceInfo()
    -- difficultyID 8 = Mythic Keystone
    return difficultyID == 8
end

local function IsKeystoneInProgress()
    -- C_ChallengeMode.IsChallengeModeActive() returns true while the timer
    -- is running (after starting, before completion/depletion).
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive()
end

local function ShouldAutoReply(cfg)
    if not cfg or not cfg.enabled then return false end
    if not IsInMythicPlus() then return false end
    if cfg.onlyInProgress and not IsKeystoneInProgress() then return false end
    return true
end

-- ============================================================
-- Throttle: don't spam the same person
-- ============================================================
local function ShouldReplyTo(sender)
    local now = GetTime()
    local last = recentReplies[sender]
    if last and (now - last) < REPLY_COOLDOWN then
        return false
    end
    recentReplies[sender] = now
    return true
end

-- Clean up stale entries periodically
C_Timer.NewTicker(300, function()
    local now = GetTime()
    for sender, ts in pairs(recentReplies) do
        if (now - ts) > REPLY_COOLDOWN * 2 then
            recentReplies[sender] = nil
        end
    end
end)

-- ============================================================
-- Event handler
-- ============================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")

frame:SetScript("OnEvent", function(self, event, ...)
    local cfg = GetConfig()
    if not cfg then return end

    -- Clear throttle table when a key ends so people get fresh replies next run
    if event == "CHALLENGE_MODE_COMPLETED" then
        wipe(recentReplies)
        return
    end

    if not ShouldAutoReply(cfg) then return end

    local message = cfg.message or ""
    if message == "" then return end

    if event == "CHAT_MSG_WHISPER" and cfg.replyWhispers then
        local _, sender = ...
        if sender and ShouldReplyTo(sender) then
            SendChatMessage(message, "WHISPER", nil, sender)
        end

    elseif event == "CHAT_MSG_BN_WHISPER" and cfg.replyBNetWhispers then
        local _, _, _, _, _, _, _, _, _, _, _, _, presenceID = ...
        -- presenceID (arg13) is the BNet friend's account ID
        if presenceID and ShouldReplyTo("bnet:" .. presenceID) then
            BNSendWhisper(presenceID, message)
        end
    end
end)
