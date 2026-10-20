#!/bin/sh
# openccu-lite: lite-addon-delay, an addon's start delay at boot (task 369). With a stand-in
# systemctl (is-system-running answers what the case says) and a stand-in sleep that records its
# argument: it waits the seconds while the system boots, not on a later start, and never refuses a
# start - a bad argument or an unknown state is no delay, exit 0 every time.
#
# Usage: sh scripts/testcases/lite-addon-delay-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
D="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-addon-delay"
[ -x "$D" ] || { echo "$D not found or not executable"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
printf '#!/bin/sh\n[ "$1" = is-system-running ] || exit 2\ncat "%s/state" 2>/dev/null\n[ "$(cat "%s/state" 2>/dev/null)" = running ]\n' "$T" "$T" > "$T/systemctl"
printf '#!/bin/sh\necho "$1" >> "%s/slept"\n' "$T" > "$T/sleep"
chmod 755 "$T/systemctl" "$T/sleep"

# case <state> <name> <seconds> <want-slept or -> <description>
case_() {
  rm -f "$T/slept"
  if [ "$1" = none ]; then rm -f "$T/state"; else echo "$1" > "$T/state"; fi
  out=$(OCCU_SYSTEMCTL="$T/systemctl" OCCU_SLEEP="$T/sleep" sh "$D" "$2" "$3" 2>&1)
  rc=$?
  got=$(cat "$T/slept" 2>/dev/null || echo -)
  if [ "$rc" = 0 ] && [ "$got" = "$4" ]; then ok "$5"; else bad "$5: rc $rc, slept $got, out: $out"; fi
}
case_ starting redmatic 30 30 "booting: waits the delay"
case_ initializing hmm 600 600 "initializing: waits, up to 600 s"
case_ running redmatic 30 - "running: a later start does not wait"
case_ degraded redmatic 30 - "degraded: no wait"
case_ none redmatic 30 - "no state (no systemctl answer): no wait"
case_ starting redmatic 0 - "0: no delay"
case_ starting redmatic 601 - "601: out of range, no delay"
case_ starting redmatic 3x - "not a number: no delay"
case_ starting redmatic "" - "no seconds: no delay"
case_ starting "../x" 30 - "a bad name: nothing"
case_ starting "" 30 - "no name: nothing"
echo starting > "$T/state"
out=$(OCCU_SYSTEMCTL="$T/systemctl" OCCU_SLEEP="$T/sleep" sh "$D" redmatic 30)
[ "$out" = "lite-addon-delay: redmatic waits 30 s after its radio interfaces" ] && ok "the journal line" || bad "journal line: $out"

[ "$fails" = 0 ] && echo "lite-addon-delay: all cases passed" || { echo "lite-addon-delay: $fails case(s) failed"; exit 1; }
