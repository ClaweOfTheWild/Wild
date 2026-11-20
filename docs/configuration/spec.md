---
title: Doc-less configuration - Spec
description: Players understand and use Wild through clear controls, complete slash commands, and help inside the game.
---

# Doc-less configuration - Spec

Wild gives players the information they need to understand, configure, and use
its functionality without leaving the game. One alphabetical catalog shows
the slash commands. Complex options have an information icon.

**Doc-less** means a separate player manual is not required. It does not mean
developer documentation is absent.

## Problem

Players cannot make informed choices when an option hides its purpose, accepted
values, requirements, or effects. A separate manual interrupts play and separates
the explanation from the control. A feature that is available only through the
interface also prevents a player from using an equivalent slash command.

## Outcomes and impact

- **Player outcome:** A player understands an option and completes the related
  task without an external manual or knowledge of the addon's code.
- **Domain signal:** Zero user-facing settings or actions lack an equivalent
  slash command or the information needed to use them.
- **DORA direction:** Explicit behavior contracts are expected to reduce change
  failures and shorten the diagnosis of configuration regressions. No direct
  improvement in deployment frequency or lead time is assumed.

## Users and jobs

| User | Job |
| --- | --- |
| A player who is unfamiliar with Wild | Understand an option and use it correctly inside the game |
| A player who wants to find a command | Find its syntax, purpose, and requirements in one list |
| A player who uses slash commands | Inspect state, change settings, and request supported actions without a configuration window |
| A player who needs extra help | Find the requirements, effects, and examples beside the relevant control |

## Scope

**In scope**

- All Wild-authored configuration text, command help, input instructions,
  warnings, and information text.
- All user-facing settings, including individual fields in rules, conditions,
  actor selections, and per-item choices.
- All player-requested actions and queries, including creating, editing,
  ordering, and removing configurable records.
- Controls in native Settings, richer editors, and other Wild feature panels.
- The command catalog, command copying, and additional information at the
  relevant control.

In this specification, **functionality** means behavior a player can configure,
request, or inspect. Internal helper functions are not separate player actions.
Ordinary navigation, scrolling, closing a window, and information controls
do not require equivalent commands.

**Out of scope**

- Installation before Wild is available in the game.
- A documentation website or a separate in-game manual.
- Changes to the purpose, defaults, or automation rules of existing features.

## Non-goals

- Removing developer specifications, guides, or optional external references.
- Running a command when a player asks to view or copy it.
- Bypassing a game restriction, required player input, or confirmation.

## Functional requirements

### FR1 - Options explain their use inside the game {#fr1}

Wild MUST let a player determine what a setting or action does from its control
and associated help. The explanation MUST identify required inputs, units,
accepted values, prerequisites, and effects when these are not clear from the
control itself. A separate manual or website MUST NOT be required.

#### Behavioral scenarios

```gherkin
Scenario: A player understands a container option
  Given a player has not used Wild's container options
  When the player reads the option and its associated help
  Then the player can identify which containers the option affects
  And the player can identify whether existing per-item choices change
  And the player does not need to open a separate manual
```

### FR2 - All player functionality has equivalent slash commands {#fr2}

Every setting, supported action, and query in scope MUST be available through
slash commands under `/wild`. This includes the full range of accepted values
and the complete configuration of rules and other editable records.

Commands MUST produce the same supported result as the equivalent interface
operation. A command that only opens a configuration window does not satisfy
command coverage for the settings inside it. A supported sequence of commands
MAY express a task that needs more than one step.

Accepted text, numeric precision, and record selection MUST be preserved. A
player MUST NOT need to edit saved data or write code to complete the task.

#### Behavioral scenarios

```gherkin
Scenario: A player configures a rule without its editor
  Given a valid rule can be created and edited through the interface
  When the player makes the same choices through supported slash commands
  Then the saved rule has the same behavior
  And each editable part of the rule is available through slash commands
  And the player does not need to open the rule editor

Scenario: A text setting preserves its value
  Given a text setting accepts spaces, quotation marks, and non-ASCII characters
  When the player sets that text through supported slash commands
  Then the saved text is identical to the accepted input
  And no text is silently removed or changed
```

### FR3 - One alphabetical catalog shows every command {#fr3}

Wild MUST show every slash command in one list on the **Commands** page.
The list MUST be in alphabetical order by command syntax. Players MUST be able
to open the page from Settings and through `/wild help`.

The list MUST include available forms, aliases, arguments, purpose, and
applicable restrictions. Any addition or change to player functionality MUST
include its corresponding command and catalog entry in the same change.
Settings and action controls MUST NOT repeat command syntax in buttons or
tooltips.

#### Behavioral scenarios

```gherkin
Scenario: A player finds a command without inspecting settings controls
  Given Wild supports more than one slash command
  When the player enters /wild help
  Then Wild opens the Commands page from Settings
  And it shows every supported command and alias in alphabetical order
  And each entry explains its syntax and purpose

Scenario: Wild adds a player action
  Given Wild adds a supported action
  When the player opens Commands
  Then the action's command appears in alphabetical order
  And the action control does not have a command icon or command tooltip
```

### FR4 - A player can copy command syntax {#fr4}

Players MUST be able to select and copy complete command syntax in the catalog.
Copied syntax MUST contain no color codes or truncation. Wild MUST show which
arguments are optional and which values the player must enter before running a
command. If the player must copy the text manually, Wild MUST give that
instruction and MUST NOT report that it copied the command.

#### Behavioral scenarios

```gherkin
Scenario: A player selects command syntax to copy
  Given a catalog entry has an argument with more than one choice
  When the player selects the entry
  Then Wild makes the full syntax available for copying as plain text
  And the syntax identifies each choice
```

### FR5 - Complex options provide additional information in place {#fr5}

An option MUST have a distinct information icon when its label and short
description do not fully explain how to use it. This includes options with
prerequisites, interactions, grouped conditions, non-obvious units, delayed
effects, or a risk of losing items, gold, or saved configuration.

Hovering over the information icon MUST reveal the additional explanation.
That explanation MUST cover the option's purpose, the required configuration,
and relevant limits or consequences. For grouped conditions or tasks with more
than one step, it MUST include at least one complete configuration example and
its expected result.

Information MUST remain available when a feature or action is disabled. A player
MUST be able to read a longer explanation without repeatedly recreating a
short-lived hover state.

#### Behavioral scenarios

```gherkin
Scenario: A player understands condition groups
  Given a player is editing a rule with more than one condition group
  When the player hovers over the information icon for the groups
  Then the explanation states how conditions and groups combine
  And it explains how included and excluded matches affect the result
  And a configuration example is available

Scenario: A feature is disabled
  Given a feature is off
  When the player inspects its information icon
  Then its configuration guidance and relevant limits are still available
```

### FR6 - Invalid or unavailable operations explain recovery {#fr6}

An invalid command or value MUST identify the problem and the accepted input or
required correction. An invalid command MUST make no configuration changes and
MUST NOT silently substitute a different value.

When an action cannot run because a prerequisite is missing, Wild MUST explain
the prerequisite. Commands MUST respect the same game restrictions and required
confirmations as their interface equivalents. An unavailable or unconfirmed
action MUST NOT be reported as completed.

Existing supported slash commands MUST retain their meaning.

#### Behavioral scenarios

```gherkin
Scenario: A setting receives an invalid value
  Given a setting has a saved value
  When the player submits a slash command with an invalid value
  Then Wild identifies the invalid input and the accepted input
  And the saved configuration remains unchanged

Scenario: A bank action is unavailable
  Given the required bank is not open
  When the player requests the bank action through a slash command
  Then Wild explains that the required bank must be open
  And it does not report a completed bank action
```

## Non-functional requirements

### NFR1 - Configuration language conforms to ASD-STE100 in en-US {#nfr1}

100% of Wild-authored text in scope MUST conform to
[ASD-STE100 Issue 9](https://asd-ste100.org/about_STE.html), with American English
(`en-US`) spelling. The same concept MUST use the same term and meaning across
controls, command help, information, and warnings.

Game-specific terms MUST follow the standard's technical-term rules. Verbatim
game names, identifiers, command tokens, and player-entered text MUST NOT be
rewritten to satisfy a general-language dictionary.

#### Behavioral scenarios

```gherkin
Scenario: A player reads an option and its command help
  Given an option is described in its control and in command help
  When the wording is checked against ASD-STE100 Issue 9
  Then both descriptions conform to its applicable rules
  And both use en-US spelling and the same terms for the same concepts
  And quoted game names and player-entered text remain unchanged
```

### NFR2 - Help and copying preserve the player's work {#nfr2}

Inspecting a command, copying a command, or reading information MUST cause zero
setting changes and zero gameplay actions. These interactions MUST NOT execute
the offered command, start automation, accept a confirmation, or save, discard,
or overwrite an unfinished edit.

#### Behavioral scenarios

```gherkin
Scenario: A player asks for help during an unfinished edit
  Given a player has an unsaved rule edit
  When the player opens Commands and copies command syntax
  Then the unsaved edit remains intact
  And no setting is changed or saved by those interactions
  And those interactions do not execute a gameplay action or the offered command
```

## Acceptance criteria

**AC1 - Verifies:** [FR1](#fr1), [FR2](#fr2), [FR3](#fr3),
[FR4](#fr4), [NFR2](#nfr2).

```gherkin
Scenario: A player restores a setting with its copied command
  Given center-circle opacity is 30 percent
  When the player copies its command syntax from Commands
  Then the syntax identifies the opacity argument in percent
  And copying does not change the setting
  When the player enters 75 for the argument and runs the command
  Then the saved setting and its interface show 75 percent
  And the player does not need an external manual
```

**AC2 - Verifies:** [FR1](#fr1), [FR2](#fr2), [FR5](#fr5),
[FR6](#fr6), [NFR1](#nfr1), [NFR2](#nfr2).

```gherkin
Scenario: A player learns an action and handles an unmet requirement
  Given a player is unfamiliar with a bank action
  And the required bank is not open
  When the player reads the action's additional information
  Then the explanation identifies its purpose and the required bank
  And it uses the same terms as the action's command help
  And reading it does not start a bank action
  When the player explicitly requests the action through its slash command
  Then Wild explains the unmet requirement inside the game
  And the player receives no false completion report
```

## Constraints and assumptions

- The game can restrict clipboard access, gameplay actions, combat behavior, or
  operations that require explicit player input. Command coverage does not
  bypass those restrictions.
- Optional external references can provide additional depth, but they are not
  required to understand or complete the tasks in scope.

## Dependencies

- Access to the official ASD-STE100 Issue 9 writing rules and dictionary for
  language review. The publisher's overview is not a substitute for the full
  standard.

## Where this connects

- [MSX specification-writing guide](https://msxorg.github.io/docs/Ways-of-Working/Spec-Driven-Development/#what-a-specification-is)
  defines the behavior-focused scope of a specification.
- [MSX specification template](https://msxorg.github.io/docs/Ways-of-Working/Spec-Driven-Development-Templates/#specification)
  defines its structure and requirement scenarios.
