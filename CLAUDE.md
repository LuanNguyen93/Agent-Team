# Agent Team — repo conventions

This repository *is* a Claude Code plugin. Everything here is configuration and
prose that another Claude reads at runtime, so the writing is the product.

## Layout rules that are not negotiable

- Only `plugin.json` lives in `plugins/agent-team/.claude-plugin/`.
  `agents/`, `skills/`, `commands/`, `hooks/`, `scripts/`, `stacks/` sit at the
  plugin root.
- `marketplace.json` lives in `.claude-plugin/` at the **repo** root.
- Agent and skill `name` values must be unique across the tree and cannot
  contain `:`.

## Before committing

From the repo root:

```bash
claude plugin validate ./plugins/agent-team
```

Also check that no agent frontmatter uses `hooks`, `mcpServers`, or
`permissionMode` — plugins ignore all three silently.

If the change touches `plugins/agent-team/tui/**`, `.github/workflows/tui-pr.yml`
fires and enforces more than a plan's gate list usually names. A green
`cargo build` and `cargo test` is *not* evidence that CI will pass — commit
`bfdb25d` shipped three CI failures with every agent honestly reporting green.
Run the real list, from these directories:

```bash
# from plugins/agent-team/tui/rust
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
cargo build --release          # needed by the --build-info cross-check below

# from plugins/agent-team/tui
bash tests/check-binaries.test.sh
bash tests/src-hash-consistency.test.sh
./check-binaries.sh            # exit 2 = nothing released yet, fine;
                               # exit 1 or a SKIPPED line = failure
```

CI then checks the built binary's `--build-info` `srcHash` against its
`bin/MANIFEST` line, and runs the whole matrix on Windows, macOS x86 and arm,
and Linux — so a local pass on one OS is a partial answer, not a complete one.

## Writing rules

- **English throughout**, including artifact templates.
- Skills carry knowledge; agents carry a role. Never duplicate doctrine into an
  agent body — reference the skill instead.
- Every agent needs an explicit "what you do not do" section. Role boundaries
  are what keep the handoff chain intact.
- Every new agent must load its skills via the Skill tool in the body, in
  addition to declaring `skills:` in frontmatter. See `docs/HARNESS-NOTES.md` §2.
- Keep `description` + `when_to_use` at most 1,536 characters combined — the
  skill listing truncates beyond that (see `docs/HARNESS-NOTES.md` §6), so 1,536
  survives intact and character 1,537 is silently lost.
- Skills use progressive disclosure: a short `SKILL.md`, detail in `references/`.

## Bash scripts

Hook scripts run on Windows (Git Bash), macOS, and Linux. Keep them POSIX-ish,
avoid tools that may be absent (`jq` in particular), and always handle the case
where the project has no gate command at all — absent must report as absent, not
as a pass.
