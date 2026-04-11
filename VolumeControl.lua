-- Wild: Volume control mini-button and popup panel
local ADDON_NAME, Wild = ...

local ICON_TEXTURE = 1405819 -- INV_Engineering_SonicEnvironmentEnhancer
local BUTTON_SIZE = 28
local ROW_HEIGHT = 22
local LABEL_WIDTH = 56
local SLIDER_WIDTH = 90
local PCT_WIDTH = 34
local CB_SIZE = 16
local PAD = 6

local CHANNELS = {
    { cvar = "Sound_MasterVolume",  enable = "Sound_EnableAllSound",   label = "Master" },
    { cvar = "Sound_SFXVolume",     enable = "Sound_EnableSFX",        label = "Effects" },
    { cvar = "Sound_MusicVolume",   enable = "Sound_EnableMusic",      label = "Music" },
    { cvar = "Sound_AmbienceVolume", enable = "Sound_EnableAmbience",  label = "Ambience" },
    { cvar = "Sound_DialogVolume",  enable = "Sound_EnableDialog",     label = "Dialog" },
}

local button, panel

-- ============================================================
-- Panel
-- ============================================================

local function CreatePanel()
    local panelW = PAD + CB_SIZE + 2 + LABEL_WIDTH + SLIDER_WIDTH + 4 + PCT_WIDTH + PAD
    local panelH = PAD + #CHANNELS * ROW_HEIGHT + PAD

    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(panelW, panelH)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.08, 0.08, 0.10, 0.92)
    f:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)

    f.rows = {}

    for i, ch in ipairs(CHANNELS) do
        local yOff = -PAD - (i - 1) * ROW_HEIGHT
        local xOff = PAD

        -- Enable checkbox
        local cb = CreateFrame("CheckButton", nil, f)
        cb:SetSize(CB_SIZE, CB_SIZE)
        cb:SetPoint("TOPLEFT", xOff, yOff - (ROW_HEIGHT - CB_SIZE) / 2)

        cb.tex = cb:CreateTexture(nil, "ARTWORK")
        cb.tex:SetAllPoints()
        cb.tex:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")

        cb.check = cb:CreateTexture(nil, "OVERLAY")
        cb.check:SetAllPoints()
        cb.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")

        cb:SetScript("OnClick", function(self)
            local enabled = GetCVar(ch.enable) == "1"
            SetCVar(ch.enable, enabled and "0" or "1")
            self.check:SetShown(not enabled)
        end)
        xOff = xOff + CB_SIZE + 2

        -- Channel label
        local label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", xOff, yOff - (ROW_HEIGHT - 10) / 2)
        label:SetWidth(LABEL_WIDTH)
        label:SetJustifyH("LEFT")
        label:SetText(ch.label)
        xOff = xOff + LABEL_WIDTH

        -- Slider
        local slider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", xOff, yOff - (ROW_HEIGHT - 14) / 2)
        slider:SetWidth(SLIDER_WIDTH)
        slider:SetHeight(14)
        slider:SetMinMaxValues(0, 1)
        slider:SetValueStep(0.01)
        slider:SetObeyStepOnDrag(true)
        slider.Low:SetText("")
        slider.High:SetText("")
        xOff = xOff + SLIDER_WIDTH + 4

        -- Percentage
        local pct = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        pct:SetPoint("TOPLEFT", xOff, yOff - (ROW_HEIGHT - 10) / 2)
        pct:SetWidth(PCT_WIDTH)
        pct:SetJustifyH("RIGHT")

        slider:SetScript("OnValueChanged", function(self, value)
            SetCVar(ch.cvar, value)
            pct:SetText(math.floor(value * 100 + 0.5) .. "%")
        end)

        f.rows[i] = { slider = slider, pct = pct, cb = cb, cvar = ch.cvar, enable = ch.enable }
    end

    f:SetScript("OnShow", function(self)
        for _, r in ipairs(self.rows) do
            local val = tonumber(GetCVar(r.cvar)) or 1
            r.slider:SetValue(val)
            r.pct:SetText(math.floor(val * 100 + 0.5) .. "%")
            r.cb.check:SetShown(GetCVar(r.enable) == "1")
        end
    end)

    f:Hide()
    return f
end

-- ============================================================
-- Draggable speaker button
-- ============================================================

local function CreateButton()
    local b = CreateFrame("Button", nil, UIParent)
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    b:SetFrameStrata("HIGH")
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ICON_TEXTURE)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local highlight = b:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(ICON_TEXTURE)
    highlight:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    highlight:SetAlpha(0.3)

    local dragged = false

    b:SetScript("OnDragStart", function(self)
        dragged = true
        self:StartMoving()
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        if Wild.db then
            Wild.db.volumeControl.buttonPos = { point, "UIParent", relPoint, x, y }
        end
    end)

    b:SetScript("OnClick", function(self)
        if dragged then
            dragged = false
            return
        end
        if not panel then
            panel = CreatePanel()
        end
        if panel:IsShown() then
            panel:Hide()
        else
            panel:ClearAllPoints()
            panel:SetPoint("TOPRIGHT", self, "BOTTOMLEFT", 0, 0)
            panel:Show()
        end
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Wild Volume")
        GameTooltip:AddLine("|cff888888Click to toggle volume controls.\nDrag to move.|r")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:RegisterForClicks("LeftButtonUp")

    return b
end

-- ============================================================
-- Public API
-- ============================================================

function Wild.ShowVolumeButton()
    if not button then
        button = CreateButton()
    end
    local pos = Wild.db and Wild.db.volumeControl and Wild.db.volumeControl.buttonPos
    button:ClearAllPoints()
    if pos then
        button:SetPoint(pos[1], pos[2], pos[3], pos[4], pos[5])
    else
        button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
    end
    button:Show()
end

function Wild.HideVolumeButton()
    if button then
        button:Hide()
    end
    if panel then
        panel:Hide()
    end
end

function Wild.ToggleVolumeButton()
    if button and button:IsShown() then
        Wild.HideVolumeButton()
    else
        Wild.ShowVolumeButton()
    end
end

function Wild.UpdateVolumeControl()
    if Wild.db and Wild.db.volumeControl and Wild.db.volumeControl.enabled then
        Wild.ShowVolumeButton()
    else
        Wild.HideVolumeButton()
    end
end

-- ============================================================
-- Auto-show on login if enabled
-- ============================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    Wild.UpdateVolumeControl()
end)
