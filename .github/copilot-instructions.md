# Wild — Copilot Instructions

## Overview

Wild is a World of Warcraft (Retail) quality-of-life addon written in Lua. It automates repairs, banking, looting, vendor sales, mail, inventory destruction, quest accept/hand-in, gossip, and group applications.

## Language & Runtime

- **Lua 5.1** targeting the WoW client API (no standard `io`, `os`, `require`).
- **Retail 12.1.5 (build 70391)** uses interface `120105` in `Wild.toc`. API contracts come from the [matching UI source](https://github.com/Gethe/wow-ui-source/tree/18c6d677b605b312f3d813d498404631fb941977/Interface/AddOns/Blizzard_APIDocumentationGenerated).
- All code runs inside the WoW sandbox. Use WoW API functions (`CreateFrame`, `C_Item`, `C_Container`, `C_Bank`, `C_Item.GetItemInfo`, etc.).
- Item queries use `C_Item.GetItemInfoInstant`, `C_Item.GetDetailedItemLevelInfo`, `C_Item.GetItemClassInfo`, `C_Item.GetItemSubClassInfo`, and `C_Item.GetItemSpell`, not their removed global aliases. Do not depend on `loadDeprecationFallbacks`.
- No external build tools or package managers. Files are loaded by `Wild.toc` in strict order.

## Architecture

- **Addon table**: `local ADDON_NAME, Wild = ...` at the top of every file. All public API and state lives on `Wild`.
- **Saved variables**: `WildDB` is the single persistent store (declared in `Wild.toc`). Referenced as `Wild.db` after `ADDON_LOADED`. All settings read/write through `Wild.db`. Saved variables are the **source of truth** for all settings.
- **Load order** is defined in [Wild.toc](../Wild.toc). `Core.lua` loads first (defaults, migrations), `NativeSettings.lua` registers native Settings pages, and `Settings.lua` loads last (canvas editor factories). New feature files go **before** `Settings.lua`.
- **Defaults** for new settings go in the `defaults` table in `Core.lua`. Defaults are deep-merged on load via `ApplyDefaults`.

### Container Scanning

All bag scanning uses `Wild.GetPlayerBags()` which dynamically includes:
- Backpack (bag 0), numbered bags (1–4), and the reagent bag (if `Wild.db.includeReagentBag ~= false`, default `true`).

Bank scanning covers:
- **Character bank**: main slot + BankBag_1–7
- **Warband bank**: AccountBankTab_1–5
- **Guild bank**: all viewable tabs × 98 slots

### Bag Container Opening

- `Containers.lua` discovers player-bag items with `C_Container.GetContainerItemInfo(...).hasLoot`. Discovery continues when opening is off and respects `Wild.GetPlayerBags()`.
- `Wild.db.containers.autoOpenNew` defaults to `false`. `Wild.db.containers.items[itemID]` stores each boolean choice, including explicit `false` entries. Test for `nil` when discovering an ID; changing the discovery default must never overwrite an existing choice.
- Manual ID additions start disabled independently of the discovery default. `Wild.SetContainerAutoOpen(itemID, enabled)` validates, saves, notifies, and applies per-ID changes. `Wild.GetContainers()` returns sorted display records, and `Wild.ScanContainers()` rescans and permits retries after an opening timeout.
- Opening uses `C_Container.UseContainerItem` only for enabled loot containers, one at a time, after revalidating the bag slot. It waits for confirmed consumption, item data, locks, cooldowns, loot closure, and safe player/context state. Never let contextual right-click behavior sell, mail, trade, or bank a container instead.
- Reuse the shared item-action evidence helpers, including physical bags excluded from selection. Chain through bag, item-data, loot, interaction, and player-state events; timers are confirmation safety timeouts only. Preserve synchronous completion events without reentrant item uses.
- Native **Containers** contains the discovery default and manual ID dialog. Its **Container List** child canvas is lazy, scrollable, and preserves per-ID choices when native Defaults are used. See the [container guide](../README.md#auto-open-bag-containers) for commands and API contracts.

## Core Design Principles

1. **Every feature must be controllable via slash commands** (`/wild <subcommand>`). The UI is a convenience layer, not the only interface.
2. **Every feature must be callable via the Lua API** on the `Wild` table so macros and other addons can interact programmatically.
3. **No combat-lockdown issues.** Never use `SetAttribute` or create secure frames. The settings interface uses Blizzard's Settings API and ordinary addon widgets.
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

### Action Logging

- Chat reports completed actions only, never queued items, planned amounts, no-match scans, or keep decisions.
- Bank moves require matching source decreases and destination increases. Transfers are reported only after both the withdrawal and deposit are confirmed. Gold synchronization checks both player and bank balances.
- Partial successes retry the remaining quantities without double-counting earlier results. A safety timeout stops work that cannot be confirmed instead of printing success or leaving the queue stuck.
- Vendor sales require the requested item's bag count to decrease. Destruction also requires an empty cursor; picking up an item does not prove deletion.
- Completion evidence reads all physical player bags, including a reagent bag excluded from rules. This is read-only: rule matching and item selection still respect `includeReagentBag`. Otherwise, sorting into an excluded bag could look like a sale or deletion.
- Mail results and totals are recorded only on `MAIL_SEND_SUCCESS`, using actual attachment quantities. Failed or unconfirmed sends are not counted.
- Combine confirmed stacks of the same item into one result per action. Keep partial successes, but report unconfirmed work as a warning instead of claiming completion.
- Result records retain their actual source and destination even when a saved rule is edited while its operation is pending.
- Debug mode writes scan, condition, and queue diagnostics to `WildDB.log` without automatically printing them. `/wild log show [filter]` displays the last 20 matching entries; `/wild log clear` clears the buffer.

To match soulbound items with no upgrade track, put **Bind Type is Soulbound** and **Upgrade Track = None** in the same include group. Choose **Fixed value** for the upgrade-track comparison. `None` is stored as rank `0`; ranked tracks remain `1` through `6`. Use a separate **Item Type** or **Equip Slot** condition if the rule should match only equipment.

To sell equipment whose upgrade ceiling is below your currently equipped gear, create a **Sell** intent with **Bind Type is Soulbound** and **Maximum Item Level < Equipped Slot iLvl** in the same include group. Select **Maximum Item Level** as the attribute, **<** as the operator, and **Equipped Slot iLvl** as the value reference, with offset `0`. Leave **Destroy items with no sell price** unchecked. Use **<=** instead if equal ceilings should also match.

- Maximum item level comes from `C_Item.GetItemUpgradeInfo(fullItemLink).maxItemLevel`, not the track's rank or a hard-coded seasonal table. Cached equipment with no upgrade track uses its current effective item level; crafted equipped gear therefore provides a valid current-level comparison even without a track.
- The comparison requires the actual item hyperlink, supplied directly or resolved from its bag and slot. Never fall back to a bare item ID or template item level. Missing item data, unsupported equip locations, and invalid upgrade ceilings do not match.
- **Equipped Slot iLvl** uses the weakest compatible equipped slot for rings, trinkets, and one-handed weapons. If any compatible slot is empty or its level is unavailable, the comparison does not match.
- This is only an item-level comparison. It does not evaluate stats, effects, set bonuses, alternate specializations, or future recrafting. No sell intent is created or enabled automatically.

### Bank-Specific Phases

1. **Pre-load**: On `BANKFRAME_OPENED` / `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`, request item data for all bank slots via `C_Item.RequestLoadItemDataByID`. Listen for `ITEM_DATA_LOAD_RESULT` for each item. Once all arrive (or a 3s safety timeout), proceed.
2. **Queue Build**: Collect all enabled, valid, actor-matching intents whose target bank type is accessible. Order matches `Wild.db.intents` (top to bottom in Settings UI).
3. **Transfer Two-Phase**: Transfer actions (source bank → target bank) execute as withdraw → `BAG_UPDATE_DELAYED` → deposit → `BAG_UPDATE_DELAYED` → retry. Deposit only confirmed withdrawn quantities, and retry a partial deposit before withdrawing more. Both phases are event-chained.
4. **Blocked items**: Full destinations do not end the bank round. Try existing partial stacks even when no slots are empty. After the confirmation timeout, warn and advance past a stalled intent only when observed item changes are confirmed, gold is settled, and the cursor is empty. Unmatched source removal or destination receipt still stops the queue. Transfers report confirmed withdrawals left in player bags separately from completed transfers.

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
- Closing the mailbox cancels future batches. An already-sent batch may still be logged on `MAIL_SEND_SUCCESS`, but its late acknowledgment never resumes the stopped queue.

### Destroy-Specific Behaviour

- Items are destroyed directly via `PickupContainerItem` + `DeleteCursorItem`.
- Each hardware-button click waits for verified bag removal and an empty cursor before advancing. After each pass, re-scan from that confirmed bag update since bag slots may have shifted.
- Existing typed-delete popups remain under the player's control. A logging safety timeout must not cancel or bypass an active deletion confirmation.
- `Wild.QueueDestroyItems(items, onComplete)` reports confirmed item quantities to `onComplete(count, cancelled)`, not attempted clicks or stack counts.

### Concurrency Guards

- **No concurrent queues**: Each processor has a re-entrant guard preventing a second run while one is active.
- **Debounce**: Bank/inventory triggers debounce within 1s of the last trigger.

## Slash Commands

Primary command: `/wild`

```
/wild                       — Open WoW Settings > AddOns > Wild
/wild native [page]         — Open native WoW Settings; for example, /wild native speed
/wild help                  — Print available commands
/wild <feature> on|off      — Enable/disable a feature
/wild <feature> <setting>   — Get or set a specific setting
/wild bank run              — Manually trigger bank filter rules (while bank is open)
/wild bank rules            — List configured filter rules
/wild repair on|off         — Toggle auto-repair
/wild repair guild on|off   — Toggle guild funds
/wild loot on|off           — Toggle quick loot
/wild containers            — Open container settings
/wild containers default on|off — Set the default for newly discovered container IDs
/wild containers add <id> [on|off] — Add an ID; disabled unless on is specified
/wild containers <id> on|off — Change an ID's saved opening choice
/wild containers list|scan  — List choices or rescan and retry containers
/wild lfg on|off            — Toggle LFG quick apply
/wild dialog on|off         — Toggle manual keyboard confirmation of popups, queues, and delve entry
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
-- Settings > AddOns > Wild
Wild.OpenSettings()              -- Returns true/false; optional page name
Wild.OpenNativeSettings()        -- Returns true/false
Wild.OpenNativeSettings("Speed") -- Optional page name, case-insensitive
Wild.ToggleSettings()            -- Compatibility alias; opens native Settings, never toggles it closed

-- Feature toggles
Wild.SetFeatureEnabled(feature, enabled)  -- "lfg", "circle", "repair", "loot", "bank"
Wild.IsFeatureEnabled(feature)

-- Circle
Wild.UpdateScreenCenterCircle()

-- Loot
Wild.SetQuickLoot(enabled)

-- Bag containers (discovery default is off; per-ID choices are independent)
Wild.SetContainerAutoOpen(itemID, enabled) -- Add or update a boolean choice; returns true/false
Wild.GetContainers()                     -- Sorted display records, not mutable settings
Wild.ScanContainers()                    -- Rescan bags and retry timed-out IDs

-- Dialog Key (standard popups, queue/role checks, and delve entry; not NPC gossip or quest windows)
Wild.SetDialogKey("SPACE")   -- Validates and saves the key; returns true/false
Wild.ConfirmDialog()        -- Requires a hardware event; returns true if a button was clicked
Wild.UpdateDialogKey()

-- Recipe knowledge (used by normal intent conditions and tooltip collection status)
Wild.IsRecipeKnown(itemID, containerInfo) -- true/false, or nil if tooltip data is unavailable

-- Equipment upgrade ceiling (requires a full hyperlink or bag and slot)
Wild.GetMaxItemLevel(itemID, containerInfo) -- number, or nil if unavailable/not supported

-- Bank
Wild.GetFilterRuleSummary(rule)
Wild.RunBankRules()          -- Trigger filter rules manually
Wild.AddFilterRule(rule)     -- Add a rule programmatically
Wild.RemoveFilterRule(index)
Wild.GetFilterRules()        -- Returns the rules table

-- Settings
Wild.GetSetting(key)
Wild.SetSetting(key, value)
Wild.GetDefaultSetting(key)      -- Returns a copy for table-valued defaults
Wild.NotifySettingsChanged(key)  -- Refresh native controls and editors after direct table mutations
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
6. Add a native page in `NativeSettings.lua`, using standard Settings controls wherever possible. Use a canvas editor in `Settings.lua` only for richer controls.
7. All state reads/writes go through `Wild.db`. Use shared setters and notify native controls and editors after directly changing rule or actor tables.

## UI Conventions

- Native `Settings > AddOns > Wild` is the only settings window. `/wild`, `/wild native [page]`, `Wild.OpenSettings()`, `Wild.OpenNativeSettings()`, and the compatibility API `Wild.ToggleSettings()` all open native Settings. Repeated calls do not close it or discard pending game settings.
- Prefer standard Blizzard controls, layouts, search, tooltips, color pickers, and input dialogs. Native controls use proxy settings backed by `Wild.db`; do not create a second configuration store or add a settings library.
- Pass evaluated scalar default values to `Settings.RegisterProxySetting`, never default callbacks. Blizzard evaluates callable defaults outside a secure wrapper during initialization, tainting the setting's `variable` field and subsequent native action-button settings lookups. Getter and setter callbacks remain supported.
- Settings dropdowns use `DropdownButton` with `WowStyle1DropdownTemplate` and `SetupMenu`; actor label menus use `MenuUtil.CreateContextMenu`. Never use `UIDropDownMenuTemplate`, `UIDropDownMenu_*`, or `ToggleDropDownMenu`: their shared globals can taint Blizzard's secure action paths even when initialized in a hidden settings window.
- Cast History leaves `UseAction` and secure action-button scripts untouched, even when disabled. Action-bar item casts use the bag/equipment spell cache and `UNIT_SPELLCAST_SENT`/`UNIT_SPELLCAST_SUCCEEDED`; the sent event preserves item metadata if a bag update removes the last stack before the success event.
- Native pages preserve existing options and units. Sliders also offer **Enter Value** for precise input; center-circle size can exceed the slider's visual range. Native page Defaults reset configuration only, never rules, actors, or collected data. The existing explicit `/wild reset` remains separate.
- Settings remain editable while their feature is disabled, so users can configure options before enabling automation. Parent controls group related options without blocking edits. Center-circle opacity supports **0-100%**.
- World-event helpers are grouped under the native **Events** category, with **Darkmoon Faire** and **Saltheril's Soiree** child pages. Add future world-event helpers under their event name in this group. Preserve the `Soiree` navigation alias and existing slash/public APIs when organizing pages.
- The native **Events > Darkmoon Faire** page retains **Show Shopping List Now**, which uses `Wild.ShowDarkmoonHelper()` independently of automatic helper visibility and location.
- Intent Rules, Actors, Character, Dungeon Bar, and Auto-Reply create their richer canvas editors lazily through `Wild.CreateSettingsCanvas()`. Each native page retains its own instance. Heavy editors use scroll wrappers (`HookScrollChildWidth`).
- Refreshing settings must not write saved values or discard focused, unsaved text. Native proxy bindings guard against change callbacks caused by clamped slider display values; the label still shows the actual saved value. Settings visibility includes native Wild pages and Wild controls displayed in native search results.
- No global frame names on child widgets except where required by templates.
- Dark backdrop with subtle borders. Refer to existing panels for colour values.
- Addon chat prefix: `|cff00ccffWild:|r` (info), `|cffff6600Wild:|r` (warning/error).
- Use `Wild.Print(message)` for chat output containing item links, including rule summaries and debug messages. It inserts a native item texture immediately before every item hyperlink without changing the link or its quality atlas. Keep saved debug messages unformatted. Use readable action labels instead of Unicode bank arrows or mail symbols, which may be missing from the chat font.
- `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON/OFF)` on checkbox toggles.
- Format money amounts with `Wild.FormatGold(copper)`, which delegates to WoW's `GetMoneyString` with thousands separators. Native coin icons are used when colorblind mode is off; localized denomination text is used when it is on. Do not cache the formatted result or add a separate addon setting. Rule inputs still use their documented units (gold for hold targets, copper for sell-price conditions).
- **Dialog Key** is opt-in (`dialogKey.enabled = false`, key `SPACE`). Configure it in native Settings or via `/wild dialog`. Only a physical key press confirms the topmost eligible standard popup, LFG queue proposal, queue role check, or delve entry window; nothing is auto-accepted. Named native buttons use temporary click bindings. Blizzard's unnamed, unprotected `DelvesDifficultyPickerFrame.EnterDelveButton` is clicked directly and the key is consumed so it does not also jump; Wild never chooses or changes the delve tier. Resolve these load-on-demand frames when the key is pressed rather than loading Blizzard UI addons. Normal bindings and text entry are preserved. Wild does not prepare new confirmations in combat or while Wild settings are open.
- Item destruction is a separate opt-in (`dialogKey.destroy = false`). It covers `DELETE_ITEM`, `DELETE_QUEST_ITEM`, `DELETE_GOOD_ITEM`, and `DELETE_GOOD_QUEST_ITEM` only. On explicit confirmation, fill the edit box with localized `DELETE_ITEM_CONFIRM_STRING`, then use the normal Yes button. Never modify popup definitions or bypass other typed confirmations, disabled buttons, or confirmation delays.
- **Soiree Advisor** is opt-in (`soiree.enabled = false`) and advisory-only. `/wild soiree on|off|show|hide` and the native **Events > Saltheril's Soiree** page control it. `Soiree.lua` detects the visible four-option Player Choice from Lord Saltheril's non-secret NPC GUID, reads absolute friendship standings, and requires the four current previews to be entered manually. Never parse localized descriptions or assume structured reward lists contain every invitation effect. Keep preview data session-only and clear it when the selector changes or closes. The pure `Wild.CalculateSoireeRecommendation(progress, offers)` maximizes current-week useful reputation, not a guaranteed future-week count. See [the Soiree guide](../README.md) for the input contract, APIs, and limitations.

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
