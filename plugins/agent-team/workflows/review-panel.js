export const meta = {
  name: 'review-panel',
  description: 'Review a change through several independent lenses, then adversarially verify each finding before reporting it',
  whenToUse: 'Before merging a branch or shipping a feature, when a single sequential reviewer would anchor on one class of issue',
  phases: [
    { title: 'Scope', detail: 'establish what changed' },
    { title: 'Review', detail: 'one agent per lens, in parallel' },
    { title: 'Verify', detail: 'independent skeptics try to refute each finding' },
    { title: 'Report', detail: 'rank and deduplicate what survived' },
  ],
}

// A single reviewer gravitates to one class of issue and stops. Independent
// lenses cover more, and adversarial verification stops plausible-but-wrong
// findings from reaching the user - which is what trains people to ignore
// reviews.

const target = typeof args === 'string' && args.trim() ? args.trim() : 'the current diff against the default branch'

const FINDINGS = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'summary', 'failure'],
        properties: {
          file: { type: 'string' },
          line: { type: 'number' },
          summary: { type: 'string', description: 'One sentence stating the defect' },
          failure: { type: 'string', description: 'Concrete inputs or state, and the wrong result they produce' },
          severity: { type: 'string', enum: ['blocking', 'should-fix', 'consider'] },
        },
      },
    },
  },
}

const VERDICT = {
  type: 'object',
  required: ['refuted', 'reason'],
  properties: {
    refuted: { type: 'boolean', description: 'True if the finding does not hold up' },
    reason: { type: 'string' },
  },
}

phase('Scope')
const scope = await agent(
  `Establish the scope of this review: ${target}.
Run git to list the changed files and read the diff. Report the file list, the
stated intent of the change, and any spec, story, or PR description you can find
that says what it was supposed to do.
Do not review anything yet.`,
  { label: 'scope', phase: 'Scope' },
)

const LENSES = [
  {
    key: 'correctness',
    brief: `Logic errors, off-by-one, null and undefined handling, incorrect error
handling, resources not released, race conditions, and state that can go stale.`,
  },
  {
    key: 'security',
    brief: `Unvalidated input, authorisation enforced in the UI but not on the server,
secrets in code or logs, injection, and anything that trusts the client.`,
  },
  {
    key: 'tests',
    brief: `Do the tests assert real behaviour, or assert the implementation back to
itself? Would they catch a regression? Are the stated edge cases covered?
Would the suite still pass if the function body were replaced with a constant?`,
  },
  {
    key: 'spec',
    brief: `Compliance with what was actually asked. Go criterion by criterion. Look
for correct code that solves a different problem, and criteria silently dropped.`,
  },
]

// Pipeline, not a barrier: a lens verifies its findings as soon as it finishes,
// rather than waiting for the slowest lens.
phase('Review')
const reviewed = await pipeline(
  LENSES,
  lens =>
    agent(
      `Review this change through one lens only: ${lens.key}.

${lens.brief}

Scope of the change:
${scope}

Report a finding only when you can describe the concrete failure: the input or
state, and the wrong result. "This could be a problem" without a mechanism is
noise. Verify before asserting - read the called function rather than assuming
what it does. Report nothing if the change is sound in your lens.`,
      { label: `review:${lens.key}`, phase: 'Review', schema: FINDINGS },
    ),
  (review, lens) =>
    parallel(
      (review?.findings ?? []).map(f => () =>
        agent(
          `Try to REFUTE this review finding. Your job is to show it is wrong.

File: ${f.file}${f.line ? `:${f.line}` : ''}
Claim: ${f.summary}
Alleged failure: ${f.failure}

Read the actual code and the code it calls. Check whether the failure can really
occur: is the input reachable, is it already guarded upstream, does the called
function already handle it?

Default to refuted=true when you cannot demonstrate the failure is real. A
confidently wrong finding costs more than a missed one, because someone acts on it.`,
          { label: `verify:${lens.key}:${f.file}`, phase: 'Verify', schema: VERDICT },
        ).then(v => ({ ...f, lens: lens.key, verdict: v })),
      ),
    ),
)

const all = reviewed.flat().filter(Boolean)
const survived = all.filter(f => f.verdict && !f.verdict.refuted)
log(`${all.length} findings raised, ${survived.length} survived refutation`)

if (survived.length === 0) {
  return {
    target,
    findings: [],
    summary: 'No finding survived adversarial verification. Every lens either found nothing or its findings were refuted.',
    raised: all.length,
  }
}

phase('Report')
const report = await agent(
  `Merge these verified review findings into one ranked report.

${JSON.stringify(survived, null, 2)}

Deduplicate findings that different lenses raised about the same defect. Rank
blocking first. For each, give the file, the concrete failure, and a suggested
direction - not a patch. Do not add findings of your own, and do not pad the
list to look thorough.`,
  { label: 'synthesise', phase: 'Report' },
)

return { target, raised: all.length, confirmed: survived.length, report }
