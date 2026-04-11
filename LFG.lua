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
-- Keystone -> LFG Activity Mapping
-- ============================================================
local mapToActivityCache = {}

local function FindMythicPlusActivity(challengeMapID)
    if mapToActivityCache[challengeMapID] then
        return mapToActivityCache[challengeMapID]
    end
    local mapName = C_ChallengeMode.GetMapUIInfo(challengeMapID)
    if not mapName then return nil end

    local activities = C_LFGList.GetAvailableActivities(2) -- 2 = Dungeons
    if not activities then return nil end

    -- Exact match first
    for _, id in ipairs(activities) do
        local info = C_LFGList.GetActivityInfoTable(id)
        if info and info.isMythicPlusActivity then
            if info.fullName == mapName or info.shortName == mapName then
                mapToActivityCache[challengeMapID] = id
                return id
            end
        end
    end
    -- Fuzzy substring fallback
    for _, id in ipairs(activities) do
        local info = C_LFGList.GetActivityInfoTable(id)
        if info and info.isMythicPlusActivity and info.fullName then
            if info.fullName:find(mapName, 1, true) or mapName:find(info.fullName, 1, true) then
                mapToActivityCache[challengeMapID] = id
                return id
            end
        end
    end
    return nil
end

-- ============================================================
-- Quick-List Keystone Buttons (on SearchPanel)
-- ============================================================
local function SetupKeystoneQuickList()
    local searchPanel = LFGListFrame.SearchPanel
    if not searchPanel then return end

    local container = CreateFrame("Frame", "WildKeystoneQuickList", searchPanel, "BackdropTemplate")
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    container:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
    container:SetBackdropBorderColor(0.20, 0.20, 0.25, 1)
    container:Hide()

    local titleLabel = container:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    titleLabel:SetPoint("TOPLEFT", 8, -6)
    titleLabel:SetText("|cff00ccffParty Keys|r")

    -- Anchor above the bottom action buttons
    container:SetPoint("BOTTOMLEFT", searchPanel, "BOTTOMLEFT", 1, 26)
    container:SetPoint("BOTTOMRIGHT", searchPanel, "BOTTOMRIGHT", -1, 26)

    local MAX_BUTTONS = 5
    local buttons = {}

    for i = 1, MAX_BUTTONS do
        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetHeight(22)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.12, 0.12, 0.18, 0.9)
        btn:SetBackdropBorderColor(0.25, 0.25, 0.35, 1)

        btn.label = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        btn.label:SetPoint("LEFT", 8, 0)
        btn.label:SetPoint("RIGHT", -8, 0)
        btn.label:SetJustifyH("LEFT")

        btn:SetScript("OnEnter", function(self)
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
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.12, 0.12, 0.18, 0.9)
            GameTooltip:Hide()
        end)

        if i == 1 then
            btn:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -22)
            btn:SetPoint("TOPRIGHT", container, "TOPRIGHT", -4, -22)
        else
            btn:SetPoint("TOPLEFT", buttons[i - 1], "BOTTOMLEFT", 0, -2)
            btn:SetPoint("TOPRIGHT", buttons[i - 1], "BOTTOMRIGHT", 0, -2)
        end

        btn:Hide()
        buttons[i] = btn
    end

    local function NavigateToCreateListing(challengeMapID, keystoneLevel)
        local activityID = FindMythicPlusActivity(challengeMapID)
        local mapName = C_ChallengeMode.GetMapUIInfo(challengeMapID) or "Unknown"

        if not activityID then
            print("|cff00ccffWild:|r No M+ activity found for " .. mapName .. ".")
            return
        end

        local entryCreation = LFGListFrame.EntryCreation
        if not entryCreation then return end

        -- Navigate to entry creation panel
        if LFGListEntryCreation_Show then
            pcall(LFGListEntryCreation_Show, entryCreation, LFGListFrame.baseFilters, 2)
        else
            LFGListFrame_SetActivePanel(LFGListFrame, entryCreation)
        end

        -- Select activity + fill name after frame settles
        C_Timer.After(0.05, function()
            if LFGListEntryCreation_Select then
                pcall(LFGListEntryCreation_Select, entryCreation, nil, nil, activityID)
            end

            C_Timer.After(0.05, function()
                local nameBox = entryCreation.Name
                if nameBox then
                    if type(nameBox.SetText) == "function" then
                        nameBox:SetText("+" .. keystoneLevel .. " " .. mapName)
                    elseif nameBox.EditBox and type(nameBox.EditBox.SetText) == "function" then
                        nameBox.EditBox:SetText("+" .. keystoneLevel .. " " .. mapName)
                    end
                end
            end)
        end)
    end

    local function RefreshButtons()
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
            if i > MAX_BUTTONS then break end
            local btn = buttons[i]
            local nameColor = kd.isOwn and "|cff44ff44" or "|cffaaaaaa"
            btn.label:SetText(string.format(
                "|cffffffff+%d|r %s %s(%s)|r",
                kd.level, kd.mapName, nameColor, kd.player
            ))
            btn.tipTitle = string.format("+%d %s", kd.level, kd.mapName)
            btn.tipBody = "Click to create a group listing.\nKey held by: " .. kd.player
            btn.challengeMapID = kd.mapID
            btn.keystoneLevel = kd.level
            btn:SetScript("OnClick", function(self)
                NavigateToCreateListing(self.challengeMapID, self.keystoneLevel)
            end)
            btn:Show()
            shown = shown + 1
        end

        for i = shown + 1, MAX_BUTTONS do
            buttons[i]:Hide()
        end

        if shown > 0 then
            container:SetHeight(26 + shown * 24)
            container:Show()
        else
            container:Hide()
        end
    end

    table.insert(keystoneRefreshCallbacks, RefreshButtons)

    searchPanel:HookScript("OnShow", function()
        C_Timer.After(0.2, RefreshButtons)
    end)

    C_Timer.After(0.5, RefreshButtons)
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

            SetupKeystoneQuickList()
            self:UnregisterEvent("ADDON_LOADED")
        end
    end
end)

-- Auto-accept role check works independently of Blizzard_LFGList
SetupAutoAcceptRoleCheck()
