#!/bin/sh
# openccu-lite: upstream's shellcheck rules over the lite delta - the scripts under
# buildroot-external/overlay/lite*, board/lite and scripts/ (a shell shebang; Tcl and Python are
# not shell), with the options OpenCCU's own CI passes to shellcheck. Warnings and errors fail;
# info and style findings are printed and do not (the tests' `a && ok || bad` idiom is a style
# note). So "would upstream take this?" has a mechanical answer on every push.
#
# Usage: scripts/lite-shellcheck.sh [repository root]     exit 1 with file:line: message per finding
set -u
ROOT=${1:-$(cd "$(dirname "$0")/.." && pwd)}
cd "$ROOT" || exit 2
command -v shellcheck >/dev/null 2>&1 || { echo "lite-shellcheck: shellcheck is not installed" >&2; exit 2; }

LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT
git ls-files buildroot-external/overlay board/lite scripts | grep '^buildroot-external/overlay/lite\|^board/lite/\|^scripts/' | while IFS= read -r f; do
  [ -f "$f" ] || continue
  IFS= read -r first <"$f" || continue
  case "$first" in
    '#!'*tclsh*|'#!'*python*|'#!'*expect*) ;;
    '#!'*sh*) echo "$f" ;;
  esac
done | LC_ALL=C sort >"$LIST"
n=$(wc -l <"$LIST" | tr -d ' ')
[ "$n" -gt 0 ] || { echo "lite-shellcheck: no shell script found under $ROOT" >&2; exit 2; }

# upstream's ci.yml: the SC30xx checks it silences for busybox ash's [[ ]] and the like
export SHELLCHECK_OPTS="${SHELLCHECK_OPTS:--e SC3010 -e SC3014 -e SC3057 -e SC3036 -e SC3028 -e SC3020}"
if xargs -a "$LIST" shellcheck -S warning -f gcc; then
  echo "lite-shellcheck: $n scripts, no warning or error"
  exit 0
fi
echo "lite-shellcheck: findings above (warnings and errors fail; run shellcheck without -S warning for the style notes)" >&2
exit 1
