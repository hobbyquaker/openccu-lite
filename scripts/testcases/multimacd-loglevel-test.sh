#!/bin/sh
# openccu-lite task 101: multimacd's own level in S60multimacd.
#
# The function is cut out of the init script and run against a syslog file the way start() does
# it (the script's defaults, then `. /etc/config/syslog`), so what is tested is the script's own
# code:
#   - LOGLEVEL_MULTIMACD set: multimacd runs with it;
#   - unset, empty or not one of eQ-3's levels (0-6): multimacd runs with LOGLEVEL_RFD, as before;
#   - no LOGLEVEL_RFD either: the script's default 5.
# And both start-stop-daemon lines of the script take the function's answer, none rfd's directly.
#
# Usage: sh scripts/testcases/multimacd-loglevel-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$HERE/buildroot-external/overlay/RFD/etc/init.d/S60multimacd"
[ -f "$SCRIPT" ] || { echo "missing $SCRIPT"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
sed -n '/^multimacdLogLevel() {/,/^}/p' "$SCRIPT" > "$T/fn.sh"
grep -q '^multimacdLogLevel() {' "$T/fn.sh" || { echo "multimacdLogLevel not found in $SCRIPT"; exit 2; }
# the script's own defaults, as its top lines set them
grep -E '^LOGLEVEL_(RFD|MULTIMACD)=' "$SCRIPT" > "$T/defaults.sh"

fails=0
ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# level <syslog file content>: the level multimacd would start with
level() {
  printf '%s\n' "$1" > "$T/syslog"
  # an inherited LOGLEVEL_MULTIMACD must not count: the defaults reset it, as in the script
  LOGLEVEL_MULTIMACD=9 ${MULTIMACD_TEST_SHELL:-sh} -c '. "$1"; . "$2"; . "$3"; multimacdLogLevel' sh "$T/defaults.sh" "$T/fn.sh" "$T/syslog"
}

check() { # <name> <want> <syslog content>
  got=$(level "$3")
  [ "$got" = "$2" ] && ok "$1: $got" || fail "$1: got '$got', want '$2'"
}

check "set"                         1 "$(printf 'LOGLEVEL_RFD=5\nLOGLEVEL_MULTIMACD=1')"
check "set, rfd at debug"           5 "$(printf 'LOGLEVEL_RFD=1\nLOGLEVEL_MULTIMACD=5')"
check "set in quotes"               2 "$(printf 'LOGLEVEL_RFD=5\nLOGLEVEL_MULTIMACD="2"')"
check "unset: rfd's"                4 "LOGLEVEL_RFD=4"
check "empty: rfd's"                2 "$(printf 'LOGLEVEL_RFD=2\nLOGLEVEL_MULTIMACD=')"
check "a name: rfd's"               4 "$(printf 'LOGLEVEL_RFD=4\nLOGLEVEL_MULTIMACD=debug')"
check "two digits: rfd's"           4 "$(printf 'LOGLEVEL_RFD=4\nLOGLEVEL_MULTIMACD=12')"
check "7: rfd's"                    4 "$(printf 'LOGLEVEL_RFD=4\nLOGLEVEL_MULTIMACD=7')"
check "commented out: rfd's"        2 "$(printf 'LOGLEVEL_RFD=2\n# LOGLEVEL_MULTIMACD=1')"
check "no file content: default 5"  5 ""

# both start lines use the function; no line starts multimacd with rfd's level directly
n=$(grep -c -- '--exec /bin/multimacd -- -f /var/etc/multimacd.conf -l "$(multimacdLogLevel)"' "$SCRIPT")
[ "$n" = 2 ] && ok "both start-stop-daemon lines take multimacdLogLevel" || fail "$n start lines take multimacdLogLevel, want 2"
grep -q -- '-l ${LOGLEVEL_RFD}' "$SCRIPT" && fail "a line still passes LOGLEVEL_RFD directly" || ok "no line passes LOGLEVEL_RFD directly"
# the syslog file is sourced before the first start line, so the function sees the file's keys
src=$(grep -n '\. /etc/config/syslog' "$SCRIPT" | head -1 | cut -d: -f1)
first=$(grep -n 'multimacdLogLevel)"' "$SCRIPT" | sed -n 2p | cut -d: -f1)
[ -n "$src" ] && [ -n "$first" ] && [ "$src" -lt "$first" ] && ok "the syslog file is read before start() starts multimacd" || fail "syslog sourced at line '$src', start at '$first'"

[ "$fails" -eq 0 ] && echo "multimacd-loglevel-test: all passed" || echo "multimacd-loglevel-test: $fails failed"
[ "$fails" -eq 0 ]
