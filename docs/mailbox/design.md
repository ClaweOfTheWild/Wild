---
title: Wild mailbox - Design
description: Host native mail controls with a stack grid and guarded bulk actions.
---

# Wild mailbox - Design

Wild Mail hosts the native Inbox, letter reader, and composer in one resizable
window. The standard mailbox remains the owner of the interaction.

## Specification

[Wild mailbox requirements](spec.md)

## Approach

Blizzard closes the mail interaction and clears the draft when the native
mailbox frame hides. Wild leaves that frame shown and suppresses its shell,
mouse input, and native tabs. The Wild shell hosts the native pages with
reversible parent and anchor changes. Retail offsets its controls within
fixed-size pages. Forever stretches the pages to their host, which keeps the
original mailbox's dimensions. The resize bounds reserve room for those
controls and the Send actions.

The List and Send tabs use Blizzard's tab handler. WoW stores the callback
that opens the mailbox, so Wild hooks the tab reset within that callback
rather than the global show function. Wild also observes later tab changes
so Reply opens Send and a completed native reply returns to List.
Opening a letter replaces the list inside the same shell. Other tabs place
the letter behind the shell without hiding it: Blizzard's hide script can
clear the message ID before the native Reply handler reads it. Disabling
Wild Mail moves the letter back before hiding the shell.

## Data and contracts

The grid reads inbox headers and occupied slots when Items opens or the inbox
updates. Search and sort use the snapshot and retain the original message
and slot for each stack. Resizing reflows visible rows without reading the
inbox again. The window keeps its size across visits until the UI reloads.
Closing the mailbox clears the snapshot and search.

The grid colors each icon border with WoW's palette for the quality reported
by `GetInboxItem`. It clears the border when it reuses an icon for an
attachment without quality data. Item-load events update the color without
changing the search or the selected letters. Quality does not affect
attachment identity.

For bags and quivers, the grid matches WoW's localized `CONTAINER_SLOTS`
line in the attachment tooltip data without showing a tooltip. The capacity
appears in the upper-left corner, separate from the stack count. Missing
data uses the same item-load refresh as other attachment details. The
capacity does not affect attachment identity or sort order.

WoW exposes mutable inbox indexes rather than a message ID. Before reading
or taking, Wild compares the live header and slots with the selected stack.
Reusing or moving an icon cancels a press that started on its old stack.
Hover uses the native tooltip. Only an explicit read command loads a letter
from Items, because `GetInboxText` marks it as read. Icon clicks and the take
command share one request path. It rejects stale slots and C.O.D. payments
and reflects successful removal on the next inbox update.

Wild binds checkboxes to each row's current inbox index after WoW updates
the native page. The same selection applies on both receiving tabs and
does not depend on the grid search. A change to the loaded sequence or its
contents invalidates the displayed selection. Wild hides the native Open All
button and deactivates the Forever controller footer while the replacement
is visible so those controls cannot bypass the selection.

The receive queue records the loaded inbox and eligible indexes when the
player starts an action. Return and delete show the scope and consequences
before the first request. The queue checks the inbox again before that request
and works from highest to lowest index so confirmed removals cannot shift the
remaining targets. A mail event starts the confirmation check. The queue
advances only when the pending flag clears and the requested change is visible
with all other letters unchanged. It stops on a failure, a timeout, an
unexpected change such as an inbox refill, or exit from the receiving view.
It does not read bodies to infer eligibility.

The Process rules button, the run command, and the automatic open handler
start the same queue. It selects items through the intent engine, uses the
native composer and Send button, and leaves confirmations to the player. It
checks the draft, cursor, and mail command state before each batch. After
preparing the draft, it checks for a native mail lock again and runs WoW's
Send validation before it submits the batch. `MAIL_SEND_SUCCESS` confirms
the send and lets the queue continue without another click. An acknowledgment
after a timeout or close can update the log, but cannot start another batch.

The window and send queue share a mailbox visit. Enabling the window prevents
the next automatic collection request, not one already sent to WoW. If the
standard window uses both automatic options, collection waits during the rule
send queue. The rule bypass key affects automatic starts only.

## Testing strategy

Run the mailbox, native settings, and intent logging fixtures with Lua 5.1.
They simulate the WoW API to check the window lifecycle, selective pickup,
settings and command parity, draft protection, and mail acknowledgments.
The mailbox fixture keeps the same show callback that WoW registers and
checks both orders of the native open and Wild's mail event.

For a live check on Retail and Forever, use a test character with two unread
letters. Include a bag of known capacity, a stack of another item, and money
in one letter. Enable **Use Wild mailbox**, reload the UI, and open the
mailbox. Check that **Items** opens first and that the bag shows its capacity
without a hover. Check that search, sort, and resize work together. Take one
stack. Confirm that other stacks and money remain and the letter stays unread.
When a C.O.D. letter is available, check that **Items** rejects pickup and that
**List** opens the native payment prompt. Do not accept the charge.

Open a letter on **List** and select Reply. Confirm that the addressed draft
appears in **Send** and that **Process rules** does not change it. Toggle Wild
Mail off and check that WoW shows the draft in the standard window. Resize to
the minimum size with Wild Mail on and check that all controls fit. Check
that Escape and the close button end the mailbox interaction.

Use disposable mail for bulk checks. Check letters on two native inbox
pages and switch to **Items**. Search for text that matches nothing and
confirm that the bulk buttons still say **selected**. Cancel a return and
verify that no letter leaves the inbox. Confirm a return for checked
letters and verify that unchecked letters remain. Toggle unread protection
and check which empty letters the delete confirmation counts before
confirming. On Forever, verify that the native controller Open All shortcut
is inactive in Wild Mail and returns in the standard window.

Use two Mail rules for different low-value test stacks and approved test
recipients. Check that opening the mailbox does not send anything by default.
Select **Process rules** once. Check that each recipient gets the correct stack
without a separate **Send** click. Repeat with **Run Mail rules on open** enabled.
Verify that the bypass key prevents the automatic send while a manual run still
works.

## Client contracts

- [Pinned Retail mail UI][retail-mail]
- [Pinned Forever mail UI][forever-mail]
- [GetInboxText marks a message as read][mail-text]

[retail-mail]: https://github.com/Gethe/wow-ui-source/blob/18c6d677b605b312f3d813d498404631fb941977/Interface/AddOns/Blizzard_MailFrame/MailFrame.lua
[forever-mail]: https://github.com/Gethe/wow-ui-source/blob/17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c/Interface/AddOns/Blizzard_MailFrame/MailFrame.lua
[mail-text]: https://warcraft.wiki.gg/wiki/API_GetInboxHeaderInfo#Returns
