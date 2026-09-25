#!/bin/sh
# openccu-lite: the lab boot check for "the journal is the one log" (D-59). Run on a booted box:
#
#   ssh root@<box> 'sh -s' < scripts/lite-log-inventory.sh
#
# It lists
#   1. every regular file a process has open that is named like a log (*.log, *.log.N) or lives
#      under /var/log outside the journal, with the process and its unit;
#   2. every regular file named like a log under /var, /tmp, /run and /usr/local
#      (node_modules and the journal directories are left out).
#
# Each line is one of
#   FAIL    a log file of the system - the check fails;
#   REPORT  a file of an addon (under /usr/local/addons, an addon's /tmp installer file, or opened by
#           an addon-*.service process): the addon's own project owns it, so it is reported, not failed;
#   OK      a documented exception: /usr/local/var/recovery/*.log, the recovery's install log waiting
#           to be carried into the journal (task 145; the recovery writes it, occulited removes it).
#
# Exit 1 when there is a FAIL line, 0 otherwise.
set -u

fails=0
reports=0
SEEN=$(mktemp)
trap 'rm -f "$SEEN"' EXIT

size() { wc -c <"$1" 2>/dev/null | tr -d ' '; }

# classify <path> [unit]: prints FAIL, REPORT or OK
classify() {
  case "$1" in
    /usr/local/var/recovery/*.log) echo OK; return ;;
    /usr/local/addons/*|/usr/local/etc/config/addons/*|/tmp/*addon*|/tmp/*-inst.*) echo REPORT; return ;;
  esac
  case "${2:-}" in addon-*) echo REPORT; return ;; esac
  echo FAIL
}

emit() {  # emit <verdict> <text>
  echo "$1 $2"
  case "$1" in FAIL) fails=$((fails+1)) ;; REPORT) reports=$((reports+1)) ;; esac
}

logname() {
  case "$1" in
    /var/log/journal/*|/run/log/journal/*|/usr/local/var/log/journal/*) return 1 ;;
    *.log|*.log.[0-9]|*.log.[0-9][0-9]|/var/log/*) return 0 ;;
  esac
  return 1
}

echo "== open files"
for p in /proc/[0-9]*; do
  pid=${p#/proc/}
  for fd in "$p"/fd/*; do
    t=$(readlink "$fd" 2>/dev/null) || continue
    case "$t" in /*) ;; *) continue ;; esac
    [ -f "$t" ] || continue
    logname "$t" || continue
    # one line per process and file, however many descriptors it holds on it
    grep -qxF "$pid $t" "$SEEN.pids" 2>/dev/null && continue
    echo "$pid $t" >>"$SEEN.pids"
    comm=$(cat "$p/comm" 2>/dev/null)
    unit=$(sed -n 's|^0::.*/\([^/]*\.service\).*|\1|p' "$p/cgroup" 2>/dev/null | head -1)
    v=$(classify "$t" "$unit")
    emit "$v" "open pid=$pid comm=$comm unit=${unit:--} $t ($(size "$t") bytes)"
    echo "$t" >>"$SEEN"
  done
done

echo "== files named like logs"
find /var /tmp /run /usr/local \( -name node_modules -o -path /var/log/journal -o -path /run/log/journal -o -path /usr/local/var/log/journal -o -path /proc \) -prune \
  -o -type f \( -name '*.log' -o -name '*.log.[0-9]' -o -name '*.log.[0-9][0-9]' \) -print 2>/dev/null | sort -u |
while IFS= read -r f; do
  grep -qxF "$f" "$SEEN" && continue
  echo "$(classify "$f") file $f ($(size "$f") bytes)"
done > "$SEEN.files"
while IFS= read -r line; do
  set -- $line
  emit "$1" "${line#* }"
done < "$SEEN.files"
# anything regular directly under /var/log that is not named *.log
for f in /var/log/*; do
  [ -f "$f" ] || continue
  case "$f" in *.log|*.log.[0-9]*) continue ;; esac
  grep -qxF "$f" "$SEEN" && continue
  emit "$(classify "$f")" "file $f ($(size "$f") bytes)"
done
rm -f "$SEEN.files"

echo "== result: $fails FAIL, $reports REPORT"
[ "$fails" -eq 0 ]
