-- Wild: Loot settings
local ADDON_NAME, Wild = ...

-- ============================================================
-- Auto-Loot: toggles the game's built-in autoLootDefault CVar
-- The modifier key to skip auto-loot uses the AUTOLOOTTOGGLE
-- binding, which the game handles natively.
-- ============================================================

local function ApplyAutoLoot()
    if not Wild.db then return end
    SetCVar("autoLootDefault", Wild.db.lootAutoLoot and "1" or "0")
end

function Wild.SetAutoLoot(enabled)
    if not Wild.db then return end
    Wild.db.lootAutoLoot = enabled
    ApplyAutoLoot()
end

function Wild.SetAutoLootModifier(modifier)
    if not Wild.db then return end
    Wild.db.lootAutoLootModifier = modifier
    SetModifiedClick("AUTOLOOTTOGGLE", modifier)
    SaveBindings(GetCurrentBindingSet())
end

-- ============================================================
-- Quick Loot: speeds up looting by calling LootSlot on each
-- item as soon as LOOT_READY fires, with a time gate to avoid
-- issues (based on Leatrix_Plus approach).
-- ============================================================

local QUICK_LOOT_DELAY = 0.3
local tDelay = 0

local quickLootFrame = CreateFrame("Frame")

local function FastLoot()
    if not Wild.db or not Wild.db.lootQuickLoot then return end
    if GetTime() - tDelay >= QUICK_LOOT_DELAY then
        tDelay = GetTime()
        if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
            for i = GetNumLootItems(), 1, -1 do
                LootSlot(i)
            end
            tDelay = GetTime()
        end
    end
end

function Wild.SetQuickLoot(enabled)
    if not Wild.db then return end
    Wild.db.lootQuickLoot = enabled
    if enabled then
        quickLootFrame:RegisterEvent("LOOT_READY")
    else
        quickLootFrame:UnregisterEvent("LOOT_READY")
    end
end

quickLootFrame:SetScript("OnEvent", FastLoot)

-- ============================================================
-- Initialise on load
-- ============================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if addon ~= ADDON_NAME then return end

    C_Timer.After(0, function()
        if not Wild.db then return end
        ApplyAutoLoot()
        -- Restore modifier binding
        local mod = Wild.db.lootAutoLootModifier or "SHIFT"
        SetModifiedClick("AUTOLOOTTOGGLE", mod)
        -- Enable/disable quick loot listener
        Wild.SetQuickLoot(Wild.db.lootQuickLoot)
    end)

    self:UnregisterEvent("ADDON_LOADED")
end)
