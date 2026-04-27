-- Wild: Slash command parser & dispatcher
local ADDON_NAME, Wild = ...

local INFO = "|cff00ccffWild:|r "
local WARN = "|cffff6600Wild:|r "

local function Print(msg) print(INFO .. msg) end
local function PrintWarn(msg) print(WARN .. msg) end

local function ParseArgs(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        args[#args + 1] = word
    end
    return args
end

local function OnOff(str)
    if not str then return nil end
    str = str:lower()
    if str == "on" or str == "true" or str == "1" or str == "enable" then return true end
    if str == "off" or str == "false" or str == "0" or str == "disable" then return false end
    return nil
end

local function StatusText(enabled)
    return enabled and "|cff44ff44enabled|r" or "|cffff4444disabled|r"
end

-- Feature display names (for readable output)
local FEATURE_NAMES = {
    lfg              = "LFG Quick Apply",
    autoconfirmrole  = "LFG Auto-Confirm Role",
    autoacceptqueue  = "LFG Auto-Accept Queue",
    lfgfilters       = "LFG Result Filters",
    circle           = "Screen Center Circle",
    repair           = "Auto-Repair",
    loot             = "Quick Loot",
    autoloot         = "Auto-Loot",
    bank             = "Warband Bank",
    bankcharacter    = "Character Bank",
    bankguild        = "Guild Bank",
    reputation       = "Reputation Auto-Collapse",
    delve            = "Delve Auto-Select Power",
    tooltip          = "Tooltip Enhancements",
    auctionhouse     = "Auction House Defaults",
    craftingorders   = "Crafting Orders Defaults",
    dungeonbar       = "Dungeon Bar",
    autoaccept       = "Quest Auto-Accept",
    autohandin       = "Quest Auto-Hand-In",
    durabilityequipped = "Durability on Equipped",
    durabilitytotal    = "Durability Total Overlay",
    durabilitybags     = "Durability on Bag Items",
}

-- ============================================================
-- Generic feature on/off handler
-- ============================================================

local function HandleGenericFeature(feature, args)
    local name = FEATURE_NAMES[feature] or feature
    if #args == 0 then
        Print(name .. ": " .. StatusText(Wild.IsFeatureEnabled(feature)))
        return true
    end
    local val = OnOff(args[1])
    if val ~= nil then
        Wild.SetFeatureEnabled(feature, val)
        Print(name .. " " .. StatusText(val))
        return true
    end
    return false
end

-- ============================================================
-- Subcommand handlers
-- ============================================================

local subcommands = {}

-- /wild help
subcommands.help = function()
    print("|cff00ccff--- Wild Commands ---|r")
    Print("/wild — Toggle settings window")
    Print("/wild help — Show this help")
    Print("/wild status — Show all feature states")
    Print("/wild <feature> on|off — Toggle a feature")
    print(" ")
    print("|cff00ccff  Features:|r lfg, circle, repair, loot, autoloot,")
    print("    bank, bankcharacter, bankguild, reputation,")
    print("    delve, tooltip, auctionhouse (ah), craftingorders (co), dungeonbar (bar),")
    print("    autoaccept, autohandin, autoconfirmrole, autoacceptqueue, lfgfilters,")
    print("    volume (vol), durability (dur)")
    print(" ")
    Print("/wild lfg on|off — Toggle LFG quick apply")
    Print("/wild lfg autoconfirm on|off — Auto-confirm role")
    Print("/wild lfg autoaccept on|off — Auto-accept queue")
    Print("/wild lfg filters on|off — Toggle result filters")
    Print("/wild lfg keys on|off — Toggle keystone panel")
    Print("/wild lfg anchor <position> — Set keystone panel anchor (right|left|topleft|topright|bottomleft|bottomright)")
    print(" ")
    Print("/wild circle on|off — Toggle center circle")
    Print("/wild circle size <n> — Set circle size")
    Print("/wild circle thickness <n> — Set circle thickness")
    Print("/wild circle opacity <0-100> — Set circle opacity")
    Print("/wild circle color <r> <g> <b> — Set circle color (0-1 floats)")
    Print("/wild circle offset <x> <y> — Set circle offset")
    print(" ")
    Print("/wild repair on|off — Toggle auto-repair")
    Print("/wild repair guild on|off — Toggle guild funds")
    Print("/wild loot on|off — Toggle quick loot")
    Print("/wild loot modifier shift|ctrl|alt|none — Set auto-loot modifier key")
    print(" ")
    Print("/wild bank on|off — Toggle warband bank")
    Print("/wild bank character on|off — Toggle character bank")
    Print("/wild bank guild on|off — Toggle guild bank")
    Print("/wild bank run — Manually trigger bank filter rules")
    Print("/wild bank rules — List all bank filter rules")
    print(" ")
    Print("/wild quests on|off — Toggle all quest automation")
    Print("/wild quests accept on|off — Toggle quest auto-accept")
    Print("/wild quests handin on|off — Toggle quest auto-hand-in")
    print(" ")
    Print("/wild gossip — Show gossip automation status")
    Print("/wild gossip single on|off — Toggle auto-select single option")
    Print("/wild gossip quest on|off — Toggle auto-select quest options")
    Print("/wild gossip delve on|off — Toggle auto-select delve options")
    Print("/wild gossip skip on|off — Toggle auto-select skip options")
    print(" ")
    Print("/wild dungeonbar on|off — Toggle dungeon bar")
    Print("/wild dungeonbar show|hide|toggle — Control visibility")
    print(" ")
    Print("/wild volume on|off — Toggle volume control button")
    print(" ")
    Print("/wild durability — Show durability overlay status")
    Print("/wild durability on|off — Toggle all durability overlays")
    Print("/wild durability equipped on|off — Toggle per-slot equipped overlays")
    Print("/wild durability total on|off — Toggle total durability overlay")
    Print("/wild durability bags on|off — Toggle bag item overlays")
    print(" ")
    Print("/wild trace start — Start recording events")
    Print("/wild trace stop — Stop recording")
    Print("/wild trace filter <text> — Filter events by name")
    Print("/wild trace show — Show last 50 entries in chat")
    Print("/wild trace clear — Clear the log")
    print(" ")
    Print("/wild find <name> — Search items across all characters")
    Print("/wild datastore — Show cross-character datastore status")
    Print("/wild datastore refresh — Re-scan current character's bags")
    print(" ")
    Print("/wild delay — Show all timing settings")
    Print("/wild delay <setting> <seconds> — Set a timing value")
    Print("  Settings: rule, pass, bankstart, guildbankstart,")
    Print("  sellinterval, sellstart, mailstart, mailbatch,")
    Print("  destroystart, preloadtimeout")
    print(" ")
    Print("/wild reset — Reset all settings to defaults")
end

-- /wild status
subcommands.status = function()
    print("|cff00ccff--- Wild Status ---|r")
    -- Ordered list for predictable output
    local order = {
        "lfg", "autoconfirmrole", "autoacceptqueue", "lfgfilters",
        "circle", "repair", "loot", "autoloot",
        "bank", "bankcharacter", "bankguild",
        "reputation", "delve", "tooltip",
        "auctionhouse", "craftingorders", "dungeonbar", "autoaccept", "autohandin", "volume",
        "durabilityequipped", "durabilitytotal", "durabilitybags",
    }
    for _, feature in ipairs(order) do
        local name = FEATURE_NAMES[feature] or feature
        Print(name .. ": " .. StatusText(Wild.IsFeatureEnabled(feature)))
    end
end

-- /wild reset
subcommands.reset = function()
    Wild.ResetSettings()
end

-- /wild circle [on|off|size|thickness|opacity|color|offset]
subcommands.circle = function(args)
    if HandleGenericFeature("circle", args) then return end

    local sub = args[1]:lower()
    if sub == "size" then
        local n = tonumber(args[2])
        if not n then Print("Usage: /wild circle size <number>") return end
        Wild.SetSetting("screenCenterCircleSize", n)
        Wild.UpdateScreenCenterCircle()
        Print("Circle size set to " .. n)
    elseif sub == "thickness" then
        local n = tonumber(args[2])
        if not n then Print("Usage: /wild circle thickness <number>") return end
        Wild.SetSetting("screenCenterCircleThickness", n)
        Wild.UpdateScreenCenterCircle()
        Print("Circle thickness set to " .. n)
    elseif sub == "opacity" then
        local n = tonumber(args[2])
        if not n then Print("Usage: /wild circle opacity <0-100>") return end
        local color = Wild.GetSetting("screenCenterCircleColor") or { r = 1, g = 1, b = 1, a = 0.7 }
        color.a = math.max(0, math.min(1, n / 100))
        Wild.SetSetting("screenCenterCircleColor", color)
        Wild.UpdateScreenCenterCircle()
        Print("Circle opacity set to " .. n .. "%")
    elseif sub == "color" then
        local r = tonumber(args[2])
        local g = tonumber(args[3])
        local b = tonumber(args[4])
        if not r or not g or not b then Print("Usage: /wild circle color <r> <g> <b> (0-1)") return end
        local color = Wild.GetSetting("screenCenterCircleColor") or { r = 1, g = 1, b = 1, a = 0.7 }
        color.r, color.g, color.b = r, g, b
        Wild.SetSetting("screenCenterCircleColor", color)
        Wild.UpdateScreenCenterCircle()
        Print(string.format("Circle color set to (%.2f, %.2f, %.2f)", r, g, b))
    elseif sub == "offset" then
        local x = tonumber(args[2])
        local y = tonumber(args[3])
        if not x or not y then Print("Usage: /wild circle offset <x> <y>") return end
        Wild.SetSetting("screenCenterCircleOffsetX", x)
        Wild.SetSetting("screenCenterCircleOffsetY", y)
        Wild.UpdateScreenCenterCircle()
        Print(string.format("Circle offset set to (%d, %d)", x, y))
    else
        Print("Unknown circle subcommand: " .. sub .. ". Try /wild help")
    end
end

-- /wild lfg [on|off|autoconfirm|autoaccept|filters|keys|anchor]
subcommands.lfg = function(args)
    if HandleGenericFeature("lfg", args) then return end

    local sub = args[1]:lower()
    if sub == "autoconfirm" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild lfg autoconfirm on|off") return end
        Wild.SetFeatureEnabled("autoconfirmrole", v)
        Print("Auto-Confirm Role " .. StatusText(v))
    elseif sub == "autoaccept" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild lfg autoaccept on|off") return end
        Wild.SetFeatureEnabled("autoacceptqueue", v)
        Print("Auto-Accept Queue " .. StatusText(v))
    elseif sub == "filters" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild lfg filters on|off") return end
        Wild.SetFeatureEnabled("lfgfilters", v)
        Print("LFG Result Filters " .. StatusText(v))
    elseif sub == "keys" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild lfg keys on|off") return end
        Wild.db.lfg.keystoneButtons = v
        Print("Keystone Panel " .. StatusText(v))
        if Wild.__keystonePanelRefresh then Wild.__keystonePanelRefresh() end
    elseif sub == "anchor" then
        local valid = { right = "RIGHT", left = "LEFT", topleft = "TOPLEFT", topright = "TOPRIGHT", bottomleft = "BOTTOMLEFT", bottomright = "BOTTOMRIGHT" }
        local val = args[2] and valid[args[2]:lower()]
        if not val then
            Print("Usage: /wild lfg anchor right|left|topleft|topright|bottomleft|bottomright")
            Print("Current: " .. (Wild.db.lfg.keystoneAnchor or "RIGHT"))
            return
        end
        Wild.db.lfg.keystoneAnchor = val
        Print("Keystone panel anchor: " .. val)
        if Wild.__keystonePanelApplyAnchor then Wild.__keystonePanelApplyAnchor() end
    else
        Print("Unknown lfg subcommand: " .. sub .. ". Try /wild help")
    end
end

-- /wild repair [on|off|guild]
subcommands.repair = function(args)
    if HandleGenericFeature("repair", args) then return end

    local sub = args[1]:lower()
    if sub == "guild" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild repair guild on|off") return end
        Wild.SetSetting("vendorRepairUseGuild", v)
        Print("Guild repair funds " .. StatusText(v))
    else
        Print("Unknown repair subcommand: " .. sub .. ". Try /wild help")
    end
end

-- /wild loot [on|off|modifier]
subcommands.loot = function(args)
    if HandleGenericFeature("loot", args) then return end

    local sub = args[1]:lower()
    if sub == "modifier" then
        local mod = args[2] and args[2]:upper()
        if mod ~= "SHIFT" and mod ~= "CTRL" and mod ~= "ALT" and mod ~= "NONE" then
            Print("Usage: /wild loot modifier shift|ctrl|alt|none")
            return
        end
        Wild.SetSetting("lootAutoLootModifier", mod)
        Print("Loot modifier set to " .. mod)
    else
        Print("Unknown loot subcommand: " .. sub .. ". Try /wild help")
    end
end

-- /wild bank [on|off|character|guild|warband|run|rules]
subcommands.bank = function(args)
    if #args == 0 then
        Print("Warband Bank: " .. StatusText(Wild.IsFeatureEnabled("bank")))
        Print("Character Bank: " .. StatusText(Wild.IsFeatureEnabled("bankcharacter")))
        Print("Guild Bank: " .. StatusText(Wild.IsFeatureEnabled("bankguild")))
        return
    end

    local sub = args[1]:lower()
    local val = OnOff(sub)
    if val ~= nil then
        Wild.SetFeatureEnabled("bank", val)
        Print("Warband Bank " .. StatusText(val))
        return
    end

    if sub == "warband" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild bank warband on|off") return end
        Wild.SetFeatureEnabled("bank", v)
        Print("Warband Bank " .. StatusText(v))
    elseif sub == "character" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild bank character on|off") return end
        Wild.SetFeatureEnabled("bankcharacter", v)
        Print("Character Bank " .. StatusText(v))
    elseif sub == "guild" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild bank guild on|off") return end
        Wild.SetFeatureEnabled("bankguild", v)
        Print("Guild Bank " .. StatusText(v))
    elseif sub == "run" then
        Wild.RunBankIntents()
        Print("Bank intents executed.")
    elseif sub == "rules" then
        if not Wild.db or not Wild.db.intents then Print("No bank intents configured.") return end
        local any = false
        for _, info in ipairs({
            { target = "warband",   label = "Warband" },
            { target = "character", label = "Character" },
            { target = "guild",     label = "Guild" },
        }) do
            local count = 0
            for i, intent in ipairs(Wild.db.intents) do
                if intent.target == info.target
                    and (intent.action == "deposit" or intent.action == "withdraw" or intent.action == "hold") then
                    count = count + 1
                    if count == 1 then Print(info.label .. " bank intents:") end
                    any = true
                    local state = (intent.enabled ~= false) and "|cff44ff44ON|r" or "|cffff4444OFF|r"
                    local summary = Wild.GetIntentSummary and Wild.GetIntentSummary(intent) or "?"
                    print(string.format("  %d. [%s] %s", i, state, summary))
                end
            end
        end
        if not any then Print("No bank intents configured.") end
    else
        Print("Unknown bank subcommand: " .. sub .. ". Try /wild help")
    end
end

-- /wild reputation [on|off]  (alias: rep)
subcommands.reputation = function(args)
    if HandleGenericFeature("reputation", args) then return end
    Print("Usage: /wild reputation on|off")
end
subcommands.rep = subcommands.reputation

-- /wild delve [on|off]
subcommands.delve = function(args)
    if HandleGenericFeature("delve", args) then return end
    Print("Usage: /wild delve on|off")
end

-- /wild tooltip [on|off]
subcommands.tooltip = function(args)
    if HandleGenericFeature("tooltip", args) then return end
    Print("Usage: /wild tooltip on|off")
end

-- /wild auctionhouse [on|off]  (alias: ah)
subcommands.auctionhouse = function(args)
    if HandleGenericFeature("auctionhouse", args) then return end
    Print("Usage: /wild auctionhouse on|off")
end
subcommands.ah = subcommands.auctionhouse

-- /wild craftingorders [on|off]  (alias: co)
subcommands.craftingorders = function(args)
    if HandleGenericFeature("craftingorders", args) then return end
    Print("Usage: /wild craftingorders on|off")
end
subcommands.co = subcommands.craftingorders

-- /wild dungeonbar [on|off|show|hide|toggle]  (alias: bar)
subcommands.dungeonbar = function(args)
    if #args == 0 then
        Print("Dungeon Bar: " .. StatusText(Wild.IsFeatureEnabled("dungeonbar")))
        return
    end

    local sub = args[1]:lower()
    local val = OnOff(sub)
    if val ~= nil then
        Wild.SetFeatureEnabled("dungeonbar", val)
        if val and Wild.ShowDungeonBar then
            Wild.ShowDungeonBar()
        elseif not val and Wild.HideDungeonBar then
            Wild.HideDungeonBar()
        end
        Print("Dungeon Bar " .. StatusText(val))
        return
    end

    if sub == "show" then
        if Wild.ShowDungeonBar then Wild.ShowDungeonBar() end
    elseif sub == "hide" then
        if Wild.HideDungeonBar then Wild.HideDungeonBar() end
    elseif sub == "toggle" then
        if Wild.ToggleDungeonBar then Wild.ToggleDungeonBar() end
    else
        Print("Usage: /wild dungeonbar on|off|show|hide|toggle")
    end
end
subcommands.bar = subcommands.dungeonbar

-- /wild quests [on|off|accept|handin]  (alias: quest)
subcommands.quests = function(args)
    if #args == 0 then
        Print("Quest Auto-Accept: " .. StatusText(Wild.IsFeatureEnabled("autoaccept")))
        Print("Quest Auto-Hand-In: " .. StatusText(Wild.IsFeatureEnabled("autohandin")))
        return
    end

    local sub = args[1]:lower()
    if sub == "accept" or sub == "autoaccept" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild quests accept on|off") return end
        Wild.SetFeatureEnabled("autoaccept", v)
        Print("Quest Auto-Accept " .. StatusText(v))
    elseif sub == "handin" or sub == "autohandin" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild quests handin on|off") return end
        Wild.SetFeatureEnabled("autohandin", v)
        Print("Quest Auto-Hand-In " .. StatusText(v))
    else
        -- Treat as on/off for both together
        local val = OnOff(sub)
        if val ~= nil then
            Wild.SetFeatureEnabled("autoaccept", val)
            Wild.SetFeatureEnabled("autohandin", val)
            Print("Quest Auto-Accept " .. StatusText(val))
            Print("Quest Auto-Hand-In " .. StatusText(val))
        else
            Print("Usage: /wild quests [accept|handin] on|off")
        end
    end
end
subcommands.quest = subcommands.quests

-- /wild gossip [single|quest|delve|skip on|off]
subcommands.gossip = function(args)
    if #args == 0 then
        local g = Wild.db and Wild.db.gossip
        if not g then Print("Gossip settings unavailable.") return end
        Print("Gossip Auto-Select Single: " .. StatusText(g.autoSelectSingle))
        Print("Gossip Auto-Select Quest: " .. StatusText(g.autoSelectQuest))
        Print("Gossip Auto-Select Delve: " .. StatusText(g.autoSelectDelve))
        Print("Gossip Auto-Skip: " .. StatusText(g.autoSkip))
        return
    end

    local sub = args[1]:lower()
    if sub == "single" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild gossip single on|off") return end
        Wild.db.gossip.autoSelectSingle = v
        Print("Gossip Auto-Select Single " .. StatusText(v))
    elseif sub == "quest" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild gossip quest on|off") return end
        Wild.db.gossip.autoSelectQuest = v
        Print("Gossip Auto-Select Quest " .. StatusText(v))
    elseif sub == "delve" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild gossip delve on|off") return end
        Wild.db.gossip.autoSelectDelve = v
        Print("Gossip Auto-Select Delve " .. StatusText(v))
    elseif sub == "skip" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild gossip skip on|off") return end
        Wild.db.gossip.autoSkip = v
        Print("Gossip Auto-Skip " .. StatusText(v))
    else
        -- Treat as on/off for all gossip automation
        local val = OnOff(sub)
        if val ~= nil then
            Wild.db.gossip.autoSelectSingle = val
            Wild.db.gossip.autoSelectQuest = val
            Wild.db.gossip.autoSelectDelve = val
            Wild.db.gossip.autoSkip = val
            Print("Gossip automation " .. StatusText(val))
        else
            Print("Usage: /wild gossip [single|quest|delve|skip] on|off")
        end
    end
end

-- Simple on/off features that don't have subcommands
for _, feat in ipairs({ "autoloot", "autoconfirmrole", "autoacceptqueue", "lfgfilters", "autoaccept", "autohandin" }) do
    if not subcommands[feat] then
        subcommands[feat] = function(args) HandleGenericFeature(feat, args) end
    end
end

-- /wild find <name> — search for items across all characters
subcommands.find = function(args)
    if #args == 0 then
        Print("Usage: /wild find <item name>")
        return
    end
    local query = table.concat(args, " ")
    local results = Wild.FindItems(query)
    if #results == 0 then
        Print("No items matching \"" .. query .. "\" found in datastore.")
        return
    end
    Print("Items matching \"" .. query .. "\":")
    for _, r in ipairs(results) do
        local display = r.link or r.name or tostring(r.itemID)
        local detail = Wild.FormatItemBreakdown(r.breakdown)
        print(string.format("  %s — %dx total (%s)", display, r.total, detail))
    end
end
subcommands.search = subcommands.find

-- /wild volume on|off — toggle volume control button
subcommands.volume = function(args)
    HandleGenericFeature("volume", args)
end
subcommands.vol = subcommands.volume

-- /wild durability [on|off|equipped|total|bags]  (alias: dur)
subcommands.durability = function(args)
    if #args == 0 then
        local db = Wild.db and Wild.db.durability
        if not db then Print("Durability settings unavailable.") return end
        Print("Durability on Equipped Items: " .. StatusText(db.showEquipped))
        Print("Durability Total Overlay: " .. StatusText(db.showEquippedTotal))
        Print("Durability on Bag Items: " .. StatusText(db.showBags))
        return
    end

    local sub = args[1]:lower()

    -- Global on/off toggles all three
    local val = OnOff(sub)
    if val ~= nil then
        Wild.SetFeatureEnabled("durabilityequipped", val)
        Wild.SetFeatureEnabled("durabilitytotal", val)
        Wild.SetFeatureEnabled("durabilitybags", val)
        Print("Durability overlays " .. StatusText(val))
        return
    end

    if sub == "equipped" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild durability equipped on|off") return end
        Wild.SetFeatureEnabled("durabilityequipped", v)
        Print("Durability on Equipped Items " .. StatusText(v))
    elseif sub == "total" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild durability total on|off") return end
        Wild.SetFeatureEnabled("durabilitytotal", v)
        Print("Durability Total Overlay " .. StatusText(v))
    elseif sub == "bags" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild durability bags on|off") return end
        Wild.SetFeatureEnabled("durabilitybags", v)
        Print("Durability on Bag Items " .. StatusText(v))
    else
        Print("Usage: /wild durability [equipped|total|bags] on|off")
    end
end
subcommands.dur = subcommands.durability

-- /wild datastore [status|clear|refresh] — manage cross-character datastore
subcommands.datastore = function(args)
    local sub = args[1] and args[1]:lower() or "status"

    if sub == "status" then
        local lines = Wild.GetDatastoreSummary()
        if type(lines) == "string" then
            Print(lines)
        else
            for _, line in ipairs(lines) do
                print(line)
            end
        end
    elseif sub == "refresh" then
        Wild.SnapshotBags()
        Print("Bags refreshed for current character.")
    else
        Print("Usage: /wild datastore [status|refresh]")
    end
end
subcommands.ds = subcommands.datastore

-- /wild delay [setting] [seconds]
subcommands.delay = function(args)
    local DELAY_SETTINGS = {
        rule            = { key = "ruleDelay",          label = "Rule delay" },
        pass            = { key = "passDelay",          label = "Pass delay" },
        bankstart       = { key = "bankStartDelay",     label = "Bank start delay" },
        guildbankstart  = { key = "guildBankStartDelay",label = "Guild bank start delay" },
        sellinterval    = { key = "sellInterval",       label = "Sell interval" },
        sellstart       = { key = "sellStartDelay",     label = "Sell start delay" },
        mailstart       = { key = "mailStartDelay",     label = "Mail start delay" },
        mailbatch       = { key = "mailBatchDelay",     label = "Mail batch delay" },
        destroystart    = { key = "destroyStartDelay",  label = "Destroy start delay" },
        preloadtimeout  = { key = "preloadTimeout",     label = "Preload timeout" },
    }

    local sub = args[1] and args[1]:lower() or nil

    if not sub then
        -- Show all current values
        print("|cff00ccff--- Wild Timing Settings ---|r")
        local order = { "rule", "pass", "bankstart", "guildbankstart", "sellinterval", "sellstart", "mailstart", "mailbatch", "destroystart", "preloadtimeout" }
        for _, name in ipairs(order) do
            local s = DELAY_SETTINGS[name]
            Print(s.label .. ": " .. (Wild.db.advanced[s.key] or 0.3) .. "s")
        end
        return
    end

    local setting = DELAY_SETTINGS[sub]
    if not setting then
        Print("Unknown delay setting: " .. sub .. ". Options: rule, pass, bankstart, guildbankstart, sellinterval, sellstart, mailstart, mailbatch, destroystart, preloadtimeout")
        return
    end

    local val = tonumber(args[2])
    if not val then
        Print(setting.label .. ": " .. (Wild.db.advanced[setting.key] or 0.3) .. "s")
        return
    end
    val = math.max(0.1, math.min(1.0, math.floor(val * 10 + 0.5) / 10))
    Wild.db.advanced[setting.key] = val
    Print(setting.label .. " set to " .. val .. "s.")
end

-- ============================================================
-- Main dispatcher
-- ============================================================

function Wild.HandleSlashCommand(msg)
    msg = strtrim(msg or "")
    if msg == "" then
        Wild.ToggleSettings()
        return
    end

    local args = ParseArgs(msg)
    local cmd = tremove(args, 1):lower()

    if subcommands[cmd] then
        subcommands[cmd](args)
    elseif Wild.FEATURES[cmd] then
        HandleGenericFeature(cmd, args)
    else
        PrintWarn("Unknown command: " .. cmd .. ". Type /wild help for a list.")
    end
end

-- ============================================================
-- Event Trace (/wild trace)
-- ============================================================

do
    local traceFrame = CreateFrame("Frame")
    local traceRecording = false
    local traceFilter = nil
    local MAX_TRACE_ARGS = 10

    local function ArgsToString(...)
        local n = select("#", ...)
        if n == 0 then return "" end
        local parts = {}
        for i = 1, math.min(n, MAX_TRACE_ARGS) do
            parts[i] = tostring(select(i, ...))
        end
        return table.concat(parts, ", ")
    end

    traceFrame:SetScript("OnEvent", function(self, event, ...)
        if not traceRecording then return end
        if traceFilter and not event:lower():find(traceFilter, 1, true) then return end
        if not Wild.db then return end
        Wild.db.eventTrace = Wild.db.eventTrace or {}
        local entry = string.format("[%.3f] %s", GetTime(), event)
        local args = ArgsToString(...)
        if args ~= "" then
            entry = entry .. " | " .. args
        end
        table.insert(Wild.db.eventTrace, entry)
    end)

    subcommands.trace = function(args)
        local sub = args[1] and args[1]:lower() or ""

        if sub == "start" then
            if not Wild.db then Print("Settings not loaded yet.") return end
            Wild.db.eventTrace = Wild.db.eventTrace or {}
            traceRecording = true
            traceFrame:RegisterAllEvents()
            local msg = "Event trace started."
            if traceFilter then
                msg = msg .. " Filter: |cffffffff" .. traceFilter .. "|r"
            end
            Print(msg)

        elseif sub == "stop" then
            traceRecording = false
            traceFrame:UnregisterAllEvents()
            local count = Wild.db and Wild.db.eventTrace and #Wild.db.eventTrace or 0
            Print("Event trace stopped. " .. count .. " entries logged.")
            Print("/reload to flush to WildDB.eventTrace in saved variables.")

        elseif sub == "clear" then
            if Wild.db then Wild.db.eventTrace = {} end
            Print("Event trace log cleared.")

        elseif sub == "filter" then
            local f = args[2] and args[2]:trim() or ""
            if f == "" then
                traceFilter = nil
                Print("Trace filter cleared (logging all events).")
            else
                traceFilter = f:lower()
                Print("Trace filter set to |cffffffff" .. f .. "|r")
            end

        elseif sub == "show" then
            if not Wild.db or not Wild.db.eventTrace or #Wild.db.eventTrace == 0 then
                Print("Event trace log is empty.")
                return
            end
            local count = #Wild.db.eventTrace
            local start = math.max(1, count - 49)
            Print("Last " .. (count - start + 1) .. " of " .. count .. " entries:")
            for i = start, count do
                print("  " .. Wild.db.eventTrace[i])
            end

        else
            Print("/wild trace start — Start recording events")
            Print("/wild trace stop — Stop recording")
            Print("/wild trace filter <text> — Only log events matching text")
            Print("/wild trace filter — Clear filter")
            Print("/wild trace show — Show last 50 entries in chat")
            Print("/wild trace clear — Clear the log")
            Print("Log is saved to WildDB.eventTrace in saved variables.")
        end
    end
end

-- ============================================================
-- Register slash command
-- ============================================================

SLASH_WILD1 = "/wild"
SlashCmdList["WILD"] = Wild.HandleSlashCommand
