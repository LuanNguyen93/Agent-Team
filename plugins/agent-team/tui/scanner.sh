#!/usr/bin/env bash
# The scanner: the single source of structural truth about a plugin tree.
#
# It reads every agent, skill and command, interprets their frontmatter, and
# emits one ADR-0004 document on stdout. Nothing else in this system interprets
# frontmatter - not the TUI, not CI. That is the whole point: one set of rules,
# in one place, that both consumers ask rather than re-derive.
#
# Bar it has to hold (CLAUDE.md, ADR-0002): POSIX-ish bash, no `jq`, runnable on
# Windows Git Bash / macOS / Linux. It is also the CI validator, so it must run
# where the hooks already run.
#
#   scanner.sh scan [--plugin-root P] [--mode maintainer|user] [--path PROJECT]
#
# Exit codes:
#   0  scanned; no findings of severity error
#   1  scanned; at least one error-severity finding (document still on stdout)
#   2  could not scan at all (nothing on stdout; reason on stderr)
#
# PERFORMANCE, and why this file looks the way it does. Every helper below sets
# a global instead of printing, and is called as `je "$x"` rather than
# `$(je "$x")`. Command substitution forks; at ~10 escapes per agent, the
# obvious version forks 5,000 times for the 500-agent budget case and misses the
# 30s target by an order of magnitude on Git Bash, where fork is expensive.
# There are no forks in any per-file or per-line path here.

set -uo pipefail

SCHEMA_VERSION="1.0"

# ---------------------------------------------------------------- arguments --

usage() {
  echo "usage: scanner.sh scan [--plugin-root P] [--mode maintainer|user] [--path PROJECT]" >&2
}

[ $# -gt 0 ] || { usage; exit 2; }
SUBCOMMAND="$1"; shift

PLUGIN_ROOT=""; MODE=""; PROJECT_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="${2:-}";  shift 2 || exit 2 ;;
    --mode)        MODE="${2:-}";         shift 2 || exit 2 ;;
    --path)        PROJECT_PATH="${2:-}"; shift 2 || exit 2 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

case "$SUBCOMMAND" in
  scan) ;;
  *) echo "unknown subcommand: $SUBCOMMAND" >&2; usage; exit 2 ;;
esac

# ------------------------------------------------------------ root and mode --

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SELF_DIR="."

# Default root is the plugin this scanner ships inside - the observation ADR-0003
# turns on. No hunting through install caches for a plausible-but-wrong root.
[ -n "$PLUGIN_ROOT" ] || PLUGIN_ROOT="$SELF_DIR/.."

if [ ! -d "$PLUGIN_ROOT" ]; then
  echo "scanner: plugin root does not exist: $PLUGIN_ROOT" >&2
  exit 2
fi
PLUGIN_ROOT="$(cd "$PLUGIN_ROOT" && pwd)"

# Mode by the scanner's own location (ADR-0003): a marketplace manifest above
# the plugin root means this is the source repo, not an install.
if [ -z "$MODE" ]; then
  if [ -f "$SELF_DIR/../../../.claude-plugin/marketplace.json" ]; then
    MODE="maintainer"
  else
    MODE="user"
  fi
fi
case "$MODE" in
  maintainer|user) ;;
  *) echo "scanner: --mode must be maintainer or user, got: $MODE" >&2; exit 2 ;;
esac

ROOT_OUT="${PLUGIN_ROOT//\\//}"
PROJECT_OUT="${PROJECT_PATH//\\//}"

# ------------------------------------------------------- helpers (no forks) --

# Escape into JE. Backslash first, or it double-escapes what follows.
JE=""
je() {
  JE="$1"
  JE="${JE//\\/\\\\}"
  JE="${JE//\"/\\\"}"
  JE="${JE//	/\\t}"
  JE="${JE//$'\r'/\\r}"
  JE="${JE//$'\n'/\\n}"
}

# Characters, not bytes (ADR-0004). ${#s} is byte-based unless the locale says
# otherwise, and this script cannot rely on the locale across Git Bash, macOS
# and Linux. ASCII takes the fast path; anything else drops UTF-8 continuation
# bytes (10xxxxxx) and counts what is left.
CLEN=0
clen() {
  case "$1" in
    *[$'\x80'-$'\xff']*)
      local stripped="${1//[$'\x80'-$'\xbf']/}"
      CLEN=${#stripped} ;;
    *) CLEN=${#1} ;;
  esac
}

# ["a","b"] from a newline-separated list, into JARR.
JARR=""
jarr_lines() {
  local acc="" item rest="$1"
  while [ -n "$rest" ]; do
    item="${rest%%$'\n'*}"
    if [ "$item" = "$rest" ]; then rest=""; else rest="${rest#*$'\n'}"; fi
    [ -n "$item" ] || continue
    je "$item"; acc="$acc,\"$JE\""
  done
  JARR="[${acc#,}]"
}

# ["a","b"] from a space-separated list, into JARR.
jarr_words() {
  local acc="" item
  for item in $1; do je "$item"; acc="$acc,\"$JE\""; done
  JARR="[${acc#,}]"
}

# ------------------------------------------------------------ frontmatter ----

FM_PARSED=0
FM_NAME=""; FM_DESCRIPTION=""; FM_MODEL=""; FM_WHEN=""; FM_ARGHINT=""
FM_SKILLS=""; FM_FORBIDDEN=""; BODY_LOADED=""

parse_file() {
  FM_PARSED=0
  FM_NAME=""; FM_DESCRIPTION=""; FM_MODEL=""; FM_WHEN=""; FM_ARGHINT=""
  FM_SKILLS=""; FM_FORBIDDEN=""; BODY_LOADED=""

  local line first=1 in_fm=0 closed=0 in_body=0
  local key val current_list="" body="" para="" rest token

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"

    if [ $first -eq 1 ]; then
      first=0
      if [ "$line" = "---" ]; then in_fm=1; continue; fi
      in_body=1                       # no frontmatter at all
    fi

    if [ $in_fm -eq 1 ]; then
      if [ "$line" = "---" ]; then in_fm=0; closed=1; in_body=1; continue; fi

      case "$line" in
        [[:space:]]*-[[:space:]]*)     # a list item continues the open key
          if [ -n "$current_list" ]; then
            val="${line#*- }"
            val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
            case "$val" in '"'*'"') val="${val#\"}"; val="${val%\"}" ;;
                           "'"*"'") val="${val#\'}"; val="${val%\'}" ;; esac
            case "$current_list" in skills) FM_SKILLS="$FM_SKILLS$val"$'\n' ;; esac
          fi
          continue ;;
      esac

      case "$line" in
        [![:space:]]*:*)
          key="${line%%:*}"
          val="${line#*:}"
          val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
          case "$val" in '"'*'"') val="${val#\"}"; val="${val%\"}" ;;
                         "'"*"'") val="${val#\'}"; val="${val%\'}" ;; esac
          current_list=""
          case "$key" in
            name)          FM_NAME="$val" ;;
            description)   FM_DESCRIPTION="$val" ;;
            model)         FM_MODEL="$val" ;;
            when_to_use)   FM_WHEN="$val" ;;
            argument-hint) FM_ARGHINT="$val" ;;
            skills)        current_list="skills" ;;
            hooks|mcpServers|permissionMode) FM_FORBIDDEN="$FM_FORBIDDEN $key" ;;
          esac ;;
      esac
      continue
    fi

    if [ $in_body -eq 1 ]; then
      # Only the paragraph naming the Skill tool matters, and that phrase wraps
      # across lines often enough that looking line-at-a-time misses it.
      if [ -z "$line" ]; then
        case "$para" in *"Skill tool"*) body="$body $para" ;; esac
        para=""
      else
        para="$para $line"
      fi
    fi
  done < "$1"

  case "$para" in *"Skill tool"*) body="$body $para" ;; esac
  [ $closed -eq 1 ] && FM_PARSED=1

  # Backticked names inside that paragraph are the skills the body loads.
  rest="$body"
  while [ -n "$rest" ]; do
    case "$rest" in *'`'*) ;; *) break ;; esac
    rest="${rest#*\`}"
    token="${rest%%\`*}"
    case "$token" in
      ''|*[!a-z0-9-]*) ;;
      *) BODY_LOADED="$BODY_LOADED$token"$'\n' ;;
    esac
    rest="${rest#*\`}"
  done
}

# ------------------------------------------------------------- collection ----

FINDINGS=""
HAS_ERROR=0
add_finding() { FINDINGS="$FINDINGS$1	$2	$3	$4	$5"$'\n'; }

AGENTS_JSON=""; SKILLS_JSON=""; COMMANDS_JSON=""; EDGES_JSON=""

# One `sort` per directory - three forks total, not per file.
list_sorted() {
  [ -d "$1" ] || return 0
  local f
  for f in "$1"/$2; do [ -e "$f" ] && printf '%s\n' "$f"; done | LC_ALL=C sort
}

# --- agents ------------------------------------------------------------------
while IFS= read -r file; do
  [ -n "$file" ] || continue
  parse_file "$file"
  rel="${file#$PLUGIN_ROOT/}"; rel="${rel//\\//}"

  if [ $FM_PARSED -eq 0 ]; then
    add_finding warning FRONTMATTER_UNPARSABLE \
      "no closing --- delimiter, so no frontmatter could be read" "$rel" ""
  fi

  # Declared and loaded disagreeing is exactly the failure that is invisible at
  # runtime: the doctrine arrives on one path and not the other.
  seen=""
  rest="$FM_SKILLS"
  while [ -n "$rest" ]; do
    s="${rest%%$'\n'*}"; if [ "$s" = "$rest" ]; then rest=""; else rest="${rest#*$'\n'}"; fi
    [ -n "$s" ] || continue
    case "$seen" in *"|$s|"*) continue ;; esac
    seen="$seen|$s|"
    case $'\n'"$BODY_LOADED" in
      *$'\n'"$s"$'\n'*) d=false ;;
      *)                d=true  ;;
    esac
    je "$FM_NAME"; a="$JE"; je "$s"
    EDGES_JSON="$EDGES_JSON,{\"agent\":\"$a\",\"skill\":\"$JE\",\"declaredOnly\":$d,\"loadedOnly\":false}"
  done

  rest="$BODY_LOADED"
  while [ -n "$rest" ]; do
    s="${rest%%$'\n'*}"; if [ "$s" = "$rest" ]; then rest=""; else rest="${rest#*$'\n'}"; fi
    [ -n "$s" ] || continue
    case "$seen" in *"|$s|"*) continue ;; esac
    # The load paragraph also backticks prose like `references/scope.md`; only a
    # real skill directory is an edge.
    [ -d "$PLUGIN_ROOT/skills/$s" ] || continue
    seen="$seen|$s|"
    je "$FM_NAME"; a="$JE"; je "$s"
    EDGES_JSON="$EDGES_JSON,{\"agent\":\"$a\",\"skill\":\"$JE\",\"declaredOnly\":false,\"loadedOnly\":true}"
  done

  je "$FM_NAME";        n="$JE"
  je "$rel";            f="$JE"
  je "$FM_DESCRIPTION"; d="$JE"
  je "$FM_MODEL";       m="$JE"
  clen "$FM_DESCRIPTION"; dl=$CLEN
  jarr_lines "$FM_SKILLS";  sk="$JARR"
  jarr_lines "$BODY_LOADED"; ld="$JARR"
  jarr_words "$FM_FORBIDDEN"; fb="$JARR"
  [ $FM_PARSED -eq 1 ] && p=true || p=false

  AGENTS_JSON="$AGENTS_JSON,{\"name\":\"$n\",\"file\":\"$f\",\"description\":\"$d\",\"descriptionLength\":$dl,\"model\":\"$m\",\"skills\":$sk,\"loadedSkills\":$ld,\"forbiddenFields\":$fb,\"parsed\":$p,\"editableFields\":[\"name\",\"description\",\"model\"],\"removableFields\":$fb}"
done <<EOF
$(list_sorted "$PLUGIN_ROOT/agents" '*.md')
EOF

# --- skills ------------------------------------------------------------------
while IFS= read -r dir; do
  [ -n "$dir" ] && [ -d "$dir" ] || continue
  rel="${dir#$PLUGIN_ROOT/}"; rel="${rel//\\//}"

  if [ -f "$dir/SKILL.md" ]; then
    parse_file "$dir/SKILL.md"
    hm=true
  else
    FM_PARSED=0; FM_NAME=""; FM_DESCRIPTION=""; FM_WHEN=""
    hm=false
    add_finding error SKILL_MISSING_MANIFEST "skill directory has no SKILL.md" "$rel" ""
    HAS_ERROR=1
  fi

  name="$FM_NAME"
  [ -n "$name" ] || name="${dir##*/}"
  hr=false; [ -d "$dir/references" ] && hr=true
  [ $FM_PARSED -eq 1 ] && p=true || p=false

  je "$name";           n="$JE"
  je "$rel";            f="$JE"
  je "$FM_DESCRIPTION"; d="$JE"
  je "$FM_WHEN";        w="$JE"
  clen "$FM_DESCRIPTION"; dl=$CLEN
  clen "$FM_WHEN";        wl=$CLEN

  SKILLS_JSON="$SKILLS_JSON,{\"name\":\"$n\",\"dir\":\"$f\",\"description\":\"$d\",\"descriptionLength\":$dl,\"whenToUse\":\"$w\",\"whenToUseLength\":$wl,\"hasManifest\":$hm,\"hasReferences\":$hr,\"parsed\":$p,\"editableFields\":[\"name\",\"description\",\"when_to_use\"],\"removableFields\":[]}"
done <<EOF
$(list_sorted "$PLUGIN_ROOT/skills" '*')
EOF

# --- commands ----------------------------------------------------------------
while IFS= read -r file; do
  [ -n "$file" ] || continue
  parse_file "$file"
  rel="${file#$PLUGIN_ROOT/}"; rel="${rel//\\//}"
  base="${file##*/}"
  [ $FM_PARSED -eq 1 ] && p=true || p=false

  je "${base%.md}";     n="$JE"
  je "$rel";            f="$JE"
  je "$FM_DESCRIPTION"; d="$JE"
  je "$FM_ARGHINT";     ah="$JE"

  COMMANDS_JSON="$COMMANDS_JSON,{\"name\":\"$n\",\"file\":\"$f\",\"description\":\"$d\",\"argumentHint\":\"$ah\",\"parsed\":$p}"
done <<EOF
$(list_sorted "$PLUGIN_ROOT/commands" '*.md')
EOF

# --- findings ----------------------------------------------------------------
FINDINGS_JSON=""
while IFS=$'\t' read -r sev code msg file field; do
  [ -n "$sev" ] || continue
  je "$sev";   s1="$JE"
  je "$code";  s2="$JE"
  je "$msg";   s3="$JE"
  je "$file";  s4="$JE"
  je "$field"; s5="$JE"
  FINDINGS_JSON="$FINDINGS_JSON,{\"severity\":\"$s1\",\"code\":\"$s2\",\"message\":\"$s3\",\"file\":\"$s4\",\"field\":\"$s5\",\"relatedFiles\":[]}"
done <<EOF
$(printf '%s' "$FINDINGS" | LC_ALL=C sort)
EOF

# --- emit --------------------------------------------------------------------
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '')"
je "$ROOT_OUT";    ROOT_ESC="$JE"
je "$PROJECT_OUT"; PROJ_ESC="$JE"

printf '{"schemaVersion":"%s","generatedAt":"%s","mode":"%s","root":"%s","projectRoot":"%s",' \
  "$SCHEMA_VERSION" "$GENERATED_AT" "$MODE" "$ROOT_ESC" "$PROJ_ESC"
printf '"agents":[%s],'    "${AGENTS_JSON#,}"
printf '"skills":[%s],'    "${SKILLS_JSON#,}"
printf '"commands":[%s],'  "${COMMANDS_JSON#,}"
printf '"loadEdges":[%s],' "${EDGES_JSON#,}"
printf '"findings":[%s]}\n' "${FINDINGS_JSON#,}"

[ $HAS_ERROR -eq 1 ] && exit 1
exit 0
