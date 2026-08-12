# UX behaviour

The states below are part of the design. A screen designed only in its populated
state is a screen that will look broken most of the time a real user meets it.

## Every data view needs four states

| State | Requirement |
|---|---|
| **Loading** | Skeleton matching the real layout, not a spinner. Prevents layout shift. |
| **Empty** | Explain what goes here and give the action that fills it. Never just "No data". |
| **Error** | Say what failed, whether it is the user's doing, and offer a retry. |
| **Populated** | Test with 1 row, with 500, and with a pathologically long value. |

A "no results after filtering" state is distinct from "nothing exists yet" and
needs different words - one offers clearing filters, the other offers creating.

## Feedback

- Any action over ~400ms needs a visible pending state, and the trigger must
  disable to prevent double submission.
- Destructive actions confirm, and the confirm button names the act - "Delete 3
  invoices", not "OK".
- Success needs acknowledgement. Silence reads as failure.
- Errors appear next to the field that caused them, not only in a banner.

## Forms

- **Labels above inputs**, always visible. Placeholder-as-label fails on focus
  and fails screen readers.
- Validate on blur, not on every keystroke. Re-validate on submit.
- Error text says how to fix it: "Password needs 8+ characters", not "Invalid".
- Never clear a user's input on a failed submit.
- Mark optional fields, not required ones, when most are required.
- Correct input types so mobile keyboards match (`email`, `tel`, `numeric`).

## Navigation and state

- The URL reflects where the user is. Reload and back must work.
- Filters, sorting, and pagination belong in the URL, not only in memory.
- Never trap focus or hijack browser back.

## Motion

- 150-250ms for most transitions. Longer feels sluggish; shorter is invisible.
- Animate transform and opacity. Animating layout properties causes jank.
- Respect `prefers-reduced-motion` - reduce to a fade or remove entirely.
- Motion should explain a relationship (where a panel came from), not decorate.

## Destructive and irreversible

- Prefer undo over confirm where the action can be reversed.
- Where it truly cannot, require the confirm to state the consequence.
- Never make the destructive action the visually primary one.
