-- Wild: Shared condition evaluation engine
-- Used by Bank, Vendor, Mail, and Inventory intent systems
local ADDON_NAME, Wild = ...

local COPPER_PER_GOLD = 10000

-- ============================================================
-- Quality display names & colors
-- ============================================================

local QUALITY_NAMES = {
    [0] = "Poor", [1] = "Common", [2] = "Uncommon",
    [3] = "Rare", [4] = "Epic", [5] = "Legendary",
}

-- ============================================================
-- Profession skill line IDs
-- ============================================================

local PROFESSION_SKILL_LINES = {
    [171] = "Alchemy",
    [164] = "Blacksmithing",
    [333] = "Enchanting",
    [202] = "Engineering",
    [182] = "Herbalism",
    [773] = "Inscription",
    [755] = "Jewelcrafting",
    [165] = "Leatherworking",
    [186] = "Mining",
    [393] = "Skinning",
    [197] = "Tailoring",
}

-- ============================================================
-- Class constants
-- ============================================================

local CLASS_FILES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK",
    "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local CLASS_LABELS = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter",
    ROGUE = "Rogue", PRIEST = "Priest", DEATHKNIGHT = "Death Knight",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock",
    MONK = "Monk", DRUID = "Druid", DEMONHUNTER = "Demon Hunter",
    EVOKER = "Evoker",
}

-- ============================================================
-- Equip location mappings
-- ============================================================

local EQUIP_LOC_TO_SLOTS = {
    INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3},
    INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5}, INVTYPE_WAIST = {6},
    INVTYPE_LEGS = {7}, INVTYPE_FEET = {8}, INVTYPE_WRIST = {9},
    INVTYPE_HAND = {10}, INVTYPE_FINGER = {11, 12},
    INVTYPE_TRINKET = {13, 14}, INVTYPE_CLOAK = {15},
    INVTYPE_WEAPON = {16, 17}, INVTYPE_2HWEAPON = {16},
    INVTYPE_WEAPONMAINHAND = {16}, INVTYPE_WEAPONOFFHAND = {17},
    INVTYPE_HOLDABLE = {17}, INVTYPE_SHIELD = {17},
    INVTYPE_RANGED = {16}, INVTYPE_RANGEDRIGHT = {16},
}

local EQUIP_LOC_LABELS = {
    INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder",
    INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest (Robe)", INVTYPE_WAIST = "Waist",
    INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet", INVTYPE_WRIST = "Wrist",
    INVTYPE_HAND = "Hands", INVTYPE_FINGER = "Ring", INVTYPE_TRINKET = "Trinket",
    INVTYPE_CLOAK = "Back", INVTYPE_WEAPON = "One-Hand", INVTYPE_2HWEAPON = "Two-Hand",
    INVTYPE_WEAPONMAINHAND = "Main Hand", INVTYPE_WEAPONOFFHAND = "Off Hand",
    INVTYPE_HOLDABLE = "Held In Off-Hand", INVTYPE_SHIELD = "Shield",
    INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged",
}

-- ============================================================
-- Bind type constants
-- ============================================================

local BIND_LABELS = {
    none = "None",
    boe = "Bind on Equip",
    soulbound = "Soulbound",
    warbound = "Warbound",
}

-- ============================================================
-- Expansion constants
-- ============================================================

local EXPANSION_NAMES = {
    [0] = "Classic", [1] = "TBC", [2] = "WotLK", [3] = "Cata",
    [4] = "MoP", [5] = "WoD", [6] = "Legion", [7] = "BfA",
    [8] = "SL", [9] = "DF", [10] = "TWW", [11] = "Midnight",
}

local EXPANSION_IDS = {}
for id, name in pairs(EXPANSION_NAMES) do EXPANSION_IDS[name] = id end

-- ============================================================
-- Upgrade track constants
-- ============================================================

local UPGRADE_TRACK_NAMES = {
    [0] = "None", [1] = "Explorer", [2] = "Adventurer", [3] = "Veteran",
    [4] = "Champion", [5] = "Hero", [6] = "Myth",
}

local UPGRADE_TRACK_IDS = {}
for id, name in pairs(UPGRADE_TRACK_NAMES) do UPGRADE_TRACK_IDS[name] = id end

-- ============================================================
-- Class-to-armor-subtype mapping
-- Armor subclassID: 1=Cloth, 2=Leather, 3=Mail, 4=Plate
-- ============================================================

local CLASS_ARMOR_SUBCLASS = {
    WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
    HUNTER = 3, SHAMAN = 3, EVOKER = 3,
    ROGUE = 2, MONK = 2, DRUID = 2, DEMONHUNTER = 2,
    MAGE = 1, WARLOCK = 1, PRIEST = 1,
}

-- ============================================================
-- Tooltip upgrade track parser
-- ============================================================

local function ParseUpgradeTrackFromTooltip(tooltipData)
    if not tooltipData or not tooltipData.lines then return nil end
    for _, line in ipairs(tooltipData.lines) do
        local text = line.leftText
        if text then
            -- Strip color codes
            local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            -- Match track name + fraction at end of line (handles "Adventurer 1/6"
            -- as well as "Upgrade Level: Adventurer 1/6")
            local track = clean:match("(%a+) %d+/%d+$")
            if track and UPGRADE_TRACK_IDS[track] then
                return UPGRADE_TRACK_IDS[track]
            end
        end
    end
    return nil
end

-- ============================================================
-- Attribute definitions
-- ============================================================

local ATTRIBUTES = {
    -- Item attributes
    {
        key = "item.name", label = "Item Name", category = "Item",
        valueType = "string",
        resolve = function(itemID, containerInfo, charCtx)
            return (GetItemInfo(itemID))
        end,
    },
    {
        key = "item.id", label = "Item ID", category = "Item",
        valueType = "id",
        resolve = function(itemID) return itemID end,
    },
    {
        key = "item.quality", label = "Quality", category = "Item",
        valueType = "quality",
        resolve = function(itemID, containerInfo)
            local q = containerInfo and containerInfo.quality
            if not q then _, _, q = GetItemInfo(itemID) end
            return q
        end,
    },
    {
        key = "item.ilvl", label = "Item Level", category = "Item",
        valueType = "number",
        resolve = function(itemID, containerInfo)
            -- Use the item link for actual effective ilvl (accounts for upgrades/bonus IDs)
            local link = containerInfo and containerInfo.hyperlink
            if link then
                local ilvl = GetDetailedItemLevelInfo(link)
                if ilvl then return ilvl end
            end
            -- Fallback to base template ilvl
            local _, _, _, ilvl = GetItemInfo(itemID)
            return ilvl
        end,
    },
    {
        key = "item.type", label = "Item Type", category = "Item",
        valueType = "itemtype",
        resolve = function(itemID)
            local _, _, _, _, _, classID = GetItemInfoInstant(itemID)
            return classID
        end,
    },
    {
        key = "item.subtype", label = "Item Subtype", category = "Item",
        valueType = "itemsubtype",
        resolve = function(itemID)
            local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
            if classID and subclassID then return classID * 1000 + subclassID end
        end,
    },
    {
        key = "item.sellprice", label = "Sell Price (copper)", category = "Item",
        valueType = "number",
        resolve = function(itemID, containerInfo)
            return Wild.GetEffectiveSellPrice(itemID, containerInfo) or 0
        end,
    },
    {
        key = "item.equiploc", label = "Equip Slot", category = "Item",
        valueType = "equiploc",
        resolve = function(itemID)
            local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemID)
            return (equipLoc and equipLoc ~= "") and equipLoc or nil
        end,
    },
    {
        key = "item.isReagent", label = "Is Crafting Reagent", category = "Item",
        valueType = "boolean",
        resolve = function(itemID)
            local isCraftingReagent = select(17, GetItemInfo(itemID))
            return isCraftingReagent and true or false
        end,
    },
    {
        key = "item.isKnown", label = "Is Known", category = "Collection",
        valueType = "boolean",
        resolve = function(itemID)
            -- 1) Toy
            if C_ToyBox and C_ToyBox.GetToyInfo then
                local _, toyID = C_ToyBox.GetToyInfo(itemID)
                if toyID then return PlayerHasToy(itemID) and true or false end
            end
            -- 2) Mount
            if C_MountJournal and C_MountJournal.GetMountFromItem then
                local mountID = C_MountJournal.GetMountFromItem(itemID)
                if mountID then
                    local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                    return isCollected and true or false
                end
            end
            local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
            -- 3) Pet (classID 15 = Miscellaneous, subclassID 2 = Companion Pets)
            if classID == 15 and subclassID == 2 then
                if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                    local _, _, _, _, _, _, _, _, _, _, _, _, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
                    if speciesID then
                        local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
                        return numCollected and numCollected > 0
                    end
                end
                return false
            end
            -- 4) Appearance (equippable gear with a transmog look)
            if C_TransmogCollection then
                local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemID)
                if equipLoc and equipLoc ~= "" then
                    local appearanceID = C_TransmogCollection.GetItemInfo(itemID)
                    if appearanceID then
                        local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
                        if sources then
                            for _, source in ipairs(sources) do
                                if source.isCollected then return true end
                            end
                        end
                        return false
                    end
                end
            end
            -- 5) Recipe (classID 9)
            if classID == 9 then
                local _, spellID = GetItemSpell(itemID)
                if spellID then
                    return (IsSpellKnown(spellID) or IsPlayerSpell(spellID)) and true or false
                end
                return false
            end
            -- 6) Anything else that teaches a spell (covers decor, etc.)
            local _, spellID = GetItemSpell(itemID)
            if spellID then
                return (IsSpellKnown(spellID) or IsPlayerSpell(spellID)) and true or false
            end
            return false
        end,
    },
    {
        key = "item.isToy", label = "Is Toy", category = "Collection",
        valueType = "boolean",
        resolve = function(itemID)
            if not C_ToyBox or not C_ToyBox.GetToyInfo then return false end
            local _, toyID = C_ToyBox.GetToyInfo(itemID)
            return toyID ~= nil
        end,
    },
    {
        key = "item.isMount", label = "Is Mount", category = "Collection",
        valueType = "boolean",
        resolve = function(itemID)
            if not C_MountJournal then return false end
            local mountID = C_MountJournal.GetMountFromItem(itemID)
            return mountID ~= nil
        end,
    },
    {
        key = "item.isPet", label = "Is Pet", category = "Collection",
        valueType = "boolean",
        resolve = function(itemID)
            local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
            return classID == 15 and subclassID == 2
        end,
    },
    {
        key = "item.bind", label = "Bind Type", category = "Item",
        valueType = "bind",
        resolve = function(itemID, containerInfo)
            -- Scan a list of tooltip lines for bind-type text; returns bind key or nil
            local function ScanLinesForBind(lines, ci)
                for _, line in ipairs(lines) do
                    local text = line.leftText
                    if text then
                        local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):trim():lower()
                        if clean == "soulbound" then
                            return "soulbound"
                        elseif clean == "warbound until equipped"
                            or clean == "warbound"
                            or clean == "account bound"
                            or clean == "blizzard account bound" then
                            return "warbound"
                        elseif clean == "binds when equipped" then
                            if ci and ci.isBound then return "soulbound" end
                            return "boe"
                        elseif clean == "binds when picked up" then
                            return "soulbound"
                        elseif clean == "binds when used" then
                            if ci and ci.isBound then return "soulbound" end
                            return "none"
                        end
                    end
                end
                return nil
            end

            -- Enum.ItemBind: 0=None,1=BoP,2=BoE,3=BoU,4=Quest,7=ToWoWAccount,8=ToBnetAccount,9=WarboundUntilEquipped
            -- GetItemInfo returns bindType=1 (BoP) for many warbound items whose DB entry
            -- predates the warbound system.  Tooltip text is always authoritative, so scan
            -- the tooltip FIRST when we have a bag+slot, then fall back to GetItemInfo.

            -- 1) Tooltip scanning – works for items in bags/bank where bag+slot are known
            if containerInfo and containerInfo.bag and containerInfo.slot
               and C_TooltipInfo and C_TooltipInfo.GetBagItem then
                local data = C_TooltipInfo.GetBagItem(containerInfo.bag, containerInfo.slot)
                if data then
                    if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
                    if data.lines then
                        local result = ScanLinesForBind(data.lines, containerInfo)
                        if result then return result end
                    end
                end
            end

            -- 2) Pre-parsed tooltip lines (from TooltipDataProcessor when bag/slot unavailable)
            if containerInfo and containerInfo.tooltipLines then
                local result = ScanLinesForBind(containerInfo.tooltipLines, containerInfo)
                if result then return result end
            end

            -- 3) Hyperlink tooltip scan – works when bag/slot missing (bank UI, links)
            local link = containerInfo and containerInfo.hyperlink
            if link and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
                local data = C_TooltipInfo.GetHyperlink(link)
                if data then
                    if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
                    if data.lines then
                        local result = ScanLinesForBind(data.lines, containerInfo)
                        if result then return result end
                    end
                end
            end

            -- 4) GetItemInfo numeric fallback
            local source = (containerInfo and containerInfo.hyperlink) or itemID
            local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(source)

            if not bindType then
                -- Request data for next time
                if C_Item and C_Item.RequestLoadItemDataByID then
                    C_Item.RequestLoadItemDataByID(itemID)
                end
                if containerInfo and containerInfo.isBound then
                    return "soulbound"
                end
                return "none"
            end

            -- Warbound / Account-Bound (7=ToWoWAccount, 8=ToBnetAccount, 9=WarboundUntilEquipped)
            if bindType == 7 or bindType == 8 or bindType == 9 then return "warbound" end
            -- Soulbound (1=OnAcquire, 4=Quest)
            if bindType == 1 or bindType == 4 then return "soulbound" end
            -- Bind on Use – treat as none (soulbound once used)
            if bindType == 3 then
                if containerInfo and containerInfo.isBound then return "soulbound" end
                return "none"
            end
            -- Bind on Equip (check if already bound → soulbound)
            if bindType == 2 then
                if containerInfo and containerInfo.isBound then
                    return "soulbound"
                end
                return "boe"
            end
            -- Unknown / none – trust isBound if set
            if containerInfo and containerInfo.isBound then
                return "soulbound"
            end
            return "none"
        end,
    },
    {
        key = "item.expansionID", label = "Expansion", category = "Item",
        valueType = "expansion",
        resolve = function(itemID)
            local expansionID = select(15, GetItemInfo(itemID))
            return expansionID ~= nil and EXPANSION_NAMES[expansionID] or nil
        end,
    },
    {
        key = "item.isWrongArmorType", label = "Is Wrong Armor Type", category = "Item",
        valueType = "boolean",
        resolve = function(itemID, containerInfo, charCtx)
            local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
            -- classID 4 = Armor
            if classID ~= 4 or not subclassID then return false end
            -- Ignore non-typed armor: 0=Misc/Generic (trinkets, rings, neck, etc.), 6=Shield
            if subclassID == 0 or subclassID == 6 then return false end
            local expectedSub = CLASS_ARMOR_SUBCLASS[charCtx.classFile]
            if not expectedSub then return false end
            return subclassID ~= expectedSub
        end,
    },
    {
        key = "item.upgradeTrack", label = "Upgrade Track", category = "Item",
        valueType = "upgradetrack",
        resolve = function(itemID, containerInfo, charCtx)
            if containerInfo and containerInfo.bag and containerInfo.slot
               and C_TooltipInfo and C_TooltipInfo.GetBagItem then
                local data = C_TooltipInfo.GetBagItem(containerInfo.bag, containerInfo.slot)
                if data and TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
                local track = ParseUpgradeTrackFromTooltip(data)
                if track then return track end
            end
            -- Fallback: try hyperlink tooltip when bag/slot unavailable
            local link = containerInfo and containerInfo.hyperlink
            if link and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
                local data = C_TooltipInfo.GetHyperlink(link)
                if data and TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
                local track = ParseUpgradeTrackFromTooltip(data)
                if track then return track end
            end
            -- No upgrade track found — treat as "None" (lower than any track)
            return 0
        end,
    },
    -- Character attributes
    {
        key = "char.profession", label = "Has Profession", category = "Character",
        valueType = "profession",
        resolve = function(itemID, containerInfo, charCtx) return charCtx.professions end,
    },
    {
        key = "char.class", label = "Character Class", category = "Character",
        valueType = "class",
        resolve = function(itemID, containerInfo, charCtx) return charCtx.classFile end,
    },
    {
        key = "char.level", label = "Character Level", category = "Character",
        valueType = "number",
        resolve = function(itemID, containerInfo, charCtx) return charCtx.level end,
    },
}

-- ============================================================
-- Dynamic value references (for numeric comparisons)
-- ============================================================

local DYNAMIC_REFS = {
    {
        key = "char.avgilvl", label = "Avg Item Level",
        resolve = function(itemID, containerInfo, charCtx) return charCtx.avgIlvl end,
    },
    {
        key = "char.avgilvl.equipped", label = "Avg Equipped iLvl",
        resolve = function(itemID, containerInfo, charCtx) return charCtx.avgIlvlEquipped end,
    },
    {
        key = "char.slotilvl", label = "Equipped Slot iLvl",
        resolve = function(itemID, containerInfo, charCtx)
            local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemID)
            if not equipLoc or equipLoc == "" then return nil end
            local slots = EQUIP_LOC_TO_SLOTS[equipLoc]
            if not slots then return nil end
            local lowest
            for _, slotID in ipairs(slots) do
                local ilvl = charCtx.slotIlvls[slotID]
                if ilvl and (not lowest or ilvl < lowest) then lowest = ilvl end
            end
            return lowest
        end,
    },
    {
        key = "char.level", label = "Character Level",
        resolve = function(itemID, containerInfo, charCtx) return charCtx.level end,
    },
    {
        key = "char.slotUpgradeTrack", label = "Equipped Slot Track",
        resolve = function(itemID, containerInfo, charCtx)
            local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemID)
            if not equipLoc or equipLoc == "" then return 0 end
            local slots = EQUIP_LOC_TO_SLOTS[equipLoc]
            if not slots then return 0 end
            local best
            for _, slotID in ipairs(slots) do
                local track = charCtx.slotUpgradeTracks and charCtx.slotUpgradeTracks[slotID]
                if track and (not best or track > best) then best = track end
            end
            return best or 0
        end,
    },
}

-- ============================================================
-- Operators
-- ============================================================

local OPERATORS = {
    { key = "=",            label = "=",               forTypes = { number = true, quality = true, upgradetrack = true, id = true } },
    { key = "!=",           label = "!=",    forTypes = { number = true, quality = true, upgradetrack = true, id = true } },
    { key = "<",            label = "<",               forTypes = { number = true, quality = true, upgradetrack = true } },
    { key = "<=",           label = "<=",    forTypes = { number = true, quality = true, upgradetrack = true } },
    { key = ">",            label = ">",               forTypes = { number = true, quality = true, upgradetrack = true } },
    { key = ">=",           label = ">=",    forTypes = { number = true, quality = true, upgradetrack = true } },
    { key = "is",           label = "is",              forTypes = { string = true, itemtype = true, itemsubtype = true, equiploc = true, class = true, profession = true, bind = true, boolean = true, expansion = true } },
    { key = "is_not",       label = "is not",          forTypes = { string = true, itemtype = true, itemsubtype = true, equiploc = true, class = true, profession = true, bind = true, boolean = true, expansion = true } },
    { key = "contains",     label = "contains",        forTypes = { string = true } },
    { key = "not_contains", label = "doesn't contain", forTypes = { string = true } },
}

-- ============================================================
-- Build lookup tables
-- ============================================================

local ATTR_BY_KEY = {}
for _, attr in ipairs(ATTRIBUTES) do ATTR_BY_KEY[attr.key] = attr end

local REF_BY_KEY = {}
for _, ref in ipairs(DYNAMIC_REFS) do REF_BY_KEY[ref.key] = ref end

-- ============================================================
-- Returns a set of skill line IDs the player currently has
-- ============================================================

local function GetPlayerProfessionSkillLines()
    local result = {}
    local prof1, prof2 = GetProfessions()
    for _, idx in ipairs({ prof1, prof2 }) do
        if idx then
            local _, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
            if skillLine then
                result[skillLine] = true
            end
        end
    end
    return result
end

-- ============================================================
-- Character context builder (built once per automation pass)
-- ============================================================

local function BuildCharContext()
    local avgIlvl, avgIlvlEquipped = GetAverageItemLevel()
    local _, classFile = UnitClass("player")
    local level = UnitLevel("player")

    local slotIlvls = {}
    local slotUpgradeTracks = {}
    for _, slotID in ipairs({1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17}) do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local ilvl = GetDetailedItemLevelInfo(link)
            if ilvl then slotIlvls[slotID] = ilvl end
            if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
                local data = C_TooltipInfo.GetInventoryItem("player", slotID)
                if data and TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
                local track = ParseUpgradeTrackFromTooltip(data)
                if track then slotUpgradeTracks[slotID] = track end
            end
        end
    end

    return {
        avgIlvl = avgIlvl,
        avgIlvlEquipped = avgIlvlEquipped,
        classFile = classFile,
        level = level,
        slotIlvls = slotIlvls,
        slotUpgradeTracks = slotUpgradeTracks,
        professions = GetPlayerProfessionSkillLines(),
    }
end

-- ============================================================
-- Condition summary formatting (moved above debug helper)
-- ============================================================

-- Forward declaration (defined later, after actor matching)
local GetConditionsSummary

local OP_DISPLAY = {
    ["="] = "=", ["!="] = "!=", ["<"] = "<", ["<="] = "<=",
    [">"] = ">", [">="] = ">=",
    ["is"] = "is", ["is_not"] = "is not",
    ["contains"] = "contains", ["not_contains"] = "doesn't contain",
}

local function FormatConditionValue(cond, attrDef)
    if cond.ref then
        local refDef = REF_BY_KEY[cond.ref]
        local label = refDef and refDef.label or cond.ref
        if cond.offset and cond.offset ~= 0 then
            if cond.offset > 0 then
                return label .. " + " .. cond.offset
            else
                return label .. " - " .. math.abs(cond.offset)
            end
        end
        return label
    end

    local vt = attrDef and attrDef.valueType
    if vt == "quality" then
        return QUALITY_NAMES[cond.value] or tostring(cond.value)
    elseif vt == "upgradetrack" then
        return UPGRADE_TRACK_NAMES[cond.value] or tostring(cond.value)
    elseif vt == "itemtype" then
        return GetItemClassInfo(cond.value) or tostring(cond.value)
    elseif vt == "itemsubtype" then
        local classID = math.floor((cond.value or 0) / 1000)
        local subclassID = (cond.value or 0) % 1000
        local typeName = GetItemClassInfo(classID) or "?"
        local subName = GetItemSubClassInfo(classID, subclassID) or "?"
        return typeName .. " > " .. subName
    elseif vt == "profession" then
        return PROFESSION_SKILL_LINES[cond.value] or tostring(cond.value)
    elseif vt == "class" then
        return CLASS_LABELS[cond.value] or tostring(cond.value)
    elseif vt == "equiploc" then
        return EQUIP_LOC_LABELS[cond.value] or tostring(cond.value)
    elseif vt == "bind" then
        return BIND_LABELS[cond.value] or tostring(cond.value)
    elseif vt == "expansion" then
        return tostring(cond.value or "?")
    elseif vt == "boolean" then
        if cond.value == true then return "Yes" end
        return "No"
    end
    return tostring(cond.value or "?")
end

-- ============================================================
-- Debug helper
-- ============================================================

local function DebugMsg(msg)
    if not Wild.db or not Wild.db.advanced or not Wild.db.advanced.debug then return end
    print("|cff00ccffWild [Rules]:|r " .. msg)
end

local function FormatActualValue(left, attrDef)
    if left == nil then return "|cff888888nil|r" end
    local vt = attrDef and attrDef.valueType
    if vt == "quality" then
        return (QUALITY_NAMES[left] or tostring(left)) .. " (" .. tostring(left) .. ")"
    elseif vt == "upgradetrack" then
        return (UPGRADE_TRACK_NAMES[left] or tostring(left)) .. " (" .. tostring(left) .. ")"
    elseif vt == "boolean" then
        return left and "Yes" or "No"
    elseif vt == "bind" then
        return BIND_LABELS[left] or tostring(left)
    elseif vt == "itemtype" then
        return (GetItemClassInfo(left) or tostring(left))
    elseif vt == "itemsubtype" then
        local classID = math.floor((left or 0) / 1000)
        local subclassID = (left or 0) % 1000
        return (GetItemClassInfo(classID) or "?") .. " > " .. (GetItemSubClassInfo(classID, subclassID) or "?")
    elseif vt == "equiploc" then
        return EQUIP_LOC_LABELS[left] or tostring(left)
    elseif vt == "class" then
        return CLASS_LABELS[left] or tostring(left)
    elseif vt == "profession" then
        if type(left) == "table" then
            local names = {}
            for id in pairs(left) do names[#names + 1] = PROFESSION_SKILL_LINES[id] or tostring(id) end
            return "{" .. table.concat(names, ", ") .. "}"
        end
        return tostring(left)
    elseif vt == "expansion" then
        return tostring(left)
    end
    return tostring(left)
end

-- ============================================================
-- Condition evaluation
-- ============================================================

local function ResolveRightValue(cond, itemID, containerInfo, charCtx)
    if cond.ref then
        local refDef = REF_BY_KEY[cond.ref]
        if not refDef then return nil end
        local val = refDef.resolve(itemID, containerInfo, charCtx)
        if val and cond.offset and cond.offset ~= 0 then val = val + cond.offset end
        return val
    end
    return cond.value
end

local function EvaluateCondition(cond, itemID, containerInfo, charCtx)
    local attrDef = ATTR_BY_KEY[cond.attr]
    if not attrDef then return true end

    local left = attrDef.resolve(itemID, containerInfo, charCtx)
    local op = cond.op
    local right = ResolveRightValue(cond, itemID, containerInfo, charCtx)

    -- Evaluate the result
    local result
    if left == nil then
        result = false
    elseif right == nil then
        result = false
    else
        local vt = attrDef.valueType

        -- Set-based: profession
        if vt == "profession" then
            if op == "is" then result = left[right] == true
            elseif op == "is_not" then result = not left[right]
            else result = false end

        -- Boolean
        elseif vt == "boolean" then
            if op == "is" then result = left == right
            elseif op == "is_not" then result = left ~= right
            else result = false end

        -- Bind type
        elseif vt == "bind" then
            if op == "is" then result = left == right
            elseif op == "is_not" then result = left ~= right
            else result = false end

        -- String
        elseif vt == "string" then
            local l = tostring(left):lower()
            local r = tostring(right):lower()
            if op == "is" then result = l == r
            elseif op == "is_not" then result = l ~= r
            elseif op == "contains" then result = l:find(r, 1, true) ~= nil
            elseif op == "not_contains" then result = l:find(r, 1, true) == nil
            else result = false end

        -- Expansion (compare string names)
        elseif vt == "expansion" then
            if op == "is" then result = left == right
            elseif op == "is_not" then result = left ~= right
            else result = false end

        -- Enum types
        elseif vt == "itemtype" or vt == "itemsubtype" or vt == "equiploc" or vt == "class" then
            if op == "is" then result = left == right
            elseif op == "is_not" then result = left ~= right
            else result = false end

        -- Numeric / quality
        else
            local l = tonumber(left) or 0
            local r = tonumber(right) or 0
            if op == "=" then result = l == r
            elseif op == "!=" then result = l ~= r
            elseif op == "<" then result = l < r
            elseif op == "<=" then result = l <= r
            elseif op == ">" then result = l > r
            elseif op == ">=" then result = l >= r
            else result = false end
        end
    end

    -- Debug output
    if Wild.db and Wild.db.advanced and Wild.db.advanced.debug then
        local attrLabel = attrDef.label or cond.attr
        local opLabel = OP_DISPLAY[cond.op] or cond.op
        local actualStr = FormatActualValue(left, attrDef)
        local expectedStr = FormatConditionValue(cond, attrDef)
        local tag = result and "|cff44ff44PASS|r" or "|cffff4444FAIL|r"
        DebugMsg(string.format("  %s: actual=%s, expected %s %s -> %s",
            attrLabel, actualStr, opLabel, expectedStr, tag))
    end

    return result
end

local function IntentMatchesItem(intent, itemID, containerInfo, charCtx)
    local groups = intent.groups
    if not groups or #groups == 0 then return false end

    local isDebug = Wild.db and Wild.db.advanced and Wild.db.advanced.debug
    if isDebug then
        local itemName = GetItemInfo(itemID) or ("ItemID:" .. tostring(itemID))
        DebugMsg(string.format("Evaluating |cffffffff%s|r against %d group(s)", itemName, #groups))
    end

    -- Separate include and exclude groups
    local includeGroups, excludeGroups = {}, {}
    for _, group in ipairs(groups) do
        if group.mode == "exclude" then
            excludeGroups[#excludeGroups + 1] = group
        else
            includeGroups[#includeGroups + 1] = group
        end
    end

    -- Must have at least one include group
    if #includeGroups == 0 then return false end

    -- Include: item must match at least one include group (OR between groups)
    local matched = false
    for gi, group in ipairs(includeGroups) do
        local conds = group.conditions
        if conds and #conds > 0 then
            local groupMatch = true
            if isDebug then
                local summary = GetConditionsSummary(conds)
                DebugMsg(string.format("  Include group %d: %s", gi, summary))
            end
            for _, cond in ipairs(conds) do
                if not EvaluateCondition(cond, itemID, containerInfo, charCtx) then
                    groupMatch = false
                    break
                end
            end
            if groupMatch then
                if isDebug then DebugMsg(string.format("  Include group %d => |cff44ff44MATCH|r", gi)) end
                matched = true
                break
            else
                if isDebug then DebugMsg(string.format("  Include group %d => |cffff4444NO MATCH|r", gi)) end
            end
        end
    end

    if not matched then
        if isDebug then DebugMsg("  => |cffff4444NO MATCH|r (no include group matched)") end
        return false
    end

    -- Exclude: if item matches ANY exclude group, reject it
    for gi, group in ipairs(excludeGroups) do
        local conds = group.conditions
        if conds and #conds > 0 then
            local groupMatch = true
            if isDebug then
                local summary = GetConditionsSummary(conds)
                DebugMsg(string.format("  Exclude group %d: %s", gi, summary))
            end
            for _, cond in ipairs(conds) do
                if not EvaluateCondition(cond, itemID, containerInfo, charCtx) then
                    groupMatch = false
                    break
                end
            end
            if groupMatch then
                if isDebug then DebugMsg("  => |cffff4444EXCLUDED|r (exclude group matched)") end
                return false
            else
                if isDebug then DebugMsg(string.format("  Exclude group %d => |cff44ff44not excluded|r", gi)) end
            end
        end
    end

    if isDebug then DebugMsg("  => |cff44ff44MATCH|r (included, not excluded)") end
    return true
end

-- ============================================================
-- Intent completeness validation
-- Returns true if the intent has all required fields to be processed.
-- Returns false, reason if the intent is incomplete.
-- ============================================================

local ACTIONS_REQUIRING_TARGET = { deposit = true, withdraw = true, transfer = true, gold = true }
local ACTIONS_REQUIRING_CONDITIONS = { sell = true, destroy = true, deposit = true, withdraw = true, transfer = true, mail = true }

local function ValidateIntent(intent)
    if not intent then return false, "nil intent" end
    if not intent.action or intent.action == "" then return false, "missing action" end

    -- Gold intents don't need conditions
    if intent.action == "gold" then
        if not intent.target then return false, "gold intent missing target" end
        if not intent.goldTarget or intent.goldTarget <= 0 then return false, "gold intent missing goldTarget" end
        return true
    end

    -- All other item-matching actions need at least one group with conditions
    if ACTIONS_REQUIRING_CONDITIONS[intent.action] then
        local groups = intent.groups
        if not groups or #groups == 0 then return false, "no groups" end
        local hasInclude = false
        for gi, group in ipairs(groups) do
            local conds = group.conditions
            if not conds or #conds == 0 then return false, "group " .. gi .. " has no conditions" end
            if group.mode ~= "exclude" then hasInclude = true end
            for ci, cond in ipairs(conds) do
                if not cond.attr or cond.attr == "" then return false, "group " .. gi .. " condition " .. ci .. " missing attribute" end
                if not cond.op or cond.op == "" then return false, "group " .. gi .. " condition " .. ci .. " missing operator" end
                if cond.value == nil and not cond.ref then return false, "group " .. gi .. " condition " .. ci .. " missing value" end
                if not ATTR_BY_KEY[cond.attr] then return false, "group " .. gi .. " condition " .. ci .. " unknown attribute '" .. tostring(cond.attr) .. "'" end
            end
        end
        if not hasInclude then return false, "no include groups" end
    end

    -- Target required for bank/gold actions
    if ACTIONS_REQUIRING_TARGET[intent.action] and not intent.target then
        return false, "missing target"
    end

    -- Mail must have a recipient
    if intent.action == "mail" and (not intent.recipient or intent.recipient == "") then
        return false, "missing recipient"
    end

    -- Transfer needs source
    if intent.action == "transfer" and not intent.source then
        return false, "missing source"
    end

    return true
end

-- ============================================================
-- Actor matching
-- ============================================================

local function CharMatchesActorValue(charKey, actorValue, charLabels)
    if actorValue == "Everyone" then return true end
    if actorValue == charKey then return true end
    for _, lbl in ipairs(charLabels) do
        if lbl == actorValue then return true end
    end
    return false
end

local function IntentMatchesActor(intent)
    local actors = intent.actors
    if not actors or #actors == 0 then return true end -- no filter = everyone

    local name = UnitName("player")
    local realm = GetRealmName()
    local charKey = name .. "-" .. realm
    local charLabels = Wild.GetActorLabels and Wild.GetActorLabels(charKey) or {}

    -- Separate includes and excludes
    local includes, excludes = {}, {}
    for _, entry in ipairs(actors) do
        if entry.exclude then
            excludes[#excludes + 1] = entry.value
        else
            includes[#includes + 1] = entry.value
        end
    end

    -- Check excludes first: if character matches any exclude, reject
    for _, val in ipairs(excludes) do
        if CharMatchesActorValue(charKey, val, charLabels) then
            return false
        end
    end

    -- If there are includes, character must match at least one
    if #includes > 0 then
        for _, val in ipairs(includes) do
            if CharMatchesActorValue(charKey, val, charLabels) then
                return true
            end
        end
        return false
    end

    -- Only excludes, no includes: everyone except excluded
    return true
end

-- ============================================================
-- Condition summary formatting
-- ============================================================

GetConditionsSummary = function(conditions)
    if not conditions or #conditions == 0 then return "No conditions" end
    local parts = {}
    for _, cond in ipairs(conditions) do
        local attrDef = ATTR_BY_KEY[cond.attr]
        local attrLabel = attrDef and attrDef.label or cond.attr
        local opLabel = OP_DISPLAY[cond.op] or cond.op
        local valStr = FormatConditionValue(cond, attrDef)
        table.insert(parts, attrLabel .. " " .. opLabel .. " " .. valStr)
    end
    return table.concat(parts, ", ")
end

-- ============================================================
-- Intent summary formatting: "Who | verb | [all] what | [target]"
-- ============================================================

local PROFESSION_PRACTITIONER = {
    [171] = "Alchemist", [164] = "Blacksmith", [333] = "Enchanter",
    [202] = "Engineer", [182] = "Herbalist", [773] = "Scribe",
    [755] = "Jewelcrafter", [165] = "Leatherworker", [186] = "Miner",
    [393] = "Skinner", [197] = "Tailor",
}

local ACTION_LABELS = {
    deposit  = "|cffffcc00deposits|r",
    withdraw = "|cff00ff00withdraws|r",
    sell     = "|cffffcc00sells|r",
    destroy  = "|cffff4444destroys|r",
    mail     = "|cff88aaffmails|r",
    gold     = "|cffffd700keeps|r",
    transfer = "|cff00ccfftransfers|r",
}

local TARGET_LABELS = {
    character = "Personal Bank",
    warband   = "Warband Bank",
    guild     = "Guild Bank",
}

local function StartsWithVowel(s)
    local c = s:sub(1, 1):lower()
    return c == "a" or c == "e" or c == "i" or c == "o" or c == "u"
end

local function FormatWhoClause(charConds)
    if #charConds == 0 then return "Everyone" end
    local positives, negatives = {}, {}
    for _, cond in ipairs(charConds) do
        if cond.attr == "char.class" then
            local name = CLASS_LABELS[cond.value] or tostring(cond.value)
            if cond.op == "is" then
                table.insert(positives, name .. "s")
            elseif cond.op == "is_not" then
                local art = StartsWithVowel(name) and "an" or "a"
                table.insert(negatives, "not " .. art .. " " .. name)
            end
        elseif cond.attr == "char.profession" then
            local prac = PROFESSION_PRACTITIONER[cond.value] or PROFESSION_SKILL_LINES[cond.value] or tostring(cond.value)
            if cond.op == "is" then
                table.insert(positives, prac .. "s")
            elseif cond.op == "is_not" then
                local art = StartsWithVowel(prac) and "an" or "a"
                table.insert(negatives, "not " .. art .. " " .. prac)
            end
        elseif cond.attr == "char.level" then
            local val = FormatConditionValue(cond, ATTR_BY_KEY[cond.attr])
            if cond.op == ">=" then
                table.insert(positives, "Level " .. val .. "+")
            elseif cond.op == "<=" then
                table.insert(positives, "up to Level " .. val)
            else
                table.insert(positives, "Level " .. (OP_DISPLAY[cond.op] or cond.op) .. " " .. val)
            end
        end
    end
    if #positives > 0 and #negatives > 0 then
        return table.concat(positives, " ") .. " who are " .. table.concat(negatives, " and ")
    elseif #positives > 0 then
        return table.concat(positives, " ")
    elseif #negatives > 0 then
        return "Everyone who is " .. table.concat(negatives, " and ")
    end
    return "Everyone"
end

local function FormatItemDescription(itemConds)
    if #itemConds == 0 then return "items" end

    local nameVal, nameOp
    local idVal
    local qualExact
    local qualMin, qualMax
    local typeID, subtypeCode
    local bindVal, bindOp
    local reagentVal
    local isKnownVal
    local isToyVal, isMountVal, isPetVal
    local ilvlRefParts = {}
    local ilvlStatParts = {}
    local extras = {}

    for _, cond in ipairs(itemConds) do
        if cond.attr == "item.name" then
            nameVal, nameOp = cond.value, cond.op
        elseif cond.attr == "item.id" then
            idVal = cond.value
        elseif cond.attr == "item.quality" then
            if cond.op == "=" then qualExact = cond.value
            elseif cond.op == ">=" then qualMin = cond.value
            elseif cond.op == "<=" then qualMax = cond.value
            else
                extras[#extras + 1] = "Quality " .. (OP_DISPLAY[cond.op] or cond.op) .. " " .. (QUALITY_NAMES[cond.value] or cond.value)
            end
        elseif cond.attr == "item.type" then
            typeID = cond.value
        elseif cond.attr == "item.subtype" then
            subtypeCode = cond.value
        elseif cond.attr == "item.bind" then
            bindVal, bindOp = cond.value, cond.op
        elseif cond.attr == "item.isReagent" then
            reagentVal = cond.value
        elseif cond.attr == "item.isKnown" then
            isKnownVal = cond.value
        elseif cond.attr == "item.isToy" then
            isToyVal = cond.value
        elseif cond.attr == "item.isMount" then
            isMountVal = cond.value
        elseif cond.attr == "item.isPet" then
            isPetVal = cond.value
        elseif cond.attr == "item.ilvl" then
            if cond.ref then
                local refDef = REF_BY_KEY[cond.ref]
                local refLabel = refDef and refDef.label or cond.ref
                local offsetStr = ""
                if cond.offset and cond.offset ~= 0 then
                    offsetStr = (cond.offset > 0 and " + " or " - ") .. math.abs(cond.offset)
                end
                local word
                if cond.op == "<" or cond.op == "<=" then word = "below"
                elseif cond.op == ">" or cond.op == ">=" then word = "above"
                else word = (OP_DISPLAY[cond.op] or cond.op) end
                ilvlRefParts[#ilvlRefParts + 1] = word .. " " .. refLabel .. offsetStr
            else
                ilvlStatParts[#ilvlStatParts + 1] = "iLvl " .. (OP_DISPLAY[cond.op] or cond.op) .. " " .. cond.value
            end
        else
            local attrDef = ATTR_BY_KEY[cond.attr]
            local attrLabel = attrDef and attrDef.label or cond.attr
            local opLabel = OP_DISPLAY[cond.op] or cond.op
            local valStr = FormatConditionValue(cond, attrDef)
            extras[#extras + 1] = attrLabel .. " " .. opLabel .. " " .. valStr
        end
    end

    -- Determine the primary noun (first match wins)
    local noun
    local consumedBind, consumedQualExact, consumedReagent = false, false, false
    local consumedCollection = false

    if nameVal then
        if nameOp == "is" then noun = "\"" .. nameVal .. "\""
        elseif nameOp == "contains" then noun = "\"" .. nameVal .. "\" items"
        elseif nameOp == "is_not" then noun = "items not named \"" .. nameVal .. "\""
        elseif nameOp == "not_contains" then noun = "items without \"" .. nameVal .. "\""
        end
    elseif idVal then
        local itemName = GetItemInfo(idVal)
        noun = itemName or ("item #" .. idVal)
    elseif subtypeCode then
        local classID = math.floor(subtypeCode / 1000)
        local subclassID = subtypeCode % 1000
        noun = GetItemSubClassInfo(classID, subclassID) or "items"
    elseif typeID then
        noun = GetItemClassInfo(typeID) or "items"
    elseif isKnownVal == true then
        noun = "already-known Collectibles"
        consumedCollection = true
    elseif isKnownVal == false then
        noun = "uncollected items"
        consumedCollection = true
    elseif isToyVal == true then
        noun = "Toys"
        consumedCollection = true
    elseif isMountVal == true then
        noun = "Mount items"
        consumedCollection = true
    elseif isPetVal == true then
        noun = "Pet items"
        consumedCollection = true
    elseif reagentVal == true then
        noun = "Reagents"
        consumedReagent = true
    elseif bindVal and bindOp == "is" then
        local BIND_NOUN = { boe = "BoEs", soulbound = "Soulbound items", warbound = "Warbound items", none = "unbound items" }
        noun = BIND_NOUN[bindVal] or ((BIND_LABELS[bindVal] or bindVal) .. " items")
        consumedBind = true
    elseif qualExact ~= nil then
        if qualExact == 0 then noun = "gray items"
        else noun = (QUALITY_NAMES[qualExact] or "?") .. " items" end
        consumedQualExact = true
    end

    -- If no specific noun yet, try to incorporate quality range into noun
    if not noun then
        if qualMin and qualMax then
            noun = (QUALITY_NAMES[qualMin] or "?") .. " to " .. (QUALITY_NAMES[qualMax] or "?") .. " items"
            qualMin, qualMax = nil, nil
        elseif qualMin then
            noun = (QUALITY_NAMES[qualMin] or "?") .. "+ items"
            qualMin = nil
        elseif qualMax then
            noun = "items up to " .. (QUALITY_NAMES[qualMax] or "?")
            qualMax = nil
        else
            noun = "items"
        end
    end

    -- Append dynamic ilvl ref directly to noun (reads naturally: "items below X")
    if #ilvlRefParts > 0 then
        noun = noun .. " " .. table.concat(ilvlRefParts, " and ")
    end

    -- Build modifier list from remaining (unconsumed) conditions
    local mods = {}

    if bindVal and not consumedBind then
        local BIND_SHORT = { boe = "BoE", soulbound = "Soulbound", warbound = "Warbound", none = "unbound" }
        local short = BIND_SHORT[bindVal] or (BIND_LABELS[bindVal] or bindVal)
        if bindOp == "is" then mods[#mods + 1] = short
        elseif bindOp == "is_not" then mods[#mods + 1] = "non-" .. short end
    end

    if reagentVal == true and not consumedReagent then
        mods[#mods + 1] = "Reagent"
    end

    if not consumedCollection then
        if isKnownVal == true then mods[#mods + 1] = "already-known"
        elseif isKnownVal == false then mods[#mods + 1] = "uncollected" end
        if isToyVal == true then mods[#mods + 1] = "Toy"
        elseif isToyVal == false then mods[#mods + 1] = "not a Toy" end
        if isMountVal == true then mods[#mods + 1] = "Mount"
        elseif isMountVal == false then mods[#mods + 1] = "not a Mount" end
        if isPetVal == true then mods[#mods + 1] = "Pet"
        elseif isPetVal == false then mods[#mods + 1] = "not a Pet" end
    end

    if qualExact and not consumedQualExact then
        if qualExact == 0 then mods[#mods + 1] = "gray"
        else mods[#mods + 1] = (QUALITY_NAMES[qualExact] or "?") .. " quality" end
    end

    if qualMin or qualMax then
        if qualMin and qualMax then
            mods[#mods + 1] = (QUALITY_NAMES[qualMin] or "?") .. " to " .. (QUALITY_NAMES[qualMax] or "?") .. " quality"
        elseif qualMin then
            mods[#mods + 1] = (QUALITY_NAMES[qualMin] or "?") .. "+ quality"
        elseif qualMax then
            mods[#mods + 1] = "up to " .. (QUALITY_NAMES[qualMax] or "?") .. " quality"
        end
    end

    for _, p in ipairs(ilvlStatParts) do mods[#mods + 1] = p end
    for _, p in ipairs(extras) do mods[#mods + 1] = p end

    if #mods > 0 then
        return noun .. ", " .. table.concat(mods, ", ")
    end
    return noun
end

local function GetIntentSummary(intent)
    local groups = intent.groups or {}

    -- Collect all conditions across all groups for char/item separation
    local charConds = {}
    for _, group in ipairs(groups) do
        if group.conditions then
            for _, c in ipairs(group.conditions) do
                if c.attr and c.attr:sub(1, 5) == "char." then
                    charConds[#charConds + 1] = c
                end
            end
        end
    end

    local who
    local actors = intent.actors
    if actors and #actors > 0 then
        local includeParts, excludeParts = {}, {}
        for _, entry in ipairs(actors) do
            if entry.exclude then
                excludeParts[#excludeParts + 1] = entry.value
            else
                includeParts[#includeParts + 1] = entry.value
            end
        end
        local parts = {}
        if #includeParts > 0 then
            parts[#parts + 1] = table.concat(includeParts, ", ")
        end
        if #excludeParts > 0 then
            parts[#parts + 1] = "not " .. table.concat(excludeParts, ", ")
        end
        who = table.concat(parts, " & ")
        -- Append char conditions if present
        local charDetail = FormatWhoClause(charConds)
        if charDetail ~= "Everyone" then
            who = who .. " " .. charDetail
        end
    else
        who = FormatWhoClause(charConds)
    end

    -- Gold: special format
    if intent.action == "gold" then
        local goldAmt = intent.goldTarget or 0
        local bank = TARGET_LABELS[intent.target] or intent.target or "Warband Bank"
        return who .. " " .. ACTION_LABELS.gold .. " " .. string.format("%dg synced with %s", goldAmt, bank)
    end

    local verb = ACTION_LABELS[intent.action] or intent.action
    local keep = intent.keep or 0

    -- Build per-group item descriptions
    local includeDescs, excludeDescs = {}, {}
    for _, group in ipairs(groups) do
        local itemConds = {}
        if group.conditions then
            for _, c in ipairs(group.conditions) do
                if not c.attr or c.attr:sub(1, 5) ~= "char." then
                    itemConds[#itemConds + 1] = c
                end
            end
        end
        local desc = FormatItemDescription(itemConds)
        if group.mode == "exclude" then
            excludeDescs[#excludeDescs + 1] = desc
        else
            includeDescs[#includeDescs + 1] = desc
        end
    end

    local itemDesc
    if #includeDescs == 1 then
        itemDesc = includeDescs[1]
    elseif #includeDescs > 1 then
        itemDesc = "(" .. table.concat(includeDescs, " |cff88aaffor|r ") .. ")"
    else
        itemDesc = "items"
    end
    if #excludeDescs > 0 then
        itemDesc = itemDesc .. " |cffff6666except|r " .. table.concat(excludeDescs, " or ")
    end

    -- Build: "Who verb [all] itemDesc [, keeping N] [to/from target]"
    local result = who .. " " .. verb

    if keep == 0 then
        result = result .. " all " .. itemDesc
    else
        result = result .. " " .. itemDesc .. ", keeping " .. keep
        if intent.action == "withdraw" or intent.action == "transfer" then
            result = result .. " in source bank"
        end
    end

    -- Target / recipient
    if intent.action == "deposit" and intent.target then
        result = result .. " to " .. (TARGET_LABELS[intent.target] or intent.target)
    elseif intent.action == "withdraw" and intent.target then
        result = result .. " from " .. (TARGET_LABELS[intent.target] or intent.target)
    elseif intent.action == "transfer" then
        local srcLabel = TARGET_LABELS[intent.source] or intent.source or "?"
        local dstLabel = TARGET_LABELS[intent.target] or intent.target or "?"
        result = result .. " from " .. srcLabel .. " to " .. dstLabel
    elseif intent.action == "mail" and intent.recipient then
        result = result .. " to " .. intent.recipient
    end

    if intent.action == "sell" and intent.destroyUnsellable then
        result = result .. " |cffff8888(destroy unsellable)|r"
    end

    return result
end

-- ============================================================
-- Inventory counting helpers
-- ============================================================

local function CountMatchingInBags(intent, charCtx)
    local total = 0
    local playerBags = Wild.GetPlayerBags and Wild.GetPlayerBags() or { BACKPACK_CONTAINER }
    if not Wild.GetPlayerBags then
        for i = 1, NUM_BAG_SLOTS do playerBags[#playerBags + 1] = i end
        if Enum.BagIndex.ReagentBag then playerBags[#playerBags + 1] = Enum.BagIndex.ReagentBag end
    end
    for _, bag in ipairs(playerBags) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then info.bag = bag; info.slot = slot end
            if info and info.itemID and IntentMatchesItem(intent, info.itemID, info, charCtx) then
                total = total + (info.stackCount or 1)
            end
        end
    end
    return total
end

-- ============================================================
-- Gold formatting helper
-- ============================================================

local function FormatGold(copper)
    local gold = math.floor(copper / COPPER_PER_GOLD)
    local silver = math.floor((copper % COPPER_PER_GOLD) / 100)
    local copperRem = copper % 100
    return string.format("%dg %ds %dc", gold, silver, copperRem)
end

-- ============================================================
-- Public API — Expose everything to Wild namespace
-- ============================================================

-- Tables
Wild.QUALITY_NAMES = QUALITY_NAMES
Wild.PROFESSION_SKILL_LINES = PROFESSION_SKILL_LINES
Wild.CLASS_FILES = CLASS_FILES
Wild.CLASS_LABELS = CLASS_LABELS
Wild.EQUIP_LOC_TO_SLOTS = EQUIP_LOC_TO_SLOTS
Wild.EQUIP_LOC_LABELS = EQUIP_LOC_LABELS
Wild.BIND_LABELS = BIND_LABELS
Wild.EXPANSION_NAMES = EXPANSION_NAMES
Wild.EXPANSION_IDS = EXPANSION_IDS
Wild.UPGRADE_TRACK_NAMES = UPGRADE_TRACK_NAMES
Wild.UPGRADE_TRACK_IDS = UPGRADE_TRACK_IDS
Wild.CLASS_ARMOR_SUBCLASS = CLASS_ARMOR_SUBCLASS
Wild.ATTRIBUTES = ATTRIBUTES
Wild.DYNAMIC_REFS = DYNAMIC_REFS
Wild.OPERATORS = OPERATORS
Wild.ATTR_BY_KEY = ATTR_BY_KEY
Wild.REF_BY_KEY = REF_BY_KEY
Wild.ACTION_LABELS = ACTION_LABELS
Wild.TARGET_LABELS = TARGET_LABELS
Wild.OP_DISPLAY = OP_DISPLAY

-- Functions
Wild.BuildCharContext = BuildCharContext
Wild.EvaluateCondition = EvaluateCondition
Wild.IntentMatchesItem = IntentMatchesItem
Wild.IntentMatchesActor = IntentMatchesActor
Wild.GetConditionsSummary = GetConditionsSummary
Wild.GetIntentSummary = GetIntentSummary
Wild.FormatConditionValue = FormatConditionValue
Wild.ValidateIntent = ValidateIntent
Wild.CountMatchingInBags = CountMatchingInBags
Wild.FormatGold = FormatGold
Wild.COPPER_PER_GOLD = COPPER_PER_GOLD
