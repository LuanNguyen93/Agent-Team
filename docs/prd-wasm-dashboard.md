# PRD: WASM Dashboard for Agent-Team

## Context
`docs/brief-wasm-dashboard.md` (2026-08-15) records the user's decision: build
a second, browser-based frontend for agent-team, alongside the existing
terminal TUI (`plugins/agent-team/tui/rust`), that (1) visualizes both the
structure graph and the cost/timeline analytics, and (2) gives live control
(start/stop/kill) over running Claude Code agent sessions via a new local
server. This PRD turns those six decisions into requirements an architect can
design against.

## Users and needs
| Role | Needs | Why |
|---|---|---|
| Agent-team maintainer/user (local, single-user) | See structure (agents/skills/commands/routing) and cost/timeline data as a rendered graphical view, not scrolled terminal text | [inferred] brief: TUI is "not easy enough to look at" |
| Same user, mid-run | Start a new agent-team run, stop or kill a running one, from the browser | [observed] brief decision 1: live process control is now in scope |
| Same user | Trust that kill/stop cannot touch a process the dashboard didn't launch | [assumed] process control over arbitrary system processes was never requested and would be a safety regression |

## Scope
### In scope
- A local server process (new) that: (a) serves structure data (reusing the
  existing scanner logic behind the structure TUI) and analytics data
  (reusing `measure-tokens.js` logic and/or the Rust `analytics` module) as
  JSON over HTTP, and (b) exposes start/stop/kill actions over agent-team
  sessions it itself launched or can identify as agent-team's own.
- A browser-based WASM/web app (new, at `plugins/agent-team/web/` or
  sibling — never inside `.claude-plugin/`) that fetches from that server and
  renders: the structure graph, the cost/timeline analytics, and session
  controls.
- A launch command that starts the local server and opens a browser tab to
  it, scoped to this repo's own agent-team install.
- Point-in-time refresh (manual or polled) of structure and analytics data.
  See FR-8 for the streaming question this PRD resolves.

### Out of scope
- Replacing or deprecating the terminal TUI — it continues unchanged.
- Multi-user or hosted/remote deployment — single local user, single local
  machine.
- Managing or visualizing more than one repo's agent-team install from one
  dashboard instance (default assumption per brief item 6 — see Open
  Questions for confirmation).
- Editing agent/skill/command frontmatter or `.agent-team.json` from the web
  app — that capability exists in the terminal structure TUI
  (`docs/prd-analytics-tui.md` epics E3/E4) and is not being duplicated here
  unless the user asks.
- Starting or killing any OS process that is not an agent-team-spawned
  Claude Code session (no general process manager).
- Authentication/authorization — single local user on localhost is assumed
  trusted; see Risks.

## Functional requirements

**FR-1 - Local data server**
- Description: A new local server process serves structure and analytics
  data as JSON over HTTP to the browser app, reusing the scanner logic
  behind the existing structure TUI and `measure-tokens.js`/Rust
  `analytics` logic, rather than reimplementing either.
- Acceptance criteria:
  - [ ] Given the server is started, when a client requests the structure
    endpoint, then it returns JSON describing agents/skills/commands and
    their routing relationships, matching what the structure TUI scanner
    would report for the same repo state.
  - [ ] Given the server is started, when a client requests the analytics
    endpoint for a project, then it returns JSON matching
    `measure-tokens.js --json`'s per-agent/model cost and timeline data for
    the same transcripts, within the tolerance an ADR sets (see Risks —
    same open item E7-2 carried forward).
  - [ ] Edge: zero agents/skills/commands in the repo — structure endpoint
    returns an empty-but-valid JSON payload (`{"agents":[],...}`), not an
    error.
  - [ ] Edge: one session transcript — analytics endpoint returns exactly
    one session's data, not an empty array.
  - [ ] Edge: many sessions (50+) and a 50,000-line transcript — endpoint
    responds within a 5s budget (matching E7-2's parse budget).
  - [ ] Failure: transcript directory unreadable or malformed `.jsonl`
    lines present — endpoint returns a 200 with the parseable subset plus a
    `malformedLines` count, or a distinct error status if nothing at all is
    readable; it never silently returns an empty success payload for a
    real failure.

**FR-2 - Structure graph view**
- Description: The web app renders agents/skills/commands and their
  routing relationships as a graphical view (not text list) in the browser.
- Acceptance criteria:
  - [ ] Given structure data with N agents and their skill/command
    references, when the view loads, then each agent, skill, and command
    appears as a distinct visual node and each reference appears as a
    distinct visual edge, and clicking a node shows its full name/type/path.
  - [ ] Edge: zero entities — view shows an explicit "no structure found"
    empty state, not a blank canvas.
  - [ ] Edge: one agent with no skills/commands — renders as a single
    isolated node, not an error.
  - [ ] Edge: 100+ nodes and 200+ edges — view remains legible (supports
    pan/zoom or equivalent) and interactive (click response) rather than
    becoming an unreadable tangle or freezing the tab.
  - [ ] Failure: structure endpoint returns an error or is unreachable —
    view shows an explicit error state naming the failure, not a blank or
    stale-looking graph.

**FR-3 - Cost/timeline analytics view**
- Description: The web app renders the token-cost/timeline analytics
  (main-vs-subagent split, per-agent/model breakdown, agent-flow timeline)
  as a graphical view, matching the data the terminal analytics screen
  shows (`docs/prd-analytics-tui.md` E7-2).
- Acceptance criteria:
  - [ ] Given a completed session's analytics data, when the view loads,
    then the main-vs-subagent cost split renders first, with the
    per-agent/model breakdown and a visual timeline of agent spans below it.
  - [ ] Given the same session's data on both frontends, when compared,
    then the web view's cost split and breakdown numbers match the
    terminal TUI's numbers for that session (same underlying data, same
    server logic).
  - [ ] Edge: zero sessions — explicit "no sessions found" empty state.
  - [ ] Edge: one session, main-only, no subagent calls — split renders as
    100%/0%, not blank or omitted.
  - [ ] Edge: 50 sessions, 30 distinct agent/model pairs — breakdown list
    scrolls without silently truncating rows.
  - [ ] Failure: analytics endpoint reports malformed lines or an
    unreadable transcript — view surfaces the same distinction the
    endpoint returns (malformed-lines count vs. hard error), not a blank
    chart.

**FR-4 - Session start**
- Description: A user can start a new agent-team session from the web app.
- Acceptance criteria:
  - [ ] Given the dashboard is open, when the user triggers "start" with a
    valid target (e.g. a command/prompt the server accepts), then the
    server launches the process and the dashboard shows it transition to a
    "running" state within one refresh/poll cycle.
  - [ ] Edge: start requested while at a to-be-defined concurrent-session
    limit — request is rejected with a clear reason, not silently dropped
    or silently queued. [OPEN: architect/PRD-review to confirm whether a
    limit exists; see Open Questions.]
  - [ ] Failure: the launch command itself fails (bad path, spawn error) —
    dashboard shows the specific failure reason, and no phantom "running"
    session is displayed.

**FR-5 - Session stop (graceful)**
- Description: A user can gracefully stop a running agent-team session the
  dashboard itself is tracking as agent-team-spawned.
- Acceptance criteria:
  - [ ] Given a running session started by or visible to this server, when
    the user triggers "stop," then the server sends a graceful-stop signal
    and the dashboard reflects "stopping" then "stopped" once the process
    exits.
  - [ ] Edge: stop requested on a session that already exited between the
    dashboard's last refresh and the click — server returns a clear
    "already stopped" result, not an error implying the action failed.
  - [ ] Failure: the process does not exit within a defined grace period —
    dashboard surfaces this (e.g. "not responding to stop") rather than
    silently reporting it as stopped.

**FR-6 - Session kill (forced), with confirmation and scoping**
- Description: A user can forcibly kill a running agent-team session, with
  an explicit confirmation step, and the server will only ever kill
  processes it identifies as agent-team-spawned — never an arbitrary OS
  process.
- Acceptance criteria:
  - [ ] Given a running session, when the user triggers "kill," then the
    UI requires an explicit confirmation step (e.g. a second click or typed
    confirmation) before the kill request is sent — a single click never
    kills a process.
  - [ ] Given a confirmed kill request, when the server receives it, then
    it verifies the target PID/handle is one it itself launched or
    otherwise positively identifies as an agent-team session before
    sending the kill signal, and refuses (with a named reason) any request
    targeting a PID it cannot positively identify.
  - [ ] Given a successful kill, when the process exits, then the
    dashboard reflects "killed"/"stopped" and the action is recorded (at
    minimum in server logs) with timestamp and target identity.
  - [ ] Edge: kill requested on a PID that has already been reassigned by
    the OS to an unrelated process since the session was launched — server
    detects the identity mismatch (e.g. via a stored process handle/start
    time, not PID alone) and refuses rather than killing the wrong process.
  - [ ] Failure: kill signal sent but process does not exit — dashboard
    surfaces this distinctly from a successful kill, does not claim
    success it cannot confirm.

**FR-7 - Launch command**
- Description: A single local command starts the data server and opens a
  browser tab to the dashboard, scoped to this repo's own agent-team
  install.
- Acceptance criteria:
  - [ ] Given the command is run from the repo root, when it executes,
    then the local server starts, binds to a local-only address (not
    exposed beyond localhost), and a browser tab opens to the dashboard
    showing this repo's data.
  - [ ] Edge: the command is run a second time while a server instance is
    already running — it either reuses the existing instance and opens a
    new tab, or reports "already running" — it never silently binds a
    conflicting second instance without telling the user.
  - [ ] Failure: the local port is unavailable — command reports the
    specific bind failure, not a generic crash.

**FR-8 - Data refresh model**
- Description: Per brief "Out of scope" note, the default is point-in-time
  refresh (manual or polled), not push/streaming — this PRD confirms that
  default for both structure and analytics views; session status (FR-4/5/6)
  needs a shorter poll interval than structure/analytics since it drives
  the confirm-before-kill safety property in FR-6.
- Acceptance criteria:
  - [ ] Given the dashboard is open, when the user triggers a manual
    refresh (or a poll interval elapses), then structure and analytics
    views re-fetch and update from the server.
  - [ ] Given a session's status changes (e.g. it exits on its own), when
    the next session-status poll occurs, then the dashboard's shown state
    updates within that poll interval — a fixed, documented interval
    (e.g. 2s), not an unbounded one.
  - [ ] Failure: a refresh/poll request fails (server unreachable) — the
    dashboard shows a stale-data indicator rather than silently keeping
    old data with no signal it's stale.

## Non-functional requirements
| Type | Target | How measured |
|---|---|---|
| Performance | Structure/analytics view first paint under 2s with 100 structure nodes / 50 sessions on localhost | manual timing or a browser perf trace against the local server |
| Performance | Session-status poll interval fixed and documented, default 2s | code/config inspection |
| Safety | Kill/stop actions only ever target agent-team-spawned processes; kill requires explicit confirmation | FR-6 acceptance criteria, code review of PID/handle identity check |
| Security | Server binds to localhost only, not `0.0.0.0` | code inspection / `netstat` check when running |

## Data
- **Structure data**: agents, skills, commands, and their routing edges.
  Source of truth: the filesystem under `plugins/agent-team/` (frontmatter +
  file layout), read fresh by the server's scanner on each request — no
  separate stored copy, matching the existing structure TUI's approach.
- **Analytics data**: per-session token/cost/timeline data. Source of truth:
  Claude Code session transcript files (`.jsonl`) on disk, read fresh per
  request via the reused `measure-tokens.js`/Rust analytics logic — no
  database, no retention policy needed since transcripts are the record.
- **Session control state**: which processes the server has launched (PID,
  start time/handle, command). Source of truth: in-memory in the server
  process for its own lifetime — [OPEN: does this need to survive a server
  restart, i.e. can the dashboard discover and re-adopt sessions it did not
  itself launch? Brief does not say; see Open Questions.]

## Epics and stories
| Epic | Story | Related FR | Priority |
|---|---|---|---|
| E8 Data server | E8-1 local server skeleton + structure endpoint | FR-1, FR-7 | high |
| E8 Data server | E8-2 analytics endpoint | FR-1, FR-3 | high |
| E9 Session control backend | E9-1 session start/list | FR-4 | high |
| E9 Session control backend | E9-2 session stop (graceful) | FR-5 | high |
| E9 Session control backend | E9-3 session kill (scoped, confirmed) | FR-6 | high |
| E10 Web app | E10-1 web app shell + launch command | FR-7 | high |
| E10 Web app | E10-2 structure graph view | FR-2 | high |
| E10 Web app | E10-3 analytics view | FR-3 | high |
| E10 Web app | E10-4 session control UI (start/stop/kill + confirm) | FR-4, FR-5, FR-6 | high |
| E10 Web app | E10-5 refresh/polling model | FR-8 | medium |

## Risks
| Risk | Impact | Mitigation |
|---|---|---|
| Kill/stop targets the wrong process (PID reuse) | Could kill an unrelated OS process — safety-critical | FR-6 requires positive identity check beyond bare PID; architect to design the handle/start-time mechanism |
| New JS/WASM toolchain has no precedent in this repo | Slows every future contributor touching `web/`; may conflict with repo's zero-dependency-tooling convention | Flag to architect as an explicit ADR decision, not a PM/story-level choice |
| `analytics`/structure code lives in `plugins/agent-team/tui/**`, which triggers the full CI gate matrix on touch | Any wasm-bindgen extraction that touches that path pulls in `.github/workflows/tui-pr.yml`'s full Windows/macOS/Linux matrix, per `CLAUDE.md` | Architect decides whether the reused Rust code is extracted to a new crate outside `tui/` or shared in place; either way this is a story-level dependency risk, not solved here |
| The E7-2 story (`docs/stories/e7-2-tui-analytics-screen.md`) already carries an open ADR item (fixture parity, rate-table single-sourcing) that this PRD's FR-1/FR-3 now also depend on | Two consumers (TUI, web server) drifting from `measure-tokens.js` independently | Same ADR must resolve both; do not let this PRD spawn a second, conflicting parity mechanism |
| No auth on the local server | Anything else on the same machine that can reach localhost could also trigger start/stop/kill | NFR: bind to localhost only; document as accepted risk for single-user local tool, escalate if that assumption is wrong |

## Open questions
- [OPEN] FR-4 edge: is there a concurrent-session limit for "start," and if
  so what is it? Not stated in the brief.
- [OPEN] Data: must session-control state (which PIDs the server launched)
  survive a server restart, or is losing track of previously-launched
  sessions on restart acceptable? Affects whether FR-5/FR-6 need persistent
  state.
- [OPEN] Brief item 6 (multi-project scope): this PRD assumes single-repo
  scope per the brief's stated default. Confirm with the user before
  architecture proceeds, since "manage running sessions" could plausibly
  span sessions launched from other agent-team installs on the same
  machine.
- [OPEN] Brief item 5 (runtime target): this PRD assumes "local command
  starts server + opens browser tab" (FR-7) per the brief's stated default.
  Confirm before architecture proceeds.
- [OPEN] Exact toolchain for the WASM/web build (wasm-pack, bundler or
  bundler-free) is explicitly left to `architect` per the brief's
  constraints — not decided here.

---

Assumptions: [assumed] single local user, localhost-only, no auth needed;
[assumed] "agent-team-spawned" sessions are identifiable by the server
(it either launched them itself via FR-4, or can positively recognize them
by process metadata) — the exact mechanism is an architecture decision, not
resolved here; [assumed] point-in-time refresh (not push/streaming) is
sufficient per brief's stated default, confirmed as FR-8.

Not covered: exact WASM toolchain, exact process-identity mechanism for
FR-6, exact wire format/schema for the JSON endpoints, exact UI layout —
all deferred to `architect`/`ux-designer`.

Open: the five items listed under "Open questions" above need answers
before or during architecture; the two brief items (5, 6) most need the
user's explicit confirmation since this PRD only assumed defaults for them.
