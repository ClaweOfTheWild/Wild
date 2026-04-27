-- Wild: LFG enhancements
-- Quick-apply, auto-confirm role, auto-accept queue, and result filtering for Premade Groups.
local ADDON_NAME, Wild = ...

local function GetConfig()
    return Wild.db and Wild.db.lfg
end

local function SetupQuickApplyHooks()
    -- Hook each search entry as Blizzard creates/updates them
    hooksecurefunc("LFGListSearchEntry_Update", function(entry)
        if entry.__wildHooked then return end
        entry.__wildHooked = true

        entry:HookScript("OnClick", function(self, button)
            local cfg = GetConfig()
            if not cfg or not cfg.quickApply then return end
            if button ~= "LeftButton" then return end
            if not self.resultID then return end

            -- Only apply if solo or group leader
            if IsInGroup() and not UnitIsGroupLeader("player") then return end

            local panel = LFGListFrame.SearchPanel
            if LFGListSearchPanelUtil_CanSelectResult(self.resultID) and panel.SignUpButton:IsEnabled() then
                if panel.selectedResult ~= self.resultID then
                    LFGListSearchPanel_SelectResult(panel, self.resultID)
                end
                LFGListSearchPanel_SignUp(panel)
            end
        end)
    end)

    -- Auto-confirm the application dialog
    LFGListApplicationDialog:HookScript("OnShow", function(self)
        local cfg = GetConfig()
        if not cfg or not cfg.quickApply then return end
        if self.SignUpButton:IsEnabled() then
            self.SignUpButton:Click()
        end
    end)
end

local function SetupAutoConfirmRole()
    -- AcceptInvite() is a protected function, so we cannot Click() the button
    -- directly from addon code. Instead, bind ENTER to the accept button while
    -- the dialog is visible so a single keypress confirms it instantly.
    local bindingOwner = CreateFrame("Frame")

    hooksecurefunc("LFGListInviteDialog_Show", function(dialog)
        local cfg = GetConfig()
        if not cfg or not cfg.autoConfirmRole then return end
        if dialog and dialog.AcceptButton then
            SetOverrideBindingClick(bindingOwner, true, "ENTER", dialog.AcceptButton:GetName() or "LFGListInviteDialogAcceptButton")
        end
    end)

    local function ClearBindings()
        ClearOverrideBindings(bindingOwner)
    end

    if LFGListInviteDialog then
        LFGListInviteDialog:HookScript("OnHide", ClearBindings)
    else
        -- Fallback: clear when the frame loads
        hooksecurefunc("LFGListInviteDialog_Hide", function()
            ClearBindings()
        end)
    end
end

local function SetupAutoAcceptRoleCheck()
    -- Auto-accept the role check popup when someone in the group queues
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
    frame:SetScript("OnEvent", function()
        local cfg = GetConfig()
        if not cfg or not cfg.autoAcceptRoleCheck then return end
        -- Accept with the currently selected role
        CompleteLFGRoleCheck(true)
    end)
end

-- ============================================================
-- Party Keystone Tracking (AngryKeystones protocol compatible)
-- ============================================================
local AK_PREFIX = "AngryKeystones"
local AK_SCHED = "Schedule|"
local partyKeys = {}   -- [shortName] = { mapID = number, level = number }
local keystoneRefreshCallbacks = {}

local function GetOwnKey()
    if not C_MythicPlus then return nil, nil end
    return C_MythicPlus.GetOwnedKeystoneChallengeMapID(),
           C_MythicPlus.GetOwnedKeystoneLevel()
end

local function SendOwnKeystoneComm()
    if not IsInGroup() then return end
    local mapID, level = GetOwnKey()
    local payload
    if mapID and mapID > 0 and level then
        payload = AK_SCHED .. mapID .. ":" .. level
    else
        payload = AK_SCHED .. "0"
    end
    local chan = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
    C_ChatInfo.SendAddonMessage(AK_PREFIX, payload, chan)
end

local function RequestPartyKeystones()
    if not IsInGroup() then return end
    local chan = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
    C_ChatInfo.SendAddonMessage(AK_PREFIX, AK_SCHED .. "request", chan)
end

local function FireKeystoneRefresh()
    for _, cb in ipairs(keystoneRefreshCallbacks) do cb() end
end

local function SetupKeystoneTracking()
    C_ChatInfo.RegisterAddonMessagePrefix(AK_PREFIX)
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    frame:RegisterEvent("CHALLENGE_MODE_START")

    local reqPending = false

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            local prefix, message, _, sender = ...
            if prefix ~= AK_PREFIX then return end
            local schedLen = #AK_SCHED
            if message:sub(1, schedLen) ~= AK_SCHED then return end
            local data = message:sub(schedLen + 1)
            local name = Ambiguate(sender, "short")
            if name == UnitName("player") then return end

            if data == "request" then
                SendOwnKeystoneComm()
            elseif data == "0" then
                partyKeys[name] = nil
                FireKeystoneRefresh()
            else
                local m, l = data:match("^(%d+):(%d+)$")
                if m and l then
                    partyKeys[name] = { mapID = tonumber(m), level = tonumber(l) }
                    FireKeystoneRefresh()
                end
            end

        elseif event == "GROUP_ROSTER_UPDATE" then
            if IsInGroup() then
                local valid = {}
                for i = 1, GetNumGroupMembers() - 1 do
                    local n = UnitName("party" .. i)
                    if n then valid[n] = true end
                end
                for n in pairs(partyKeys) do
                    if not valid[n] then partyKeys[n] = nil end
                end
            else
                wipe(partyKeys)
            end
            if not reqPending then
                reqPending = true
                C_Timer.After(1, function()
                    reqPending = false
                    RequestPartyKeystones()
                    FireKeystoneRefresh()
                end)
            end

        else -- CHALLENGE_MODE_COMPLETED / START
            C_Timer.After(2, function()
                SendOwnKeystoneComm()
                RequestPartyKeystones()
                FireKeystoneRefresh()
            end)
        end
    end)

    C_Timer.After(3, function()
        SendOwnKeystoneComm()
        RequestPartyKeystones()
    end)
    C_Timer.NewTicker(60, SendOwnKeystoneComm)
end

-- ============================================================
-- Keystone Overview Panel (attached to the LFG frame)
-- ============================================================
local ANCHOR_POINTS = {
    RIGHT      = { from = "TOPLEFT",     to = "TOPRIGHT",    x =  4, y = 0 },
    LEFT       = { from = "TOPRIGHT",    to = "TOPLEFT",     x = -4, y = 0 },
    TOPLEFT    = { from = "BOTTOMLEFT",  to = "TOPLEFT",     x = 0,  y = -4 },
    TOPRIGHT   = { from = "BOTTOMRIGHT", to = "TOPRIGHT",    x = 0,  y = -4 },
    BOTTOMLEFT = { from = "TOPLEFT",     to = "BOTTOMLEFT",  x = 0,  y =  4 },
    BOTTOMRIGHT= { from = "TOPRIGHT",    to = "BOTTOMRIGHT",  x = 0,  y =  4 },
}
local PANEL_WIDTH = 200

local function SetupKeystonePanel()
    local parent = LFGListFrame
    if not parent then return end

    local container = CreateFrame("Frame", "WildKeystonePanel", parent, "BackdropTemplate")
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    container:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
    container:SetBackdropBorderColor(0.20, 0.20, 0.25, 1)
    container:SetWidth(PANEL_WIDTH)
    container:SetFrameStrata("DIALOG")
    container:Hide()

    local titleLabel = container:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    titleLabel:SetPoint("TOPLEFT", 8, -6)
    titleLabel:SetText("|cff00ccffParty Keys|r")

    local MAX_ROWS = 5
    local rows = {}

    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, container, "BackdropTemplate")
        row:SetHeight(20)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        row:SetBackdropColor(0.12, 0.12, 0.18, 0.9)
        row:SetBackdropBorderColor(0.25, 0.25, 0.35, 1)

        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetPoint("RIGHT", -8, 0)
        row.label:SetJustifyH("LEFT")

        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.20, 0.20, 0.30, 1)
            if self.tipTitle then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.tipTitle)
                if self.tipBody then
                    GameTooltip:AddLine(self.tipBody, 1, 1, 1, true)
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.12, 0.12, 0.18, 0.9)
            GameTooltip:Hide()
        end)

        if i == 1 then
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -22)
            row:SetPoint("TOPRIGHT", container, "TOPRIGHT", -4, -22)
        else
            row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -2)
            row:SetPoint("TOPRIGHT", rows[i - 1], "BOTTOMRIGHT", 0, -2)
        end

        row:Hide()
        rows[i] = row
    end

    local function ApplyAnchor()
        container:ClearAllPoints()
        local cfg = GetConfig()
        local key = cfg and cfg.keystoneAnchor or "RIGHT"
        local a = ANCHOR_POINTS[key] or ANCHOR_POINTS.RIGHT
        container:SetPoint(a.from, parent, a.to, a.x, a.y)
    end

    local function RefreshPanel()
        local cfg = GetConfig()
        if not cfg or cfg.keystoneButtons == false then
            container:Hide()
            return
        end

        local allKeys = {}

        -- Own key
        local ownMapID, ownLevel = GetOwnKey()
        if ownMapID and ownMapID > 0 and ownLevel and ownLevel > 0 then
            local mn = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo(ownMapID)
            if mn then
                table.insert(allKeys, {
                    player = UnitName("player"),
                    mapID = ownMapID,
                    level = ownLevel,
                    mapName = mn,
                    isOwn = true,
                })
            end
        end

        -- Party keys
        for pn, ki in pairs(partyKeys) do
            if ki.mapID and ki.level then
                local mn = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo(ki.mapID)
                if mn then
                    table.insert(allKeys, {
                        player = pn,
                        mapID = ki.mapID,
                        level = ki.level,
                        mapName = mn,
                    })
                end
            end
        end

        -- Sort by level descending, then name
        table.sort(allKeys, function(a, b)
            if a.level ~= b.level then return a.level > b.level end
            return a.mapName < b.mapName
        end)

        local shown = 0
        for i, kd in ipairs(allKeys) do
            if i > MAX_ROWS then break end
            local row = rows[i]
            local nameColor = kd.isOwn and "|cff44ff44" or "|cffaaaaaa"
            row.label:SetText(string.format(
                "|cffffffff+%d|r %s %s(%s)|r",
                kd.level, kd.mapName, nameColor, kd.player
            ))
            row.tipTitle = string.format("+%d %s", kd.level, kd.mapName)
            row.tipBody = "Key held by: " .. kd.player
            row:Show()
            shown = shown + 1
        end

        for i = shown + 1, MAX_ROWS do
            rows[i]:Hide()
        end

        if shown > 0 then
            container:SetHeight(26 + shown * 22)
            ApplyAnchor()
            container:Show()
        else
            container:Hide()
        end
    end

    -- Expose for Settings UI
    Wild.__keystonePanelRefresh = RefreshPanel
    Wild.__keystonePanelApplyAnchor = ApplyAnchor

    table.insert(keystoneRefreshCallbacks, RefreshPanel)

    parent:HookScript("OnShow", function()
        C_Timer.After(0.2, RefreshPanel)
    end)
    parent:HookScript("OnHide", function()
        container:Hide()
    end)

    C_Timer.After(0.5, RefreshPanel)
end



-- Keystone tracking works independently of Blizzard_LFGList
SetupKeystoneTracking()

-- Wait for the LFG frame to be loaded (it's load-on-demand)
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, arg1)
    if arg1 == "Blizzard_LFGList" or (LFGListFrame and arg1 == ADDON_NAME) then
        if LFGListFrame then
            SetupQuickApplyHooks()
            SetupAutoConfirmRole()

            SetupKeystonePanel()
            self:UnregisterEvent("ADDON_LOADED")
        end
    end
end)

-- Auto-accept role check works independently of Blizzard_LFGList
SetupAutoAcceptRoleCheck()
