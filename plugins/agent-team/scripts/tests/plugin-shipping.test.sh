#!/usr/bin/env bash
# Guards the gap between "it is in the repo" and "it is in the plugin that is
# actually running".
#
# The bug this exists for: three skills - ai-engineering, context-discipline and
# security-discipline - were added to the tree without bumping plugin.json.
# The installer saw 0.2.1 already installed, never refreshed its cache, and for
# months every agent ran against a 15-skill plugin while every agent file told
# it to load 18. `claude plugin validate` passes throughout, because nothing it
# checks is wrong.
#
# Plain POSIX-ish, no bats and no jq, per CLAUDE.md.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

if ! command -v node >/dev/null 2>&1; then
  echo "node not available - skipping plugin shipping tests"
  exit 0
fi

# --- 1. every skill an agent names must exist on disk -----------------------
#
# An agent that is told to load a skill which is not there does not fail loudly;
# it just proceeds without the doctrine.
MISSING="$(node -e '
const fs=require("fs"), path=require("path");
const root=process.argv[1];
const read=(p)=>fs.readFileSync(p,"utf8").split("\r\n").join("\n");
const flat=(s)=>s.replace(/\s+/g," ");
const out=[];
for (const f of fs.readdirSync(path.join(root,"agents"))) {
  const body=read(path.join(root,"agents",f));
  const m=body.match(/^skills:\n((?:\s+- .+\n)+)/m);
  const declared=m?m[1].trim().split("\n").map(s=>s.replace(/^\s*-\s*/,"").trim()):[];
  // Skills named inside the paragraph that mentions the Skill tool. The phrase
  // wraps across lines in several agents, so the paragraph is flattened first.
  const para=body.split(/\n\s*\n/).map(flat).filter(p=>/Skill tool/.test(p)).join(" ");
  const named=[...para.matchAll(/`([a-z0-9-]+)`/g)].map(x=>x[1])
    .filter(n=>fs.existsSync(path.join(root,"skills",n,"SKILL.md")));
  for (const s of new Set([...declared, ...named])) {
    if (!fs.existsSync(path.join(root,"skills",s,"SKILL.md"))) out.push(f+" -> "+s+" (no such skill)");
  }
  // A skill Step 0 loads but frontmatter does not declare is the mirror bug:
  // the harness has been seen injecting the frontmatter list directly, so the
  // two have to agree or the doctrine arrives on one path and not the other.
  for (const s of new Set(named)) {
    if (!declared.includes(s)) out.push(f+" -> "+s+" (loaded at Step 0, not declared in frontmatter)");
  }
}
console.log(out.join("\n"));
' "$PLUGIN_ROOT")"

t="frontmatter and Step 0 name the same skills, and all of them exist"
[ -z "$MISSING" ] && ok "$t" || nope "$t" "$MISSING"

# --- 2. every skill on disk is reachable somehow ----------------------------
#
# A skill nothing can reach is dead weight that still ships. There are two ways
# to be reachable: an agent or command names it, or it declares `paths:` and the
# harness activates it on a file match. A skill with neither is unreachable.
ORPHANS="$(node -e '
const fs=require("fs"), path=require("path");
const root=process.argv[1];
const read=(p)=>fs.readFileSync(p,"utf8").split("\r\n").join("\n");
const dirFiles=(d)=>fs.existsSync(path.join(root,d))
  ? fs.readdirSync(path.join(root,d)).map(f=>read(path.join(root,d,f))).join("\n") : "";
const all=dirFiles("agents")+"\n"+dirFiles("commands");
const orphans=fs.readdirSync(path.join(root,"skills")).filter((s)=>{
  if (all.includes(s)) return false;
  const fm=(read(path.join(root,"skills",s,"SKILL.md")).split("---")[1])||"";
  return !/^paths:/m.test(fm);   // path-activated skills need no referrer
});
console.log(orphans.join("\n"));
' "$PLUGIN_ROOT")"

t="no skill ships without something referencing it"
[ -z "$ORPHANS" ] && ok "$t" || nope "$t" "orphaned: $ORPHANS"

# --- 3. plugin content changed since the last version bump must re-bump -----
#
# This is the one that would have caught the original bug. An installer keys off
# the version; content that ships under an already-installed version is content
# nobody receives.
if ! command -v git >/dev/null 2>&1 || ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "  skip  version-bump check (not a git repo)"
else
  VERSION_NOW="$(node -e 'console.log(require(process.argv[1]).version)' "$MANIFEST")"

  # The commit that last changed the manifest, and the version it carried there.
  LAST_MANIFEST_COMMIT="$(git -C "$REPO_ROOT" log -1 --format=%H -- "$MANIFEST" 2>/dev/null)"

  if [ -z "$LAST_MANIFEST_COMMIT" ]; then
    echo "  skip  version-bump check (manifest not committed yet)"
  else
    VERSION_THEN="$(git -C "$REPO_ROOT" show "$LAST_MANIFEST_COMMIT:plugins/agent-team/.claude-plugin/plugin.json" 2>/dev/null \
      | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).version)}catch(e){console.log("")}})')"

    # Plugin content committed after that point, ignoring the manifest itself
    # and the things an installer does not ship.
    CHANGED="$(git -C "$REPO_ROOT" diff --name-only "$LAST_MANIFEST_COMMIT" HEAD -- \
      plugins/agent-team 2>/dev/null \
      | grep -v '.claude-plugin/plugin.json' \
      | grep -v '/tests/' \
      | head -20)"

    # Uncommitted plugin content counts too - it is about to be in the same boat.
    UNCOMMITTED="$(git -C "$REPO_ROOT" status --porcelain -- plugins/agent-team 2>/dev/null \
      | sed 's/^...//' \
      | grep -v '.claude-plugin/plugin.json' \
      | grep -v '/tests/' \
      | head -20)"

    t="plugin content changed since the last bump implies a new version"
    if [ -z "$CHANGED" ] && [ -z "$UNCOMMITTED" ]; then
      ok "$t (no content change since $VERSION_THEN)"
    elif [ "$VERSION_NOW" != "$VERSION_THEN" ]; then
      ok "$t ($VERSION_THEN -> $VERSION_NOW)"
    else
      nope "$t" "version is still $VERSION_NOW but this changed since the bump:
$(printf '%s\n%s' "$CHANGED" "$UNCOMMITTED" | sed '/^$/d' | sed 's/^/       /')
     An installer keys off the version. Content shipped under an already
     installed version never reaches anyone."
    fi
  fi
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
