# Transcript parity fixture

Per ADR-0007(a): committed input, generated `expected.json`. Both
`measure-tokens.js` and the Rust TUI's `analytics::parse` are tested against
this fixture, and `measure-tokens.js` is authoritative — see the ADR for what
happens when they disagree.

## Regenerating `expected.json`

Never hand-edit `expected.json`. It is a normalised capture, not a pure one:
the regen script deletes the machine-specific `project` field and adds
`fixtureVersion`/`generator`, and nothing else - all three are excluded from
parity comparison. After any change to `measure-tokens.js`, its cost logic,
or `../../shared/rates.json`, regenerate it:

```
bash plugins/agent-team/tui/tests/regen-transcript-expected.sh
```

Then re-run the Rust parity test; a real cost change should turn it red until
`analytics::parse` is updated to match.

## Cases this fixture covers (ADR-0007's list)

| Case | Where |
|---|---|
| Zero subagent calls | session `bbbbbbbb-2222` has no `subagents/` dir |
| Attributed subagent call | `aaaaaaaa-1111/subagents/implementer-01.jsonl`, `attributionAgent: "agent-team:implementer"` |
| Unattributed subagent call | `aaaaaaaa-1111/subagents/orphan-02.jsonl`, no `attributionAgent` -> `(unattributed subagent)` |
| Opus tier | `aaaaaaaa-1111.jsonl` main call, `bbbbbbbb-2222.jsonl` first record |
| Sonnet tier | `implementer-01.jsonl` |
| Haiku tier | `orphan-02.jsonl` |
| Unrecognised model -> bills at opus | `cccccccc-3333.jsonl` first record, model `claude-nonexistent-9` |
| Malformed line | `cccccccc-3333.jsonl` line 2 of 3, invalid JSON. Line 3 is a valid billable record placed *after* it - a parser that aborts the whole file on the first bad line instead of skipping it will produce different totals and fail parity. Exactly one line in this file must fail `JSON.parse`; that count is asserted in `scripts/tests/measure-tokens.test.sh`, not stored in `expected.json` - it is Rust-only and out of the parity contract. |
| Blank line | `aaaaaaaa-1111.jsonl` second line |
| Missing `model` key -> `(unknown model)` | `bbbbbbbb-2222.jsonl` second record |
| Record with no `usage` at all -> skipped, not zero-costed | `aaaaaaaa-1111.jsonl` third record |

## Ordering

The fixture is constructed so no two rows in `byAgentModel` or any session's
`byAgent` tie on both cost and calls — see ADR-0007's "Row ordering" section.
Do not add a record without checking this still holds; a tie makes the parity
assertion's row ordering non-deterministic between the two implementations.
