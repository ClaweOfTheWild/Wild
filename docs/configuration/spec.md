---
title: Doc-less configuration - Spec
description: Players understand and use Wild through clear controls, complete slash commands, and help inside the game.
---

# Doc-less configuration - Spec

Wild gives players the information they need to understand, configure, and use
its functionality without leaving the game. Each setting or action has a command
icon. Complex options have an information icon.

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
- Command hints, command copying, and additional information at the relevant
  control.

In this specification, **functionality** means behavior a player can configure,
request, or inspect. Internal helper functions are not separate player actions.
Ordinary navigation, scrolling, closing a window, and the command and information
icons themselves do not require additional command icons.

**Out of scope**

- Installation before Wild is available in the game.
- A documentation website, a separate in-game manual, or a particular visual
  layout for help.
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

### FR3 - Each control reveals its command {#fr3}

Each setting or action control in scope MUST have an associated, visible command
icon. Hovering over the icon MUST show the slash command for that setting or
action, including its required arguments. Command and information icons MUST be
distinguishable without relying only on color.

For a saved setting, the command MUST reproduce its saved value, not toggle it
or use an unsaved draft. For an action, the command MUST identify the action and
its selected target. A command sequence MUST show every required step.

The hint MUST reflect a changed saved value or selected target before the next
copy action. If no valid saved value or complete action input exists, the hint
MUST identify the missing information. It MUST NOT present an incomplete command
as ready to run.

#### Behavioral scenarios

```gherkin
Scenario: A command hint reproduces a saved setting
  Given automatic repair is saved as off
  When the player hovers over its command icon
  Then the hint shows the command that sets automatic repair to off
  And it does not show a toggle command or the command that turns repair on

Scenario: A saved value changes while its control is visible
  Given a setting's saved value changes through a slash command
  When the player next inspects or copies the control's command
  Then the offered command reproduces the changed saved value
  And it does not use a rounded display value or an unsaved draft
```

### FR4 - A player can copy the offered command {#fr4}

Clicking the command icon MUST copy the complete offered command when the game
permits direct copying. The copied text MUST be usable command text without
display formatting, missing arguments, or silent truncation.

When direct copying is unavailable or fails, the player MUST be able to select
and copy the complete command manually inside the game. Wild MUST explain why
manual copying is needed and the required copy action. Showing text for manual
copying MUST NOT be reported as a completed clipboard copy.

#### Behavioral scenarios

```gherkin
Scenario: Direct copying is permitted
  Given a command hint offers a complete command
  And the game permits direct copying
  When the player clicks the command icon
  Then the clipboard contains the offered command without display formatting

Scenario Outline: A player needs manual copying
  Given the next direct copy <outcome>
  When the player clicks the command icon
  Then the complete command is available for selection and manual copying
  And Wild explains why manual copying is needed
  And the player receives instructions for that action
  And Wild does not claim that a clipboard copy has occurred

  Examples:
    | outcome           |
    | is not permitted  |
    | does not complete |
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
  When the player views information and copies an available saved-state command
  Then the unsaved edit remains intact
  And no setting is changed or saved by those interactions
  And those interactions do not execute a gameplay action or the offered command
```

## Acceptance criteria

**AC1 - Verifies:** [FR1](#fr1), [FR2](#fr2), [FR3](#fr3),
[FR4](#fr4), [NFR2](#nfr2).

```gherkin
Scenario: A player restores a setting with its copied command
  Given a player saves center-circle opacity as 75 percent
  When the player uses the command icon to obtain and copy its command
  Then the command represents 75 percent
  And copying does not change the setting
  When the player changes opacity to 30 percent
  And explicitly runs the copied command
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
