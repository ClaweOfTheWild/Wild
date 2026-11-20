---
title: Inbox browsing - Design
description: Read the loaded inbox and validate one attachment request in the current visit.
---

# Inbox browsing - Design

An ordinary addon pane sits beside the native Inbox tab. It suspends display
while the Send Mail tab or a native message is open, so those controls stay
under WoW's control.

## Specification

[Inbox browsing requirements](spec.md)

## Approach

`InboxBrowser.lua` reads inbox headers and occupied attachment slots on open
and on inbox updates. Search filters this snapshot without reading letter
bodies. `GetInboxText` marks a letter as read, so only a player selection
calls it. The snapshot, search, and selection are cleared on mailbox close.

WoW exposes mutable inbox indexes rather than a message ID. Before reading
or taking, the browser checks the live header and attachment slots against
the selection. A take also requires a visible pane, a loaded slot, no C.O.D.
charge, no pending native mail command, and an empty cursor outside combat.
The browser calls `TakeInboxItem` for one slot and clears the selection. It
does not retry or report a completed transfer.

The browser and `Mail.lua` share the mailbox visit. The saved browser setting
prevents the bulk queue from starting. Opening the pane manually stops the
next queued collection request. Requests already sent to WoW cannot be undone.

## Testing strategy

Run `lua tests\InboxBrowserTest.lua` with Lua 5.1. The fixture uses simulated
WoW frames and inbox events because the game API is only available in the
client. It checks the addon's behavior, not native frame layout or server
confirmation.

For a live check, use a test character with prepared non-C.O.D. mail in Retail
and Forever. Send a message with two distinct attachments and a small amount
of money. Search for the second attachment, read the message, and take that
stack. Verify that only that stack arrives in the bags, the first attachment
and money remain, and the filter updates. Check that the pane does not cover
an open native letter and that a prepared C.O.D. message cannot be taken from
the pane. Do not confirm a charge for the check.

## Client contracts

- [Pinned Retail mail UI][retail-mail]
- [Pinned Forever mail UI][forever-mail]
- [GetInboxText marks a message as read][mail-text]

[retail-mail]: https://github.com/Gethe/wow-ui-source/blob/18c6d677b605b312f3d813d498404631fb941977/Interface/AddOns/Blizzard_MailFrame/MailFrame.lua
[forever-mail]: https://github.com/Gethe/wow-ui-source/blob/17ed2c3e8471cdc3806ab0d26a082be7c67d3d7c/Interface/AddOns/Blizzard_MailFrame/MailFrame.lua
[mail-text]: https://warcraft.wiki.gg/wiki/API_GetInboxHeaderInfo#Returns
