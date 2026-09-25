#!/bin/sh
# openccu-lite: no task, decision or bug ids in what the lite overlays put in front of a user.
#
# "Edit unit..." on the Services page shows `systemctl cat`, the Log page shows the journal, and
# /etc on the box is there to be read. Roadmap references ("task 20", "D-30", "B-3", "Q-5",
# "OQ-1", "28.8") mean nothing there. Checked: every file under buildroot-external/overlay/lite*/,
# and every file of the other overlays (the ones shared with upstream, which the lite images carry
# as well) that says "openccu-lite" - a lite edit of an upstream file:
#
#   - every file that is not a script (units, drop-ins, timers, targets, presets, the
#     journald/system drop-ins, the configuration templates, lighttpd's fragments): whole file;
#   - scripts (a #! first line): every line that is not a comment, and the whole body of every
#     here-document, comment lines included - that is the unit text a generator writes and the
#     messages a script prints;
#   - scripts that are themselves copied somewhere a user reads them (WHOLE_SCRIPTS): whole file.
#
# Comments of the other scripts are for developers and are not checked.
#
# Usage: scripts/lite-id-guard.sh [repository root]     exit 1 with file:line: text per finding
set -u

ROOT=${1:-$(cd "$(dirname "$0")/.." && pwd)}
cd "$ROOT" || exit 2

# installed onto the userfs as an addon's rc.d script (lite-addon-rc)
WHOLE_SCRIPTS="usr/libexec/occu/addon-rc-wrapper"

# (^|non-word)X-n for D, B, OQ, Q, A; "task n"/"tasks n"/"Aufgabe n"; a sub-task number like
# 28.8 or 27.4 that is not part of a longer dotted number (127.0.0.1, 3.89.8). No interval
# expressions ({1,2}): mawk 1.3.4-20200120 (Debian bookworm's) has none and would match nothing.
ID_RE='(^|[^A-Za-z0-9_-])(D|B|OQ|Q|A)-[0-9]+|[Tt]asks? [0-9]+|Aufgabe [0-9]+|(^|[^0-9.])[1-9][0-9]\.[0-9][0-9]?([^0-9.]|$)'

set -- buildroot-external/overlay/lite*
[ -d "$1" ] || { echo "lite-id-guard: no buildroot-external/overlay/lite* under $ROOT" >&2; exit 2; }

LIST=$(mktemp)
FOUND=$(mktemp)
trap 'rm -f "$LIST" "$FOUND"' EXIT
{
  find "$@" -type f
  # the shared overlays: only the files with a lite edit - upstream's own text is not ours to judge
  for d in buildroot-external/overlay/*; do
    case "$d" in buildroot-external/overlay/lite*) continue ;; esac
    [ -d "$d" ] && grep -rlF 'openccu-lite' "$d"
  done
} | LC_ALL=C sort >"$LIST"

checked=0
while IFS= read -r f; do
  checked=$((checked + 1))
  mode=whole
  first=
  IFS= read -r first <"$f" || :
  if case "$first" in '#!'*) true ;; *) false ;; esac; then
    mode=script
    for w in $WHOLE_SCRIPTS; do
      case "$f" in */"$w") mode=whole ;; esac
    done
  fi
  # the regex goes through the environment: gawk processes escape sequences in -v values and
  # turns the "\." of ID_RE into "any character" (mawk does not, which hid it on a workstation)
  ID_RE="$ID_RE" awk -v mode="$mode" -v file="$f" '
    function hit(line) { if (line ~ ENVIRON["ID_RE"]) printf "%s:%d: %s\n", file, FNR, line }
    mode == "whole" { hit($0); next }
    # script mode: here-document bodies in full, everything else but comment-only lines
    heredoc != "" {
      t = $0
      if (strip_tabs) sub(/^\t+/, "", t)
      if (t == heredoc) { heredoc = ""; next }
      hit($0); next
    }
    /^[ \t]*#/ { next }
    {
      hit($0)
      if (match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/)) {
        tok = substr($0, RSTART, RLENGTH)
        strip_tabs = (tok ~ /^<<-/)
        sub(/^<<-?[ \t]*/, "", tok)
        gsub(/["\047]/, "", tok)
        heredoc = tok
      }
    }
  ' "$f" >>"$FOUND"
done <"$LIST"

if [ -s "$FOUND" ]; then
  cat "$FOUND"
  echo "lite-id-guard: $(wc -l <"$FOUND") line(s) with a task, decision or bug id in $checked files checked" >&2
  exit 1
fi
echo "lite-id-guard: $checked files checked, no ids"
exit 0
