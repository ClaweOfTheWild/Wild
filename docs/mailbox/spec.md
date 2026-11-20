---
title: Inbox browsing - Spec
description: Find mail and take a selected attachment without collecting the rest.
---

# Inbox browsing - Spec

Players can find a message or attachment in their current character's mailbox
without paging through the native inbox or collecting all mail.

## Functional requirements

### FR1 - Search loaded mail {#fr1}

The browser MUST list every available message for the current character and
show the loaded and total counts. It MUST refresh when WoW updates the inbox.
It MUST filter by sender, subject, and attachment name with case-insensitive
substring matching. The browser MUST open a message body only after an
explicit selection.

### FR2 - Take one attachment {#fr2}

The browser MUST show the selected message's text, attachments, and money or
C.O.D. charge when WoW supplies them. A take action MUST request only the
attachment stack selected by the player. It MUST reject stale selections
and leave C.O.D. confirmation to the native inbox.

#### Behavioral scenarios

```gherkin
Scenario: A message contains two attachments and money
  Given the browser is open and the attachments are available
  When the player searches for one attachment and selects its message
  Then the browser shows both attachments and the enclosed amount
  When the player selects Take for the matching attachment
  Then the other attachment and the money remain in the inbox
```

### FR3 - Keep collection deliberate {#fr3}

The browser MUST offer manual and opt-in automatic display. It MUST stop
Wild's bulk collection for the remainder of a browsing visit without
changing the saved bulk collection setting or the outgoing mail rules.

## Constraints

- The browser can search only the messages and attachment names WoW exposes.
- The browser MUST NOT read unselected bodies or save mail text or search
  terms between mailbox visits.

## Where this connects

- [Design](design.md)
- [Configuration](../configuration/spec.md)
