# Wild

Wild is a World of Warcraft Retail quality-of-life addon for players who want
configurable interaction helpers and automation. Macro and addon authors can
call its public functions on the `Wild` table. It targets Retail 12.1.5 and
uses the game's Lua 5.1 environment without addon libraries.

Open **Settings > AddOns > Wild** with `/wild`. Use `/wild help` for commands.
Settings are stored in `WildDB`; the settings UI, slash commands, and public
setters share that store.

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

1. Enable **Wild > Soiree > Show Soiree reputation advisor**, or run
   `/wild soiree on`. Automatic display is off by default.
2. Open Saltheril's invitation selector. The advisor opens with blank preview
   fields. Drag it aside to keep the native previews visible. To open it
   manually without enabling automatic display, use `/wild soiree show` or
   **Show Advisor Now** on the native Soiree settings page.
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

## Developer checks

Run the focused specifications with a Lua 5.1 interpreter from the repository
root. They do not need a running WoW client or addon dependencies.

```powershell
lua tests\SoireePlannerTest.lua
lua tests\SoireeAdvisorTest.lua
lua tests\NativeSettingsTest.lua
```

The fixtures cover the supported API shapes and the manual fallback. A live
client smoke check should confirm selector detection and layout; mock tests
do not establish that the selector supplies complete structured reward data.

## Sources

- [Pinned Retail Player Choice API](https://github.com/Gethe/wow-ui-source/blob/18c6d677b605b312f3d813d498404631fb941977/Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerChoiceDocumentation.lua)
- [Pinned Retail friendship reputation API](https://github.com/Gethe/wow-ui-source/blob/18c6d677b605b312f3d813d498404631fb941977/Interface/AddOns/Blizzard_APIDocumentationGenerated/GossipInfoDocumentation.lua)
- [Lord Saltheril, NPC 240832](https://www.wowhead.com/npc=240832/lord-saltheril)
- [Soiree quests, Favors, and invitation mechanics](https://warcraft.wiki.gg/wiki/Saltheril%27s_Soiree)
- [Silvermoon Court and Fortify overview](https://www.icy-veins.com/wow/silvermoon-court-renown-guide)
- [Magisters ranks](https://www.wowhead.com/faction=2711/magisters),
  [Blood Knights ranks](https://www.wowhead.com/faction=2712/blood-knights),
  [Farstriders ranks](https://www.wowhead.com/faction=2713/farstriders), and
  [Shades of the Row ranks](https://www.wowhead.com/faction=2714/shades-of-the-row)
- [Retail 12.1.5 friendship thresholds](https://wago.tools/db2/FriendshipRepReaction?build=12.1.5.70391)
