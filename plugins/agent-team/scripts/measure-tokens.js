#!/usr/bin/env node
'use strict';
//
// Report what a session actually cost, split between the main context and the
// subagents it delegated to.
//
// The question this exists to answer is not "how many tokens" - the CLI already
// shows that - but "where did they go". Two sessions of the same token count
// cost wildly different amounts depending on whether the work happened in one
// enormous context that gets re-read on every turn, or in subagents whose
// intermediate material dies with them. This prints that split.
//
// Zero dependencies and plain CommonJS: this repo has no package.json, no
// build step, and no install hook, so anything beyond the Node standard
// library would have nowhere to be installed from.
//
// Usage:
//   node measure-tokens.js                     # this project, human-readable
//   node measure-tokens.js --project <dir>     # a specific transcript dir
//   node measure-tokens.js --json              # machine-readable
//   node measure-tokens.js --fillers           # what filled the biggest context

const fs = require('fs');
const path = require('path');
const os = require('os');

// List price per million tokens, plus the cache write/read multipliers,
// loaded from the one file both this script and the Rust TUI read - see
// ADR-0007. `require` parses JSON natively, so this stays zero-dependency.
// A missing or malformed rates.json is a hard failure, not a silent
// fallback table, per the ADR.
const rates = require(path.join(__dirname, '..', 'tui', 'shared', 'rates.json'));
const RATES = rates.tiers;

// An unrecognised model bills as the most expensive tier. Guessing cheap would
// make a new model silently disappear from the report it exists to appear in.
function tierOf(model) {
  const m = String(model || '').toLowerCase();
  if (m.includes('haiku')) return 'haiku';
  if (m.includes('sonnet')) return 'sonnet';
  return 'opus';
}

function costOf(usage, model) {
  const r = RATES[tierOf(model)];
  return (
    (usage.input_tokens || 0) * r.input +
    (usage.output_tokens || 0) * r.output +
    (usage.cache_creation_input_tokens || 0) * r.input * rates.cacheWriteMultiplier +
    (usage.cache_read_input_tokens || 0) * r.input * rates.cacheReadMultiplier
  ) / 1e6;
}

// What one request had to carry. Cache reads are the bulk of it on any session
// that has run for a while, which is the whole point: a context is paid for
// again on every turn that follows it.
function contextOf(usage) {
  return (usage.input_tokens || 0) +
    (usage.cache_creation_input_tokens || 0) +
    (usage.cache_read_input_tokens || 0);
}

// Claude Code stores a project's transcripts under a directory named after the
// project path with every non-alphanumeric byte replaced by a dash.
function projectDirFor(cwd) {
  return path.join(os.homedir(), '.claude', 'projects', cwd.replace(/[^a-zA-Z0-9]/g, '-'));
}

function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full));
    else if (entry.name.endsWith('.jsonl')) out.push(full);
  }
  return out;
}

// A transcript under a `subagents/` directory belongs to a delegated context.
// Everything else is the main one.
function isSubagent(relPath) {
  return relPath.split(path.sep).includes('subagents');
}

// The session a transcript belongs to is the first path segment, with the
// `.jsonl` suffix dropped for a top-level main transcript.
function sessionIdFor(relPath) {
  return relPath.split(path.sep)[0].replace(/\.jsonl$/, '');
}

function emptyBucket() {
  return { calls: 0, cost: 0, output: 0, cacheRead: 0, cacheWrite: 0, contexts: [] };
}

// A row of the agent x model table. `key` is internal bookkeeping only, never
// serialised - it exists so the same agent+model pair accumulates into one row
// instead of one per call.
function emptyRow(agent, model) {
  return { agent, model, calls: 0, cacheRead: 0, cacheWrite: 0, output: 0, cost: 0 };
}

function rowKey(agent, model) {
  return agent + ' ' + model;
}

// Adds one call's usage to its agent+model row in `map`, creating the row on
// first sight. Shared by the global table and every per-session table so both
// are derived from the same per-record numbers rather than recomputed.
function addToRow(map, agent, model, usage, cost) {
  const key = rowKey(agent, model);
  if (!map.has(key)) map.set(key, emptyRow(agent, model));
  const row = map.get(key);
  row.calls += 1;
  row.cacheRead += usage.cache_read_input_tokens || 0;
  row.cacheWrite += usage.cache_creation_input_tokens || 0;
  row.output += usage.output_tokens || 0;
  row.cost += cost;
}

// Deterministic order: most expensive first, ties broken by call volume, so
// the table reads the same way on every run and is safe to assert against.
function sortedRows(map) {
  return [...map.values()].sort((a, b) => b.cost - a.cost || b.calls - a.calls);
}

function foldRows(rows) {
  return rows.reduce((t, r) => ({
    calls: t.calls + r.calls,
    cacheRead: t.cacheRead + r.cacheRead,
    cacheWrite: t.cacheWrite + r.cacheWrite,
    output: t.output + r.output,
    cost: t.cost + r.cost,
  }), { calls: 0, cacheRead: 0, cacheWrite: 0, output: 0, cost: 0 });
}

function collect(projectDir) {
  const sessions = new Map();
  const byAgentModelMap = new Map();

  for (const file of walk(projectDir)) {
    const rel = path.relative(projectDir, file);
    const id = sessionIdFor(rel);
    const which = isSubagent(rel) ? 'sub' : 'main';

    if (!sessions.has(id)) {
      sessions.set(id, { id, main: emptyBucket(), sub: emptyBucket(), byAgentMap: new Map() });
    }
    const session = sessions.get(id);
    const bucket = session[which];

    for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
      if (!line.trim()) continue;
      let record;
      // A transcript is appended to live. A half-written final line is normal,
      // not a reason to report nothing.
      try { record = JSON.parse(line); } catch (e) { continue; }

      const usage = record && record.message && record.message.usage;
      if (!usage) continue;

      // Every real record carries a model, but a JSON key can always be
      // missing - normalise here rather than let `undefined` reach the
      // tables, where it crashes printAgentRows and vanishes from --json
      // (JSON.stringify drops undefined values).
      const model = record.message.model || '(unknown model)';
      const cost = costOf(usage, model);
      bucket.calls += 1;
      bucket.cost += cost;
      bucket.output += usage.output_tokens || 0;
      bucket.cacheRead += usage.cache_read_input_tokens || 0;
      bucket.cacheWrite += usage.cache_creation_input_tokens || 0;
      bucket.contexts.push(contextOf(usage));

      // Most subagent records carry attributionAgent, but not all of them do -
      // a record missing it is still delegated spend and must fall back on
      // `which`, not on a constant. Falling back to '(main context)' here
      // billed real subagent spend to the main context: two cuts of the same
      // data (byAgentModel's (main context) rows vs sessions[].main.cost)
      // disagreed by exactly the unattributed subagent total.
      const agentKey = record.attributionAgent ||
        (which === 'sub' ? '(unattributed subagent)' : '(main context)');
      addToRow(byAgentModelMap, agentKey, model, usage, cost);
      addToRow(session.byAgentMap, agentKey, model, usage, cost);
    }
  }

  const byAgentModel = sortedRows(byAgentModelMap);
  const cumulative = foldRows(byAgentModel);

  const sessionList = [...sessions.values()]
    .map((session) => {
      session.byAgent = sortedRows(session.byAgentMap);
      delete session.byAgentMap;
      return finalise(session);
    })
    .filter((s) => s.main.calls > 0 || s.sub.calls > 0)
    .sort((a, b) => b.totalCost - a.totalCost);

  return { sessions: sessionList, byAgentModel, cumulative };
}

function finalise(session) {
  for (const key of ['main', 'sub']) {
    const b = session[key];
    const n = b.contexts.length;
    b.avgContext = n ? b.contexts.reduce((a, c) => a + c, 0) / n : 0;
    b.maxContext = n ? Math.max(...b.contexts) : 0;
    delete b.contexts;
  }
  session.totalCost = session.main.cost + session.sub.cost;
  session.subShare = session.totalCost ? session.sub.cost / session.totalCost : 0;
  return session;
}

function readRecords(file) {
  const records = [];
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    try { records.push(JSON.parse(line)); } catch (e) { /* see above */ }
  }
  return records;
}

// A control character, not a space, because agent labels like "(main context)"
// contain spaces themselves and this key is split back apart below.
const ROW_KEY_SEP = String.fromCharCode(1);
function rowsKey(agent, tool) {
  return agent + ROW_KEY_SEP + tool;
}

// Which tool results filled the context, and which agent's turn spent them.
// Only worth asking of one session, so it is opt-in rather than part of every
// report - but that one session includes whatever it delegated, because a
// subagent's oversized tool result is still context that session paid for.
function fillers(projectDir, sessionId) {
  const file = path.join(projectDir, sessionId + '.jsonl');
  if (!fs.existsSync(file)) return [];

  // The main transcript's own records have no attributionAgent, so it is
  // fixed here rather than read per-record. Each subagent file supplies its
  // own via the field, same as collect() does.
  const sources = [{ agent: '(main context)', file }];
  const subDir = path.join(projectDir, sessionId, 'subagents');
  if (fs.existsSync(subDir)) {
    for (const f of walk(subDir)) sources.push({ agent: null, file: f });
  }

  const bytes = new Map();
  const calls = new Map();
  const add = (agent, tool, n) => {
    if (!n) return;
    const key = rowsKey(agent, tool);
    bytes.set(key, (bytes.get(key) || 0) + n);
    calls.set(key, (calls.get(key) || 0) + 1);
  };

  for (const source of sources) {
    const records = readRecords(source.file);

    // A tool_result carries the id of the call it answers, not its name. Ids
    // are scoped to the transcript that issued them, so this map is rebuilt
    // per source rather than shared across the whole session.
    const nameById = new Map();
    for (const r of records) {
      const content = r.message && r.message.content;
      if (!Array.isArray(content)) continue;
      for (const block of content) {
        if (block.type === 'tool_use') nameById.set(block.id, block.name);
      }
    }

    for (const r of records) {
      const agent = source.agent || r.attributionAgent || '(unknown agent)';

      // A tool result is recorded twice: a short reference inside
      // message.content, and the real payload at the top level in
      // `toolUseResult`. Reading only the reference undercounts a 40k result
      // as 17 bytes - which is exactly the wrong answer for the one function
      // meant to find what filled the context.
      if (r.toolUseResult !== undefined) {
        let id = null;
        const c = r.message && r.message.content;
        if (Array.isArray(c)) for (const b of c) if (b.type === 'tool_result') id = b.tool_use_id;
        const payload = typeof r.toolUseResult === 'string'
          ? r.toolUseResult
          : JSON.stringify(r.toolUseResult || '');
        add(agent, nameById.get(id) || '(unknown tool)', payload.length);
      }

      // Attachments ride alongside the message rather than inside it.
      if (r.attachment) add(agent, '(attachments)', JSON.stringify(r.attachment).length);

      const content = r.message && r.message.content;
      if (typeof content === 'string') {
        if (r.message.role === 'user') add(agent, '(prompts and replies)', content.length);
        continue;
      }
      if (!Array.isArray(content)) continue;
      for (const block of content) {
        if (block.type === 'text') add(agent, '(prompts and replies)', block.text.length);
        else if (block.type === 'thinking') add(agent, '(thinking)', (block.thinking || '').length);
        // What we SEND to a tool also stays in the context - a long Write payload
        // or a heredoc script is charged for the rest of the session too.
        else if (block.type === 'tool_use') add(agent, '(tool inputs)', JSON.stringify(block.input || '').length);
      }
    }
  }

  const total = [...bytes.values()].reduce((a, b) => a + b, 0) || 1;
  return [...bytes.entries()]
    .map(([key, b]) => {
      const sep = key.indexOf(ROW_KEY_SEP);
      return {
        agent: key.slice(0, sep),
        tool: key.slice(sep + 1),
        calls: calls.get(key),
        tokens: Math.round(b / 4),          // ~4 bytes per token, good enough to rank
        share: b / total,
      };
    })
    .sort((a, b) => b.tokens - a.tokens);
}

const K = (n) => Math.round(n / 1000) + 'k';
const money = (n) => '$' + n.toFixed(2);
const pct = (n) => Math.round(n * 100) + '%';

// Shared by the agent x model table and every per-session agent table, so a
// column width change only has to happen in one place.
function printAgentRows(rows) {
  console.log(
    'agent'.padEnd(28), 'model'.padEnd(20), 'calls'.padStart(6),
    'cache rd'.padStart(9), 'cache wr'.padStart(9), 'output'.padStart(8), 'cost'.padStart(9)
  );
  for (const r of rows) {
    console.log(
      r.agent.slice(0, 27).padEnd(28), r.model.slice(0, 19).padEnd(20),
      String(r.calls).padStart(6), K(r.cacheRead).padStart(9),
      K(r.cacheWrite).padStart(9), K(r.output).padStart(8), money(r.cost).padStart(9)
    );
  }
}

function report(projectDir, sessions, byAgentModel, opts) {
  const { showFillers, byAgent, perSession } = opts;
  const totals = sessions.reduce((t, s) => ({
    cost: t.cost + s.totalCost,
    main: t.main + s.main.cost,
    sub: t.sub + s.sub.cost,
    cacheRead: t.cacheRead + s.main.cacheRead + s.sub.cacheRead,
    cacheWrite: t.cacheWrite + s.main.cacheWrite + s.sub.cacheWrite,
    output: t.output + s.main.output + s.sub.output,
  }), { cost: 0, main: 0, sub: 0, cacheRead: 0, cacheWrite: 0, output: 0 });

  console.log('\n' + projectDir);
  console.log(sessions.length + ' session(s), estimated ' + money(totals.cost) + ' at list price\n');

  // --per-session only ever means "the agent table, once per session" - it
  // has no other meaning, so it implies --by-agent rather than needing its
  // own error branch for being passed alone.
  if (perSession) {
    for (const s of sessions) {
      console.log('\nSession ' + s.id.slice(0, 8));
      printAgentRows(s.byAgent);
    }
  } else if (byAgent) {
    printAgentRows(byAgentModel);
  } else {
    console.log(
      'session'.padEnd(10), 'total'.padStart(9), 'main'.padStart(9),
      'calls'.padStart(6), 'avg ctx'.padStart(8), 'max ctx'.padStart(8),
      'sub'.padStart(9), 'calls'.padStart(6), 'sub%'.padStart(6)
    );
    for (const s of sessions) {
      console.log(
        s.id.slice(0, 8).padEnd(10), money(s.totalCost).padStart(9), money(s.main.cost).padStart(9),
        String(s.main.calls).padStart(6), K(s.main.avgContext).padStart(8),
        K(s.main.maxContext).padStart(8), money(s.sub.cost).padStart(9),
        String(s.sub.calls).padStart(6), pct(s.subShare).padStart(6)
      );
    }
  }

  console.log('\nWhere the money went');
  console.log('  main context'.padEnd(34), money(totals.main).padStart(9), pct(totals.cost ? totals.main / totals.cost : 0).padStart(6));
  console.log('  delegated to subagents'.padEnd(34), money(totals.sub).padStart(9), pct(totals.cost ? totals.sub / totals.cost : 0).padStart(6));
  console.log('  of which re-read context'.padEnd(34), K(totals.cacheRead).padStart(9));

  const worst = sessions[0];
  if (worst && worst.main.maxContext > 200000) {
    console.log(
      '\nThe largest context reached ' + K(worst.main.maxContext) +
      '. Every turn after that point re-reads it.'
    );
  }

  if (showFillers && worst) {
    const rows = fillers(projectDir, worst.id);
    if (rows.length) {
      console.log('\nWhat filled session ' + worst.id.slice(0, 8));
      // Grouped by agent, in the order each agent's first (and therefore
      // heaviest, since rows are sorted by tokens) row appears - a subagent
      // that only contributed a rounding error still gets its own heading
      // rather than being merged into the delegating context's numbers.
      const byAgent = new Map();
      for (const r of rows) {
        if (!byAgent.has(r.agent)) byAgent.set(r.agent, []);
        byAgent.get(r.agent).push(r);
      }
      for (const [agent, agentRows] of byAgent) {
        console.log('  ' + agent);
        for (const r of agentRows.slice(0, 10)) {
          console.log(
            '    ' + r.tool.padEnd(22), String(r.calls).padStart(5),
            K(r.tokens).padStart(8), pct(r.share).padStart(6)
          );
        }
      }
    }
  }
  console.log();
}

function main(argv) {
  const wantJson = argv.includes('--json');
  const showFillers = argv.includes('--fillers');
  const perSession = argv.includes('--per-session');
  // --per-session has only one meaning - the agent table, scoped per session -
  // so it implies --by-agent rather than requiring both flags.
  const byAgent = argv.includes('--by-agent') || perSession;
  const at = argv.indexOf('--project');
  const projectDir = at !== -1 && argv[at + 1] ? argv[at + 1] : projectDirFor(process.cwd());

  if (!fs.existsSync(projectDir)) {
    console.error('No transcripts at ' + projectDir);
    console.error('Pass --project <dir> if this project stores them elsewhere.');
    return 1;
  }

  const { sessions, byAgentModel, cumulative } = collect(projectDir);

  if (wantJson) {
    const totals = { cost: sessions.reduce((t, s) => t + s.totalCost, 0) };
    console.log(JSON.stringify({ project: projectDir, sessions, totals, byAgentModel, cumulative }, null, 2));
    return 0;
  }

  if (!sessions.length) {
    console.log('\nNo billed requests found under ' + projectDir + '\n');
    return 0;
  }

  report(projectDir, sessions, byAgentModel, { showFillers, byAgent, perSession });
  return 0;
}

process.exit(main(process.argv.slice(2)));
