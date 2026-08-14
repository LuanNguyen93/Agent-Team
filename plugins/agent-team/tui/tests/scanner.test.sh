#!/usr/bin/env bash
# E1-1: the scanner reads agents/skills/commands and emits one ADR-0004 document.
#
# The scanner is the single source of structural truth (docs/architecture.md):
# nothing outside it interprets frontmatter. So these tests assert on the JSON
# contract, not on rendering - the TUI and CI both consume exactly this.
#
# Bash under the repo bar: POSIX-ish, no jq. Assertions read the JSON with node,
# which is already this repo's test convention (scripts/tests/*.test.sh).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/../scanner.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

if ! command -v node >/dev/null 2>&1; then
  echo "node not available - skipping scanner tests"
  exit 0
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"
trap 'rm -rf "$TMP"' EXIT

# Read a dotted path out of JSON on stdin. Prints PARSE_ERR rather than dying,
# so a broken document fails the assertion it belongs to instead of the run.
jget() {
  node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{
    const o=JSON.parse(s);
    const v=process.argv[1].split(".").reduce((a,k)=>a&&a[/^\d+$/.test(k)?+k:k],o);
    console.log(Array.isArray(v)?v.length:(v===undefined?"UNDEF":String(v)));
  }catch(e){console.log("PARSE_ERR")}
});' "$1"
}

# --- the real tree, maintainer mode -----------------------------------------
OUT="$(bash "$SCANNER" scan --plugin-root "$PLUGIN_ROOT" 2>"$TMP/err")"; RC=$?

t="scan exits 0 on this repo"
[ $RC -eq 0 ] && ok "$t" || nope "$t" "rc=$RC err=$(cat "$TMP/err")"

t="stdout is valid JSON"
[ "$(printf '%s' "$OUT" | jget schemaVersion)" != "PARSE_ERR" ] && ok "$t" \
  || nope "$t" "$(printf '%s' "$OUT" | head -c 300)"

t="schemaVersion is 1.0"
v="$(printf '%s' "$OUT" | jget schemaVersion)"
[ "$v" = "1.0" ] && ok "$t" || nope "$t" "got '$v'"

t="mode is maintainer when scanning the repo tree"
v="$(printf '%s' "$OUT" | jget mode)"
[ "$v" = "maintainer" ] && ok "$t" || nope "$t" "got '$v'"

# The counts the story pins. They are observed values, so a change here is a
# real change in the tree and should be looked at, not silently re-baselined.
t="agents array has 11 entries"
v="$(printf '%s' "$OUT" | jget agents)"
[ "$v" = "11" ] && ok "$t" || nope "$t" "expected 11 got $v"

t="skills array has 18 entries"
v="$(printf '%s' "$OUT" | jget skills)"
[ "$v" = "18" ] && ok "$t" || nope "$t" "expected 18 got $v"

t="commands array has 4 entries"
v="$(printf '%s' "$OUT" | jget commands)"
[ "$v" = "4" ] && ok "$t" || nope "$t" "expected 4 got $v"

t="every top-level field of the ADR-0004 document is present"
MISSING="$(printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const need=["schemaVersion","generatedAt","mode","root","projectRoot","agents","skills","commands","loadEdges","findings"];
  try{const o=JSON.parse(s);console.log(need.filter(k=>o[k]===undefined).join(","))}catch(e){console.log("PARSE_ERR")}
});')"
[ -z "$MISSING" ] && ok "$t" || nope "$t" "missing: $MISSING"

t="no field is ever null - absent means \"\", 0, false or []"
NULLS="$(printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const bad=[];
  const walk=(v,p)=>{ if(v===null){bad.push(p);return;}
    if(Array.isArray(v))v.forEach((x,i)=>walk(x,p+"["+i+"]"));
    else if(v&&typeof v==="object")for(const k of Object.keys(v))walk(v[k],p+"."+k); };
  try{walk(JSON.parse(s),"");console.log(bad.slice(0,5).join(","))}catch(e){console.log("PARSE_ERR")}
});')"
[ -z "$NULLS" ] && ok "$t" || nope "$t" "null at: $NULLS"

t="an agent entry carries the E1-1 fields"
BAD="$(printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const a=JSON.parse(s).agents.find(x=>x.name==="implementer");
    if(!a)return console.log("implementer not found");
    const bad=[];
    if(!a.file.endsWith("agents/implementer.md"))bad.push("file="+a.file);
    if(!a.description)bad.push("empty description");
    if(a.descriptionLength!==a.description.length)bad.push("descriptionLength mismatch");
    if(a.model!=="sonnet")bad.push("model="+a.model);
    if(!Array.isArray(a.skills)||!a.skills.includes("tdd-discipline"))bad.push("skills="+JSON.stringify(a.skills));
    if(a.parsed!==true)bad.push("parsed="+a.parsed);
    console.log(bad.join("; "));
  }catch(e){console.log("PARSE_ERR "+e.message)}
});')"
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

t="a skill entry carries the E1-1 fields"
BAD="$(printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const k=JSON.parse(s).skills.find(x=>x.name==="quality-gates");
    if(!k)return console.log("quality-gates not found");
    const bad=[];
    if(!k.dir.endsWith("skills/quality-gates"))bad.push("dir="+k.dir);
    if(k.hasReferences!==true)bad.push("hasReferences="+k.hasReferences);
    if(k.hasManifest!==true)bad.push("hasManifest="+k.hasManifest);
    if(!k.whenToUse)bad.push("empty whenToUse");
    console.log(bad.join("; "));
  }catch(e){console.log("PARSE_ERR "+e.message)}
});')"
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

t="arrays are sorted, because the contract says the output is diffable"
BAD="$(printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const o=JSON.parse(s);
    const sorted=(a,k)=>a.map(x=>x[k]).every((v,i,arr)=>i===0||arr[i-1]<=v);
    const bad=[];
    if(!sorted(o.agents,"file"))bad.push("agents");
    if(!sorted(o.skills,"dir"))bad.push("skills");
    if(!sorted(o.commands,"file"))bad.push("commands");
    console.log(bad.join(","));
  }catch(e){console.log("PARSE_ERR")}
});')"
[ -z "$BAD" ] && ok "$t" || nope "$t" "unsorted: $BAD"

# --- load edges: declared vs actually loaded --------------------------------
# This is the mismatch that is invisible at runtime - a skill in frontmatter the
# body never loads, or a Step 0 load the frontmatter never declares.
t="loadEdges relate agents to skills"
v="$(printf '%s' "$OUT" | jget loadEdges)"
[ "$v" != "0" ] && [ "$v" != "PARSE_ERR" ] && ok "$t" || nope "$t" "got $v edges"

t="a matched edge is neither declaredOnly nor loadedOnly"
BAD="$(printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const e=JSON.parse(s).loadEdges.find(x=>x.agent==="implementer"&&x.skill==="tdd-discipline");
    if(!e)return console.log("edge not found");
    console.log((e.declaredOnly===false&&e.loadedOnly===false)?"":"declaredOnly="+e.declaredOnly+" loadedOnly="+e.loadedOnly);
  }catch(e){console.log("PARSE_ERR")}
});')"
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

t="no edge is both declaredOnly and loadedOnly"
BAD="$(printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{console.log(JSON.parse(s).loadEdges.filter(e=>e.declaredOnly&&e.loadedOnly).map(e=>e.agent+"/"+e.skill).join(","))}catch(e){console.log("PARSE_ERR")}
});')"
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

# --- edges: empty, one, many ------------------------------------------------
mk_tree() {  # dir
  mkdir -p "$1/agents" "$1/skills" "$1/commands"
}
mk_agent() {  # dir name
  printf -- '---\nname: %s\ndescription: A test agent named %s.\nmodel: sonnet\nskills:\n  - some-skill\n---\n\nBody.\n\n**Step 0**: load `some-skill` via the Skill tool.\n' "$2" "$2" > "$1/agents/$2.md"
}

EMPTY="$TMP/empty"; mk_tree "$EMPTY"
OUT="$(bash "$SCANNER" scan --plugin-root "$EMPTY" 2>"$TMP/err")"; RC=$?
t="an empty agents/ directory yields an empty array, not an error"
{ [ $RC -eq 0 ] && [ "$(printf '%s' "$OUT" | jget agents)" = "0" ]; } && ok "$t" \
  || nope "$t" "rc=$RC agents=$(printf '%s' "$OUT" | jget agents) err=$(cat "$TMP/err")"

ONE="$TMP/one"; mk_tree "$ONE"; mk_agent "$ONE" solo
OUT="$(bash "$SCANNER" scan --plugin-root "$ONE" 2>/dev/null)"
t="a single agent produces one fully-populated entry"
BAD="$(printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const a=JSON.parse(s).agents;
    if(a.length!==1)return console.log("length="+a.length);
    const x=a[0],bad=[];
    if(x.name!=="solo")bad.push("name="+x.name);
    if(x.model!=="sonnet")bad.push("model="+x.model);
    if(x.descriptionLength<=0)bad.push("descriptionLength="+x.descriptionLength);
    console.log(bad.join("; "));
  }catch(e){console.log("PARSE_ERR")}
});')"
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

MANY="$TMP/many"; mk_tree "$MANY"
i=0; while [ $i -lt 500 ]; do mk_agent "$MANY" "agent$(printf '%03d' $i)"; i=$((i+1)); done
START=$(date +%s)
OUT="$(bash "$SCANNER" scan --plugin-root "$MANY" 2>/dev/null)"; RC=$?
ELAPSED=$(( $(date +%s) - START ))
t="500 agents scan without crashing"
{ [ $RC -eq 0 ] && [ "$(printf '%s' "$OUT" | jget agents)" = "500" ]; } && ok "$t" \
  || nope "$t" "rc=$RC agents=$(printf '%s' "$OUT" | jget agents)"
t="500 agents scan inside the 30s budget (took ${ELAPSED}s)"
[ "$ELAPSED" -le 30 ] && ok "$t" || nope "$t" "took ${ELAPSED}s"

# --- failures ---------------------------------------------------------------
OUT="$(bash "$SCANNER" scan --plugin-root "$TMP/not-there" 2>"$TMP/err")"; RC=$?
t="a missing plugin root exits non-zero"
[ $RC -ne 0 ] && ok "$t" || nope "$t" "rc=$RC"
t="a missing plugin root emits no JSON on stdout"
[ -z "$OUT" ] && ok "$t" || nope "$t" "stdout was: $OUT"
t="a missing plugin root names the path it looked for"
case "$(cat "$TMP/err")" in *not-there*) ok "$t";; *) nope "$t" "$(cat "$TMP/err")";; esac

# Unparsable frontmatter must degrade, not abort: one bad file cannot blind the
# scanner to the other 500.
BADFM="$TMP/badfm"; mk_tree "$BADFM"; mk_agent "$BADFM" good
printf -- '---\nname: broken\n  description: "unclosed\nmodel\n---\nBody.\n' > "$BADFM/agents/broken.md"
printf 'no frontmatter at all\n' > "$BADFM/agents/naked.md"
OUT="$(bash "$SCANNER" scan --plugin-root "$BADFM" 2>/dev/null)"; RC=$?
t="an unparsable frontmatter block does not crash the scan"
[ $RC -eq 0 ] || [ $RC -eq 1 ] && ok "$t" || nope "$t" "rc=$RC"
t="the other agents in the tree are still scanned"
[ "$(printf '%s' "$OUT" | jget agents)" = "3" ] && ok "$t" \
  || nope "$t" "expected 3 got $(printf '%s' "$OUT" | jget agents)"
t="a file with no frontmatter is recorded as parsed:false"
BAD="$(printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const a=JSON.parse(s).agents.find(x=>x.file.endsWith("naked.md"));
    console.log(a?(a.parsed===false?"":"parsed="+a.parsed):"naked.md not scanned");
  }catch(e){console.log("PARSE_ERR")}
});')"
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

t="an unparsable file produces a finding rather than silence"
BAD="$(printf '%s' "$OUT" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const f=JSON.parse(s).findings.filter(x=>x.file.endsWith("naked.md"));
    console.log(f.length?"":"no finding for naked.md");
  }catch(e){console.log("PARSE_ERR")}
});')"
[ -z "$BAD" ] && ok "$t" || nope "$t" "$BAD"

# --- JSON escaping ----------------------------------------------------------
# A description with a quote or a backslash must not produce a broken document.
ESC="$TMP/esc"; mk_tree "$ESC"
printf -- '---\nname: quoted\ndescription: He said "hello" and C:\\path\\to — plus a tab\tthere.\nmodel: opus\n---\nBody.\n' > "$ESC/agents/quoted.md"
OUT="$(bash "$SCANNER" scan --plugin-root "$ESC" 2>/dev/null)"
t="quotes, backslashes and tabs in a description survive as valid JSON"
v="$(printf '%s' "$OUT" | jget agents)"
[ "$v" = "1" ] && ok "$t" || nope "$t" "got $v; output: $(printf '%s' "$OUT" | head -c 200)"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
