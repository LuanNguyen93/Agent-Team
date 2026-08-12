---
description: Route a build request through the agent team at the right planning depth - QUICK, FEATURE, or PROJECT.
argument-hint: [what you want built]
---

Route this request through the agent team: **$ARGUMENTS**

Load the `workflow-router` skill and follow it.

1. **Classify** the request as QUICK, FEATURE, or PROJECT, and state the tier and
   your reason in one line before doing anything else, so the user can correct you.
2. **Route** to the agents for that tier.
3. **Stop for sign-off** after the PRD on a PROJECT, before spending tokens on
   architecture and design.

Hold these regardless of tier:

- No code before a plan — on QUICK the plan may be one sentence.
- Review runs on a fresh context. The agent that wrote the code does not review it.
- A failing gate stops the line. Route to `debugger`; do not patch around it.

If the request is a question rather than a build request, answer it directly
instead of routing.
