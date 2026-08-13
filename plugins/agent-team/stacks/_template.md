# Stack profile: <name>

Copy this file to add support for another stack. Keep it short — a profile is a
lookup table, not a tutorial.

Applies when: <the file or dependency that identifies this stack>

## Gates

| Gate | Typical command | Notes |
|---|---|---|
| typecheck | | |
| lint | | |
| dependency audit | | |
| test | | |
| build | | |

The secret scan is deliberately not a row here: it is stack-independent and the
gate runner applies it to every project, so a profile never declares it.

Order them cheapest-and-most-localised first. If this stack has no equivalent
for a gate, leave the row out rather than inventing a command — an invented gate
reports a pass it has not earned.

## Conventions to detect and follow

- Package manager / dependency file:
- Project layout:
- Test file location and naming:
- Formatting and lint config:

## Skills that apply

List the plugin skills relevant to this stack.

## Things to check in review on this stack

The mistakes that are common and specific to this stack. Keep it to things a
general reviewer would miss.
