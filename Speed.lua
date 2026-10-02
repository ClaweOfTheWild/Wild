-- Wild: Draggable movement speed indicator
local ADDON_NAME, Wild = ...

local BASE_RUN_SPEED = 7 -- Yards per second at 100% running speed.
local UPDATE_INTERVAL = 0.1
local ICON_SIZE = 16
local ICON_GAP = 3
local PADDING_X = 4
local PADDING_Y = 2
local speedFrame

local function UpdateText()
    local isGliding, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
    local speed = isGliding and forwardSpeed or GetUnitSpeed("player")
    if issecretvalue and issecretvalue(speed) then
        speedFrame.text:SetText("--")
    else
        local percent = math.floor(speed / BASE_RUN_SPEED * 100 + 0.5)
        speedFrame.text:SetText(percent .. "%")
    end
    speedFrame:SetHeight(
        PADDING_Y * 2 + math.max(ICON_SIZE, math.ceil(speedFrame.text:GetStringHeight()))
    )
end

local function CreateSpeedFrame()
    if speedFrame then return speedFrame end

    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.08, 0.08, 0.10, 0.80)
    f:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)

    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        Wild.db.speed.position = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    f:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        self.elapsed = 0
    end)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(ICON_SIZE, ICON_SIZE)
    f.icon:SetPoint("LEFT", f, "LEFT", PADDING_X, 0)
    f.icon:SetTexture("Interface\\PetBattles\\PetBattle-StatIcons")
    f.icon:SetTexCoord(0, 0.5, 0.5, 1)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("RIGHT", f, "RIGHT", -PADDING_X, 0)
    f.text:SetJustifyH("RIGHT")
    f.text:SetTextColor(1, 1, 1)
    f.text:SetText("8888%")
    f:SetWidth(PADDING_X * 2 + ICON_SIZE + ICON_GAP + math.ceil(f.text:GetStringWidth()))

    -- Skyriding speed changes continuously without a matching event.
    f.elapsed = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < UPDATE_INTERVAL then return end
        self.elapsed = 0
        UpdateText()
    end)

    speedFrame = f
    return f
end

function Wild.UpdateSpeedIndicator()
    local db = Wild.db and Wild.db.speed
    if not db or not db.enabled then
        if speedFrame then speedFrame:Hide() end
        return
    end

    local f = CreateSpeedFrame()
    f:ClearAllPoints()
    local pos = db.position
    if pos then
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -68)
    end
    UpdateText()
    f:Show()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
    Wild.UpdateSpeedIndicator()
end)
