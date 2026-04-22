-- Wild: Centralized debug log system with ring buffer
local ADDON_NAME, Wild = ...

local MAX_LOG_ENTRIES = 5000

-- ============================================================
-- Core logging function
-- ============================================================

--- Write a debug log entry to the saved-variable ring buffer.
--- Entries are only recorded when debug mode is enabled.
--- @param source string Short tag identifying the subsystem (e.g. "Bank", "Rules")
--- @param msg string The log message
function Wild.Log(source, msg)
    if not Wild.db or not Wild.db.advanced or not Wild.db.advanced.debug then return end

    local log = Wild.db.log
    if not log then
        Wild.db.log = { entries = {}, nextIndex = 1 }
        log = Wild.db.log
    end

    local entries = log.entries
    local idx = log.nextIndex

    entries[idx] = {
        t = GetTime(),
        d = date("%Y-%m-%d %H:%M:%S"),
        s = source,
        m = msg,
    }

    idx = idx + 1
    if idx > MAX_LOG_ENTRIES then
        idx = 1
    end
    log.nextIndex = idx

    -- Also print to chat when debug is on
    print(string.format("|cff00ccffWild [%s]:|r %s", source, msg))
end

-- ============================================================
-- Query helpers
-- ============================================================

--- Return the log entries in chronological order.
--- @param filterText string|nil Optional case-insensitive substring filter on source or message
--- @return table Array of log entry tables { t, d, s, m }
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
               or entry.m:lower():find(filter, 1, true) then
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
