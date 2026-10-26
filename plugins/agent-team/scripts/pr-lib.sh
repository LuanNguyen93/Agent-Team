#!/usr/bin/env bash
# Shared helpers for pr-gather.sh and pr-create.sh. Source it; do not run it.

# pr_urldecode <s> - "My%20Project" -> "My Project". `%` escaped for bash 3.2.
pr_urldecode() { printf '%b' "${1//\%/\\x}"; }

# pr_parse_remote <url> -> PR_PROVIDER (github|gitlab|azure|unknown), and for
# azure PR_ORG (org URL) / PR_PROJECT / PR_REPO; for github/gitlab PR_ORG is the
# owner/group and PR_REPO the repo. Never guesses: an unparseable URL is
# "unknown", and the caller decides what that means.
pr_parse_remote() {
  local url="$1" rest host
  PR_PROVIDER="unknown"; PR_ORG=""; PR_PROJECT=""; PR_REPO=""
  url="${url%.git}"; url="${url%/}"
  case "$url" in
    *github.com[:/]*)
      PR_PROVIDER="github"; rest="${url#*github.com}"; rest="${rest#[:/]}"
      PR_ORG="${rest%%/*}"; PR_REPO="${rest#*/}" ;;
    *gitlab.com[:/]*|*gitlab.*[:/]*)
      PR_PROVIDER="gitlab"; rest="${url#*gitlab*}"; rest="${rest#[:/]}"; rest="${rest#*[:/]}"
      PR_ORG="${rest%/*}"; PR_REPO="${rest##*/}" ;;
    git@ssh.dev.azure.com:v3/*)
      PR_PROVIDER="azure"; rest="${url#git@ssh.dev.azure.com:v3/}"
      PR_ORG="https://dev.azure.com/${rest%%/*}"; rest="${rest#*/}"
      PR_PROJECT="${rest%%/*}"; PR_REPO="${rest#*/}" ;;
    *dev.azure.com/*)
      PR_PROVIDER="azure"; rest="${url#*dev.azure.com/}"
      PR_ORG="https://dev.azure.com/${rest%%/*}"; rest="${rest#*/}"
      case "$rest" in
        _git/*) PR_REPO="${rest#_git/}"; PR_PROJECT="$PR_REPO" ;;
        *) PR_PROJECT="${rest%%/_git/*}"; PR_REPO="${rest##*/_git/}" ;;
      esac ;;
    *.visualstudio.com/*)
      PR_PROVIDER="azure"; host="${url#*://}"; host="${host%%/*}"; host="${host#*@}"
      PR_ORG="https://${host}"; rest="${url#*"${host}"/}"
      case "$rest" in
        _git/*) PR_REPO="${rest#_git/}"; PR_PROJECT="$PR_REPO" ;;
        *) PR_PROJECT="${rest%%/_git/*}"; PR_REPO="${rest##*/_git/}" ;;
      esac ;;
  esac
  PR_PROJECT="$(pr_urldecode "$PR_PROJECT")"; PR_REPO="$(pr_urldecode "$PR_REPO")"
  [ "$PR_PROVIDER" != "unknown" ]
}

# pr_default_branch <repo> - the remote default from origin/HEAD, or empty.
pr_default_branch() {
  local head
  head="$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" || { printf ''; return; }
  printf '%s' "${head#origin/}"
}

# pr_resolve_base <repo> - develop if origin has it, else the remote default,
# else main. A hardcoded default is the most common way a PR gets the wrong base.
pr_resolve_base() {
  local d
  if git -C "$1" show-ref --verify --quiet refs/remotes/origin/develop; then printf 'develop'; return; fi
  d="$(pr_default_branch "$1")"
  printf '%s' "${d:-main}"
}
