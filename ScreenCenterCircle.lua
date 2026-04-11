-- Wild: Screen Center Circle
-- Draws a smooth circle at the center of the screen.
-- Uses line segments for the ring, with segment count scaled to both
-- circumference and thickness so joints are always sub-pixel.
-- Falls back to a filled circle (masked texture) when the diameter is
-- too small for a visible hole.
local ADDON_NAME, Wild = ...

local TWO_PI = math.pi * 2
local cos, sin, ceil, max = math.cos, math.sin, math.ceil, math.max

local circleFrame
local lines = {}
local lineCount = 0

-- Filled-circle fallback for tiny sizes
local dotTexture, dotMask

local function CreateCircle()
    if circleFrame then return end

    circleFrame = CreateFrame("Frame", "WildScreenCenterCircle", UIParent)
    circleFrame:SetFrameStrata("BACKGROUND")
    circleFrame:SetAllPoints(UIParent)
    circleFrame:SetIgnoreParentAlpha(true)

    -- Solid filled circle used when the ring hole would be invisible
    dotTexture = circleFrame:CreateTexture(nil, "OVERLAY")
    dotTexture:SetColorTexture(1, 1, 1, 1)
    dotMask = circleFrame:CreateMaskTexture()
    dotMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    dotMask:SetAllPoints(dotTexture)
    dotTexture:AddMaskTexture(dotMask)
    dotTexture:Hide()

    circleFrame:Hide()
end

local function GetLine(index)
    if not lines[index] then
        lines[index] = circleFrame:CreateLine(nil, "OVERLAY")
        lines[index]:Hide()
    end
    return lines[index]
end

local function HideLines(from, to)
    for i = from, to do
        lines[i]:Hide()
    end
end

local function UpdateCircle()
    if not circleFrame then return end
    local db = Wild.db
    if not db or not db.screenCenterCircle then
        circleFrame:Hide()
        return
    end

    local size      = db.screenCenterCircleSize or 40
    local thickness = db.screenCenterCircleThickness or 2
    local color     = db.screenCenterCircleColor or { r = 1, g = 1, b = 1, a = 0.7 }
    local offsetX   = db.screenCenterCircleOffsetX or 0
    local offsetY   = db.screenCenterCircleOffsetY or 0
    local radius    = size / 2

    -- When the circle is so small that the inner hole would vanish,
    -- show a smooth filled dot instead of jagged line stubs.
    if size <= thickness * 2 then
        HideLines(1, lineCount)
        lineCount = 0
        local dotSize = max(1, size + thickness)
        dotTexture:ClearAllPoints()
        dotTexture:SetSize(dotSize, dotSize)
        dotTexture:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        dotTexture:SetColorTexture(color.r, color.g, color.b, color.a)
        dotTexture:Show()
        circleFrame:Show()
        return
    end

    dotTexture:Hide()

    -- Segment count must satisfy two constraints for invisible joints:
    --  1) Follow the curve: ~1 segment per 2px of circumference
    --  2) Hide square-cap notches: thicker lines need more segments
    --     (gap ≈ thickness * tan(π/N); gap < 0.5px when N > thickness*7)
    local circumference = TWO_PI * radius
    local numSegments = max(48, ceil(circumference / 2), ceil(thickness * 7))
    local angleStep = TWO_PI / numSegments

    for i = 1, numSegments do
        local a1 = (i - 1) * angleStep
        local a2 = i * angleStep

        local line = GetLine(i)
        line:ClearAllPoints()
        line:SetStartPoint("CENTER", UIParent,
            offsetX + cos(a1) * radius,
            offsetY + sin(a1) * radius)
        line:SetEndPoint("CENTER", UIParent,
            offsetX + cos(a2) * radius,
            offsetY + sin(a2) * radius)
        line:SetThickness(thickness)
        line:SetColorTexture(color.r, color.g, color.b, color.a)
        line:Show()
    end

    HideLines(numSegments + 1, lineCount)
    lineCount = numSegments

    circleFrame:Show()
end

-- Expose update function so settings can call it
Wild.UpdateScreenCenterCircle = UpdateCircle

-- Initialize
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addon)
    if addon ~= ADDON_NAME then return end

    CreateCircle()

    C_Timer.After(0, function()
        UpdateCircle()
    end)

    self:UnregisterEvent("ADDON_LOADED")
end)
