#!/bin/sh
# openccu-lite: the boot's warnings against an allowlist.
#
# Reads `journalctl -p warning -o short` lines (as lite-qemu-test.sh's guest driver hands them on,
# with its "  | " prefix, or plain) and prints every warning that no line of the allowlist explains.
# A new warning fails: it is either fixed or added to the allowlist with the reason it may stay.
#
#   lite-boot-warnings.sh <allowlist> [journal file]     (stdin without a file)
#
# Each warning is reduced to "<identifier>: <message>" - the time, the host name and the pid go,
# continuation lines (a stack trace's indented lines, whether journalctl indented them or the
# daemon logged each line as an entry of its own) are dropped - before it is matched.
#
# The allowlist: one line per allowed warning, "<extended regular expression> ## <reason>". The
# expression is matched against the reduced line (anchor it yourself); the reason is required.
# Empty lines and lines starting with "#" are comments. A line without a reason fails the check, so
# nothing gets in without saying why.
#
# Exit: 0 every warning allowed, 1 a warning the allowlist does not explain, 2 a bad allowlist.
set -u
ALLOW=${1:?allowlist}
[ -r "$ALLOW" ] || { echo "lite-boot-warnings: cannot read $ALLOW" >&2; exit 2; }
shift
awk -v allowfile="$ALLOW" '
BEGIN {
  n = 0; bad = 0
  while ((getline l < allowfile) > 0) {
    if (l ~ /^[ \t]*$/ || l ~ /^#/) continue
    i = index(l, " ## ")
    reason = i ? substr(l, i + 4) : ""
    if (i == 0 || reason ~ /^[ \t]*$/) { printf "lite-boot-warnings: %s: no reason: %s\n", allowfile, l > "/dev/stderr"; bad = 1; continue }
    re[++n] = substr(l, 1, i - 1)
  }
  close(allowfile)
  if (bad) exit 2
  seen = 0; new = 0
}
{
  line = $0
  sub(/^  \| /, "", line)
  if (line ~ /^\[rc=/ || line ~ /^-- / || line ~ /^[ \t]*$/) next
  # an indented line continues the entry above it (journalctl indents the rest of a multi-line message)
  if (line ~ /^[ \t]/) next
  # "Oct 10 19:57:01 host ident[pid]: message"
  if (!sub(/^[A-Z][a-z][a-z] [ 0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9](\.[0-9]+)? [^ ]+ /, "", line)) next
  sub(/\[[0-9]+\]: /, ": ", line)
  # a Java stack trace written to stdout is one entry per line: its "\tat ..." lines start with
  # blanks after the identifier and belong to the entry above them
  if (line ~ /^[^ :]+: [ \t]/) next
  seen++
  for (k = 1; k <= n; k++) if (line ~ re[k]) next
  new++
  print "new warning: " line
}
END {
  if (bad) exit 2
  printf "lite-boot-warnings: %d warning(s), %d not in the allowlist\n", seen, new
  exit new ? 1 : 0
}' "$@"
