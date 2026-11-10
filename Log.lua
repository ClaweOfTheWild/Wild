-- Wild: Confirmed action history, warnings, and opt-in diagnostics
local ADDON_NAME, Wild = ...

local MAX_LOG_ENTRIES = 5000
local RESULT_FIELDS = {
    "action", "status", "itemID", "link", "count", "copper",
    "source", "target", "recipient", "unconfirmedCount", "unconfirmedCopper", "reason", "errorType",
}
local ACTION_VERBS = {
    sell = "Sold", deposit = "Deposited", withdraw = "Withdrew",
    transfer = "Transferred", mail = "Mailed", destroy = "Destroyed",
}
local BANK_NAMES = { character = "Character bank", warband = "Warband bank", guild = "Guild bank" }

-- ============================================================
-- Core logging function
-- ============================================================

local function WriteLogEntry(source, msg, kind, details)
    if not Wild.db then return end
    local log = Wild.db.log
    if not log then
        Wild.db.log = { entries = {}, nextIndex = 1 }
        log = Wild.db.log
    end

    local entries = log.entries
    local idx = log.nextIndex

    local entry = {
        t = GetTime(),
        d = date("%Y-%m-%d %H:%M:%S"),
        s = source,
        m = msg,
        kind = kind,
    }
    for _, key in ipairs(RESULT_FIELDS) do entry[key] = details and details[key] end
    entries[idx] = entry

    idx = idx + 1
    if idx > MAX_LOG_ENTRIES then
        idx = 1
    end
    log.nextIndex = idx
    return entry
end

--- Save diagnostics only when debug mode is enabled; never print them.
--- @param source string Processor name, such as "Bank" or "Rules"
--- @param msg string Unformatted diagnostic message
function Wild.Log(source, msg)
    if not Wild.db or not Wild.db.advanced or not Wild.db.advanced.debug then return end
    WriteLogEntry(source, msg, "debug")
end

--- Format a confirmed item or gold result using the current money display.
--- @param action string sell, deposit, withdraw, transfer, mail, or destroy
--- @param result table Item quantity or copper amount, with its actual route
--- @return string Display message without the Wild chat prefix
function Wild.FormatActionResult(action, result)
    local subject
    if result.itemID then
        subject = string.format("%s \195\151%d", result.link or ("Item " .. result.itemID), result.count)
    else
        subject = Wild.FormatGold(result.copper)
    end
    local message = assert(ACTION_VERBS[action], "Unknown item action") .. " " .. subject
    if action == "sell" then
        message = message .. " for " .. Wild.FormatGold(result.copper)
    elseif action == "deposit" then
        message = message .. " to " .. (BANK_NAMES[result.target] or result.target)
    elseif action == "withdraw" then
        message = message .. " from " .. (BANK_NAMES[result.source] or result.source)
    elseif action == "transfer" then
        message = message .. " from " .. (BANK_NAMES[result.source] or result.source)
            .. " to " .. (BANK_NAMES[result.target] or result.target)
    elseif action == "mail" then
        message = message .. " to " .. result.recipient
    end
    return message .. "."
end

--- Save one newly confirmed quantity. Result tables are copied, not retained.
--- @param source string Processor name
--- @param action string sell, deposit, withdraw, transfer, mail, or destroy
--- @param result table Confirmed count and item metadata, or copper for gold; not a running total
function Wild.LogAction(source, action, result)
    assert(ACTION_VERBS[action], "Unknown item action")
    assert((result.count and result.count > 0) or (not result.itemID and result.copper and result.copper > 0),
        "An action log requires a confirmed quantity")
    local details = {}
    for _, key in ipairs(RESULT_FIELDS) do details[key] = result[key] end
    details.action, details.status = action, "confirmed"
    details.source = result.source or "bags"
    details.target = result.target or (action == "withdraw" and "bags")
        or (action == "sell" and "vendor") or (action == "mail" and result.recipient)
    local message = ACTION_VERBS[action]
    if result.itemID then
        message = message .. ": " .. (result.link or ("Item " .. result.itemID)) .. " x" .. result.count
    end
    if result.copper then message = message .. "; copper=" .. result.copper end
    message = message .. "; from " .. details.source
    if details.target then message = message .. "; to " .. details.target end
    WriteLogEntry(source, message, "action", details)
end

--- Save a warning even with debug off, then print it once.
--- @param source string Processor name
--- @param message string Warning text without the Wild chat prefix
--- @param details table|nil Structured reason, status, route, and unresolved quantities
function Wild.Warn(source, message, details)
    WriteLogEntry(source, message, "warning", details)
    Wild.Print("|cffff6600Wild:|r " .. message)
end

--- Keep native errors as context, not as proof that a particular item failed.
function Wild.LogClientError(source, errorType, message)
    WriteLogEntry(source, message, "warning", {
        status = "client_error", reason = "ui_error", errorType = errorType,
    })
end

--- Save item-specific unresolved requests separately from completed actions.
function Wild.LogUnconfirmedItemActions(source, action, batch, context)
    for _, item in ipairs(Wild.GetUnconfirmedItemActionEntries(batch)) do
        local details = {
            action = action, status = context and context.status or "unconfirmed", itemID = item.itemID, link = item.link,
            unconfirmedCount = item.count, source = context and context.source,
            target = context and context.target, recipient = context and context.recipient,
            reason = context and context.reason,
        }
        local label = details.status == "failed" and "Failed" or details.status == "skipped" and "Skipped" or "Unconfirmed"
        local message = label .. " " .. action .. ": " .. (item.link or ("Item " .. item.itemID)) .. " x" .. item.count
        if details.source then message = message .. "; from " .. details.source end
        if details.target then message = message .. "; to " .. details.target end
        if details.reason then message = message .. "; " .. details.reason end
        WriteLogEntry(source, message, "warning", details)
    end
end

-- ============================================================
-- Query helpers
-- ============================================================

--- Return the log entries in chronological order.
--- @param filterText string|nil Case-insensitive filter on source, message, kind, action, status, or reason
--- @return table Chronological records with timestamps, messages, and optional structured action or failure fields
function Wild.GetLogEntries(filterText)
    if not Wild.db or not Wild.db.log then return {} end

    local log = Wild.db.log
    local entries = log.entries
    local nextIdx = log.nextIndex
    local result = {}
    local filter = filterText and filterText:lower() or nil

    -- Ring buffer: read from nextIndex..MAX to get oldest, then 1..nextIndex-1
    local total = #entries
    if total == 0 then return result end

    -- If the buffer hasn't wrapped yet, nextIndex-1 is the count
    local startIdx
    if total < MAX_LOG_ENTRIES or entries[nextIdx] == nil then
        startIdx = 1
    else
        startIdx = nextIdx
    end

    for i = 0, total - 1 do
        local readIdx = ((startIdx - 1 + i) % total) + 1
        local entry = entries[readIdx]
        if entry then
            if not filter
               or entry.s:lower():find(filter, 1, true)
               or entry.m:lower():find(filter, 1, true)
               or (entry.action and entry.action:lower():find(filter, 1, true))
               or (entry.kind and entry.kind:lower():find(filter, 1, true))
               or (entry.status and entry.status:lower():find(filter, 1, true))
               or (entry.reason and entry.reason:lower():find(filter, 1, true)) then
                result[#result + 1] = entry
            end
        end
    end

    return result
end

--- Return the total number of stored log entries.
--- @return number
function Wild.GetLogCount()
    if not Wild.db or not Wild.db.log then return 0 end
    return #(Wild.db.log.entries)
end

--- Clear all stored log entries.
function Wild.ClearLog()
    if Wild.db then
        Wild.db.log = { entries = {}, nextIndex = 1 }
    end
end
