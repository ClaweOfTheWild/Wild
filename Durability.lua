-- Wild: Durability percentage overlay on equipped and bag items
local ADDON_NAME, Wild = ...

local EQUIPPED_SLOTS = {
    1,  -- Head
    3,  -- Shoulder
    5,  -- Chest
    6,  -- Waist
    7,  -- Legs
    8,  -- Feet
    9,  -- Wrist
    10, -- Hands
    16, -- Main Hand
    17, -- Off Hand
}

local equippedTexts = {}
local bagTexts = {}
local totalFrame

-- ============================================================
-- Helpers
-- ============================================================

local function GetDurabilityPercent(current, maximum)
    if not maximum or maximum == 0 then return nil end
    return math.floor((current / maximum) * 100 + 0.5)
end

local function ColorForPercent(pct)
    if pct <= 25 then
        return 1, 0.2, 0.2
    elseif pct <= 50 then
        return 1, 0.6, 0
    else
        return 0.2, 1, 0.2
    end
end

-- ============================================================
-- Equipped items overlay
-- ============================================================

local function UpdateEquippedSlot(slotID)
    local current, maximum = GetInventoryItemDurability(slotID)
    local fs = equippedTexts[slotID]
    if not current or not maximum or maximum == 0 then
        if fs then fs:Hide() end
        return
    end

    local pct = GetDurabilityPercent(current, maximum)
    if not pct then
        if fs then fs:Hide() end
        return
    end

    -- Find the slot frame on the character panel
    local slotName = ({
        [1]  = "CharacterHeadSlot",
        [3]  = "CharacterShoulderSlot",
        [5]  = "CharacterChestSlot",
        [6]  = "CharacterWaistSlot",
        [7]  = "CharacterLegsSlot",
        [8]  = "CharacterFeetSlot",
        [9]  = "CharacterWristSlot",
        [10] = "CharacterHandsSlot",
        [16] = "CharacterMainHandSlot",
        [17] = "CharacterSecondaryHandSlot",
    })[slotID]

    local slotFrame = slotName and _G[slotName]
    if not slotFrame then
        if fs then fs:Hide() end
        return
    end

    if not fs then
        fs = slotFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        fs:SetPoint("BOTTOM", slotFrame, "BOTTOM", 0, 2)
        equippedTexts[slotID] = fs
    end

    local r, g, b = ColorForPercent(pct)
    fs:SetTextColor(r, g, b)
    fs:SetText(pct .. "%")
    fs:Show()
end

local function UpdateAllEquipped()
    local db = Wild.db
    if not db or not db.durability or not db.durability.showEquipped then
        for _, fs in pairs(equippedTexts) do
            fs:Hide()
        end
        return
    end
    for _, slotID in ipairs(EQUIPPED_SLOTS) do
        UpdateEquippedSlot(slotID)
    end
end

local function HideAllEquipped()
    for _, fs in pairs(equippedTexts) do
        fs:Hide()
    end
end

-- ============================================================
-- Total durability overlay (draggable)
-- ============================================================

local function CreateTotalFrame()
    if totalFrame then return totalFrame end

    local f = CreateFrame("Frame", "WildDurabilityTotal", UIParent, "BackdropTemplate")
    f:SetSize(70, 24)
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
        if Wild.db and Wild.db.durability then
            Wild.db.durability.totalPosition = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("CENTER")

    totalFrame = f
    return f
end

local function UpdateTotal()
    local db = Wild.db
    if not db or not db.durability or not db.durability.showEquippedTotal then
        if totalFrame then totalFrame:Hide() end
        return
    end

    local f = CreateTotalFrame()

    local totalCurrent, totalMaximum = 0, 0
    for _, slotID in ipairs(EQUIPPED_SLOTS) do
        local current, maximum = GetInventoryItemDurability(slotID)
        if current and maximum and maximum > 0 then
            totalCurrent = totalCurrent + current
            totalMaximum = totalMaximum + maximum
        end
    end

    if totalMaximum == 0 then
        f:Hide()
        return
    end

    local pct = GetDurabilityPercent(totalCurrent, totalMaximum)
    if not pct then
        f:Hide()
        return
    end

    local r, g, b = ColorForPercent(pct)
    f.text:SetTextColor(r, g, b)
    f.text:SetText(pct .. "%")

    -- Restore saved position
    f:ClearAllPoints()
    local pos = db.durability.totalPosition
    if pos then
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -40)
    end

    f:Show()
end

-- ============================================================
-- Bag items overlay
-- ============================================================

local function UpdateBagSlot(bag, slot)
    local key = bag .. ":" .. slot
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local fs = bagTexts[key]

    if not info or not info.hyperlink then
        if fs then fs:Hide() end
        return
    end

    local durCurrent, durMax = C_Container.GetContainerItemDurability(bag, slot)
    if not durCurrent or not durMax or durMax == 0 then
        if fs then fs:Hide() end
        return
    end

    local pct = GetDurabilityPercent(durCurrent, durMax)
    if not pct then
        if fs then fs:Hide() end
        return
    end

    -- Find the bag slot button
    local button
    if ContainerFrameUtil_GetItemButtonAndContainer then
        button = ContainerFrameUtil_GetItemButtonAndContainer(bag, slot)
    end
    if not button then
        -- Fallback: try the combined bag frame item buttons
        local bagFrameName = "ContainerFrame" .. (bag + 1)
        local bagFrame = _G[bagFrameName]
        if bagFrame then
            local itemName = bagFrameName .. "Item" .. slot
            button = _G[itemName]
        end
    end

    if not button then
        if fs then fs:Hide() end
        return
    end

    if not fs then
        fs = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        fs:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
        bagTexts[key] = fs
    end

    local r, g, b = ColorForPercent(pct)
    fs:SetTextColor(r, g, b)
    fs:SetText(pct .. "%")
    fs:Show()
end

local function UpdateAllBags()
    local db = Wild.db
    if not db or not db.durability or not db.durability.showBags then
        for _, fs in pairs(bagTexts) do
            fs:Hide()
        end
        return
    end

    -- Hide existing texts first (slots may have shifted)
    for _, fs in pairs(bagTexts) do
        fs:Hide()
    end

    local bags = Wild.GetPlayerBags and Wild.GetPlayerBags() or { 0, 1, 2, 3, 4 }
    for _, bag in ipairs(bags) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            UpdateBagSlot(bag, slot)
        end
    end
end

local function HideAllBags()
    for _, fs in pairs(bagTexts) do
        fs:Hide()
    end
end

-- ============================================================
-- Event handling
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        -- Hook the character frame
        if CharacterFrame then
            CharacterFrame:HookScript("OnShow", function()
                UpdateAllEquipped()
                UpdateTotal()
            end)
            CharacterFrame:HookScript("OnHide", function()
                HideAllEquipped()
            end)
        end

        -- Listen for durability changes
        self:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        return
    end

    if event == "UPDATE_INVENTORY_DURABILITY" or event == "PLAYER_EQUIPMENT_CHANGED" then
        if CharacterFrame and CharacterFrame:IsShown() then
            UpdateAllEquipped()
        end
        UpdateTotal()
    end

    if event == "UPDATE_INVENTORY_DURABILITY" or event == "BAG_UPDATE_DELAYED" then
        UpdateAllBags()
    end
end)

-- ============================================================
-- Public API
-- ============================================================

function Wild.UpdateDurabilityOverlays()
    if CharacterFrame and CharacterFrame:IsShown() then
        UpdateAllEquipped()
    else
        HideAllEquipped()
    end
    UpdateTotal()
    UpdateAllBags()
end
