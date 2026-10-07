#!/bin/sh
# openccu-lite B-307: lite-radio-gate, an ExecCondition= of every radio unit, refuses a start while a
# radio change holds the units (/run/occulite/radio/changing, its line a deadline in seconds of
# /proc/uptime) and lets it through without the marker or past its deadline. Exit 1 skips the unit
# (inactive, not failed), exit 0 starts it. Then the five units: each carries the check, as root,
# after its plan marker. Nothing needs root.
#
# Usage: sh scripts/testcases/lite-radio-gate-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
CHK="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-radio-gate"
U="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system"
[ -f "$CHK" ] || { echo "lite-radio-gate not found at $CHK"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

DIR="$T/radio"
mkdir -p "$DIR"
uptime() { printf '%s 12345.67\n' "$1" > "$T/uptime"; }

expect() { # rc what
  OCCU_RADIO_RUN_DIR="$DIR" OCCU_UPTIME="$T/uptime" sh "$CHK" rfd > "$T/out" 2>&1
  rc=$?
  if [ "$rc" = "$1" ]; then ok "$2"; else bad "$2 (exit $rc: $(cat "$T/out"))"; fi
}

[ -x "$CHK" ] && ok "the check is executable" || bad "$CHK must be executable"
uptime 600.25
expect 0 "no change running: the unit starts"
printf '900\n' > "$DIR/changing"
expect 1 "a change holds the units: the start is skipped"
grep -q 'rfd is started by the change' "$T/out" && ok "the journal line names the unit and why" || bad "the line: $(cat "$T/out")"
uptime 899.99
expect 1 "one second before the deadline: still held"
uptime 900.00
expect 0 "at the deadline: the gate no longer holds"
uptime 4000.5
expect 0 "long past the deadline (the change died): the unit starts"
printf '900' > "$DIR/changing"
uptime 100
expect 1 "a deadline without a newline holds as well"
: > "$DIR/changing"
expect 1 "an empty marker holds (it is never written so)"
printf 'soon\n' > "$DIR/changing"
expect 1 "a marker that is no number holds"
printf '900\n' > "$DIR/changing"
rm -f "$T/uptime"
expect 1 "no readable uptime: held while the marker is there"
# the change lets the units through one by one, in boot order, as it starts them
uptime 100
printf '900\nmultimacd\n' > "$DIR/changing"
expect 1 "multimacd let through, rfd still held"
printf '900\nmultimacd\nrfd\n' > "$DIR/changing"
expect 0 "rfd let through: the change's own start"
grep -q 'let through by the radio change' "$T/out" && ok "the journal line says it is the change's start" || bad "the line: $(cat "$T/out")"
printf '900\nrfd-other\nxrfd\n' > "$DIR/changing"
expect 1 "only the unit's exact name lets it through"
printf 'rfd\n' > "$DIR/changing"
expect 1 "a name on the deadline's line lets nothing through"
rm -f "$DIR/changing"
expect 0 "the marker gone: the unit starts"

# the units
for d in multimacd rfd hmipserver hs485d hmlangw; do
  f="$U/$d.service"
  marker=$(grep -n "^ExecCondition=/bin/sh -c 'test -e /run/occulite/radio/$d.enabled'\$" "$f" | cut -d: -f1)
  gate=$(grep -n "^ExecCondition=+/usr/libexec/occu/lite-radio-gate $d\$" "$f" | cut -d: -f1)
  start=$(grep -n '^ExecStart=' "$f" | head -1 | cut -d: -f1)
  if [ -n "$gate" ] && [ -n "$marker" ] && [ -n "$start" ] && [ "$marker" -lt "$gate" ] && [ "$gate" -lt "$start" ]; then
    ok "$d.service: the radio change's gate, as root, after its plan marker"
  else
    bad "$d.service: needs ExecCondition=+/usr/libexec/occu/lite-radio-gate $d after the plan marker and before ExecStart= (marker $marker, gate $gate, start $start)"
  fi
  [ "$(grep -c 'lite-radio-gate' "$f")" = 1 ] && ok "$d.service: one gate" || bad "$d.service: the gate $(grep -c 'lite-radio-gate' "$f") times"
done

[ "$fails" = 0 ] && echo "lite-radio-gate: all cases passed" || { echo "lite-radio-gate: $fails case(s) failed"; exit 1; }
