#!/usr/bin/env bash
# Tests for pr-gather.sh and pr-create.sh (the pr-create skill's scripts).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATHER="$SCRIPT_DIR/../pr-gather.sh"; CREATE="$SCRIPT_DIR/../pr-create.sh"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
command -v node >/dev/null 2>&1 || { echo "node not available - skipping"; exit 0; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t agentteam)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/remote.git"; REPO="$TMP/repo"
git init -q --bare "$REMOTE"
git init -q "$REPO"; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
git -C "$REPO" checkout -q -b main
echo a > "$REPO/a.txt"; git -C "$REPO" add .; git -C "$REPO" commit -qm "chore: init"
git -C "$REPO" remote add origin "$REMOTE"; git -C "$REPO" push -q -u origin main
git -C "$REPO" remote set-head origin main
git -C "$REPO" checkout -q -b feat/42-thing
printf 'b\n' > "$REPO/b.txt"; git -C "$REPO" add .; git -C "$REPO" commit -qm "feat(core): add b (#42)"
# fake gh that records argv
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<EOS
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TMP/gh-args"; echo "https://github.com/o/r/pull/7"
EOS
chmod +x "$BIN/gh"
field() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);const v=process.argv[1].split(".").reduce((a,k)=>a==null?a:a[k],j);console.log(typeof v==="object"?JSON.stringify(v):v)})' "$1"; }

echo "pr-gather.sh"
OUT="$(bash "$GATHER" --repo "$REPO" 2>/dev/null)"; RC=$?
t="emits JSON, exit 0"; [ $RC -eq 0 ] && printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>JSON.parse(s))' 2>/dev/null && ok "$t" || nope "$t" "rc=$RC out='$OUT'"
t="base resolves to origin/HEAD (main) when no develop"; [ "$(printf '%s' "$OUT" | field baseBranch)" = "main" ] && ok "$t" || nope "$t" "$(printf '%s' "$OUT" | field baseBranch)"
t="aheadCount=1, commit subject present"; [ "$(printf '%s' "$OUT" | field aheadCount)" = "1" ] && printf '%s' "$OUT" | grep -q 'add b' && ok "$t" || nope "$t" "$OUT"
t="issueIds picked from branch name"; [ "$(printf '%s' "$OUT" | field issueIds)" = '["42"]' ] && ok "$t" || nope "$t" "$(printf '%s' "$OUT" | field issueIds)"
t="hasUpstream=false before push, onDefaultBranch=false"; [ "$(printf '%s' "$OUT" | field hasUpstream)" = "false" ] && [ "$(printf '%s' "$OUT" | field onDefaultBranch)" = "false" ] && ok "$t" || nope "$t" "$OUT"
t="numstat lists b.txt with 1 addition"; printf '%s' "$OUT" | grep -q '"file": *"b.txt"' && ok "$t" || nope "$t" "$OUT"
t="template falls back to the plugin pr-description template"; printf '%s' "$OUT" | field template | grep -q '## What' && ok "$t" || nope "$t" "$(printf '%s' "$OUT" | field templatePath)"
mkdir -p "$REPO/.github"; echo "## Custom" > "$REPO/.github/PULL_REQUEST_TEMPLATE.md"
t="repo .github template wins"; bash "$GATHER" --repo "$REPO" 2>/dev/null | field template | grep -q '## Custom' && ok "$t" || nope "$t" ""
rm -rf "$REPO/.github"
git -C "$REPO" checkout -q -b develop main; git -C "$REPO" push -q -u origin develop; git -C "$REPO" checkout -q feat/42-thing
t="develop wins over origin/HEAD when present"; [ "$(bash "$GATHER" --repo "$REPO" 2>/dev/null | field baseBranch)" = "develop" ] && ok "$t" || nope "$t" ""
t="--base-branch overrides"; [ "$(bash "$GATHER" --repo "$REPO" --base-branch main 2>/dev/null | field baseBranch)" = "main" ] && ok "$t" || nope "$t" ""
t="diff capped + diffTruncated flag"; OUT2="$(bash "$GATHER" --repo "$REPO" --max-diff-bytes 10 2>/dev/null)"; [ "$(printf '%s' "$OUT2" | field diffTruncated)" = "true" ] && ok "$t" || nope "$t" "$OUT2"
t="provider detected from origin (github)"; git -C "$REPO" remote set-url origin git@github.com:o/r.git; [ "$(bash "$GATHER" --repo "$REPO" --base-branch main 2>/dev/null | field provider)" = "github" ] && ok "$t" || nope "$t" ""
git -C "$REPO" remote set-url origin "$REMOTE"

echo "pr-create.sh"
DESC="$TMP/d.md"; echo "body" > "$DESC"
t="refuses when no upstream"; ERR="$(bash "$CREATE" --repo "$REPO" --title t --description-file "$DESC" 2>&1)"; RC=$?; [ $RC -ne 0 ] && printf '%s' "$ERR" | grep -qi 'upstream' && ok "$t" || nope "$t" "rc=$RC $ERR"
git -C "$REPO" push -q -u origin feat/42-thing
echo c > "$REPO/c.txt"; git -C "$REPO" add .; git -C "$REPO" commit -qm "feat: c"
t="refuses when ahead of upstream"; ERR="$(bash "$CREATE" --repo "$REPO" --title t --description-file "$DESC" 2>&1)"; RC=$?; [ $RC -ne 0 ] && printf '%s' "$ERR" | grep -qi 'ahead' && ok "$t" || nope "$t" "rc=$RC $ERR"
git -C "$REPO" push -q
t="refuses from the default branch"; git -C "$REPO" checkout -q main; ERR="$(bash "$CREATE" --repo "$REPO" --title t --description-file "$DESC" --target-branch develop 2>&1)"; RC=$?; [ $RC -ne 0 ] && printf '%s' "$ERR" | grep -qi 'default branch' && ok "$t" || nope "$t" "rc=$RC $ERR"; git -C "$REPO" checkout -q feat/42-thing
t="unknown provider -> clear error"; ERR="$(bash "$CREATE" --repo "$REPO" --title t --description-file "$DESC" 2>&1)"; RC=$?; [ $RC -ne 0 ] && printf '%s' "$ERR" | grep -qi 'provider' && ok "$t" || nope "$t" "rc=$RC $ERR"
git -C "$REPO" remote set-url origin git@github.com:o/r.git
git -C "$REPO" config branch.feat/42-thing.remote origin
t="github dry-run prints gh pr create with base/head/title"; OUT="$(PATH="$BIN:$PATH" bash "$CREATE" --repo "$REPO" --title "feat(core): add b (#42)" --description-file "$DESC" --dry-run 2>&1)"; RC=$?; [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -q 'gh pr create' && printf '%s' "$OUT" | grep -q -- '--base develop' && printf '%s' "$OUT" | grep -q -- '--head feat/42-thing' && ok "$t" || nope "$t" "rc=$RC $OUT"
t="github real run calls gh with --body-file and --draft, prints URL"; OUT="$(PATH="$BIN:$PATH" bash "$CREATE" --repo "$REPO" --title t --description-file "$DESC" --draft 2>&1)"; RC=$?; [ $RC -eq 0 ] && grep -q -- '--body-file' "$TMP/gh-args" && grep -q -- '--draft' "$TMP/gh-args" && printf '%s' "$OUT" | grep -q 'pull/7' && ok "$t" || nope "$t" "rc=$RC $OUT $(cat "$TMP/gh-args")"
t="azure dry-run passes explicit --organization/--project/--repository"; git -C "$REPO" remote set-url origin https://dev.azure.com/MyOrg/My%20Project/_git/my-repo; OUT="$(bash "$CREATE" --repo "$REPO" --title t --description-file "$DESC" --dry-run 2>&1)"; printf '%s' "$OUT" | grep -q 'az repos pr create' && printf '%s' "$OUT" | grep -q 'dev.azure.com/MyOrg' && printf '%s' "$OUT" | grep -q 'My Project' && printf '%s' "$OUT" | grep -q -- '--detect false' && ok "$t" || nope "$t" "$OUT"
t="gitlab dry-run uses glab mr create"; git -C "$REPO" remote set-url origin git@gitlab.com:g/r.git; OUT="$(bash "$CREATE" --repo "$REPO" --title t --description-file "$DESC" --dry-run 2>&1)"; printf '%s' "$OUT" | grep -q 'glab mr create' && ok "$t" || nope "$t" "$OUT"

echo; echo "passed: $PASS  failed: $FAIL"; [ "$FAIL" -eq 0 ]
