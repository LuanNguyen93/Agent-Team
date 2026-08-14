#!/usr/bin/env node
'use strict';
//
// Report whether the main context announced a planning tier and then kept
// editing without delegating.
//
// tier-guard.sh (PreToolUse on Edit|Write|NotebookEdit) needs to know: did the
// main context ever say "this is a FEATURE/PROJECT", and if so, how many
// undelegated edits have happened since, and did a Task call happen since.
// This script answers exactly that, from the transcript, and nothing else -
// policy (block or not) lives in tier-guard.sh, not here.
//
// "Top-level" follows the convention measure-tokens.js uses: a record with no
// attributionAgent field is the main context's own turn; a record that has one
// came from a subagent's own transcript merged into the same file. Only
// top-level records count, in both directions - the announcement and the
// edits/Task since it.
//
// Usage: node tier-scan.js <transcript-path>
// Prints one line: "TIER EDITS_SINCE HAS_TASK_SINCE", e.g. "FEATURE 6 0", or
// "NONE 0 0" when no tier was ever announced.

const fs = require('fs');

// Loose by design: backticked tier name, optional whitespace, then a dash of
// any common flavour (hyphen, en dash, em dash). Case-insensitive so a model
// that varies capitalisation still gets caught.
const TIER_RE = /`(QUICK|FEATURE|PROJECT)`\s*[-–—]/i;

function readRecords(file) {
  const records = [];
  let raw;
  try {
    raw = fs.readFileSync(file, 'utf8');
  } catch (e) {
    return records;
  }
  for (const line of raw.split('\n')) {
    if (!line.trim()) continue;
    try { records.push(JSON.parse(line)); } catch (e) { /* half-written line; skip */ }
  }
  return records;
}

// The last tier a top-level text block announced, and the index of the
// record that announced it.
function findLastAnnouncement(records) {
  let tier = null;
  let index = -1;
  for (let i = 0; i < records.length; i++) {
    const r = records[i];
    if (r.attributionAgent) continue; // subagent record, not top-level
    const content = r.message && r.message.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block.type !== 'text' || typeof block.text !== 'string') continue;
      const m = block.text.match(TIER_RE);
      if (m) {
        tier = m[1].toUpperCase();
        index = i;
      }
    }
  }
  return { tier, index };
}

// Top-level Edit/Write/NotebookEdit count, and whether a top-level Task
// occurred, at or after startIndex.
function countSince(records, startIndex) {
  let edits = 0;
  let hasTask = false;
  for (let i = startIndex; i < records.length; i++) {
    const r = records[i];
    if (r.attributionAgent) continue; // subagent's own tool call, not this context's
    const content = r.message && r.message.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block.type !== 'tool_use') continue;
      if (block.name === 'Edit' || block.name === 'Write' || block.name === 'NotebookEdit') {
        edits += 1;
      } else if (block.name === 'Task') {
        hasTask = true;
      }
    }
  }
  return { edits, hasTask };
}

function main(argv) {
  const transcript = argv[2];
  if (!transcript) {
    console.log('NONE 0 0');
    return;
  }
  const records = readRecords(transcript);
  const { tier, index } = findLastAnnouncement(records);
  if (!tier) {
    console.log('NONE 0 0');
    return;
  }
  const { edits, hasTask } = countSince(records, index);
  console.log(`${tier} ${edits} ${hasTask ? 1 : 0}`);
}

main(process.argv);
