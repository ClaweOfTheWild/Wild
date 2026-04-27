-- Wild: Core addon initialization
local ADDON_NAME, Wild = ...

-- Default saved variables
local defaults = {
    includeReagentBag = true,
    lfg = {
        quickApply = true,
        autoConfirmRole = false,
        autoAcceptRoleCheck = false,
        keystoneButtons = true,
        keystoneAnchor = "RIGHT",
    },
    screenCenterCircle = false,
    screenCenterCircleSize = 40,
    screenCenterCircleColor = { r = 1, g = 1, b = 1, a = 0.7 },
    screenCenterCircleThickness = 2,
    screenCenterCircleOffsetX = 0,
    screenCenterCircleOffsetY = 0,
    bankCharacter = {
        enabled = false,
    },
    bankWarband = {
        enabled = false,
        depositWarbound = false,
        depositReagents = false,
    },
    bankGuild = {
        enabled = false,
    },
    vendorAutoRepair = false,
    vendorRepairUseGuild = false,
    lootQuickLoot = true,
    lootAutoLoot = true,
    lootAutoLootModifier = "SHIFT",
    reputationCollapseMode = "off",
    reputationCollapsedHeaders = {},
    currencyCollapseMode = "off",
    currencyCollapsedHeaders = {},
    delveAutoSelectPower = true,
    tooltip = {
        enabled = true,
        lines = {
            itemID = "always",
            itemType = "settings",
            itemLevel = "never",
            sellPrice = "never",
            equipSlot = "never",
            quality = "never",
            stackSize = "never",
            expansionID = "never",
            bindType = "never",
            isReagent = "never",
            collectionStatus = "never",
            intentMatch = "never",
            crossCharCount = "never",
        },
    },
    auctionHouse = {
        enabled = false,
        filters = {},
        minLevel = 0,
        maxLevel = 0,
    },
    craftingOrders = {
        enabled = false,
        filters = {},
        minLevel = 0,
        maxLevel = 0,
    },
    dungeonBar = {
        enabled = false,
        autoShowInInstance = false,
        position = nil,
        pullPresets = { 3, 5, 8, 10 },
        showReadyCheck = true,
        showCancelPull = true,
        showCustomPull = false,
        customPullSeconds = 10,
        showDisband = false,
        showTooltips = false,
    },
    quests = {
        autoAccept = false,
        acceptNormal = true,       -- accept regular (one-time) quests
        acceptDaily = true,        -- accept daily quests
        acceptWeekly = true,       -- accept weekly quests
        acceptRepeatable = true,   -- accept repeatable quests
        acceptTrivial = false,     -- accept grey / low-level quests
        toggleKey = 4,             -- 1 = none, 2 = ALT, 3 = CTRL, 4 = SHIFT — hold to invert automation
        autoHandIn = false,
        autoSelectReward = true,   -- pick highest-value reward when handing in
    },
    gossip = {
        autoSelectSingle = false,  -- auto-select when only one gossip option
        autoSelectQuest = false,   -- auto-select gossip options typed as quest
        autoSelectDelve = false,   -- auto-select gossip options typed as delve
        autoSkip = false,          -- auto-select gossip options that offer a skip
        skipIfQuest = true,        -- also skip gossip if there are quest or delve dialogs
        darkmoonTeleport = false,  -- always accept the Darkmoon Faire teleport dialog
        toggleKey = 4,             -- 1 = none, 2 = ALT, 3 = CTRL, 4 = SHIFT — hold to bypass automation
    },
    autoReply = {
        enabled = false,
        message = "I'm currently in a Mythic+ dungeon and can't respond right now. I'll get back to you after the key!",
        replyWhispers = true,      -- reply to /whisper
        replyBNetWhispers = true,  -- reply to Battle.net whispers
        onlyInProgress = true,     -- only while the key timer is running (not during downtime inside)
    },
    darkmoonFaire = {
        showProfessionHelper = false, -- show a shopping list when entering a DMF staging area
    },
    durability = {
        showEquipped = false,
        showEquippedTotal = false,
        totalPosition = nil,
        showBags = false,
    },
    mail = {
        autoOpen = false,
    },
    volumeControl = {
        enabled = false,
        buttonPos = nil,
    },
    intents = {},
    actors = {
        characters = {},
        labels = {},
    },
    datastore = {
        characters = {},
        guilds = {},
        warband = {},
    },
    advanced = {
        debug = false,
        ruleDelay = 0.3,          -- seconds to wait before processing the next intent/rule
        passDelay = 0.3,          -- seconds to wait before retrying the same rule after bags settle
        bankStartDelay = 0.3,     -- seconds before bank intent processing begins after bank opens
        guildBankStartDelay = 0.3, -- seconds before guild bank intent processing begins
        sellInterval = 0.3,       -- seconds between selling individual items at a vendor
        sellStartDelay = 0.3,     -- seconds before sell processing begins after merchant opens
        mailStartDelay = 0.3,     -- seconds before mail send processing begins after mailbox opens
        mailBatchDelay = 0.3,     -- seconds between mail batches (groups of 12 attachments)
        destroyStartDelay = 0.3,  -- seconds before destroy processing begins after trigger
        preloadTimeout = 0.3,     -- safety timeout for item data preloading (seconds)
    },
    log = {
        entries = {},
        nextIndex = 1,
    },
}

-- Deep merge: apply default values for missing keys, recursing into tables
local function ApplyDefaults(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" and not v[1] then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

-- Initialize saved variables on login
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if addon ~= ADDON_NAME then return end

    if not WildDB then
        WildDB = {}
    end

    if not WildDB.intents then WildDB.intents = {} end

    -- Migrate legacy collection conditions to unified item.isKnown
    local LEGACY_KNOWN_ATTRS = {
        ["item.isKnownToy"] = true,
        ["item.isKnownMount"] = true,
        ["item.isKnownPet"] = true,
        ["item.isPetMaxed"] = true,
        ["item.isKnownAppearance"] = true,
        ["item.isRecipe"] = true,
    }
    for _, intent in ipairs(WildDB.intents) do
        -- Migrate flat conditions to groups
        if intent.conditions and not intent.groups then
            for _, cond in ipairs(intent.conditions) do
                if LEGACY_KNOWN_ATTRS[cond.attr] then
                    cond.attr = "item.isKnown"
                end
            end
            if #intent.conditions > 0 then
                intent.groups = { { mode = "include", conditions = intent.conditions } }
            else
                intent.groups = {}
            end
            intent.conditions = nil
        elseif intent.groups then
            for _, group in ipairs(intent.groups) do
                if group.conditions then
                    for _, cond in ipairs(group.conditions) do
                        if LEGACY_KNOWN_ATTRS[cond.attr] then
                            cond.attr = "item.isKnown"
                        end
                    end
                end
            end
        end
    end

    -- Migrate goldTarget / keep from intent root into groups
    for _, intent in ipairs(WildDB.intents) do
        local migrated = false
        -- Migrate goldTarget into a gold-kind include group
        if intent.goldTarget and intent.goldTarget > 0 then
            if not intent.groups then intent.groups = {} end
            table.insert(intent.groups, 1, { mode = "include", kind = "gold", gold = intent.goldTarget })
            migrated = true
        end
        intent.goldTarget = nil
        -- Migrate keep into existing item include groups as count
        local keep = intent.keep
        if keep and keep > 0 then
            for _, g in ipairs(intent.groups or {}) do
                if g.mode ~= "exclude" and g.kind ~= "gold" then
                    if g.count == nil then
                        g.count = keep
                    end
                end
            end
            migrated = true
        end
        intent.keep = nil
        -- Ensure all include item groups have kind = "items"
        for _, g in ipairs(intent.groups or {}) do
            if g.mode ~= "exclude" and not g.kind then
                g.kind = "items"
            end
        end

        -- Migrate hold condition-based item groups to simplified kind="item"
        if intent.action == "hold" then
            for _, g in ipairs(intent.groups or {}) do
                if g.kind == "items" and g.conditions and #g.conditions == 1 then
                    local c = g.conditions[1]
                    if c.attr == "item.id" and c.op == "=" and c.value then
                        g.kind = "item"
                        g.itemID = tonumber(c.value)
                        g.conditions = nil
                    end
                end
            end
        end
    end

    ApplyDefaults(WildDB, defaults)
    Wild.db = WildDB

    self:UnregisterEvent("ADDON_LOADED")
end)

-- ============================================================
-- Character data collection (runs after PLAYER_LOGIN)
-- ============================================================

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if not Wild.db then return end

        -- Ensure actors structure exists
        if not Wild.db.actors then Wild.db.actors = { characters = {}, labels = {} } end
        if not Wild.db.actors.characters then Wild.db.actors.characters = {} end
        if not Wild.db.actors.labels then Wild.db.actors.labels = {} end

        -- Ensure "Everyone" label exists
        local hasEveryone = false
        for _, lbl in ipairs(Wild.db.actors.labels) do
            if lbl.name == "Everyone" then hasEveryone = true; break end
        end
        if not hasEveryone then
            table.insert(Wild.db.actors.labels, 1, { name = "Everyone" })
        end

        -- Small delay to let all data load
        C_Timer.After(2, function()
            Wild.CollectCurrentCharacter()
        end)

        -- Listen for events that affect character labels
        self:RegisterEvent("PLAYER_LEVEL_UP")
        self:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
        self:RegisterEvent("SKILL_LINES_CHANGED")
        self:UnregisterEvent("PLAYER_LOGIN")
        return
    end

    -- Debounce updates from rapid-fire events
    if self._pendingUpdate then return end
    self._pendingUpdate = true
    C_Timer.After(1, function()
        self._pendingUpdate = nil
        Wild.CollectCurrentCharacter()
    end)
end)

function Wild.CollectCurrentCharacter()
    if not Wild.db or not Wild.db.actors then return end

    local name = UnitName("player")
    local realm = GetRealmName()
    local fullName = name .. "-" .. realm
    local _, classFile = UnitClass("player")
    local _, race = UnitRace("player")
    local faction = UnitFactionGroup("player")
    local level = UnitLevel("player")
    local avgIlvl = select(1, GetAverageItemLevel()) or 0

    -- Gather professions
    local profs = {}
    local prof1, prof2 = GetProfessions()
    for _, idx in ipairs({ prof1, prof2 }) do
        if idx then
            local profName, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
            if skillLine then
                profs[skillLine] = profName or true
            end
        end
    end

    local chars = Wild.db.actors.characters
    local existing = chars[fullName] or {}

    chars[fullName] = {
        name = name,
        realm = realm,
        class = classFile,
        race = race,
        faction = faction,
        level = level,
        ilvl = math.floor(avgIlvl),
        professions = profs,
        labels = existing.labels or {},
        lastSeen = time(),
    }

    -- Ensure "Everyone" label is always assigned
    local charLabels = chars[fullName].labels
    local hasEveryone = false
    for _, lbl in ipairs(charLabels) do
        if lbl == "Everyone" then hasEveryone = true; break end
    end
    if not hasEveryone then
        table.insert(charLabels, 1, "Everyone")
    end
end

-- NOTE: Inventory snapshot system has moved to CharacterData.lua
-- See Wild.SnapshotBags(), Wild.SnapshotBank(), Wild.SnapshotWarbandBank(),
-- Wild.SnapshotGuildBank(), Wild.GetItemTotal(), Wild.FindItems()

function Wild.GetActorLabels(charKey)
    if not Wild.db or not Wild.db.actors then return {} end
    local char = Wild.db.actors.characters[charKey]
    if not char then return {} end

    -- Combine auto-discovered labels with custom labels
    local labels = {}

    -- Class
    local classLabel = Wild.CLASS_LABELS and Wild.CLASS_LABELS[char.class] or char.class
    if classLabel then labels[#labels + 1] = classLabel end

    -- Race
    if char.race then labels[#labels + 1] = char.race end

    -- Faction
    if char.faction then labels[#labels + 1] = char.faction end

    -- Professions
    if char.professions then
        for skillLine, profName in pairs(char.professions) do
            if type(profName) == "string" then
                labels[#labels + 1] = profName
            elseif Wild.PROFESSION_SKILL_LINES and Wild.PROFESSION_SKILL_LINES[skillLine] then
                labels[#labels + 1] = Wild.PROFESSION_SKILL_LINES[skillLine]
            end
        end
    end

    -- Custom labels
    if char.labels then
        for _, lbl in ipairs(char.labels) do
            labels[#labels + 1] = lbl
        end
    end

    return labels
end

function Wild.GetAllActorOptions()
    -- Returns a flat list of all possible actor values grouped by type
    local options = {}
    local seen = {}

    -- "Everyone" is always available as a built-in label
    seen["Everyone"] = true
    options[#options + 1] = { value = "Everyone", category = "Labels" }

    -- Custom labels
    local labels = Wild.db and Wild.db.actors and Wild.db.actors.labels or {}
    for _, lbl in ipairs(labels) do
        if not seen[lbl.name] then
            seen[lbl.name] = true
            options[#options + 1] = { value = lbl.name, category = "Labels" }
        end
    end

    -- Auto labels: classes
    if Wild.CLASS_FILES then
        for _, classFile in ipairs(Wild.CLASS_FILES) do
            local name = Wild.CLASS_LABELS and Wild.CLASS_LABELS[classFile] or classFile
            if name and not seen[name] then
                seen[name] = true
                options[#options + 1] = { value = name, category = "Classes" }
            end
        end
    end

    -- Auto labels: factions
    for _, faction in ipairs({ "Alliance", "Horde", "Neutral" }) do
        if not seen[faction] then
            seen[faction] = true
            options[#options + 1] = { value = faction, category = "Factions" }
        end
    end

    -- Auto labels: professions
    if Wild.PROFESSION_SKILL_LINES then
        local sorted = {}
        for _, name in pairs(Wild.PROFESSION_SKILL_LINES) do
            sorted[#sorted + 1] = name
        end
        table.sort(sorted)
        for _, name in ipairs(sorted) do
            if not seen[name] then
                seen[name] = true
                options[#options + 1] = { value = name, category = "Professions" }
            end
        end
    end

    -- Characters
    local chars = Wild.db and Wild.db.actors and Wild.db.actors.characters or {}
    local charKeys = {}
    for key in pairs(chars) do charKeys[#charKeys + 1] = key end
    table.sort(charKeys)
    for _, key in ipairs(charKeys) do
        if not seen[key] then
            seen[key] = true
            local data = chars[key]
            local classLabel = Wild.CLASS_LABELS and Wild.CLASS_LABELS[data.class] or data.class or ""
            options[#options + 1] = { value = key, display = key .. "  |cff888888(" .. classLabel .. ")|r", category = "Characters" }
        end
    end

    return options
end

-- Expose addon table
Wild.name = ADDON_NAME
Wild.defaults = defaults

-- ============================================================
-- Dotted-key navigation helpers
-- ============================================================

local function GetNestedValue(tbl, path)
    for segment in path:gmatch("[^%.]+") do
        if type(tbl) ~= "table" then return nil end
        tbl = tbl[segment]
    end
    return tbl
end

local function SetNestedValue(tbl, path, value)
    local segments = {}
    for segment in path:gmatch("[^%.]+") do
        segments[#segments + 1] = segment
    end
    for i = 1, #segments - 1 do
        local seg = segments[i]
        if type(tbl[seg]) ~= "table" then
            tbl[seg] = {}
        end
        tbl = tbl[seg]
    end
    tbl[segments[#segments]] = value
end

-- ============================================================
-- Feature registry
-- ============================================================

local FEATURES = {
    lfg              = { key = "lfg.quickApply" },
    autoconfirmrole  = { key = "lfg.autoConfirmRole" },
    autorolecheck    = { key = "lfg.autoAcceptRoleCheck" },

    circle           = { key = "screenCenterCircle",    onToggle = function() Wild.UpdateScreenCenterCircle() end },
    repair           = { key = "vendorAutoRepair" },
    loot             = { key = "lootQuickLoot",         onToggle = function(v) Wild.SetQuickLoot(v) end },
    autoloot         = { key = "lootAutoLoot",          onToggle = function(v) Wild.SetAutoLoot(v) end },
    bank             = { key = "bankWarband.enabled" },
    bankcharacter    = { key = "bankCharacter.enabled" },
    bankguild        = { key = "bankGuild.enabled" },
    reputation       = { key = "reputationAutoCollapse" },
    delve            = { key = "delveAutoSelectPower" },
    tooltip          = { key = "tooltip.enabled" },
    auctionhouse     = { key = "auctionHouse.enabled" },
    craftingorders   = { key = "craftingOrders.enabled" },
    mail             = { key = "mail.autoOpen" },
    dungeonbar       = { key = "dungeonBar.enabled" },
    autoaccept       = { key = "quests.autoAccept" },
    autohandin       = { key = "quests.autoHandIn" },
    volume           = { key = "volumeControl.enabled", onToggle = function() Wild.UpdateVolumeControl() end },
    durability       = { key = "durability.showEquipped", onToggle = function() Wild.UpdateDurabilityOverlays() end },
    durabilityequipped = { key = "durability.showEquipped", onToggle = function() Wild.UpdateDurabilityOverlays() end },
    durabilitytotal  = { key = "durability.showEquippedTotal", onToggle = function() Wild.UpdateDurabilityOverlays() end },
    durabilitybags   = { key = "durability.showBags", onToggle = function() Wild.UpdateDurabilityOverlays() end },
}

Wild.FEATURES = FEATURES

-- ============================================================
-- Public API — Effective sell price
-- Uses C_TooltipInfo to get the real vendor price (accounts for
-- upgrades / bonus IDs) and falls back to GetItemInfo base price.
-- ============================================================

function Wild.GetEffectiveSellPrice(itemID, containerInfo)
    -- 1) Tooltip money from bag item (most accurate, includes upgrade scaling)
    if containerInfo and containerInfo.bag and containerInfo.slot
       and C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local data = C_TooltipInfo.GetBagItem(containerInfo.bag, containerInfo.slot)
        if data then
            if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
            if data.money then return data.money end
        end
    end

    -- 2) Tooltip money from hyperlink (works outside bags)
    local link = containerInfo and containerInfo.hyperlink
    if link and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local data = C_TooltipInfo.GetHyperlink(link)
        if data then
            if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
            if data.money then return data.money end
        end
    end

    -- 3) Fallback: GetItemInfo base sell price
    local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemID)
    return sellPrice or 0
end

-- ============================================================
-- Public API — Feature toggles
-- ============================================================

function Wild.IsFeatureEnabled(feature)
    if not Wild.db then return false end
    local info = FEATURES[feature:lower()]
    if not info then return false end
    return GetNestedValue(Wild.db, info.key) and true or false
end

function Wild.SetFeatureEnabled(feature, enabled)
    if not Wild.db then return end
    local info = FEATURES[feature:lower()]
    if not info then
        print("|cffff6600Wild:|r Unknown feature: " .. tostring(feature))
        return
    end
    SetNestedValue(Wild.db, info.key, enabled)
    if info.onToggle then info.onToggle(enabled) end
end

-- ============================================================
-- Public API — Generic settings
-- ============================================================

function Wild.GetSetting(key)
    if not Wild.db then return nil end
    return GetNestedValue(Wild.db, key)
end

function Wild.SetSetting(key, value)
    if not Wild.db then return end
    SetNestedValue(Wild.db, key, value)
end

function Wild.ResetSettings()
    if not Wild.db then return end
    wipe(Wild.db)
    ApplyDefaults(Wild.db, defaults)
    if Wild.UpdateScreenCenterCircle then Wild.UpdateScreenCenterCircle() end
    if Wild.SetQuickLoot then Wild.SetQuickLoot(Wild.db.lootQuickLoot) end
    print("|cff00ccffWild:|r All settings reset to defaults.")
end
