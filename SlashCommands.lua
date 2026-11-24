-- Wild: Slash command catalog and dispatcher
local ADDON_NAME, Wild = ...

local INFO = "|cff00ccffWild:|r "
local WARN = "|cffff6600Wild:|r "

local function Print(msg) Wild.Print(INFO .. msg) end
local function PrintWarn(msg) Wild.Print(WARN .. msg) end

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

local function FeatureStatus(feature)
    if not Wild.IsFeatureAvailable(feature) then return "|cffffaa00not available|r" end
    return StatusText(Wild.IsFeatureEnabled(feature))
end

-- Feature display names (for readable output)
local FEATURE_NAMES = {
    lfg              = "LFG Quick Apply",
    autoconfirmrole  = "LFG Auto-Confirm Role",
    autoacceptqueue  = "LFG Auto-Accept Queue",
    lfgfilters       = "LFG Result Filters",
    circle           = "Screen Center Circle",
    casthistory      = "Cast History",
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
    mail             = "Automatic Incoming Mail Collection",
    mailautosend     = "Automatic Mail Rules",
    inbox            = "Wild Mailbox",
    inboxkeepunread  = "Keep Unread Mail",
    dungeonbar       = "Dungeon Bar",
    autoreply        = "Mythic+ Auto-Reply",
    autoaccept       = "Quest Auto-Accept",
    autohandin       = "Quest Auto-Hand-In",
    durabilityequipped = "Durability on Equipped",
    durabilitytotal    = "Durability Total Overlay",
    durabilitybags     = "Durability on Bag Items",
    speed              = "Speed Indicator",
    dialog             = "Dialog Key",
    soiree             = "Soiree Reputation Advisor",
}

-- ============================================================
-- Generic feature on/off handler
-- ============================================================

local function HandleGenericFeature(feature, args)
    local name = FEATURE_NAMES[feature] or feature
    if #args == 0 then
        Print(name .. ": " .. FeatureStatus(feature))
        return true
    end
    local val = OnOff(args[1])
    if val ~= nil then
        if Wild.SetFeatureEnabled(feature, val) then Print(name .. " " .. StatusText(val)) end
        return true
    end
    return false
end

-- ============================================================
-- Subcommand handlers
-- ============================================================

local WILD_SLASH = "/wild"
local commandHandlers = {}
local commandCatalog = {}

local function AddCatalogEntry(syntax, description)
    commandCatalog[#commandCatalog + 1] = { syntax = syntax, description = description }
end

local function CommandSyntax(name, arguments)
    return WILD_SLASH .. (name == "" and "" or " " .. name) .. (arguments == "" and "" or " " .. arguments)
end

-- Register each accepted form beside its handler so the Commands page does not maintain a separate list.
local function RegisterCommand(name, forms, handler, aliases)
    assert(not commandHandlers[name] and #forms > 0, "Invalid command registration: " .. name)
    commandHandlers[name] = handler
    for _, form in ipairs(forms) do
        AddCatalogEntry(CommandSyntax(name, form[1]), form[2])
    end
    for _, alias in ipairs(aliases or {}) do
        assert(not commandHandlers[alias], "Duplicate command alias: " .. alias)
        commandHandlers[alias] = handler
        local arguments = #forms == 1 and forms[1][1] or "[<arguments>]"
        AddCatalogEntry(CommandSyntax(alias, arguments), "Alias for " .. CommandSyntax(name, "") .. ". Use the same arguments.")
    end
end

local function RegisterFeatureCommand(name, description, aliases)
    RegisterCommand(name, { { "[on|off]", description } }, function(args)
        if not HandleGenericFeature(name, args) then
            PrintWarn("Usage: " .. CommandSyntax(name, "[on|off]"))
        end
    end, aliases)
end

local function OpenCommands()
    Wild.OpenSettings("Commands")
end

RegisterCommand("", { { "", "Open Wild settings." } }, function()
    Wild.OpenSettings()
end)

RegisterCommand("help", { { "", "Open the Commands page." } }, OpenCommands)

RegisterCommand("status", { { "", "Show the client mode and feature states." } }, function()
    print("|cff00ccff--- Wild Status ---|r")
    Print("Client mode: " .. Wild.GetClientMode())
    -- Ordered list for predictable output
    local order = {
        "lfg", "autoconfirmrole", "autoacceptqueue", "lfgfilters",
        "circle", "casthistory", "repair", "loot", "autoloot",
        "bank", "bankcharacter", "bankguild",
        "reputation", "delve", "tooltip",
        "auctionhouse", "craftingorders", "mail", "mailautosend", "inbox",
        "dungeonbar", "autoreply", "autoaccept", "autohandin", "volume",
        "durabilityequipped", "durabilitytotal", "durabilitybags",
        "speed", "dialog", "soiree",
    }
    for _, feature in ipairs(order) do
        local name = FEATURE_NAMES[feature] or feature
        Print(name .. ": " .. FeatureStatus(feature))
    end
    Print("New container auto-open: " .. StatusText(Wild.GetSetting("containers.autoOpenNew")))
end)

RegisterCommand("client", { { "", "Show the detected WoW client mode." } }, function()
    Print("Client mode: " .. Wild.GetClientMode())
end)

RegisterCommand("reset", { { "", "Reset Wild settings and clear this client's collected item data and container list." } }, function()
    Wild.ResetSettings()
end)

RegisterCommand("native", {
    { "[<page>]", "Open Wild settings or go to a page by name, for example speed." },
}, function(args)
    local page = #args > 0 and table.concat(args, " ") or nil
    Wild.OpenSettings(page)
end)

RegisterCommand("containers", {
    { "", "Open container settings." },
    { "<itemID> on|off", "Set whether a container with this item ID opens automatically." },
    { "add <itemID> [on|off]", "Save a container item ID. Auto-open is off unless you specify on." },
    { "default [on|off]", "Show or set auto-open for newly discovered containers only." },
    { "list", "Show saved container IDs and their auto-open settings." },
    { "legacy", "Show archived container choices from older files with no client tag." },
    { "scan", "Scan bags for containers and retry containers that timed out." },
}, function(args)
    if #args == 0 then Wild.OpenSettings("Containers"); return end
    local sub = args[1]:lower()
    if sub == "default" and #args <= 2 then
        if #args == 1 then
            Print("New container auto-open: " .. StatusText(Wild.GetSetting("containers.autoOpenNew")))
            return
        end
        local enabled = OnOff(args[2])
        if enabled ~= nil then
            Wild.SetSetting("containers.autoOpenNew", enabled)
            Print("New container auto-open " .. StatusText(enabled) .. ". Existing choices are unchanged.")
            return
        end
    elseif sub == "list" and #args == 1 then
        local items = Wild.GetContainers()
        if #items == 0 then Print("No containers saved yet."); return end
        for _, item in ipairs(items) do
            Print((item.link or item.name) .. " (ID " .. item.itemID .. "): auto-open " .. StatusText(item.autoOpen))
        end
        return
    elseif sub == "legacy" and #args == 1 then
        local choices, ids = Wild.GetLegacyContainerChoices(), {}
        for itemID in pairs(choices) do ids[#ids + 1] = itemID end
        if #ids == 0 then Print("No archived container choices."); return end
        table.sort(ids)
        Print("Archived container choices (unknown client; not active):")
        for _, itemID in ipairs(ids) do
            Print("ID " .. itemID .. ": auto-open was " .. StatusText(choices[itemID]))
        end
        Print("Use /wild containers add <itemID> [on|off] to save a choice for this client.")
        return
    elseif sub == "scan" and #args == 1 then
        Wild.ScanContainers()
        return
    else
        local itemID, enabled
        if sub == "add" and (#args == 2 or #args == 3) then
            itemID = args[2]
            if #args == 2 then enabled = false else enabled = OnOff(args[3]) end
        elseif #args == 2 then
            itemID, enabled = args[1], OnOff(args[2])
        end
        if itemID and enabled ~= nil then
            if Wild.SetContainerAutoOpen(itemID, enabled) then
                Print("Container ID " .. tonumber(itemID) .. ": auto-open " .. StatusText(enabled))
            end
            return
        end
    end
    PrintWarn("Usage: /wild containers [default on|off|add <itemID> [on|off]|<itemID> on|off|list|legacy|scan]")
end)

RegisterCommand("mail", {
    { "[on|off]", "Show or set automatic collection of incoming mail." },
    { "autosend [on|off]", "Show or set whether Mail rules run when you open a mailbox." },
    { "preview", "Show the outgoing Mail rule plan at an open mailbox without sending." },
    { "run", "Run Mail rules at an open mailbox. Finish or clear the draft first." },
}, function(args)
    local action = args[1] and args[1]:lower()
    if action == "autosend" and #args <= 2 then
        if HandleGenericFeature("mailautosend", { args[2] }) then return end
    elseif action == "preview" and #args == 1 then
        Wild.ShowMailRulePlan()
        return
    elseif action == "run" and #args == 1 then
        local started, message, reason = Wild.RunMailIntents()
        if not started and reason ~= "no_matches" then PrintWarn(message) end
        return
    elseif #args <= 1 and HandleGenericFeature("mail", args) then
        return
    end
    PrintWarn("Usage: /wild mail [on|off|autosend [on|off]|preview|run]")
end)

local INBOX_SCOPE_HELP = " Omit scope to use the selection, or all loaded mail if none is selected."
RegisterCommand("inbox", {
    { "[on|off]", "Show or set whether to use Wild Mail or the standard mailbox." },
    { "delete [all|selected]", "Delete letters with no items or gold after confirmation." .. INBOX_SCOPE_HELP },
    { "hide", "Return to the standard mailbox for this visit." },
    { "keepunread [on|off]", "Show or set whether deleting empty mail keeps unread letters." },
    { "open [all|selected]", "Collect items and gold. Skip C.O.D. and GM mail." .. INBOX_SCOPE_HELP },
    { "read <message>", "On Items, show a numbered letter in chat and mark it as read." },
    { "return [all|selected]", "Return eligible mail to its senders after confirmation." .. INBOX_SCOPE_HELP },
    { "search [<text>]", "Open Items and filter by sender, subject, or attachment. Omit text to clear the filter." },
    { "select <message> on|off", "Select or deselect a loaded letter by its inbox number." },
    { "show", "Open the Items tab at the current mailbox." },
    { "sort [inbox|name|sender|size]", "Show or set the attachment sort order." },
    { "take <message> <slot>", "Take a stack after reading its letter. Hover over the attachment for its mail and slot numbers." },
}, function(args, message)
    local action = args[1] and args[1]:lower()
    if action == "search" then
        Wild.ShowInboxBrowser(message:match("^%S+%s+%S+%s*(.*)$") or "")
    elseif action == "sort" then
        if #args == 1 then
            Print("Attachment sort order: " .. Wild.GetSetting("mail.inboxSort"))
        elseif #args == 2 then
            local order = args[2]:lower()
            if Wild.SetSetting("mail.inboxSort", order) then Print("Attachment sort order: " .. order) end
        else
            PrintWarn("Usage: /wild inbox sort [inbox|name|sender|size]")
        end
    elseif action == "show" and #args == 1 then
        Wild.ShowInboxBrowser()
    elseif action == "hide" and #args == 1 then
        Wild.HideInboxBrowser()
    elseif action == "keepunread" and #args <= 2 then
        if not HandleGenericFeature("inboxkeepunread", { args[2] }) then
            PrintWarn("Usage: /wild inbox keepunread [on|off]")
        end
    elseif action == "select" and #args == 3 and args[2]:match("^%d+$") and OnOff(args[3]) ~= nil then
        Wild.SetInboxSelection(tonumber(args[2]), OnOff(args[3]))
    elseif (action == "open" or action == "return" or action == "delete") and #args <= 2 then
        Wild.RunInboxBulk(action, args[2] and args[2]:lower())
    elseif action == "read" and #args == 2 and args[2]:match("^%d+$") then
        Wild.ReadInboxMessage(tonumber(args[2]))
    elseif action == "take" and #args == 3 and args[2]:match("^%d+$") and args[3]:match("^%d+$") then
        Wild.TakeInboxAttachment(tonumber(args[2]), tonumber(args[3]))
    elseif #args > 1 or not HandleGenericFeature("inbox", args) then
        PrintWarn("Use /wild help for inbox commands. Hover over an icon for its mail and slot numbers.")
    end
end)

RegisterCommand("soiree", {
    { "[on|off]", "Show or set automatic advice when you open Saltheril's invitation selector. Retail only." },
    { "hide", "Close Saltheril's Soiree advisor. Retail only." },
    { "show", "Open Saltheril's Soiree advisor for the current selector. Retail only." },
}, function(args)
    if #args == 1 and args[1]:lower() == "show" then
        Wild.ShowSoireeAdvisor()
    elseif #args == 1 and args[1]:lower() == "hide" then
        Wild.HideSoireeAdvisor()
    elseif not HandleGenericFeature("soiree", args) then
        PrintWarn("Usage: /wild soiree [on|off|show|hide]")
    end
end)

RegisterCommand("dialog", {
    { "[on|off]", "Show or set keyboard confirmation of supported dialogs." },
    { "destroy on|off", "Set whether the confirmation key can permanently destroy an item without typing DELETE." },
    { "key <key>", "Set the confirmation key. Examples: SPACE, ENTER, CTRL-F2." },
}, function(args)
    if #args == 0 then
        Print("Dialog Key: " .. StatusText(Wild.IsFeatureEnabled("dialog")))
        Print("Item destruction: " .. StatusText(Wild.GetSetting("dialogKey.destroy")))
        Print("Confirmation key: " .. tostring(Wild.GetSetting("dialogKey.key")))
        return
    end
    if HandleGenericFeature("dialog", args) then return end
    local sub = args[1]:lower()
    if sub == "key" and #args == 2 then
        if Wild.SetDialogKey(args[2]) then
            Print("Dialog key set to " .. Wild.GetSetting("dialogKey.key"))
        end
    elseif sub == "destroy" and #args == 2 then
        local enabled = OnOff(args[2])
        if enabled == nil then
            PrintWarn("Usage: /wild dialog destroy on|off")
            return
        end
        Wild.SetSetting("dialogKey.destroy", enabled)
        Print("Dialog item destruction " .. StatusText(enabled))
        if enabled then PrintWarn("The confirmation key can permanently destroy the item on your cursor.") end
    else
        PrintWarn("Usage: /wild dialog [on|off|key <key>|destroy on|off]")
    end
end)

RegisterCommand("circle", {
    { "[on|off]", "Show or set whether the center circle appears." },
    { "color <r> <g> <b>", "Set red, green, and blue values from 0 to 1." },
    { "offset <x> <y>", "Move the circle from the screen center by these horizontal and vertical offsets." },
    { "opacity <percent>", "Set the circle opacity from 0 to 100 percent." },
    { "size <pixels>", "Set the circle diameter in pixels." },
    { "thickness <pixels>", "Set the circle line width in pixels." },
}, function(args)
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
end)

RegisterCommand("lfg", {
    { "[on|off]", "Show or set Quick Apply for the group finder. Retail only." },
    { "anchor left|right|topleft|topright|bottomleft|bottomright", "Set the keystone panel position. Retail only." },
    { "autoaccept on|off", "Set whether to accept queue role checks automatically. Retail only." },
    { "autoconfirm on|off", "Set whether to confirm your role automatically when invited. Retail only." },
    { "filters on|off", "Legacy command. LFG Result Filters are not available." },
    { "keys on|off", "Show or hide the keystone panel. Retail only." },
}, function(args)
    if HandleGenericFeature("lfg", args) then return end

    local sub = args[1]:lower()
    if sub == "autoconfirm" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild lfg autoconfirm on|off") return end
        if Wild.SetFeatureEnabled("autoconfirmrole", v) then Print("Auto-Confirm Role " .. StatusText(v)) end
    elseif sub == "autoaccept" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild lfg autoaccept on|off") return end
        if Wild.SetFeatureEnabled("autoacceptqueue", v) then Print("Auto-Accept Queue " .. StatusText(v)) end
    elseif sub == "filters" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild lfg filters on|off") return end
        if Wild.SetFeatureEnabled("lfgfilters", v) then Print("LFG Result Filters " .. StatusText(v)) end
    elseif sub == "keys" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild lfg keys on|off") return end
        if not Wild.SetSetting("lfg.keystoneButtons", v) then return end
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
        if not Wild.SetSetting("lfg.keystoneAnchor", val) then return end
        Print("Keystone panel anchor: " .. val)
        if Wild.__keystonePanelApplyAnchor then Wild.__keystonePanelApplyAnchor() end
    else
        Print("Unknown lfg subcommand: " .. sub .. ". Try /wild help")
    end
end)

RegisterCommand("repair", {
    { "[on|off]", "Show or set automatic repairs at vendors." },
    { "guild on|off", "Set whether to try guild funds first when repairing." },
}, function(args)
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
end)

RegisterCommand("loot", {
    { "[on|off]", "Show or set Quick Loot." },
    { "modifier shift|ctrl|alt|none", "Set the modifier key that reverses normal Auto-Loot behavior." },
}, function(args)
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
end)

RegisterCommand("intents", {
    { "bypass [shift|ctrl|alt|none]", "Show or set the intent rule bypass key." },
}, function(args)
    if not args[1] or args[1]:lower() ~= "bypass" or #args > 2 then
        PrintWarn("Usage: /wild intents bypass [shift|ctrl|alt|none]")
        return
    end
    if args[2] and not Wild.SetSetting("intentBypassModifier", args[2]:upper()) then return end
    Print("Intent rule bypass key: " .. Wild.GetSetting("intentBypassModifier"))
end)

RegisterCommand("bank", {
    { "[on|off]", "Show all bank feature states, or set Warband Bank automation." },
    { "character on|off", "Turn Character Bank automation on or off." },
    { "guild on|off", "Turn Guild Bank automation on or off." },
    { "rules", "Show saved bank rules." },
    { "run", "Run bank rules at the open bank." },
    { "warband on|off", "Turn Warband Bank automation on or off." },
}, function(args)
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
                    Wild.Print(string.format("  %d. [%s] %s", i, state, summary))
                end
            end
        end
        if not any then Print("No bank intents configured.") end
    else
        Print("Unknown bank subcommand: " .. sub .. ". Try /wild help")
    end
end)

RegisterCommand("dungeonbar", {
    { "[on|off]", "Show or set whether the Dungeon Bar is enabled." },
    { "hide", "Hide the Dungeon Bar." },
    { "show", "Show the Dungeon Bar when it is enabled." },
    { "toggle", "Switch Dungeon Bar visibility." },
}, function(args)
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
end, { "bar" })

RegisterCommand("casts", {
    { "[on|off]", "Show Cast History settings, or turn recording on or off." },
    { "clear", "Clear the current cast history." },
    { "direction left|right|up|down", "Set the direction cast icons move." },
    { "fade <seconds>", "Set the delay before icons fade, from 1 to 30 seconds." },
    { "length <count>", "Set how many casts each track keeps, from 1 to 20." },
    { "lock", "Lock the Cast History start point." },
    { "move", "Unlock the Cast History start point so you can drag it." },
    { "reset", "Restore the default Cast History start point." },
    { "size <pixels>", "Set the icon size from 20 to 100 pixels." },
    { "spacing <pixels>", "Set the gap between tracks from 0 to 100 pixels." },
    { "text on|off", "Show or hide spell and item names." },
    { "textsize <pixels>", "Set the name text size from 8 to 32 pixels." },
    { "unlock", "Unlock the Cast History start point so you can drag it." },
}, function(args)
    local config = Wild.db and Wild.db.castHistory
    if not config then
        PrintWarn("Cast history settings are not loaded yet.")
        return
    end

    if #args == 0 then
        Print("Cast History: " .. StatusText(config.enabled))
        Print(string.format(
            "Size: %d, text: %s, length: %d/track, fade after: %.1fs, spacing: %d, direction: %s, start point: %s",
            config.iconSize,
            config.showText and (config.textSize .. "px") or "off",
            config.historyLength,
            config.fadeAfter,
            config.trackSpacing,
            config.direction:lower(),
            config.locked == false and "unlocked" or "locked"
        ))
        return
    end

    local sub = args[1]:lower()
    local enabled = OnOff(sub)
    if enabled ~= nil then
        Wild.SetCastHistoryEnabled(enabled)
        Print("Cast History " .. StatusText(enabled))
    elseif sub == "size" then
        local size = tonumber(args[2])
        if not size then Print("Usage: /wild casts size <20-100>") return end
        Wild.SetCastHistorySize(size)
        Print("Cast History icon size set to " .. config.iconSize .. ".")
    elseif sub == "text" then
        local visible = OnOff(args[2])
        if visible == nil then Print("Usage: /wild casts text on|off") return end
        Wild.SetCastHistoryTextVisible(visible)
        Print("Cast History text " .. StatusText(visible))
    elseif sub == "textsize" then
        local size = tonumber(args[2])
        if not size then Print("Usage: /wild casts textsize <8-32>") return end
        Wild.SetCastHistoryTextSize(size)
        Print("Cast History text size set to " .. config.textSize .. ".")
    elseif sub == "length" then
        local length = tonumber(args[2])
        if not length then Print("Usage: /wild casts length <1-20>") return end
        Wild.SetCastHistoryLength(length)
        Print("Cast History length set to " .. config.historyLength .. ".")
    elseif sub == "fade" then
        local seconds = tonumber(args[2])
        if not seconds then Print("Usage: /wild casts fade <1-30>") return end
        Wild.SetCastHistoryFadeAfter(seconds)
        Print(string.format("Cast History will fade after %.1f seconds.", config.fadeAfter))
    elseif sub == "spacing" then
        local spacing = tonumber(args[2])
        if not spacing then Print("Usage: /wild casts spacing <0-100>") return end
        Wild.SetCastHistoryTrackSpacing(spacing)
        Print("Cast History track spacing set to " .. config.trackSpacing .. ".")
    elseif sub == "direction" then
        if not Wild.SetCastHistoryDirection(args[2]) then
            Print("Usage: /wild casts direction left|right|up|down")
            return
        end
        Print("Cast History direction set to " .. config.direction:lower() .. ".")
    elseif sub == "move" or sub == "unlock" then
        Wild.SetCastHistoryMoveMode(true)
        Print("Cast History start point unlocked. Drag the cyan marker, then run /wild casts lock.")
    elseif sub == "lock" then
        Wild.SetCastHistoryMoveMode(false)
        Print("Cast History start point locked.")
    elseif sub == "reset" then
        Wild.ResetCastHistoryPosition()
        Print("Cast History start point reset.")
    elseif sub == "clear" then
        Wild.ClearCastHistory()
        Print("Cast History cleared.")
    else
        Print("Usage: /wild casts on|off|size <20-100>|text on|off|textsize <8-32>|length <1-20>|fade <1-30>|spacing <0-100>|direction left|right|up|down|move|lock|reset|clear")
    end
end, { "cast", "casthistory" })

RegisterCommand("quests", {
    { "[on|off]", "Show or set both automatic quest acceptance and hand-in." },
    { "accept on|off", "Set automatic quest acceptance." },
    { "autoaccept on|off", "Alias for quests accept." },
    { "autohandin on|off", "Alias for quests handin." },
    { "handin on|off", "Set automatic quest hand-in." },
}, function(args)
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
end, { "quest" })

RegisterCommand("gossip", {
    { "[on|off]", "Show gossip settings, or set all supported gossip automation." },
    { "delve on|off", "Set automatic selection of delve options. Retail only." },
    { "quest on|off", "Set automatic selection of quest options." },
    { "single on|off", "Set automatic selection when an NPC offers one option." },
    { "skip on|off", "Set automatic selection of options that skip dialog or content." },
}, function(args)
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
        Wild.SetSetting("gossip.autoSelectSingle", v)
        Print("Gossip Auto-Select Single " .. StatusText(v))
    elseif sub == "quest" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild gossip quest on|off") return end
        Wild.SetSetting("gossip.autoSelectQuest", v)
        Print("Gossip Auto-Select Quest " .. StatusText(v))
    elseif sub == "delve" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild gossip delve on|off") return end
        if not Wild.SetSetting("gossip.autoSelectDelve", v) then return end
        Print("Gossip Auto-Select Delve " .. StatusText(v))
    elseif sub == "skip" then
        local v = OnOff(args[2])
        if v == nil then Print("Usage: /wild gossip skip on|off") return end
        Wild.SetSetting("gossip.autoSkip", v)
        Print("Gossip Auto-Skip " .. StatusText(v))
    else
        -- Treat as on/off for all gossip automation
        local val = OnOff(sub)
        if val ~= nil then
            Wild.SetSetting("gossip.autoSelectSingle", val)
            Wild.SetSetting("gossip.autoSelectQuest", val)
            if Wild.IsSettingAvailable("gossip.autoSelectDelve") then
                Wild.SetSetting("gossip.autoSelectDelve", val)
            end
            Wild.SetSetting("gossip.autoSkip", val)
            Print("Gossip automation " .. StatusText(val))
        else
            Print("Usage: /wild gossip [single|quest|delve|skip] on|off")
        end
    end
end)

RegisterFeatureCommand("auctionhouse", "Show or set default Auction House filters.", { "ah" })
RegisterFeatureCommand("autoaccept", "Show or set automatic quest acceptance.")
RegisterFeatureCommand("autoacceptqueue", "Show or set automatic acceptance of queue role checks. Retail only.")
RegisterFeatureCommand("autoconfirmrole", "Show or set automatic role confirmation when invited. Retail only.")
RegisterFeatureCommand("autohandin", "Show or set automatic quest hand-in.")
RegisterFeatureCommand("autoloot", "Show or set WoW's Auto-Loot setting.")
RegisterFeatureCommand("autoreply", "Show or set automatic replies to Mythic+ whispers. Retail only.")
RegisterFeatureCommand("autorolecheck", "Show or set automatic acceptance of queue role checks. Retail only.")
RegisterFeatureCommand("bankcharacter", "Show or set Character Bank automation.")
RegisterFeatureCommand("bankguild", "Show or set Guild Bank automation.")
RegisterFeatureCommand("craftingorders", "Show or set default Crafting Orders filters.", { "co" })
RegisterFeatureCommand("delve", "Show or set automatic selection of the first power option in delves. Retail only.")
RegisterFeatureCommand("durabilitybags", "Show or set durability overlays on items in bags.")
RegisterFeatureCommand("durabilityequipped", "Show or set durability overlays on equipped items.")
RegisterFeatureCommand("durabilitytotal", "Show or set the total durability overlay.")
RegisterFeatureCommand("inboxkeepunread", "Show or set whether deleting empty mail keeps unread letters.")
RegisterFeatureCommand("lfgfilters", "Legacy command. LFG Result Filters are not available.")
RegisterFeatureCommand("mailautosend", "Show or set whether Mail rules run when you open a mailbox.")
RegisterFeatureCommand("reputation", "Show or set automatic collapse of reputation headers.", { "rep" })
RegisterFeatureCommand("speed", "Show or set the movement speed display. Normal running speed is 100 percent.")
RegisterFeatureCommand("tooltip", "Show or set item tooltip enhancements.")

RegisterCommand("find", {
    { "[<name|itemID>]", "Open Item Search, or show recorded locations in chat by partial name or exact item ID." },
}, function(args, message)
    if #args == 0 then
        Wild.OpenItemSearch()
        return
    end
    local query = message:match("^%S+%s+(.+)$")
    local results = Wild.FindItems(query)
    if #results == 0 then
        Print("No matching items in your recorded inventory.")
        return
    end
    Print("Items matching \"" .. query .. "\":")
    for _, r in ipairs(results) do
        local display = r.link or r.name or tostring(r.itemID)
        local detail = Wild.FormatItemBreakdown(r.breakdown, r.sentMail)
        if r.total > 0 then detail = string.format("%dx total (%s)", r.total, detail) end
        Wild.Print(string.format("  %s — %s", display, detail))
    end
end, { "search" })

RegisterCommand("itemsearch", {
    { "[on|off|lock|unlock]", "Show the Item Search button status, show or hide the button, or lock or unlock its position." },
}, function(args)
    local sub = args[1] and args[1]:lower()
    if not sub then
        local visible = Wild.GetSetting("itemSearch.showButton")
        local locked = Wild.GetSetting("itemSearch.locked")
        Print("Item Search button: " .. (visible and "shown" or "hidden") ..
            ". Position: " .. (locked and "locked" or "unlocked") .. ".")
    elseif #args == 1 and (sub == "on" or sub == "off") then
        if Wild.SetSetting("itemSearch.showButton", sub == "on") then
            Print("Item Search button " .. (sub == "on" and "shown." or "hidden."))
        end
    elseif #args == 1 and (sub == "lock" or sub == "unlock") then
        if Wild.SetSetting("itemSearch.locked", sub == "lock") then
            Print("Item Search button position " .. (sub == "lock" and "locked." or "unlocked."))
        end
    else
        PrintWarn("Usage: /wild itemsearch [on|off|lock|unlock]")
    end
end)

RegisterCommand("volume", {
    { "[on|off]", "Show or set whether the volume control button appears." },
    { "timeout [<seconds>]", "Show or set the volume panel timeout. Set it to 0 to keep the panel open." },
}, function(args)
    if #args <= 1 and HandleGenericFeature("volume", args) then return end
    if args[1] and args[1]:lower() == "timeout" and #args <= 2 then
        if not Wild.db then PrintWarn("Volume settings have not loaded yet."); return end
        if args[2] and not Wild.SetSetting("volumeControl.autoHideDelay", tonumber(args[2])) then return end
        local seconds = Wild.GetSetting("volumeControl.autoHideDelay")
        if seconds == 0 then
            Print("Volume panel auto-hide is off (timeout 0 seconds).")
        else
            Print("Volume panel auto-hide timeout: " .. seconds .. " seconds.")
        end
        return
    end
    PrintWarn("Usage: /wild volume on|off|timeout [seconds]. Use 0 to keep the panel open.")
end, { "vol" })

RegisterCommand("durability", {
    { "[on|off]", "Show or set all durability overlays." },
    { "bags on|off", "Show or hide durability on items in bags." },
    { "equipped on|off", "Show or hide durability on equipped items." },
    { "total on|off", "Show or hide the total durability overlay." },
}, function(args)
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
end, { "dur" })

RegisterCommand("datastore", {
    { "[status]", "Show this client's cross-character item store." },
    { "refresh", "Scan the current character's bags again." },
}, function(args)
    local sub = args[1] and args[1]:lower() or "status"

    if sub == "status" then
        local lines = Wild.GetDatastoreSummary()
        if type(lines) == "string" then
            Print(lines)
        else
            for _, line in ipairs(lines) do
                Wild.Print(line)
            end
        end
    elseif sub == "refresh" then
        if not Wild.GetClientData() then PrintWarn("Datastore not initialized for this client."); return end
        Wild.SnapshotBags()
        Print("Bags refreshed for current character.")
    else
        Print("Usage: /wild datastore [status|refresh]")
    end
end, { "ds" })

do
    local settings = {
        { name = "rule", key = "ruleDelay", label = "Rule delay" },
        { name = "pass", key = "passDelay", label = "Pass delay" },
        { name = "bankstart", key = "bankStartDelay", label = "Bank start delay" },
        { name = "guildbankstart", key = "guildBankStartDelay", label = "Guild bank start delay" },
        { name = "sellinterval", key = "sellInterval", label = "Sell interval" },
        { name = "sellstart", key = "sellStartDelay", label = "Sell start delay" },
        { name = "mailstart", key = "mailStartDelay", label = "Mail start delay" },
        { name = "mailbatch", key = "mailBatchDelay", label = "Mail batch delay" },
        { name = "destroystart", key = "destroyStartDelay", label = "Destroy start delay" },
        { name = "preloadtimeout", key = "preloadTimeout", label = "Preload timeout" },
    }
    local forms = { { "", "Show all timing settings." } }
    local byName, names = {}, {}
    for _, setting in ipairs(settings) do
        byName[setting.name] = setting
        names[#names + 1] = setting.name
        forms[#forms + 1] = {
            setting.name .. " [<seconds>]",
            "Show or set the " .. setting.label:lower() .. ". Use 0.1 to 1 second in steps of 0.1.",
        }
    end

    RegisterCommand("delay", forms, function(args)
        local sub = args[1] and args[1]:lower()
        if not sub then
            print("|cff00ccff--- Wild Timing Settings ---|r")
            for _, setting in ipairs(settings) do
                Print(setting.label .. ": " .. (Wild.db.advanced[setting.key] or 0.3) .. "s")
            end
            return
        end

        local setting = byName[sub]
        if not setting then
            Print("Unknown delay setting: " .. sub .. ". Options: " .. table.concat(names, ", "))
            return
        end

        local val = tonumber(args[2])
        if not val then
            Print(setting.label .. ": " .. (Wild.db.advanced[setting.key] or 0.3) .. "s")
            return
        end
        val = math.max(0.1, math.min(1.0, math.floor(val * 10 + 0.5) / 10))
        Wild.SetSetting("advanced." .. setting.key, val)
        Print(setting.label .. " set to " .. val .. "s.")
    end)
end

RegisterCommand("log", {
    { "", "Show the count of saved log entries." },
    { "clear", "Clear saved actions, warnings, and diagnostics." },
    { "show [<filter>]", "Show the last 20 matching log entries in chat." },
}, function(args)
    local sub = args[1] and args[1]:lower() or ""
    if sub == "clear" then
        Wild.ClearLog()
        Print("Log cleared.")
    elseif sub == "show" then
        local filter = #args > 1 and table.concat(args, " ", 2) or nil
        local entries = Wild.GetLogEntries(filter)
        local start = math.max(1, #entries - 19)
        Print(string.format("Log: %d matching entries (showing the last 20).", #entries))
        for i = start, #entries do
            local entry = entries[i]
            local message = entry.kind == "action" and Wild.FormatActionResult(entry.action, entry) or entry.m
            Wild.Print(string.format("|cff00ccffWild [%s]:|r %s %s", entry.s, entry.d, message))
        end
    else
        Print(string.format("Log: %d saved entries. Actions and failures are always saved; debug adds diagnostics. Use /wild log show [filter] or /wild log clear.", Wild.GetLogCount()))
    end
end)

-- ============================================================
-- Main dispatcher
-- ============================================================

function Wild.HandleSlashCommand(msg)
    msg = strtrim(msg or "")
    local args = ParseArgs(msg)
    local cmd = (tremove(args, 1) or ""):lower()
    local handler = commandHandlers[cmd]

    if handler then
        handler(args, msg)
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

    RegisterCommand("trace", {
        { "", "Open the Commands page to find event trace commands." },
        { "clear", "Clear saved event trace entries." },
        { "filter [<text>]", "Record only events with matching names. Omit text to clear the filter." },
        { "show", "Show the last 50 event trace entries in chat." },
        { "start", "Start recording events." },
        { "stop", "Stop recording events." },
    }, function(args)
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
                Wild.Print("  " .. Wild.db.eventTrace[i])
            end

        elseif sub == "" then
            OpenCommands()
        else
            PrintWarn("Unknown trace command: " .. sub .. ". Use /wild help to find trace commands.")
        end
    end)
end

-- ============================================================
-- Register slash command
-- ============================================================

SLASH_WILD1 = WILD_SLASH
SlashCmdList["WILD"] = Wild.HandleSlashCommand
SLASH_WILDDUNGEONBAR1 = "/wbar"
SlashCmdList["WILDDUNGEONBAR"] = function()
    Wild.ToggleDungeonBar()
end
AddCatalogEntry(SLASH_WILDDUNGEONBAR1, "Switch Dungeon Bar visibility.")

table.sort(commandCatalog, function(left, right) return left.syntax < right.syntax end)

--- Return copies of the alphabetized command syntax and descriptions.
function Wild.GetCommandCatalog()
    local entries = {}
    for index, entry in ipairs(commandCatalog) do
        entries[index] = { syntax = entry.syntax, description = entry.description }
    end
    return entries
end
