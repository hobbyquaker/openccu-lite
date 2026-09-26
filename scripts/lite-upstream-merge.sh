#!/bin/sh
# openccu-lite: settles a merge of an upstream OpenCCU tag into lite along
# scripts/lite-upstream-paths.txt. The fork has removed upstream files (the Home Assistant add-ons,
# upstream's CI, the OCI product, ...) and rewritten some as its own (the issue forms,
# CONTRIBUTING.md). A tag that changes a removed file stops the merge with a modify/delete
# conflict, a tag that adds a file under a removed directory brings it back without one, and a
# tag that changes a rewritten file conflicts or, worse, merges into it. This script, run while
# the merge is uncommitted:
#
#   - removes every `remove` path again (index and working tree), conflicted or not;
#   - takes every `ours` path from lite (HEAD) whole, and removes files upstream added under it;
#   - lists the conflicts that are left - those are real ones and are resolved by hand.
#
# Usage:
#   git merge --no-commit <upstream tag>
#   scripts/lite-upstream-merge.sh           settle the list's paths, print what is left
#   scripts/lite-upstream-merge.sh --check   change nothing; exit 1 if a removed path is tracked
#                                            or (during a merge) an `ours` path differs from HEAD
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 2
LIST=${LITE_UPSTREAM_PATHS:-scripts/lite-upstream-paths.txt}
[ -f "$LIST" ] || { echo "lite-upstream-merge: $LIST not found" >&2; exit 2; }
CHECK=
case "${1:-}" in
  --check) CHECK=1 ;;
  '') ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac
MERGING=
git rev-parse -q --verify MERGE_HEAD >/dev/null && MERGING=1
if [ -z "$CHECK" ] && [ -z "$MERGING" ]; then
  echo "lite-upstream-merge: no merge in progress (run it after git merge --no-commit <tag>);" \
    "settling the working tree anyway" >&2
fi
bad=0

# the `remove` pathspecs, in one call so the :(exclude) lines apply to the others
set --
while read -r kw spec; do
  [ "$kw" = remove ] && [ -n "$spec" ] && set -- "$@" "$spec"
done <"$LIST"
if [ $# -gt 0 ]; then
  if [ -n "$CHECK" ]; then
    left=$(git ls-files -- "$@" | sort -u)
    if [ -n "$left" ]; then
      echo "lite-upstream-merge: removed upstream paths are tracked again:" >&2
      printf '%s\n' "$left" | sed 's/^/  /' >&2
      bad=1
    fi
  else
    n=$(git ls-files -- "$@" | sort -u | wc -l | tr -d ' ')
    git rm -r -q -f --ignore-unmatch -- "$@" || exit 1
    echo "lite-upstream-merge: $n removed upstream path(s) deleted again"
  fi
fi

# the `ours` pathspecs: lite's version whole
set --
while read -r kw spec; do
  [ "$kw" = ours ] && [ -n "$spec" ] && set -- "$@" "$spec"
done <"$LIST"
if [ $# -gt 0 ]; then
  if [ -n "$CHECK" ]; then
    if [ -n "$MERGING" ] && ! git diff --cached --quiet HEAD -- "$@"; then
      echo "lite-upstream-merge: lite's own files differ from lite:" >&2
      git diff --cached --name-status HEAD -- "$@" >&2
      bad=1
    fi
  else
    FILES=$(mktemp) || exit 2
    trap 'rm -f "$FILES"' EXIT
    { git ls-files -- "$@"; git ls-tree -r --name-only HEAD -- "$@"; } | sort -u >"$FILES"
    n=0
    while IFS= read -r f; do
      if git cat-file -e "HEAD:$f" 2>/dev/null; then
        git checkout -q HEAD -- "$f" || exit 1
      else
        git rm -q -f -- "$f" || exit 1
      fi
      n=$((n+1))
    done <"$FILES"
    echo "lite-upstream-merge: $n file(s) of lite's own taken from lite"
  fi
fi

conflicts=$(git diff --name-only --diff-filter=U)
if [ -n "$conflicts" ]; then
  echo "lite-upstream-merge: conflicts left to resolve by hand:"
  printf '%s\n' "$conflicts" | sed 's/^/  /'
  [ -n "$CHECK" ] && bad=1
fi
exit $bad
