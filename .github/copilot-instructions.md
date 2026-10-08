# Wild — Copilot Instructions

## Overview

Wild is a World of Warcraft (Retail) quality-of-life addon written in Lua. It automates repairs, banking, looting, vendor sales, mail, inventory destruction, quest accept/hand-in, gossip, and group applications.

## Language & Runtime

- **Lua 5.1** targeting the WoW client API (no standard `io`, `os`, `require`).
- All code runs inside the WoW sandbox. Use WoW API functions (`CreateFrame`, `C_Item`, `C_Container`, `C_Bank`, `GetItemInfo`, etc.).
- No external build tools or package managers. Files are loaded by `Wild.toc` in strict order.

## Architecture

- **Addon table**: `local ADDON_NAME, Wild = ...` at the top of every file. All public API and state lives on `Wild`.
- **Saved variables**: `WildDB` is the single persistent store (declared in `Wild.toc`). Referenced as `Wild.db` after `ADDON_LOADED`. All settings read/write through `Wild.db`. Saved variables are the **source of truth** for all settings.
- **Load order** is defined in [Wild.toc](../Wild.toc). `Core.lua` loads first (defaults, migrations), `Settings.lua` loads last (UI). New feature files go **before** `Settings.lua`.
- **Defaults** for new settings go in the `defaults` table in `Core.lua`. Defaults are deep-merged on load via `ApplyDefaults`.

### Container Scanning

All bag scanning uses `Wild.GetPlayerBags()` which dynamically includes:
- Backpack (bag 0), numbered bags (1–4), and the reagent bag (if `Wild.db.includeReagentBag ~= false`, default `true`).

Bank scanning covers:
- **Character bank**: main slot + BankBag_1–7
- **Warband bank**: AccountBankTab_1–5
- **Guild bank**: all viewable tabs × 98 slots

## Core Design Principles

1. **Every feature must be controllable via slash commands** (`/wild <subcommand>`). The UI is a convenience layer, not the only interface.
2. **Every feature must be callable via the Lua API** on the `Wild` table so macros and other addons can interact programmatically.
3. **No combat-lockdown issues.** Never use `SetAttribute` or secure frames. The settings window is a regular `DIALOG`-strata frame.
4. **Minimal footprint.** Only automate what the user explicitly enables. Most features default to **off** (see defaults in `Core.lua`).
5. **Event-driven over time-based.** Prefer WoW API events (`BAG_UPDATE_DELAYED`, `ITEM_DATA_LOAD_RESULT`, `MAIL_SEND_SUCCESS`, etc.) over `C_Timer.After`. Timers only for safety timeouts or inherently time-based logic (debounce). The intent processing queue, item pre-loading, and multi-phase operations (transfers) must all chain via events.
6. **Reagent bag always included by default.** Use `Wild.GetPlayerBags()` to get the correct bag list.

## Intent / Rule Engine

All automation (bank, vendor, mail, inventory destroy) uses a unified intent system stored in `Wild.db.intents`. Every intent processor follows the **retry-until-done** pattern:

1. **Scan** the relevant containers for items matching the intent's conditions.
2. **Act** on one batch of matching items (move, sell, mail, destroy).
3. **Wait** for the appropriate completion event:
   - `BAG_UPDATE_DELAYED` — bank, vendor, destroy (bag contents changed)
   - `MAIL_SEND_SUCCESS` — mail (batch sent successfully)
4. **Re-scan** — repeat if items remain; stop when zero matches. If an item hasn't moved yet when the completion event fires, the re-scan will still see it and try again.
5. **Done** — when a scan finds ZERO matching items, signal complete and advance to the next rule.
6. **Safety cap** of 50 passes per intent to prevent infinite loops.

Condition evaluation lives in `Conditions.lua` and is shared across all processors.

To match soulbound items with no upgrade track, put **Bind Type is Soulbound** and **Upgrade Track = None** in the same include group. Choose **Fixed value** for the upgrade-track comparison. `None` is stored as rank `0`; ranked tracks remain `1` through `6`. Use a separate **Item Type** or **Equip Slot** condition if the rule should match only equipment.

### Bank-Specific Phases

1. **Pre-load**: On `BANKFRAME_OPENED` / `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`, request item data for all bank slots via `C_Item.RequestLoadItemDataByID`. Listen for `ITEM_DATA_LOAD_RESULT` for each item. Once all arrive (or a 3s safety timeout), proceed.
2. **Queue Build**: Collect all enabled, valid, actor-matching intents whose target bank type is accessible. Order matches `Wild.db.intents` (top to bottom in Settings UI).
3. **Transfer Two-Phase**: Transfer actions (source bank → target bank) execute as withdraw → `BAG_UPDATE_DELAYED` → deposit → `BAG_UPDATE_DELAYED` → retry. Both phases are event-chained.

### Vendor-Specific Behaviour

- Items are sold one-per-tick via an `OnUpdate` frame (0.2s interval) to avoid server throttling.
- After each sell batch completes, `BAG_UPDATE_DELAYED` triggers a re-scan.
- Item data is pre-loaded via `Item:ContinueOnItemLoad` before the first scan.
- Vendor sale amounts use `Wild.GetEffectiveSellPrice(itemID, containerInfo)`, shared with price conditions and tooltips. It reads `Enum.TooltipDataLineType.SellPrice` lines and their `price` field, converts bag-stack totals to per-item copper, and preserves the full item hyperlink in fallbacks. Multiply this unit price by the sold stack count exactly once.
- Recipe automation is configured only in **Intent Rules**, with no dedicated checkbox or slash toggle. The condition picker groups **Item Type**, **Item Subtype**, and **Recipes** under **Item types and subtypes**.
- Under **Recipes**, **Recipe Knowledge** offers **Already known / Not yet known**, and **Recipe Profession** offers **Known profession / Unknown profession**. Both conditions implicitly require a recipe item and work with any intent action. They store booleans internally, but their editor, summaries, and debug output show the readable state labels.
- To sell unneeded soulbound recipes, create a **Sell** intent with two include groups: **Bind Type is Soulbound + Recipe Knowledge is Already known**, and **Bind Type is Soulbound + Recipe Profession is Unknown profession**. Include groups are OR; conditions within a group are AND. Leave **Destroy items with no sell price** unchecked. Tradeable/warbound recipes and unlearned recipes for current professions are then kept, even when skill requirements are unmet.
- Recipe binding uses the recipe's item metadata and actual bag binding state, with `C_Item.IsItemBindToAccount` and `C_Item.IsItemBindToAccountUntilEquip` taking precedence for Warbound items. Never infer recipe binding from tooltip lines: they can describe the crafted equipment instead. Missing recipe binding data does not match any binding condition.
- Recipe knowledge uses the localized `ITEM_SPELL_KNOWN` tooltip line, not the item's use/learning spell. Missing tooltip data does not match either known or unknown conditions. Missing-profession detection uses recipe subclasses and the character's primary and secondary profession skill lines; unrecognized subclasses are not assumed unusable.
- Existing intents created by the former recipe shortcut remain ordinary editable intents; only the obsolete `recipeSelling` marker is removed on load.

### Mail-Specific Behaviour

- Items are chunked into batches of 12 (max attachments per mail).
- Each batch is sent and confirmed via `MAIL_SEND_SUCCESS` before the next batch.
- After all batches in a pass are sent, `BAG_UPDATE_DELAYED` triggers a re-scan to find newly-eligible items.
- `MAIL_FAILED` aborts the entire queue.

### Destroy-Specific Behaviour

- Items are destroyed directly via `PickupContainerItem` + `DeleteCursorItem`.
- After each pass, `BAG_UPDATE_DELAYED` triggers a re-scan since bag slots have shifted.

### Concurrency Guards

- **No concurrent queues**: Each processor has a re-entrant guard preventing a second run while one is active.
- **Debounce**: Bank/inventory triggers debounce within 1s of the last trigger.

## Slash Commands

Primary command: `/wild`

```
/wild                       — Toggle settings window
/wild help                  — Print available commands
/wild <feature> on|off      — Enable/disable a feature
/wild <feature> <setting>   — Get or set a specific setting
/wild bank run              — Manually trigger bank filter rules (while bank is open)
/wild bank rules            — List configured filter rules
/wild repair on|off         — Toggle auto-repair
/wild repair guild on|off   — Toggle guild funds
/wild loot on|off           — Toggle quick loot
/wild lfg on|off            — Toggle LFG quick apply
/wild dialog on|off         — Toggle manual keyboard confirmation of popups
/wild dialog key SPACE      — Set a keyboard key (modifier chords such as CTRL-F2 also work)
/wild dialog destroy on|off — Allow item destruction without typing DELETE
/wild circle on|off         — Toggle center circle
/wild circle size <n>       — Set circle size
/wild circle opacity <n>    — Set circle opacity (0-100)
/wild circle color <r> <g> <b> — Set circle color (0-1 floats)
/wild circle offset <x> <y> — Set circle offset
/wild reset                 — Reset all settings to defaults
```

Slash command parsing uses `ParseArgs` + `OnOff` helpers (see `SlashCommands.lua`).

## Public API

All public functions live on the `Wild` table and can be called from macros or other addons:

```lua
-- Settings window
Wild.ToggleSettings()
Wild.OpenSettings()

-- Feature toggles
Wild.SetFeatureEnabled(feature, enabled)  -- "lfg", "circle", "repair", "loot", "bank"
Wild.IsFeatureEnabled(feature)

-- Circle
Wild.UpdateScreenCenterCircle()

-- Loot
Wild.SetQuickLoot(enabled)

-- Dialog Key (standard confirmation popups only, not NPC gossip or quest windows)
Wild.SetDialogKey("SPACE")   -- Validates and saves the key; returns true/false
Wild.ConfirmDialog()        -- Requires a hardware event; returns true if a button was clicked
Wild.UpdateDialogKey()

-- Recipe knowledge (used by normal intent conditions and tooltip collection status)
Wild.IsRecipeKnown(itemID, containerInfo) -- true/false, or nil if tooltip data is unavailable

-- Bank
Wild.GetFilterRuleSummary(rule)
Wild.RunBankRules()          -- Trigger filter rules manually
Wild.AddFilterRule(rule)     -- Add a rule programmatically
Wild.RemoveFilterRule(index)
Wild.GetFilterRules()        -- Returns the rules table

-- Settings
Wild.GetSetting(key)
Wild.SetSetting(key, value)
Wild.ResetSettings()

-- Money display (amount in copper; follows WoW's colorblind setting)
Wild.FormatGold(copper)
```

## Adding a New Feature

1. Create a new `.lua` file for the feature logic.
2. Add it to `Wild.toc` **before** `Settings.lua`.
3. Add default values to the `defaults` table in `Core.lua`.
4. Expose enable/disable and configuration via `Wild.*` functions.
5. Add slash command handlers in `SlashCommands.lua`.
6. Add a settings tab via `Create<Feature>Tab()` in `Settings.lua` and register with `AddTab()`.
7. All state reads/writes go through `Wild.db`.

## UI Conventions

- Standalone `DIALOG`-strata frame (`WildSettingsFrame`), not the built-in addon settings panel.
- Sidebar (150 px) + content area. Each tab is a frame from a factory function parented to the content area.
- Tabs with heavy content use a scroll frame wrapper (`HookScrollChildWidth` pattern).
- ESC closes the window (registered in `UISpecialFrames`). Window is draggable via title bar.
- No global frame names on child widgets except where required by templates.
- Dark backdrop with subtle borders. Refer to existing panels for colour values.
- Addon chat prefix: `|cff00ccffWild:|r` (info), `|cffff6600Wild:|r` (warning/error).
- Use `Wild.Print(message)` for chat output containing item links, including rule summaries and debug messages. It inserts a native item texture immediately before every item hyperlink without changing the link or its quality atlas. Keep saved debug messages unformatted. Use readable action labels instead of Unicode bank arrows or mail symbols, which may be missing from the chat font.
- `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON/OFF)` on checkbox toggles.
- Format money amounts with `Wild.FormatGold(copper)`, which delegates to WoW's `GetMoneyString` with thousands separators. Native coin icons are used when colorblind mode is off; localized denomination text is used when it is on. Do not cache the formatted result or add a separate addon setting. Rule inputs still use their documented units (gold for hold targets, copper for sell-price conditions).
- **Dialog Key** is opt-in (`dialogKey.enabled = false`, key `SPACE`). Configure it in its settings tab or via `/wild dialog`. Only a physical key press prepares the topmost eligible standard popup and temporarily binds its native primary button; no popup is auto-accepted. Normal bindings and text entry are preserved. Wild does not prepare new confirmations in combat or while its settings window is open.
- Item destruction is a separate opt-in (`dialogKey.destroy = false`). It covers `DELETE_ITEM`, `DELETE_QUEST_ITEM`, `DELETE_GOOD_ITEM`, and `DELETE_GOOD_QUEST_ITEM` only. On explicit confirmation, fill the edit box with localized `DELETE_ITEM_CONFIRM_STRING`, then use the normal Yes button. Never modify popup definitions or bypass other typed confirmations, disabled buttons, or confirmation delays.

## Code Style

- Top-of-file comment: `-- Wild: <short description>`.
- `local ADDON_NAME, Wild = ...` immediately after.
- Private helpers are `local function`. Public API is `function Wild.FunctionName(...)`.
- Constants use `UPPER_SNAKE_CASE` locals.
- Debug output gated behind `Wild.db.advanced.debug`.

## Things to Avoid

- Do **not** use `C_Timer.After` where an event-driven approach is possible.
- Do **not** add features that default to enabled — defaults should be off unless explicitly noted otherwise.
- Do **not** use secure frames or `SetAttribute`.
- Do **not** introduce global variables; everything hangs off `Wild` or is file-local.
- Do **not** add external dependencies or libraries.
