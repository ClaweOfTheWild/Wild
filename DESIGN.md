# Wild — Design & Development Guide

## Overview

Wild is a quality-of-life addon for World of Warcraft that automates common interactions like repairs, banking, looting, and group applications. It uses a standalone UI window (not the built-in addon settings panel) so it can be opened alongside any other game frame.

## Core Principles

1. **Every feature must be controllable via slash commands.** A user should never need the UI to configure or trigger any behaviour. The UI is a convenience layer on top of the API.
2. **Every feature must be callable via the Lua API.** Other addons and macros must be able to interact with Wild programmatically through `Wild.*` functions.
3. **No combat-lockdown issues.** The settings window is a regular frame (not a secure frame), so it can be opened/closed freely. Avoid `SetAttribute` or anything requiring secure context.
4. **Minimal footprint.** Only automate what the user explicitly enables. All features default to off except LFG Quick Apply.
5. **Saved variables are the source of truth.** `WildDB` is the single persistent store. All settings live there as flat keys or simple tables.
6. **Event-driven over time-based.** Prefer WoW API events (`BAG_UPDATE_DELAYED`, `ITEM_DATA_LOAD_RESULT`, etc.) over `C_Timer.After` scheduling wherever possible. Timers are only acceptable as safety timeouts or for inherently time-based logic (e.g. debounce on bank open). The intent processing queue, item pre-loading, and multi-phase operations (transfers) must all chain via events.
7. **Reagent bag/container always included by default.** When scanning bags or bank, always include the reagent bag/container. This is controlled by the `includeReagentBag` saved variable (default `true`). Use `Wild.GetPlayerBags()` to get the current bag list.

## Architecture

```
Wild.toc           — Load order
Core.lua           — Defaults, SavedVariables init, migration, addon table
ScreenCenterCircle.lua — Circle overlay feature
LFGQuickApply.lua  — One-click LFG apply feature
WarbandBank.lua    — Bank auto-deposit, filter rules engine
Vendor.lua         — Auto-repair feature
Loot.lua           — Quick loot CVar management
Settings.lua       — Standalone UI window (sidebar + tabs)
```

### Addon Table

`Wild` is the shared addon table passed via `local ADDON_NAME, Wild = ...`. All public API functions and state hang off this table.

### Saved Variables

`WildDB` is the global SavedVariables table. `Wild.db` is set to reference it after `ADDON_LOADED`. Defaults are defined in `Core.lua` and merged on load.

### Intent Processing Engine

The intent (rule) engine is fully event-driven. The **retry-until-done** pattern applies to **all** interaction types: bank (deposit/withdraw/transfer), vendor (sell), mail, and inventory (destroy).

#### Universal Retry-Until-Done Pattern

Every intent processor follows the same loop:

1. **Scan** the relevant containers for items matching the intent's conditions.
2. **Act** on one batch of matching items (move, sell, mail, destroy).
3. **Wait** for the appropriate completion event:
   - `BAG_UPDATE_DELAYED` — bank, vendor, destroy (bag contents changed)
   - `MAIL_SEND_SUCCESS` — mail (batch sent successfully)
4. **Re-scan** the same intent. If items were found and acted on, repeat from step 1.
5. **Done** — when a scan finds ZERO matching items, signal that this rule is complete and advance to the next.
6. **Safety cap** — max 50 passes per intent to prevent infinite loops.

This model naturally handles server lag: if an item hasn't moved yet when the completion event fires, the re-scan will still see it and try again. The loop only exits when the game state confirms no work remains.

#### Bank-Specific Phases

1. **Pre-load**: On `BANKFRAME_OPENED` / `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`, request item data for all bank slots via `C_Item.RequestLoadItemDataByID`. Listen for `ITEM_DATA_LOAD_RESULT` for each item. Once all arrive (or a 3s safety timeout), proceed.

2. **Queue Build**: Collect all enabled, valid, actor-matching intents whose target bank type is accessible. Order matches `Wild.db.intents` (top to bottom in Settings UI).

3. **Transfer Two-Phase**: Transfer actions (source bank → target bank) execute as withdraw → `BAG_UPDATE_DELAYED` → deposit → `BAG_UPDATE_DELAYED` → retry. Both phases are event-chained.

#### Vendor-Specific Behaviour

- Items are sold one-per-tick via an `OnUpdate` frame (0.2s interval) to avoid server throttling.
- After each sell batch completes, `BAG_UPDATE_DELAYED` triggers a re-scan.
- Item data is pre-loaded via `Item:ContinueOnItemLoad` before the first scan.

#### Mail-Specific Behaviour

- Items are chunked into batches of 12 (max attachments per mail).
- Each batch is sent and confirmed via `MAIL_SEND_SUCCESS` before the next batch.
- After all batches in a pass are sent, `BAG_UPDATE_DELAYED` triggers a re-scan to find newly-eligible items.
- `MAIL_FAILED` aborts the entire queue.

#### Destroy-Specific Behaviour

- Items are destroyed directly via `PickupContainerItem` + `DeleteCursorItem`.
- After each pass, `BAG_UPDATE_DELAYED` triggers a re-scan since bag slots have shifted.

#### Concurrency Guards

- **No concurrent queues**: Each processor has a re-entrant guard preventing a second run while one is active.
- **Debounce**: Bank/inventory triggers debounce within 1s of the last trigger.

### Container Scanning

All bag scanning uses `Wild.GetPlayerBags()` which dynamically includes:
- Backpack (bag 0)
- Numbered bags (1–4)
- Reagent bag (if `Wild.db.includeReagentBag ~= false`, default `true`)

Bank scanning covers:
- Character bank: main slot + BankBag_1–7
- Warband bank: AccountBankTab_1–5
- Guild bank: all viewable tabs × 98 slots

## Slash Commands

Primary command: `/wild`

Current:
- `/wild` — Toggle the settings window.

### Required Expansion

All features should support slash subcommands:

```
/wild                       — Toggle settings window
/wild help                  — Print available commands
/wild <feature> on|off      — Enable/disable a feature
/wild <feature> <setting>   — Get or set a specific setting
/wild bank run              — Manually trigger bank filter rules (while bank is open)
/wild bank rules            — List configured filter rules
/wild bank keepgold <n>     — Set gold-to-keep amount
/wild repair on|off         — Toggle auto-repair
/wild repair guild on|off   — Toggle guild funds
/wild loot on|off           — Toggle quick loot
/wild lfg on|off            — Toggle LFG quick apply
/wild circle on|off         — Toggle center circle
/wild circle size <n>       — Set circle size
/wild circle opacity <n>    — Set circle opacity (0-100)
/wild circle color <r> <g> <b> — Set circle color (0-1 floats)
/wild circle offset <x> <y> — Set circle offset
/wild reset                 — Reset all settings to defaults
```

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
```

## Adding a New Feature

1. Create a new `.lua` file for the feature logic.
2. Add it to `Wild.toc` **before** `Settings.lua`.
3. Add default values to `Core.lua` defaults table.
4. Expose enable/disable and configuration via `Wild.*` functions.
5. Add slash command handlers in the slash command parser.
6. Add a tab in `Settings.lua` by creating a `Create<Feature>Tab()` function and calling `AddTab()` in the loader.
7. All feature state reads/writes go through `Wild.db`.

## UI Conventions

- The settings window is a standalone `DIALOG`-strata frame (`WildSettingsFrame`).
- Sidebar on the left (150px), content area on the right.
- Each tab is a frame created by a factory function, parented to the content area.
- Tabs with lots of content (e.g. Warband Bank) use a scroll frame wrapper.
- ESC closes the window (registered in `UISpecialFrames`).
- The window is draggable via the title bar.
- No global frame names on child widgets except where required by templates (e.g. `UIDropDownMenuTemplate`).

## Style

- Addon chat prefix: `|cff00ccffWild:|r` (info), `|cffff6600Wild:|r` (warning/error).
- Use `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON/OFF)` on checkbox toggles.
- Dark backdrop with subtle borders. Refer to existing panels for colour values.

## Things to Build

- [ ] Slash command parser with subcommands (see above).
- [ ] `Wild.SetFeatureEnabled` / `Wild.IsFeatureEnabled` convenience API.
- [ ] `Wild.GetSetting` / `Wild.SetSetting` / `Wild.ResetSettings` generic API.
- [ ] `Wild.RunBankRules()` to manually trigger bank filter rules when bank is open.
- [ ] `Wild.AddFilterRule()` / `Wild.RemoveFilterRule()` / `Wild.GetFilterRules()` API.
- [ ] Print a summary on login of what's enabled (optional, behind a verbose flag).
- [ ] Minimap button (optional, toggleable) to open settings.
- [ ] Keybind support to toggle settings window.
- [ ] Profile support (per-character overrides vs account-wide base).
