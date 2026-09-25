#!/bin/sh
# openccu-lite: no shipped configuration names a log file.
#
# The journal is the one log on an openccu-lite box (D-59). A configuration that names a *.log
# file is a file log coming back - after a rebase, a new package or a copied upstream fragment -
# and it would grow on the /var tmpfs or wear the SD card. This runs at the end of the lite
# post-build against the image's root and fails the build on a finding.
#
# Checked: every regular text file under etc/, usr/lib/systemd/ and usr/lib/tmpfiles.d/ that is not
# a script (no #! first line) - the configuration files, units, drop-ins, templates. Comment lines
# (# or ;) are skipped. A finding is a file name ending in .log or .log.N: "lighttpd-error.log",
# "${X}.log", "hm2mqtt.log.1" - not ".log" alone (a MIME table), not "debug.log-request-handling"
# (a lighttpd switch).
#
# The documented exceptions:
#   - the recovery system and the install phase of an update keep their file log
#     (/tmp/fwinstall.log); they live in the recovery system's own image, not under this root;
#   - etc/inittab: busybox init's table, which a systemd product never reads; its sysinit lines
#     name /tmp/boot.log.
#
# Usage: scripts/lite-log-guard.sh <image root>     exit 1 with file:line: text per finding
set -u

ROOT=${1:?usage: lite-log-guard.sh <image root>}
[ -d "$ROOT/etc" ] || { echo "lite-log-guard: $ROOT has no etc/" >&2; exit 2; }
cd "$ROOT" || exit 2

EXCEPTIONS="etc/inittab"
LOG_RE='[A-Za-z0-9_}]\.log(\.[0-9]+)?([^A-Za-z0-9_.-]|$)'

LIST=$(mktemp)
FOUND=$(mktemp)
trap 'rm -f "$LIST" "$FOUND"' EXIT
for d in etc usr/lib/systemd usr/lib/tmpfiles.d; do
  [ -d "$d" ] && find "$d" -type f
done | LC_ALL=C sort >"$LIST"

checked=0
while IFS= read -r f; do
  skip=
  for e in $EXCEPTIONS; do [ "$f" = "$e" ] && skip=1; done
  [ -n "$skip" ] && continue
  # text only, and no scripts
  grep -Iq . "$f" 2>/dev/null || continue
  first=
  IFS= read -r first <"$f" || :
  case "$first" in '#!'*) continue ;; esac
  checked=$((checked + 1))
  grep -nE "$LOG_RE" "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*[#;]' | sed "s|^|$f:|" >>"$FOUND"
done <"$LIST"

if [ -s "$FOUND" ]; then
  cat "$FOUND"
  echo "lite-log-guard: $(wc -l <"$FOUND") line(s) naming a log file in $checked configuration files" >&2
  exit 1
fi
echo "lite-log-guard: $checked configuration files checked, no log files named"
