# Wild — Copilot Instructions

## Overview

Wild is a World of Warcraft (Retail) quality-of-life addon written in Lua. It automates repairs, banking, looting, vendor sales, mail, inventory destruction, quest accept/hand-in, gossip, and group applications. See [DESIGN.md](../DESIGN.md) for the full design guide.

## Language & Runtime

- **Lua 5.1** targeting the WoW client API (no standard `io`, `os`, `require`).
- All code runs inside the WoW sandbox. Use WoW API functions (`CreateFrame`, `C_Item`, `C_Container`, `C_Bank`, `GetItemInfo`, etc.).
- No external build tools or package managers. Files are loaded by `Wild.toc` in strict order.

## Architecture

- **Addon table**: `local ADDON_NAME, Wild = ...` at the top of every file. All public API and state lives on `Wild`.
- **Saved variables**: `WildDB` is the single persistent store (declared in `Wild.toc`). Referenced as `Wild.db` after `ADDON_LOADED`. All settings read/write through `Wild.db`.
- **Load order** is defined in [Wild.toc](../Wild.toc). `Core.lua` loads first (defaults, migrations), `Settings.lua` loads last (UI). New feature files go **before** `Settings.lua`.
- **Defaults** for new settings go in the `defaults` table in `Core.lua`. Defaults are deep-merged on load via `ApplyDefaults`.

## Core Design Principles

1. **Every feature must be controllable via slash commands** (`/wild <subcommand>`). The UI is a convenience layer, not the only interface.
2. **Every feature must be callable via the Lua API** on the `Wild` table so macros and other addons can interact programmatically.
3. **No combat-lockdown issues.** Never use `SetAttribute` or secure frames. The settings window is a regular `DIALOG`-strata frame.
4. **Minimal footprint.** Only automate what the user explicitly enables. Most features default to **off** (see defaults in `Core.lua`).
5. **Event-driven over time-based.** Prefer WoW API events (`BAG_UPDATE_DELAYED`, `ITEM_DATA_LOAD_RESULT`, `MAIL_SEND_SUCCESS`, etc.) over `C_Timer.After`. Timers only for safety timeouts or inherently time-based logic (debounce).
6. **Reagent bag always included by default.** Use `Wild.GetPlayerBags()` to get the correct bag list.

## Intent / Rule Engine

All automation (bank, vendor, mail, inventory destroy) uses a unified intent system stored in `Wild.db.intents`. Every intent processor follows the **retry-until-done** pattern:

1. Scan containers for matching items.
2. Act on one batch.
3. Wait for the completion event (`BAG_UPDATE_DELAYED`, `MAIL_SEND_SUCCESS`).
4. Re-scan — repeat if items remain; stop when zero matches.
5. Safety cap of 50 passes.

Condition evaluation lives in `Conditions.lua` and is shared across all processors.

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
- ESC closes the window (registered in `UISpecialFrames`).
- No global frame names on child widgets except where required by templates.
- Addon chat prefix: `|cff00ccffWild:|r` (info), `|cffff6600Wild:|r` (warning/error).
- `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON/OFF)` on checkbox toggles.

## Code Style

- Top-of-file comment: `-- Wild: <short description>`.
- `local ADDON_NAME, Wild = ...` immediately after.
- Private helpers are `local function`. Public API is `function Wild.FunctionName(...)`.
- Constants use `UPPER_SNAKE_CASE` locals.
- Debug output gated behind `Wild.db.advanced.debug`.
- Slash command parsing uses `ParseArgs` + `OnOff` helpers (see `SlashCommands.lua`).

## Things to Avoid

- Do **not** use `C_Timer.After` where an event-driven approach is possible.
- Do **not** add features that default to enabled — defaults should be off unless explicitly noted otherwise.
- Do **not** use secure frames or `SetAttribute`.
- Do **not** introduce global variables; everything hangs off `Wild` or is file-local.
- Do **not** add external dependencies or libraries.
