#!/usr/bin/env node
'use strict';
//
// Print the current context size, in tokens, for the session a hook is running
// inside. Prints 0 when it cannot be determined.
//
// There is no environment variable for this. The only place the number exists
// is the transcript the harness appends to: every assistant record carries a
// `usage` block, and the newest one describes the request that just went out -
// cache reads plus cache writes plus plain input is what that request had to
// carry. That is the context.
//
// Why this matters enough to have a helper: a context is not paid for once, it
// is re-read on every following turn. Cost is roughly context x turns, so the
// size crossing a threshold is the moment to compact, and nothing in the
// session surfaces that moment on its own.
//
// Reads a hook payload on stdin when there is one. Never throws, never blocks:
// a hook that crashes on a malformed transcript would take the turn with it.

const fs = require('fs');
const path = require('path');

function readStdin() {
  try {
    // fd 0 with no data attached throws EAGAIN rather than returning empty.
    return fs.readFileSync(0, 'utf8');
  } catch (e) {
    return '';
  }
}

function argValue(argv, name) {
  const at = argv.indexOf(name);
  return at !== -1 && argv[at + 1] ? argv[at + 1] : null;
}

// The newest .jsonl directly inside dir. Used when the payload carries no
// transcript_path - the hook contract is not guaranteed to include one, and a
// hook that only works on the documented path stops working silently.
function newestTranscript(dir) {
  let best = null;
  let bestTime = -1;
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (e) {
    return null;
  }
  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith('.jsonl')) continue;
    const full = path.join(dir, entry.name);
    try {
      const t = fs.statSync(full).mtimeMs;
      if (t > bestTime) { bestTime = t; best = full; }
    } catch (e) { /* raced with a delete; skip */ }
  }
  return best;
}

// The transcript_path a PreToolUse payload carries inside a subagent
// invocation is the PARENT session's own transcript, not the subagent's -
// measured against this harness, see docs/HARNESS-NOTES.md. A subagent's own
// records live at <project>/<session_id>/subagents/agent-<agent_id>.jsonl,
// sitting next to the parent transcript. Matches on the id SUFFIX rather than
// an exact filename, and picks the newest match, so a harness that prefixes
// the file differently still resolves. Returns null (falls back to the
// parent) when nothing matches.
function subagentTranscriptOf(parentTranscript, sessionId, agentId) {
  if (!parentTranscript || !sessionId || !agentId) return null;
  const dir = path.join(path.dirname(parentTranscript), sessionId, 'subagents');
  let entries;
  try {
    entries = fs.readdirSync(dir);
  } catch (e) {
    return null;
  }
  let best = null;
  let bestTime = -1;
  const suffix = agentId + '.jsonl';
  for (const name of entries) {
    if (!name.endsWith(suffix)) continue;
    const full = path.join(dir, name);
    try {
      const t = fs.statSync(full).mtimeMs;
      if (t > bestTime) { bestTime = t; best = full; }
    } catch (e) { /* raced with a delete; skip */ }
  }
  return best;
}

// Scans backwards: the answer is almost always in the last few lines, and a
// transcript can be tens of megabytes.
function contextSizeOf(file) {
  let lines;
  try {
    lines = fs.readFileSync(file, 'utf8').split('\n');
  } catch (e) {
    return 0;
  }
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i];
    if (!line.trim()) continue;
    let record;
    try { record = JSON.parse(line); } catch (e) { continue; }
    const usage = record && record.message && record.message.usage;
    if (!usage) continue;
    return (usage.input_tokens || 0) +
      (usage.cache_creation_input_tokens || 0) +
      (usage.cache_read_input_tokens || 0);
  }
  return 0;
}

function main(argv) {
  let transcript = argValue(argv, '--transcript');
  let agentId = argValue(argv, '--agent-id');
  let payload = null;

  if (!transcript) {
    const raw = readStdin();
    if (raw.trim()) {
      try {
        payload = JSON.parse(raw);
        if (payload && payload.transcript_path) transcript = payload.transcript_path;
      } catch (e) { /* a payload we cannot read is the same as no payload */ }
    }
  }

  if (!agentId && payload && payload.agent_id) agentId = payload.agent_id;

  if (agentId && transcript) {
    const sessionId = (payload && payload.session_id) || path.basename(transcript, '.jsonl');
    const sub = subagentTranscriptOf(transcript, sessionId, agentId);
    if (sub) transcript = sub;
  }

  if (!transcript || !fs.existsSync(transcript)) {
    const dir = argValue(argv, '--project-dir');
    transcript = dir ? newestTranscript(dir) : null;
  }

  console.log(transcript ? contextSizeOf(transcript) : 0);
  return 0;
}

process.exit(main(process.argv.slice(2)));
