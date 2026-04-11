-- Wild: Darkmoon Faire profession helper
-- Shows a shopping list of items to buy from trade goods vendors before entering
-- the faire, when the player is in a staging area during the Darkmoon Faire event.
local ADDON_NAME, Wild = ...

-- ============================================================
-- Darkmoon Faire map IDs (staging areas + the isle itself)
-- ============================================================
local DARKMOON_MAPS = {
    [37]  = true,   -- Elwynn Forest (Alliance staging area)
    [7]   = true,   -- Mulgore (Horde staging area)
    [407] = true,   -- Darkmoon Island
    [408] = true,   -- Darkmoon Island (sub-zone)
}

-- ============================================================
-- Profession skill line IDs → quest data
-- Each entry: { questID, questName, itemsToBuy (or nil if nothing needed) }
-- itemsToBuy entries: { itemName, source }
-- ============================================================
local PROFESSION_QUESTS = {
    -- Crafting professions
    [171] = { -- Alchemy
        quest = "A Fizzy Fusion",
        questID = 29506,
        items = {
            { name = "Moonberry Juice", itemID = 1645, count = 5, source = "Innkeeper" },
            { name = "Fizzy Faire Drink", itemID = 19299, count = 5, source = "Sylannia" },
        },
    },
    [164] = { -- Blacksmithing
        quest = "Baby Needs Two Pair of Shoes",
        questID = 29508,
    },
    [333] = { -- Enchanting
        quest = "Putting Trash to Good Use",
        questID = 29510,
    },
    [202] = { -- Engineering
        quest = "Talkin' Tonks",
        questID = 29511,
    },
    [182] = { -- Herbalism
        quest = "Herbs for Healing",
        questID = 29514,
    },
    [773] = { -- Inscription
        quest = "Writing the Future",
        questID = 29515,
        items = {
            { name = "Light Parchment", itemID = 39354, count = 5, source = "Trade Goods" },
        },
    },
    [755] = { -- Jewelcrafting
        quest = "Keeping the Faire Sparkling",
        questID = 29516,
    },
    [165] = { -- Leatherworking
        quest = "Eyes on the Prizes",
        questID = 29517,
        items = {
            { name = "Shiny Bauble", itemID = 6529, count = 10, source = "Trade Goods" },
            { name = "Coarse Thread", itemID = 2320, count = 5, source = "Trade Goods" },
            { name = "Blue Dye", itemID = 6260, count = 5, source = "Trade Goods" },
        },
    },
    [186] = { -- Mining
        quest = "Rearm, Reuse, Recycle",
        questID = 29518,
    },
    [393] = { -- Skinning
        quest = "Tan My Hide",
        questID = 29519,
    },
    [197] = { -- Tailoring
        quest = "Banners, Banners Everywhere!",
        questID = 29520,
        items = {
            { name = "Coarse Thread", itemID = 2320, count = 1, source = "Trade Goods" },
            { name = "Red Dye", itemID = 2604, count = 1, source = "Trade Goods" },
            { name = "Blue Dye", itemID = 6260, count = 1, source = "Trade Goods" },
        },
    },
    -- Secondary professions
    [185] = { -- Cooking
        quest = "Putting the Crunch in the Frog",
        questID = 29509,
        items = {
            { name = "Simple Flour", itemID = 30817, count = 5, source = "Trade Goods" },
        },
    },
    [356] = { -- Fishing
        quest = "Spoilin' for Salty Sea Dogs",
        questID = 29513,
    },
    [794] = { -- Archaeology
        quest = "Fun for the Little Ones",
        questID = 29507,
        items = {
            { name = "Fossil Fragment", itemID = 108439, count = 15, source = "Archaeology skill" },
        },
    },
}

-- ============================================================
-- Config helper
-- ============================================================
local function GetConfig()
    return Wild.db and Wild.db.darkmoonFaire
end

-- ============================================================
-- Count how many of a given item (by itemID) the player has in bags
-- ============================================================
local DMF_BAGS = { BACKPACK_CONTAINER }
for i = 1, NUM_BAG_SLOTS do DMF_BAGS[#DMF_BAGS + 1] = i end
if Enum.BagIndex.ReagentBag then DMF_BAGS[#DMF_BAGS + 1] = Enum.BagIndex.ReagentBag end

local function CountItemInBags(targetItemID)
    local total = 0
    for _, bag in ipairs(DMF_BAGS) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == targetItemID then
                total = total + (info.stackCount or 1)
            end
        end
    end
    return total
end

-- ============================================================
-- Detect if the Darkmoon Faire world event is currently active
-- ============================================================
local function IsDarkmoonFaireActive()
    local currentDate = C_DateAndTime.GetCurrentCalendarTime()
    C_Calendar.SetAbsMonth(currentDate.month, currentDate.year)
    local numEvents = C_Calendar.GetNumDayEvents(0, currentDate.monthDay)
    for i = 1, numEvents do
        local event = C_Calendar.GetDayEvent(0, currentDate.monthDay, i)
        if event and event.calendarType == "HOLIDAY" and event.title and event.title:find("Darkmoon Faire") then
            return true
        end
    end
    return false
end

-- ============================================================
-- Detect if player is in a Darkmoon Faire area
-- ============================================================
local function IsInDarkmoonArea()
    local mapID = C_Map.GetBestMapForUnit("player")
    return mapID and DARKMOON_MAPS[mapID]
end

-- ============================================================
-- Get character professions and their skill line IDs
-- ============================================================
local function GetCharacterProfessions()
    local professions = {}
    local prof1, prof2, archaeology, fishing, cooking = GetProfessions()
    local indices = { prof1, prof2, archaeology, fishing, cooking }
    for _, idx in ipairs(indices) do
        if idx then
            local name, _, _, _, _, _, skillLineID = GetProfessionInfo(idx)
            if skillLineID then
                professions[#professions + 1] = { name = name, skillLineID = skillLineID }
            end
        end
    end
    return professions
end

-- ============================================================
-- Build the shopping list: items the player needs to buy
-- ============================================================
local function BuildShoppingList()
    local professions = GetCharacterProfessions()
    local needItems = {}
    local noItems = {}

    for _, prof in ipairs(professions) do
        local data = PROFESSION_QUESTS[prof.skillLineID]
        if data then
            local alreadyDone = C_QuestLog.IsQuestFlaggedCompleted(data.questID)
            if not alreadyDone then
                if data.items then
                    for _, item in ipairs(data.items) do
                        local have = CountItemInBags(item.itemID)
                        needItems[#needItems + 1] = {
                            profession = prof.name,
                            quest = data.quest,
                            itemName = item.name,
                            count = item.count,
                            have = have,
                            source = item.source,
                        }
                    end
                else
                    noItems[#noItems + 1] = {
                        profession = prof.name,
                        quest = data.quest,
                    }
                end
            end
        end
    end

    return needItems, noItems
end

-- ============================================================
-- UI: Popup helper frame
-- ============================================================
local helperFrame

local function CreateHelperFrame()
    if helperFrame then return helperFrame end

    helperFrame = CreateFrame("Frame", "WildDarkmoonFaireHelper", UIParent, "BackdropTemplate")
    helperFrame:SetSize(380, 300)
    helperFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    helperFrame:SetFrameStrata("DIALOG")
    helperFrame:SetMovable(true)
    helperFrame:EnableMouse(true)
    helperFrame:RegisterForDrag("LeftButton")
    helperFrame:SetScript("OnDragStart", helperFrame.StartMoving)
    helperFrame:SetScript("OnDragStop", helperFrame.StopMovingOrSizing)
    helperFrame:SetClampedToScreen(true)

    helperFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    local titleBar = helperFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleBar:SetPoint("TOP", 0, -16)
    titleBar:SetText("|cffff8800Darkmoon Faire|r — Shopping List")
    helperFrame.titleBar = titleBar

    local closeBtn = CreateFrame("Button", nil, helperFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    local scrollFrame = CreateFrame("ScrollFrame", nil, helperFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -42)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 40)

    local content = CreateFrame("Frame")
    content:SetWidth(320)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    helperFrame.content = content

    local dismissBtn = CreateFrame("Button", nil, helperFrame, "UIPanelButtonTemplate")
    dismissBtn:SetSize(100, 22)
    dismissBtn:SetPoint("BOTTOM", 0, 12)
    dismissBtn:SetText("Dismiss")
    dismissBtn:SetScript("OnClick", function() helperFrame:Hide() end)

    helperFrame:Hide()
    return helperFrame
end

local function PopulateHelper(needItems, noItems)
    local frame = CreateHelperFrame()
    local content = frame.content

    -- Clear previous font strings from our pool
    if not content.fontPool then content.fontPool = {} end
    for _, fs in ipairs(content.fontPool) do
        fs:Hide()
        fs:ClearAllPoints()
    end
    local poolIdx = 0

    -- Clear any other children (non-font-string frames)
    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end

    local yOff = -4
    local totalHeight = 4

    local function AddLine(text, template, extraLeft)
        poolIdx = poolIdx + 1
        local fs = content.fontPool[poolIdx]
        if not fs then
            fs = content:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
            content.fontPool[poolIdx] = fs
        else
            fs:SetFontObject(template or "GameFontHighlight")
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", (extraLeft or 0) + 8, yOff)
        fs:SetPoint("RIGHT", content, "RIGHT", -8, 0)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:Show()
        local h = fs:GetStringHeight() + 4
        yOff = yOff - h
        totalHeight = totalHeight + h
        return fs
    end

    if #needItems == 0 and #noItems == 0 then
        AddLine("All Darkmoon Faire profession quests are complete this month!", "GameFontGreen")
    else
        if #needItems > 0 then
            AddLine("|cffff4444Buy before entering:|r", "GameFontNormal")
            yOff = yOff - 4
            totalHeight = totalHeight + 4

            -- Group items by profession
            local byProf = {}
            local profOrder = {}
            for _, entry in ipairs(needItems) do
                if not byProf[entry.profession] then
                    byProf[entry.profession] = { quest = entry.quest, items = {} }
                    profOrder[#profOrder + 1] = entry.profession
                end
                byProf[entry.profession].items[#byProf[entry.profession].items + 1] = entry
            end

            for _, profName in ipairs(profOrder) do
                local data = byProf[profName]
                AddLine("|cffffd200" .. profName .. "|r — " .. data.quest, "GameFontHighlight", 8)
                for _, item in ipairs(data.items) do
                    local need = item.count or 1
                    local have = item.have or 0
                    local progressColor
                    if have >= need then
                        progressColor = "ff00ff00" -- green: done
                    elseif have > 0 then
                        progressColor = "ffffff00" -- yellow: partial
                    else
                        progressColor = "ffff4444" -- red: none
                    end
                    local progressStr = string.format("|c%s%d/%d|r ", progressColor, math.min(have, need), need)
                    AddLine("  |cffffffff• " .. progressStr .. item.itemName .. "|r  |cff888888(" .. item.source .. ")|r", "GameFontHighlightSmall", 16)
                end
                yOff = yOff - 4
                totalHeight = totalHeight + 4
            end
        end

        if #noItems > 0 then
            yOff = yOff - 4
            totalHeight = totalHeight + 4
            AddLine("|cff44ff44No items needed (done at the faire):|r", "GameFontNormal")
            yOff = yOff - 4
            totalHeight = totalHeight + 4
            for _, entry in ipairs(noItems) do
                AddLine("|cff888888" .. entry.profession .. " — " .. entry.quest .. "|r", "GameFontHighlightSmall", 8)
            end
        end
    end

    content:SetHeight(totalHeight + 8)

    -- Resize frame height to fit (clamped)
    local desiredH = totalHeight + 42 + 40 + 16 -- title + bottom + padding
    frame:SetHeight(math.min(math.max(desiredH, 150), 500))

    frame:Show()
end

-- ============================================================
-- Debounced helper refresh (used by bag updates and auto-buy)
-- ============================================================
local refreshTimer = nil
local function ScheduleHelperRefresh()
    if refreshTimer then return end
    refreshTimer = C_Timer.After(0.3, function()
        refreshTimer = nil
        if helperFrame and helperFrame:IsShown() then
            Wild.ShowDarkmoonHelper()
        end
    end)
end

-- ============================================================
-- Auto-buy missing Darkmoon Faire reagents from merchant
-- ============================================================
local function FindMerchantItemByName(itemName)
    local numItems = GetMerchantNumItems()
    for i = 1, numItems do
        local info = C_MerchantFrame.GetItemInfo(i)
        if info and info.name and info.name == itemName then
            return i
        end
    end
    return nil
end

local function AutoBuyDarkmoonItems()
    local cfg = GetConfig()
    if not cfg or not cfg.showProfessionHelper then return end
    if not IsInDarkmoonArea() then return end
    if not IsDarkmoonFaireActive() then return end

    local needItems, _ = BuildShoppingList()
    local bought = false

    for _, item in ipairs(needItems) do
        local need = item.count or 1
        local have = item.have or 0
        local missing = need - have
        if missing > 0 and item.source ~= "Archaeology skill" then
            local merchantIdx = FindMerchantItemByName(item.itemName)
            if merchantIdx then
                BuyMerchantItem(merchantIdx, missing)
                bought = true
                print(string.format(
                    "|cff00ccffWild:|r Bought %dx %s for Darkmoon Faire (%s).",
                    missing, item.itemName, item.profession
                ))
            end
        end
    end

    -- Refresh the helper window after buying
    if bought then
        ScheduleHelperRefresh()
    end
end

-- ============================================================
-- Refresh helper window on bag changes (to update have/need counts)
-- ============================================================
local bagUpdateFrame = CreateFrame("Frame")
bagUpdateFrame:RegisterEvent("BAG_UPDATE_DELAYED")
bagUpdateFrame:SetScript("OnEvent", function()
    if helperFrame and helperFrame:IsShown() then
        ScheduleHelperRefresh()
    end
end)

-- ============================================================
-- Hook merchant window to auto-buy DMF items
-- ============================================================
local dmfMerchantFrame = CreateFrame("Frame")
dmfMerchantFrame:RegisterEvent("MERCHANT_SHOW")
dmfMerchantFrame:SetScript("OnEvent", function()
    -- Small delay to let vendor inventory load
    C_Timer.After(0.5, AutoBuyDarkmoonItems)
end)

-- ============================================================
-- Public API
-- ============================================================
function Wild.ShowDarkmoonHelper()
    local needItems, noItems = BuildShoppingList()
    PopulateHelper(needItems, noItems)
end

-- ============================================================
-- Auto-show on zone change
-- ============================================================
local dismissed = false

local frame = CreateFrame("Frame")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(self, event)
    local cfg = GetConfig()
    if not cfg or not cfg.showProfessionHelper then return end

    if not IsInDarkmoonArea() then
        dismissed = false
        if helperFrame then helperFrame:Hide() end
        return
    end

    if dismissed then return end

    if not IsDarkmoonFaireActive() then return end

    Wild.ShowDarkmoonHelper()
end)

-- Hook OnHide once frame is created to set dismissed flag
local origCreateHelperFrame = CreateHelperFrame
CreateHelperFrame = function()
    local f = origCreateHelperFrame()
    if not f.hideHooked then
        f:HookScript("OnHide", function()
            dismissed = true
        end)
        f.hideHooked = true
    end
    return f
end
