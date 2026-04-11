-- Wild: Dungeon Bar
-- Minimalistic draggable bar with ready check, pull timers, and common M+ utilities.
local ADDON_NAME, Wild = ...

local bar
local buttons = {}
local pullTimerTicker

local function GetConfig()
    return Wild.db and Wild.db.dungeonBar
end

local function SavePosition()
    local cfg = GetConfig()
    if not cfg or not bar then return end
    local point, _, relPoint, x, y = bar:GetPoint()
    cfg.position = { point = point, relPoint = relPoint, x = x, y = y }
end

-- ============================================================
-- Pull Timer
-- ============================================================
local function CancelPullTimer()
    if pullTimerTicker then
        pullTimerTicker:Cancel()
        pullTimerTicker = nil
    end
end

local function StartPullTimer(seconds)
    CancelPullTimer()

    -- Use the Blizzard countdown API (BigWigs/DBM hook this when loaded)
    if C_PartyInfo and C_PartyInfo.DoCountdown then
        C_PartyInfo.DoCountdown(seconds)
        return
    end

    -- Fallback: announce in chat if in a group
    if not IsInGroup() then
        print("|cff00ccffWild:|r Pull timer started but you are not in a group.")
        return
    end

    local remaining = seconds
    local channel = IsInRaid() and "RAID_WARNING" or "PARTY"

    SendChatMessage(string.format("Pull in %d seconds!", remaining), channel)
    pullTimerTicker = C_Timer.NewTicker(1, function()
        remaining = remaining - 1
        if remaining <= 0 then
            SendChatMessage("Pull NOW!", channel)
            CancelPullTimer()
        elseif remaining <= 3 then
            SendChatMessage(string.format("Pull in %d...", remaining), channel)
        end
    end, seconds)
end

-- ============================================================
-- Bar Button Factory
-- ============================================================
local function CreateBarButton(parent, text, width, onClick, tooltipText)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, 24)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

    btn.label = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    btn.label:SetPoint("CENTER")
    btn.label:SetText(text)

    btn:SetScript("OnClick", onClick)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.22, 0.22, 0.28, 1)
        local cfg = GetConfig()
        if tooltipText and cfg and cfg.showTooltips then
            GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 6)
            GameTooltip:AddLine(tooltipText, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
        GameTooltip:Hide()
    end)

    table.insert(buttons, btn)
    return btn
end

-- ============================================================
-- Custom Pull Timer Input
-- ============================================================
local function CreateCustomPullInput(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(50, 24)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

    local editBox = CreateFrame("EditBox", nil, frame)
    editBox:SetSize(26, 20)
    editBox:SetPoint("LEFT", 4, 0)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:SetMaxLetters(3)
    editBox:SetFontObject("GameFontNormalSmall")
    editBox:SetJustifyH("CENTER")

    -- Restore saved value
    local cfg = GetConfig()
    local saved = cfg and cfg.customPullSeconds or 10
    editBox:SetText(tostring(saved))

    editBox:SetScript("OnEditFocusLost", function(self)
        local val = tonumber(self:GetText())
        if val and val > 0 and val <= 999 then
            local c = GetConfig()
            if c then c.customPullSeconds = val end
        elseif self:GetText() == "" then
            local c = GetConfig()
            local s = c and c.customPullSeconds or 10
            self:SetText(tostring(s))
        end
    end)
    editBox:SetScript("OnTextChanged", function(self)
        -- live-save when typing
        if self:HasFocus() then
            local val = tonumber(self:GetText())
            if val and val > 0 and val <= 999 then
                local c = GetConfig()
                if c then c.customPullSeconds = val end
            end
        end
    end)

    local goBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    goBtn:SetSize(20, 20)
    goBtn:SetPoint("LEFT", editBox, "RIGHT", 0, 0)
    goBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    goBtn:SetBackdropColor(0.2, 0.5, 0.3, 0.9)

    goBtn.icon = goBtn:CreateTexture(nil, "ARTWORK")
    goBtn.icon:SetSize(14, 14)
    goBtn.icon:SetPoint("CENTER")
    goBtn.icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    goBtn.icon:SetVertexColor(1, 1, 1, 1)

    goBtn:SetScript("OnClick", function()
        local val = tonumber(editBox:GetText())
        if val and val > 0 and val <= 999 then
            local c = GetConfig()
            if c then c.customPullSeconds = val end
            StartPullTimer(val)
            editBox:ClearFocus()
        end
    end)
    goBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.7, 0.4, 1) end)
    goBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.5, 0.3, 0.9) end)

    editBox:SetScript("OnEnterPressed", function(self)
        goBtn:GetScript("OnClick")()
    end)

    frame:SetScript("OnEnter", function(self)
        local cfg = GetConfig()
        if cfg and cfg.showTooltips then
            GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 6)
            GameTooltip:AddLine("Custom pull timer (seconds)", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return frame
end

-- ============================================================
-- Build the bar
-- ============================================================
local function CreateBar()
    if bar then return bar end

    local cfg = GetConfig()
    local presets = cfg and cfg.pullPresets or { 3, 5, 8, 10 }

    local f = CreateFrame("Frame", "WildDungeonBar", UIParent, "BackdropTemplate")
    f:SetHeight(28)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.92)
    f:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    -- Separator helper
    local function AddSeparator(parent, anchor)
        local sep = parent:CreateTexture(nil, "ARTWORK")
        sep:SetSize(1, 18)
        sep:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
        sep:SetColorTexture(0.35, 0.35, 0.4, 0.8)
        return sep
    end

    local pad = 4
    local totalWidth = pad
    local lastAnchor
    local needsSep = false -- tracks whether next section needs a leading separator

    -- Helper: anchor element as the first item or after lastAnchor
    local function AnchorFirst(widget)
        if lastAnchor then
            widget:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
            totalWidth = totalWidth + widget:GetWidth() + 4
        else
            widget:SetPoint("LEFT", f, "LEFT", pad, 0)
            totalWidth = totalWidth + widget:GetWidth()
        end
    end

    -- Helper: insert a separator before a new section when needed
    local function BeginSection()
        if needsSep and lastAnchor then
            local sep = AddSeparator(f, lastAnchor)
            totalWidth = totalWidth + 9
            lastAnchor = sep
        end
        needsSep = true
    end

    -- Ready Check (optional)
    if cfg.showReadyCheck ~= false then
        BeginSection()
        local readyBtn = CreateBarButton(f, "|cff44ff44Ready|r", 48, function()
            if IsInGroup() then
                DoReadyCheck()
            else
                print("|cff00ccffWild:|r You must be in a group to start a ready check.")
            end
        end, "Start a ready check")
        AnchorFirst(readyBtn)
        lastAnchor = readyBtn
    end

    -- Dynamic pull preset buttons
    if #presets > 0 then
        BeginSection()
        for i, seconds in ipairs(presets) do
            local label = string.format("|cffffff00P%d|r", seconds)
            local btnWidth = 32
            local pullBtn = CreateBarButton(f, label, btnWidth, function()
                StartPullTimer(seconds)
            end, string.format("Pull timer: %d seconds", seconds))
            if i == 1 then
                AnchorFirst(pullBtn)
            else
                pullBtn:SetPoint("LEFT", lastAnchor, "RIGHT", 2, 0)
                totalWidth = totalWidth + pullBtn:GetWidth() + 2
            end
            lastAnchor = pullBtn
        end
    end

    -- Custom pull input (optional)
    if cfg.showCustomPull then
        BeginSection()
        local customPull = CreateCustomPullInput(f)
        AnchorFirst(customPull)
        lastAnchor = customPull
    end

    -- Cancel pull (optional)
    if cfg.showCancelPull ~= false then
        BeginSection()
        local cancelBtn = CreateBarButton(f, "|cffff4444Stop|r", 40, function()
            CancelPullTimer()
            -- Cancel via Blizzard countdown API (0 = cancel); BigWigs/DBM hook this
            if C_PartyInfo and C_PartyInfo.DoCountdown then
                C_PartyInfo.DoCountdown(0)
            end
        end, "Cancel pull timer")
        AnchorFirst(cancelBtn)
        lastAnchor = cancelBtn
    end

    -- Disband group (optional)
    if cfg.showDisband then
        BeginSection()
        local disbandBtn = CreateBarButton(f, "|cffff8800Disband|r", 56, function()
            if not IsInGroup() then
                print("|cff00ccffWild:|r You are not in a group.")
                return
            end
            if not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then
                print("|cff00ccffWild:|r You must be the leader or assistant to disband.")
                return
            end
            StaticPopup_Show("WILD_CONFIRM_DISBAND")
        end, "Disband the group or raid")
        AnchorFirst(disbandBtn)
        lastAnchor = disbandBtn
    end

    totalWidth = totalWidth + pad

    f:SetWidth(totalWidth)

    bar = f
    return f
end

-- ============================================================
-- Rebuild the bar (called when presets change in settings)
-- ============================================================
function Wild.RebuildDungeonBar()
    local wasShown = bar and bar:IsShown()
    if bar then
        bar:Hide()
        bar:SetParent(nil)
        bar = nil
        wipe(buttons)
    end
    if wasShown then
        Wild.ShowDungeonBar()
    end
end

-- ============================================================
-- Disband confirmation dialog
-- ============================================================
StaticPopupDialogs["WILD_CONFIRM_DISBAND"] = {
    text = "Are you sure you want to disband the group?",
    button1 = "Disband",
    button2 = "Cancel",
    OnAccept = function()
        if IsInRaid() then
            for i = MAX_RAID_MEMBERS, 1, -1 do
                local name = GetRaidRosterInfo(i)
                if name and not UnitIsUnit("raid" .. i, "player") then
                    UninviteUnit(name)
                end
            end
        else
            for i = MAX_PARTY_MEMBERS, 1, -1 do
                if UnitExists("party" .. i) then
                    UninviteUnit(UnitName("party" .. i))
                end
            end
        end
        LeaveParty()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ============================================================
-- Show / Hide / Toggle
-- ============================================================
function Wild.ShowDungeonBar()
    local cfg = GetConfig()
    if not cfg or not cfg.enabled then return end
    local f = CreateBar()
    local pos = cfg.position
    f:ClearAllPoints()
    if pos then
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
    f:Show()
end

function Wild.HideDungeonBar()
    if bar then bar:Hide() end
end

function Wild.ToggleDungeonBar()
    if bar and bar:IsShown() then
        Wild.HideDungeonBar()
    else
        Wild.ShowDungeonBar()
    end
end

-- ============================================================
-- Auto show/hide in instances if configured
-- ============================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
    local cfg = GetConfig()
    if not cfg or not cfg.enabled then
        if bar then bar:Hide() end
        return
    end

    if cfg.autoShowInInstance then
        local _, instanceType = IsInInstance()
        if instanceType == "party" or instanceType == "raid" then
            Wild.ShowDungeonBar()
        else
            Wild.HideDungeonBar()
        end
    end
end)

-- Slash shortcut
SLASH_WILDDUNGEONBAR1 = "/wbar"
SlashCmdList["WILDDUNGEONBAR"] = function()
    Wild.ToggleDungeonBar()
end
