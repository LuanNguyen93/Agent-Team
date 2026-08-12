# Attribution

This plugin is a **distillation**, not a redistribution. No file from the
projects below is copied here. What was taken is the core idea each one gets
right, re-expressed and reconciled into a single non-overlapping set — because
installing all nine together produces overlapping triggers, contradictory
instructions, and a large context cost.

Each source is credited for the concept this plugin owes it. Consult the
originals; several are considerably deeper in their own domain than the
condensed version here.

| Source | Concept taken | Where it lives here |
|---|---|---|
| [BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD) | Role sequence with artifact handoff; scale-adaptive planning depth | `workflow-router`, `artifact-templates`, the agent roster |
| [superpowers](https://github.com/obra/superpowers) (Jesse Vincent, MIT) | Socratic brainstorming; TDD requiring an observed failure; four-phase debugging; fresh-eyes review | `brainstorm-grilling`, `tdd-discipline`, `debug-rca`, `reviewer` |
| [mattpocock/skills](https://github.com/mattpocock/skills) (Matt Pocock) | Grilling before code; domain modelling and shared vocabulary; review along both standards and spec-compliance axes | `brainstorm-grilling`, `reviewer` |
| [spartan-ai-toolkit](https://github.com/spartan-stratos/spartan-ai-toolkit) | Sequential blocking quality gates; atomic commits; stack profiles | `quality-gates`, `hooks/`, `stacks/` |
| [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | Structured design intelligence and a pre-delivery checklist | `design-intelligence` |
| [frontend-design](https://github.com/anthropics/skills) (Anthropic) | Aesthetic standards that avoid the generated-UI look | `design-intelligence` |
| [react-best-practices](https://github.com/vercel-labs/agent-skills) (Vercel) | React/Next rules ordered by real impact | `react-performance` |
| [webapp-testing](https://github.com/anthropics/skills) (Anthropic) | Driving the real app to verify, rather than trusting unit tests | `browser-verify` |
| [excalidraw-diagram-skill](https://github.com/coleam00/excalidraw-diagram-skill) | Editable diagrams with a self-review pass for layout defects | `diagram-excalidraw` |

Harness behaviour was verified against the
[Claude Code documentation](https://code.claude.com/docs/en/features-overview);
findings are recorded in `HARNESS-NOTES.md`.

Licences remain with their respective authors. If you maintain one of these
projects and want the attribution changed or removed, please open an issue.
