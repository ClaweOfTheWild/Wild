---
title: Wild mailbox - Spec
description: Read, collect, return, delete, and send mail in one window.
---

# Wild mailbox - Spec

Players can use one mailbox window to read letters, take selected stacks,
process groups of letters, compose mail, and run outgoing rules.

## Problem

Finding a specific attachment can require opening several letters. Players
who keep supplies in the mailbox need to take a particular stack without
collecting everything. They also need to process groups of letters without
handling each letter separately and choose when outgoing rules run.

## Scope

- The current character's inbox and the standard WoW composer.
- Bulk actions on all loaded letters or on a player-selected group.
- A read-only outgoing plan and manual and automatic runs of existing Mail
  rules. Rule editing stays in **Intent Rules**.

## Functional requirements

### FR1 - Browse and search attachment stacks {#fr1}

The **Items** tab MUST show a scrollable attachment grid, with one icon per
occupied attachment slot in the loaded inbox. It MUST show the count on stacks
with more than one item and WoW's item tooltip on hover when item data is
available. It MUST show the loaded and total message counts and refresh when
the inbox changes. Letters open in **List**, not in the grid.

Icon borders MUST use WoW's color for the attachment's quality. If the
quality is unavailable, the icon MUST have no colored border.

Bag and quiver icons MUST show their total slot capacity without a hover when
WoW reports it. The capacity MUST be distinct from the stack count. If the
capacity is unavailable, the icon MUST omit it.

Search MUST use case-insensitive substring matching. An item-name match shows
only the matching stacks. A sender or subject match includes all stacks in
that letter.

### FR2 - Take one attachment {#fr2}

Clicking a grid icon MUST request only its stack without opening the letter,
marking it as read, or collecting money. The browser MUST reject a take if the
displayed slot is stale or the icon changes during the click. It MUST leave
C.O.D. confirmation to the native controls in **List**.

### FR3 - Use one mailbox window {#fr3}

When **Use Wild mailbox** is on, Wild MUST replace the standard mailbox window
with **List**, **Items**, and **Send** tabs. **List** MUST show the WoW Inbox
and its letters. **Send** MUST show the standard composer. **Items** MUST be
the first tab on a new visit. Only the selected tab's content is visible.
The standard window MUST work when Wild Mail is off. Turning Wild Mail off
during a visit MUST restore the standard window without closing the mailbox or
clearing the draft. The setting defaults to off. Explicit show and hide
commands override the setting for the current visit only.

Using Wild Mail MUST stop automatic collection of incoming mail for the rest
of the visit without changing the saved collection or sending settings.

### FR4 - Resize the mailbox {#fr4}

The window MUST resize when the player drags its bottom-right corner. The grid
MUST reflow and preserve its search filter. Every matching stack MUST remain
reachable by scrolling. The window MUST stop shrinking before it clips the
native controls.

### FR5 - Sort attachment stacks {#fr5}

The player MUST be able to sort the grid by inbox order, item name (A-Z),
sender (A-Z), or stack size (largest first). Inbox order is the default.
Name and sender sorting MUST ignore case. Stacks with equal sort values
MUST stay in inbox and slot order. Missing item names and counts MUST sort
last in their respective modes.

The browser MUST save the player's choice and apply it immediately to the
open grid without changing the search filter or the native Inbox.

#### Behavioral scenarios

```gherkin
Scenario: Change the attachment sort order during a search
  Given the grid is open with a search that matches two different item names
  When the player selects Item name (A-Z) in Mail settings
  Then the matching stacks appear in alphabetical order
  And the search filter does not change
  And the same sort order applies the next time the player opens the grid
```

### FR6 - Control when outgoing rules run {#fr6}

Opening Wild Mail MUST show a scrollable outgoing plan on the left on all
three tabs. The plan MUST show each message in send order, with the
recipient, item names, and quantities. It MUST update when bags or rules
change and show the remaining messages during a run. Opening the preview
with `/wild mail preview` MUST NOT start a send.

**Process rules** on **Send** and `/wild mail run` MUST start the same send
queue. If the preview no longer matches the first pass when the button is
selected, Wild MUST show the updated plan without sending it. **Run Mail
rules on open** MUST be independent of automatic collection and default to
off. The intent rule bypass key MUST skip automatic sending for the visit
without blocking a manual run. Turning off automatic sending MUST stop
further automatic batches without canceling a pending send.

The queue MUST NOT start another run while one is active or a previous send
is unconfirmed. It MUST NOT overwrite a draft or send while a mail command
is pending. It MUST stop future batches if the mailbox closes. A send counts
only after confirmation, and a late confirmation MUST NOT restart a stopped
run.

When Wild scans the bags for outgoing mail, it MUST exclude soulbound items
even if they match a Mail rule. If a queued item becomes soulbound, Wild MUST
skip it before pickup.

#### Behavioral scenarios

```gherkin
Scenario: Send matching items on request
  Given a Mail rule matches a stack in the player's bags
  And another Mail rule matches a different stack for a different recipient
  And Run Mail rules on open is off
  When the player opens the mailbox
  Then the plan shows both recipients and their matching stacks
  And Wild sends nothing
  When the player selects Process rules once with no draft
  Then Wild requests a send for the first batch
  And Wild submits the next batch without another click after WoW confirms the first
  And Wild reports each batch as sent only after WoW confirms it
```

### FR7 - Process selected or loaded mail {#fr7}

Each loaded letter in **List** MUST have a checkbox. When one or more letters
are checked, the bulk buttons MUST say **selected** and apply only to those
letters. When no letters are checked, the buttons MUST say **all** and apply
to all eligible letters WoW has loaded. Selection MUST persist across inbox
pages and tabs. An inbox change that invalidates selection MUST clear the
checkmarks. A click that began with a stale selection MUST NOT become an
all-mail action. Searching **Items** MUST NOT change which letters a bulk
action affects.

- **Open mail** MUST collect available items and gold without reading bodies
  or paying C.O.D. charges.
- **Return mail** MUST follow WoW's return eligibility and require
  confirmation. A return includes any items or gold still in the letter.
- **Delete empty mail** MUST require confirmation and skip mail with items,
  gold, C.O.D., or a native Return action. It MAY delete unread letters unless
  **Keep unread mail when deleting empty mail** is on. The prompt MUST disclose
  that any letter text is deleted.

All three actions MUST skip GM mail. They MUST NOT overlap with a pending
mail command or the rule send queue. They MUST stop further requests if the
mailbox closes, a request fails, or the result cannot be confirmed.

#### Behavioral scenarios

```gherkin
Scenario: Return only checked letters from different inbox pages
  Given two pages of loaded mail contain returnable letters
  When the player checks one letter on each page
  And the player selects Return selected
  Then the confirmation identifies two letters in the selected scope
  When the player confirms the return
  Then Wild requests a return for each checked letter, one at a time
  And no unchecked letter is returned
```

## Acceptance criteria

```gherkin
# AC1 - Verifies: FR1, FR2, FR3
Scenario: Take one of several visible stacks
  Given one unread letter contains two stacks and money
  And another letter contains a stack
  And Use Wild mailbox is on
  When the player opens a mailbox
  Then the grid shows all three stacks without opening either letter
  When the player clicks the second stack from the unread letter
  Then only that stack goes to the bags if WoW accepts the request
  And the other stacks and the money remain in the inbox
  And the browser does not mark the letter as read

# AC2 - Verifies: FR3, FR6
Scenario: Reply and preserve a draft
  Given Wild Mail is on and the composer is empty
  When the player opens a letter on List and selects Reply
  Then the Send tab appears with the reply addressed
  When the player selects Process rules
  Then Wild does not change or send the draft
  When the player turns off Use Wild mailbox
  Then the draft remains in the standard composer

# AC3 - Verifies: FR1, FR3, FR7
Scenario: Collect checked mail while the item grid is filtered
  Given the player checked a letter with an attachment on List
  When the player switches to Items and searches for a nonmatching item
  Then the grid is empty and the bulk button still says Open selected
  When the player selects Open selected
  Then only eligible contents of the checked letter are requested
```

## Constraints and assumptions

- The browser can search only the messages and attachment names WoW exposes.
- Accounts subject to trial mail restrictions use the standard mailbox.
- The grid MUST NOT read message bodies. The explicit `read` command displays
  the letter in chat. The browser MUST NOT save mail text or search terms
  between mailbox visits.

## Where this connects

- [Design](design.md)
- [Configuration](../configuration/spec.md)
