# Wild

Wild is a World of Warcraft Retail and Forever quality-of-life addon for players who want
configurable interaction helpers and automation. Macro and addon authors can
call its public functions on the `Wild` table. It targets Retail 12.1.5
(`120105`) and Forever 1.60.1 (`16001`) using the game's Lua 5.1 environment
without addon libraries.

Open **Settings > AddOns > Wild** with `/wild`. Select **Commands** or enter
`/wild help` to see the alphabetical command list. Click a command and press
Ctrl+C to copy its syntax. Replace placeholders before you run it.
Settings are stored in `WildDB`; the settings UI, slash commands, and public
setters share that store.

Click the number beside a slider to enter an exact value. Press Enter to save,
or press Escape to cancel. If the field loses focus before you press Enter,
the saved value does not change.

World-event helpers are grouped under **Wild > Events**. Retail has separate pages
for **Darkmoon Faire** and **Saltheril's Soiree**. `/wild native events` opens
the group. Existing shortcuts such as `/wild native darkmoon faire` and
`/wild native soiree` open the supported event directly.

## Retail and Forever

Client detection is automatic. `/wild client` prints `retail` or `forever`;
`/wild status` includes the mode and marks unavailable features.

Forever keeps its native group finder manual. Retail Quick Apply, queue role
automation, keystone tracking, Mythic+ auto-reply, delve automation, and the
Soiree advisor are unavailable in Forever. Wild does not turn a group-selection
click into a player invitation. The native LFG settings page explains this
instead of offering controls that cannot work.

Saved choices are preserved when a feature is unavailable. `Wild.GetSetting`
returns the saved value; `Wild.IsFeatureEnabled` returns the effective state.
Attempts to enable an unavailable feature warn and return `false`. Explicitly
turning one off is allowed. Retail keeps its existing defaults and behavior.
`/wild autoreply on|off` controls the Retail Mythic+ reply feature.

Bank processors and inventory snapshots share container enumeration. Retail
uses six character-bank containers; Forever uses nine, including the base bank
and eight bank bags. Account-bank indices come from the client's enums, not
Retail offsets. Only banks permitted by the current interaction run rules;
inaccessible banks do not replace saved inventory snapshots with empty data.

Forever's keyring is read-only storage for Wild. Inventory snapshots include
its items, but automation rules do not select them. Completion evidence includes
the keyring and an excluded reagent bag, so moving an item there does not count
as selling, destroying, or opening it. Forever character keys retain first and
last names; Retail keeps its existing `Name-Realm` format.

### Client Lua API

| Function | Contract |
| --- | --- |
| `Wild.GetClientMode()` | Return `retail`, `forever`, or `unsupported` |
| `Wild.IsFeatureAvailable(feature)` | Return `true`, or `false, reason`; use the feature names accepted by `Wild.SetFeatureEnabled` |
| `Wild.IsSettingAvailable(key)` | Check a setting's availability without changing its saved value |
| `Wild.GetPlayerName()` | Return the player's name, including Forever's last name |
| `Wild.GetCharKey()` | Return the current character's datastore and actor key |
| `Wild.GetPlayerBags()` | Return automation-selection bags, respecting **Include reagent bag** |
| `Wild.GetPlayerStorageBags()` | Return all storage bags, including the reagent bag and Forever's keyring, regardless of rule settings |
| `Wild.GetCharacterBankBags()` | Return the client's character-bank container IDs |
| `Wild.GetAccountBankBags()` | Return the client's account-bank container IDs; availability is checked separately |

For example, `Wild.IsFeatureAvailable("lfg")` returns `false` with a reason in
Forever, while `Wild.IsFeatureAvailable("repair")` returns `true` in both modes.

### One master addon folder on Windows

Keep one Git checkout as the master and use a **directory junction** for the
other client:

```text
World of Warcraft\
  _retail_\Interface\AddOns\Wild\   master checkout
  _forever_\Interface\AddOns\Wild\  junction to the Retail Wild folder
```

Both clients read the same physical files. Edit or update the master, then
`/reload` in each running client to load the changes. No copying, background
sync process, or second Git checkout is needed.

Restart Forever after first creating the junction so it discovers the addon.
Later source edits need only `/reload`.

Only the addon-code folder is linked. Each client keeps its own `WildDB` saved
variables, rules, actor records, and inventory snapshots. Do not link the
clients' `WTF` folders or install a second Wild copy over the junction.
Deleting or editing files through either addon path changes the master too;
the junction is not a backup.

### Saved data

Wild keeps settings and rules in the existing `SavedVariables\Wild.lua` file.
Inventory snapshots, sent-mail estimates, and per-item container choices
are stored separately in that file by client family (`retail` or `forever`).
Normal client updates do not clear them. If you copy the file to the other
client, Wild uses the copied settings and rules but ignores the other
client's item records.

On the first load after this change, Wild archives older item records that
have no client tag. It does not guess where they came from. Sign in on each
character and visit its bank and mailbox to rebuild the active records.
Use `/wild datastore status` to see which client's inventory Wild is using.

## Cross-character inventory

Enter `/wild find` to open the Item Search window. It lists all recorded
items when the search box is empty, with one row per item ID. Enter part of a
name or the exact item ID to filter the list. Hover over a row to see the game
tooltip and Wild's recorded locations and quantities. This does not change
tooltip settings elsewhere.

Run `/wild itemsearch on` to show the magnifying-glass button. Left-click it
to open the window. Drag it to move it. Right-click it to open
**Settings > AddOns > Wild > Item Search**, where you can show, hide, or lock
the button. `/wild itemsearch lock` and `/wild itemsearch unlock` also control
the lock. Wild saves the button's position and lock between sessions. The
green W button keeps its volume and settings shortcuts.

Enter `/wild find <name or item ID>` to see the same locations in chat.
`Wild.OpenItemSearch()` opens the window. `Wild.FindItems(query)` returns
matching item records with grouped locations for the current client. Pass a
partial name or item ID, or omit the query to list all recorded items.

To see locations on other item tooltips, open `/wild native tooltips` and set
**Cross-Character Count** to **Always** or **Shift Held**.

Wild saves each character's bags, reagent bag, equipped gear, keyring where
available, personal bank, and mailbox. It tracks the shared Warband bank and
guild banks where available. To populate an alt's inventory, sign in on that
character and open its bank and mailbox. View each guild bank tab to record it.
Wild updates these records as the game reports changes. Offline counts reflect
the last available data, not a live view.

When the game confirms a manual send or a mail rule, the attachments appear
under **Sent Mail** for the recipient, even if that character has never used
Wild. This row confirms the send, not delivery, and does not add to the
inventory total. The recipient's next complete inbox check replaces these
estimates with the attachments the game shows. Wild hides expired inbox
attachments and removes unverified sends from the results after 30 days.

## Use the Wild mailbox

Turn on **Use Wild mailbox** in **Settings > AddOns > Wild > Mail**, or run
`/wild inbox on`. Wild replaces the standard mailbox window with three tabs.
Drag the bottom-right corner to resize the window. Turn the setting off to
restore the standard mailbox. The setting is off by default.
If you update Wild while WoW is running, run `/reload` before you open a
mailbox.

| Tab | What it does |
| --- | --- |
| **List** | Read and reply to letters, confirm C.O.D. payments, or check letters for bulk actions. |
| **Items** | Search and take individual attachment stacks. This tab opens first. |
| **Send** | Write mail with WoW's composer, or select **Process rules** to send items that match enabled Mail rules. |

**Items** shows one icon for each attachment stack in the mail WoW has loaded.
The border uses WoW's item quality color, such as blue for rare or purple
for epic. Attachments without quality information have no colored border.
Bag and quiver icons show their total slots in the upper-left corner when WoW
reports the capacity. A 10-slot bag shows `10`, separate from the stack count.
Scroll through the grid or search by item name, sender, or subject. Hover over
an icon for WoW's item tooltip. Click it to take that stack without opening
the letter. Other stacks and enclosed money stay in the inbox.

Set **Attachment sort order** on the **Mail** settings page. Choose **Inbox
order** (default), **Item name (A-Z)**, **Sender (A-Z)**, or **Stack size
(largest first)**. The choice is saved and applies to the open grid without
clearing the search.

On **List** or **Items**, the bulk buttons act on all loaded mail if no
letters are checked. Check letters in **List** to limit all three actions to
that selection. Checkmarks carry across inbox pages and tabs. A change to the
loaded letters or their contents clears the selection. The **Items** search
filters the grid, not the bulk actions.

| Action | What it does |
| --- | --- |
| **Open all mail** / **Open selected** | Collect items and gold. Skips C.O.D. and GM mail. Does not read letter text. |
| **Return all mail** / **Return selected** | Return mail that WoW allows you to return, including any items or gold it contains. Requires confirmation. |
| **Delete all empty mail** / **Delete selected empty** | Delete eligible mail with no items or gold. This also deletes any letter text. Requires confirmation. |

Deletion includes eligible unread letters by default. To keep them, turn on
**Keep unread mail when deleting empty mail** in **Mail** settings.

The **Outgoing plan** on the left shows each planned message in send order,
with its recipient, item names, and quantities. It updates when your bags or
rules change. Wild skips soulbound items even if they match a Mail rule.
You do not need an exclusion rule.

Select **Process rules** on **Send** to start with an empty composer.
If the plan changed before Wild starts, review the updated list and
select the button again. Wild waits for WoW to confirm each message before
sending the next. The list shows what remains, and Wild checks the bags again
for more matches after the last message. WoW confirmation prompts still
require your approval.

To run the rules when you open a mailbox, turn on **Run Mail rules on open**
in **Mail** settings. It is off by default and independent of **Collect
incoming mail automatically**. The [intent rule bypass key](#intent-actions-and-logs)
skips both automatic actions for the visit. It does not block **Process rules**.
Use `/wild mail preview` to open the plan for the current visit without
starting a send.

Using Wild Mail stops Wild's automatic collection of incoming mail for the
rest of that visit. Enable Wild Mail before you open a mailbox if you want to
prevent collection from starting.

For example, `/wild inbox search Honey Cake` opens **Items** and filters the
grid. Hover over an icon for its mail and slot numbers. To take slot 2 from
letter 3, enter `/wild inbox read 3`, then `/wild inbox take 3 2`. The first
command marks the letter as read. See **Commands** for all mailbox commands.

Use `Wild.ShowInboxBrowser("Honey Cake")`, `Wild.ReadInboxMessage(3)`, and
`Wild.TakeInboxAttachment(3, 2)` for the equivalent Lua calls. These return
`true` when the request is made, or `false` with a warning. A successful take
request is not confirmation from the game. `Wild.HideInboxBrowser()` restores
the standard mailbox for the visit. `Wild.SetInboxSelection(3, true)` checks a
letter by number. `Wild.RunInboxBulk("return", "selected")` requests a bulk
action and still requires the return confirmation. The saved settings are
`mail.showInboxBrowser`, `mail.inboxSort`, `mail.keepUnread`, and `mail.autoSend`.
`Wild.ShowMailRulePlan()` shows the plan at an open mailbox.
`Wild.GetMailRulePlan()` returns a snapshot of the next pass or the remaining
batches of an active run. `Wild.RunMailIntents()` returns `true` when it starts
a run, not when it sends a batch. If it cannot start, it returns `false` and a
reason message.

## Volume panel timeout

Enable the green W button with `/wild volume on`. Left-click it to open the
volume panel. Right-click it to open **Settings > AddOns > Wild**, the same
page as `/wild`.

The default timeout is five seconds. The timer starts each time
the panel opens, even if you do not change a volume. Each click or adjustment
restarts it. While you hold a control, the timer waits until you release it.
Hover alone does not stop the timer. Only the panel hides; the Wild icon button
stays available. The button uses the same green W as Wild's addon-list icon.

Open **Settings > AddOns > Wild > Volume** with `/wild native volume`.
**Auto-hide timeout (seconds)** sets the delay. Its number field accepts
fractions and values above the slider's 30-second range. Set `0` to keep the
panel open until you close it. For example, `/wild volume timeout 2.5` sets
the delay to 2.5 seconds. Omit the number to see the saved delay.

`Wild.SetSetting("volumeControl.autoHideDelay", 2.5)` uses the same saved value
and updates an open panel immediately. It returns `true` for a finite number
of seconds that is `0` or greater. Invalid values warn, return `false`, and
leave the saved value unchanged. `Wild.GetSetting("volumeControl.autoHideDelay")`
reads the delay. Volume controls remain off by default in both clients.

## Durability colors

Durability percentages change smoothly from green at 100%, through yellow at 50%
and orange at 25%, to red at 0%. Equipped items, bag items, and the total
equipped-durability overlay use the same gradient.

When enabled, the total overlay appears as equipment data becomes available at
login or after `/reload`. You do not need to open the character panel.

Use `/wild durability on` to show all three overlays. Configure each overlay in
**Settings > AddOns > Wild > Durability**.

## Auto-open bag containers

Open **Settings > AddOns > Wild > Containers**, or run `/wild containers`.
**Auto-open newly discovered containers** is off by default. Wild still
discovers loot containers in your bags and saves each item ID with auto-open
disabled. Enable this default to save later discoveries with auto-open enabled
and open them automatically when safe.

Use **Edit Container List**, or the **Containers > Container List** child page,
to change each item's checkbox. Checked items open; unchecked items stay
unopened. Each saved choice applies to that item ID across characters on the
same client and survives reloads. Changing the discovery default never changes
existing choices: an individually enabled container still opens when the
discovery default is off.

Use `/wild containers legacy` to review container choices archived from an
older file with no client tag. An archived ID starts disabled when Wild finds
it in your bags, even if the discovery default is on. To use an old choice,
set it for this client by item ID or change its checkbox after discovery.

**Add by Item ID** saves an ID with auto-open disabled, even if you do not own
the container yet and the discovery default is on. This lets you configure
exceptions before receiving an item. Only items the game identifies as loot
containers in player bags are opened; adding an arbitrary item ID does not make
Wild use that item.

For example, `/wild containers add 12345` saves ID `12345` with auto-open off.
Enter `/wild containers 12345 on` to turn auto-open on for that ID. See
**Commands** for all container commands.

Opening waits during combat, casting, channeling, other looting, NPC
interactions, and item-transfer windows such as a merchant, bank, mailbox, or
trade. Locked items and active cooldowns also wait. Containers open one at a
time, with bag changes confirming consumption before another open is requested.
Wild does not bypass game confirmations, unlock locked containers, or force
looting when WoW's auto-loot is off. If an open cannot be confirmed within five
seconds, Wild warns and skips that ID until a manual scan or per-item setting
change. An open loot window can remain under your control beyond this timeout.
The shared **Include reagent bag** setting applies to discovery and item selection.

The native page's Defaults restore the discovery default without clearing the
list or changing per-item choices. The explicit `/wild reset` resets settings
and clears this client's container list and inventory records. It preserves
other clients' records and the archive. Later bag scans rediscover items disabled.

### Container Lua API

| Function | Contract |
| --- | --- |
| `Wild.SetContainerAutoOpen(itemID, enabled)` | Add or update an ID with a boolean choice; apply it immediately when safe; return `true`, or warn and return `false` for invalid input |
| `Wild.GetContainers()` | Return a new array sorted by item ID, with `itemID`, `name`, `link` when available, and `autoOpen` fields |
| `Wild.ScanContainers()` | Rescan and allow retries after a safety timeout; return the number of newly discovered IDs, or warn and return `false` before settings load |
| `Wild.SetSetting("containers.autoOpenNew", enabled)` | Change the default for future discoveries only |
| `Wild.GetSetting("containers.autoOpenNew")` | Read the discovery default |

For example, `Wild.SetContainerAutoOpen(12345, false)` saves an exception in
advance. `Wild.GetSetting("containers.items.12345")` reads its boolean choice;
`Wild.SetSetting("containers.items.12345", true)` uses the same per-ID setter.
IDs must be whole numbers from `1` to `2147483647`. Names load asynchronously;
an unknown name is displayed as its item ID without changing the saved choice.
Failed background lookups do not print warnings in chat. Wild still warns if
an item ID fails to load when you set its choice directly.

## Plan a Saltheril's Soiree week

The opt-in Soiree advisor suggests an invitation and Favor allocation toward
Luminary with Magisters, Blood Knights, Farstriders, and Shades of the Row,
the four tracks for **Life of the Party**. It never sends an invitation,
accepts a quest, or spends a Favor.

### Before starting

Unlock Saltheril's Soiree and open Lord Saltheril's four-invitation selector
for **Favor of the Court** or the introductory **High Esteem** quest.
The advisor needs readable live reputation for all four factions.

**Invitation effects require manual entry.** The Player Choice API defines
structured reward lists, but their completeness for this selector's weekly
gains, losses, and bonus Favor is not verified. Wild does not parse localized
descriptions, assume missing effects are zero, or reuse a previous week's offers.

### Steps

1. Enable **Wild > Events > Saltheril's Soiree > Show Soiree reputation advisor**, or run
   `/wild soiree on`. Automatic display is off by default.
2. Open Saltheril's invitation selector. The advisor opens with blank preview
   fields. Drag it aside to keep the native previews visible. To open it
   manually without enabling automatic display, use `/wild soiree show` or
   **Show Advisor Now** on the event's native settings page.
3. Copy each invitation into its row. The four reputation columns are changes
   to the named factions, not current standings. Include the minus sign for
   losses, and explicitly enter `0` for unlisted factions. Enter `0` or `1`
   in **Bonus Favors**, excluding the three base Favors. Tab moves to the next
   field; Shift+Tab moves back.
4. Check all four rows against the native previews, then click
   **Calculate from these previews**. Read the suggested invite and each
   faction's Favor count, projected standing, and net change.
5. Make the invitation choice yourself in Blizzard's selector. Complete the
   invited faction's **Fortify the Runestones** and spend the recommended
   Favors on that many completed guest quests. A Favor does not grant its
   reputation until its quest is completed; quest availability may require
   returning later in the week.

### Verify

The advisor shows live progress toward `2500`, derived from absolute standings
rather than rank-relative bar values.
Its projection includes invitation gains and losses, `+300` Fortify reputation
for the invited faction, three base Favors plus the entered bonus, and `+100`
per completed Favor quest. Only progress up to Luminary counts as useful.
If a client reports standing above the goal, that excess can absorb invitation
losses before useful progress decreases; the goal is not assumed to be the API's
standing cap.
Unused Favors are identified when the remaining reputation needs no more quests.

The planner maximizes **this week's total useful net reputation**, then breaks
ties by balancing the largest remaining gaps and avoiding wasted Favors.
Equally good invitations are marked **tied best**. This is not a guarantee
about the fastest number of future weeks: future offers are unknown.
Temporary reputation bonuses and extra reputation sources are not modeled.

Editing any preview removes the recommendation until Calculate is clicked
again. Reputation updates refresh standings and confirmed projections without
overwriting focused draft fields. Closing or refreshing the selector, leaving
the world, entering combat, or completing the invitation quest clears its
preview session. Offers and recommendations are never saved in `WildDB`.

### If it fails

| Symptom | Cause | Resolution |
| --- | --- | --- |
| No automatic helper | The feature is off, combat is active, or the selector is not recognized | Enable `/wild soiree on`, leave combat, and reopen Saltheril's selector |
| Show asks for the selector | No visible, readable four-invitation choice from Lord Saltheril | Open the native invitation selector first; cached choice data alone is not enough |
| Reputation is unavailable | At least one faction has missing or restricted data | Unlock the event and wait for reputation data; Wild does not substitute zero |
| Reputation scale is unsupported | The API reports an invalid maximum or one below the `2500` goal | Do not use a guessed projection; the game contract needs verification |
| Calculate reports an invitation error | A field is blank or invalid | Enter whole-number changes from `-2500` to `2500` for every faction and a bonus of `0` or `1` |
| Preview fields become blank | The selector session changed | Re-enter the offers displayed in that selector; old previews are deliberately discarded |

Use `/wild soiree hide` to dismiss the helper and `/wild soiree off` to disable
automatic display. Resetting Wild settings also disables the feature.

## Soiree Lua API

| Function | Contract |
| --- | --- |
| `Wild.SetFeatureEnabled("soiree", enabled)` | Enable or disable automatic display using the shared saved setting |
| `Wild.IsFeatureEnabled("soiree")` | Read the automatic-display setting |
| `Wild.ShowSoireeAdvisor()` | Open the helper for the visible selector, without enabling automatic display; return `true` or warn and return `false` |
| `Wild.HideSoireeAdvisor()` | Hide the helper and clear its preview session |
| `Wild.UpdateSoireeAdvisor()` | Apply the saved display setting |
| `Wild.GetSoireeProgress()` | Return absolute standings keyed by faction ID, or `nil, reason` when any track is unavailable or unsupported |
| `Wild.CalculateSoireeRecommendation(progress, offers)` | Calculate without side effects; return a plan or `nil, reason` |

For example, `Wild.SetFeatureEnabled("soiree", true)` enables automatic display.
`Wild.GetSetting("soiree.enabled")` and `Wild.SetSetting("soiree.enabled", value)`
access the same setting.

The calculator accepts numeric faction keys: `2711` Magisters, `2712` Blood
Knights, `2713` Farstriders, and `2714` Shades of the Row. `progress[factionID]`
is a non-negative 32-bit integer containing the actual standing, including any
standing above `2500`. For **each** invited faction,
`offers[invitedFactionID].reputation[targetFactionID]` contains all four signed
changes, including explicit zeros, and `.bonusFavors` is `0` or `1`.
There are no default invitation effects.

The plan contains `inviteFactionID`, per-faction `favors`, goal-capped `projected`, and
`net` maps, `totalFavors`, `usedFavors`, `unusedFavors`, total `gain` and
`remaining` reputation, and the `tiedInvites` list. If every current standing
is already Luminary, `complete` is `true`, `inviteFactionID` is absent, and
offers are not required. Neither function selects anything in the game.

## Product specifications

The [Wild specifications](docs/index.md) define the required behavior and user
outcomes, including self-explanatory configuration and slash-command coverage.

## Intent actions and logs

The **Intent rule bypass key** is **Shift** by default. Hold the configured key
until the bank, guild bank, vendor, or mailbox opens. Wild does not start
intent rules for that visit. In **Settings > AddOns > Wild**, select **Ctrl**
or **Alt** to change the key. Select **None** to turn off the shortcut.

At the mailbox, the shortcut also skips automatic collection of incoming
items and gold for that visit. It does not affect automatic repairs, Warband
auto-deposits, or loot triggers.
Use `/wild bank run` or `/wild mail run` to start rules manually while the bank
or mailbox is open.

Run `/wild intents bypass shift` to set the key from chat. Use `ctrl`, `alt`,
or `none` in place of `shift`, or omit the key to read the saved value.

Wild saves confirmed intent actions and failures in `WildDB.log`, even when
Debug Mode is off. Chat reports completed quantities, not queued requests.
Failed or unconfirmed items do not increase action totals or remove earlier
successful results from the summary.

### Processing path

1. Validate enabled rules and actor filters. Match item include groups and
   apply exclude groups through `Conditions.lua`.
2. Read the source inventory, request the action, and retain its item variant
   and actual bank or mail destination.
3. Use client events and `Core.lua` evidence helpers to confirm the result.
4. Save each newly confirmed quantity once. Combine confirmed stacks of the
   same variant and route for chat output.
5. Re-scan remaining items. On failure, keep confirmed results and record
   unresolved quantities separately.

| Action | Required confirmation |
| --- | --- |
| Vendor sale | The requested variant's total decreases across all physical player bags, with an empty cursor |
| Bank deposit or withdrawal | The source decreases and the destination increases by matching quantities |
| Bank transfer | Both withdrawal and deposit are confirmed; withdrawn items left in bags are reported as withdrawals, not transfers |
| Gold synchronization | Player and bank balances show matching changes |
| Mail | `MAIL_SEND_SUCCESS`, using actual attachment quantities and the captured recipient |
| Destruction | Bag removal and an empty cursor after the player's hardware click |

Evidence includes storage excluded from rule selection, such as the reagent
bag and Forever keyring. Moving an item there is not a sale or deletion.
Duplicate events do not count the same movement twice. Vendor retries retain
late results for other pending variants without adding delays between sales.
A transfer keeps its withdrawal evidence until its deposit and retry phases
settle, including receipts that arrive after an earlier partial deposit.
A failed deletion shows earlier confirmed results while the next click remains
under player control.
Pending vendor sales and hardware deletions do not act on the same variant
at the same time. A blocked delete requires another click after the sale
settles. Vendor requests wait while the cursor is occupied.

For a **Mail** intent, set **Recipient** to the address you use for manual
mail. Keep the space in Forever's full character name, such as `Alt Family`.
Realm-qualified names, such as `Alt Family-Realm`, also keep that space.
Wild selects the Send tab, checks that the composer is empty, then prepares
each batch in WoW's composer. It uses WoW's Send button and leaves any
confirmation to the player. It does not rewrite the saved recipient.

Mail summaries show **complete** only on normal completion, or **stopped** when
the queue stops after earlier successful sends. A send acknowledgment that
arrives after a close or timeout can still update the confirmed total, but it
does not restart the queue. An unresolved send blocks another automated mail
run until the client reports success or failure.

### Read the history

Run `/wild log show` for the last 20 matching entries. For example,
`/wild log show Vendor`, `/wild log show Bank`, `/wild log show mail`, and
`/wild log show warning` filter the shared history. `/wild log` shows the saved
entry count. `/wild log clear` clears actions, warnings, and diagnostics.

The ring buffer retains the latest 5,000 entries across reloads. Debug Mode
adds scan and rule diagnostics to the same buffer; it is not required for
action history. Replay formats item icons and money when displayed.

`Wild.GetLogEntries(filter)` returns chronological records. Each has `t`
(session time), `d` (date and time), `s` (processor), `m` (stored message), and
`kind` (`action`, `warning`, or `debug`). Confirmed action records have
`status = "confirmed"`, `action`, item `itemID`, `link`, and `count` where
applicable, numeric `copper`, and the actual `source`, `target`, or `recipient`.
Each record contains a new confirmed quantity, not a running total.

Unresolved warnings use `unconfirmedCount` or `unconfirmedCopper` and a
`reason`, not completed-action counts. Native client errors retain their
`errorType` and message with `status = "client_error"`. They identify the active
processor, not an assumed item or cause. A timeout alone does not establish
that a bank is full or an item cannot be sold.

## Developer checks

Run the focused specifications with a Lua 5.1 interpreter from the repository
root. They do not need a running WoW client or addon dependencies.

```powershell
lua tests\ContainersTest.lua
lua tests\ForeverCompatibilityTest.lua
lua tests\RetailCompatibilityTest.lua
lua tests\IntentLoggingTest.lua
lua tests\InboxBrowserTest.lua
lua tests\SoireePlannerTest.lua
lua tests\SoireeAdvisorTest.lua
lua tests\NativeSettingsTest.lua
lua tests\VolumeControlTest.lua
lua tests\SpeedIndicatorTest.lua
```

The fixtures cover intent confirmations, partial failures, late events, summary
totals, history retention, and unchanged vendor intervals. They also cover
container discovery and event sequencing, plus the Soiree API shapes and manual
fallback. Mail fixtures cover native send-field preparation and full Forever
recipient names. Inventory fixtures cover confirmed sends, incomplete inbox
data, and storage refreshes. Mailbox fixtures cover the native open sequence,
tab selection, single-stack pickup, and scoped bulk actions with confirmations.
WoW APIs are simulated because they are unavailable outside the client.
A live Retail and Forever check must confirm merchant refusals, full banks,
mail acknowledgments, deletion prompts, and displayed results. The local
fixtures do not establish live server behavior or complete Soiree reward data.
Volume fixtures cover opening without adjustments, interaction resets, held
controls, cancellation, and shared timeout settings. A live client check must
confirm slider dragging and panel layout.
For the mailbox, [verify layout, selective collection, and sending in both clients](docs/mailbox/design.md#testing-strategy).
Native settings fixtures cover inline numeric entry, draft cancellation, row
reuse, and alphabetical command discovery and copying. Check number-field
placement and command list scrolling in both clients.

## Sources

- [Pinned Retail native mail preparation](https://github.com/Gethe/wow-ui-source/blob/18c6d677b605b312f3d813d498404631fb941977/Interface/AddOns/Blizzard_MailFrame/MailFrame.lua)
- [Pinned Forever native mail preparation](https://github.com/Gethe/wow-ui-source/blob/17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c/Interface/AddOns/Blizzard_MailFrame/MailFrame.lua)
- [Pinned Retail bag-container API](https://github.com/Gethe/wow-ui-source/blob/18c6d677b605b312f3d813d498404631fb941977/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua)
- [Pinned Retail Player Choice API](https://github.com/Gethe/wow-ui-source/blob/18c6d677b605b312f3d813d498404631fb941977/Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerChoiceDocumentation.lua)
- [Pinned Retail friendship reputation API](https://github.com/Gethe/wow-ui-source/blob/18c6d677b605b312f3d813d498404631fb941977/Interface/AddOns/Blizzard_APIDocumentationGenerated/GossipInfoDocumentation.lua)
- [Pinned Forever bag indices, build 70755](https://github.com/Gethe/wow-ui-source/blob/17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c/Interface/AddOns/Blizzard_APIDocumentationGenerated/BagIndexConstantsDocumentation.lua)
- [Pinned Forever bank API](https://github.com/Gethe/wow-ui-source/blob/17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c/Interface/AddOns/Blizzard_APIDocumentationGenerated/BankDocumentation.lua)
- [Pinned Forever group-finder actions](https://github.com/Gethe/wow-ui-source/blob/17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c/Interface/AddOns/Blizzard_GroupFinder_VanillaStyle/Blizzard_LFGVanilla_Browse.lua)
- [Lord Saltheril, NPC 240832](https://www.wowhead.com/npc=240832/lord-saltheril)
- [Soiree quests, Favors, and invitation mechanics](https://warcraft.wiki.gg/wiki/Saltheril%27s_Soiree)
- [Silvermoon Court and Fortify overview](https://www.icy-veins.com/wow/silvermoon-court-renown-guide)
- [Magisters ranks](https://www.wowhead.com/faction=2711/magisters),
  [Blood Knights ranks](https://www.wowhead.com/faction=2712/blood-knights),
  [Farstriders ranks](https://www.wowhead.com/faction=2713/farstriders), and
  [Shades of the Row ranks](https://www.wowhead.com/faction=2714/shades-of-the-row)
- [Retail 12.1.5 friendship thresholds](https://wago.tools/db2/FriendshipRepReaction?build=12.1.5.70391)
