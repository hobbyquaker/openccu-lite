#!/bin/sh
# openccu-lite: lite-init-addons runs `init` on the rc.d entries the way S55InitAddons' run-parts
# did - and never on a <name>.script, the addon's own script behind the addon-rc wrapper, which
# busybox run-parts ran directly as root at every boot (its name filter takes a dot). A fake rc.d,
# hm_mode, safemode and rc.prelocal; nothing needs root.
#
# Usage: sh scripts/testcases/lite-init-addons-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
INIT="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-init-addons"
[ -f "$INIT" ] || { echo "lite-init-addons not found at $INIT"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/rc.d/adir"
LOG="$T/calls"
entry() { # name [mode]
  printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$1" "$LOG" > "$T/rc.d/$1"; chmod "${2:-755}" "$T/rc.d/$1"
}
entry wrapped; entry wrapped.script; entry plain; entry .hidden; entry 'odd@name'; entry noexec 644; entry failing
printf '#!/bin/sh\necho "failing $*" >> "%s"\nexit 1\n' "$LOG" > "$T/rc.d/failing"
printf '#!/bin/sh\necho "prelocal" >> "%s"\n' "$LOG" > "$T/prelocal"; chmod 755 "$T/prelocal"
printf "HM_MODE='NORMAL'\nHM_HOST='rpi4'\n" > "$T/hm_mode"
: > "$T/oom"

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
run() { # hm_mode-file safemode-file action
  : > "$LOG"
  OCCU_ADDON_RCD="$T/rc.d" OCCU_HM_MODE_FILE="$1" OCCU_SAFEMODE_FILE="$2" OCCU_RC_PRELOCAL="$T/prelocal" OCCU_OOM_SCORE_FILE="$T/oom" \
    sh "$INIT" "$3" > "$T/out" 2>&1
}

# 1. the normal boot: rc.prelocal first, then init on every entry that run-parts would take, in name
#    order; a failing script stops nothing; the exit is 0 and the console line is S55's
run "$T/hm_mode" "$T/nosafemode" start; rc=$?
[ "$rc" = 0 ] && ok "start exits 0 although an entry failed" || bad "start exits $rc"
got=$(tr '\n' '|' < "$LOG")
[ "$got" = "prelocal|failing init|plain init|wrapped init|" ] && ok "rc.prelocal first, then init on the entries in name order" || bad "calls: $got"
grep -q "wrapped.script" "$LOG" && bad "a .script was run directly" || ok "no <name>.script is run (busybox run-parts did)"
grep -q "hidden\|odd@name\|noexec" "$LOG" && bad "a hidden, odd or non-executable entry was run" || ok "run-parts' name filter and the executable bit are kept"
[ "$(cat "$T/out")" = "Initializing Third-Party Addons: rc.prelocal, OK" ] && ok "the console line is S55InitAddons'" || bad "output: $(cat "$T/out")"
[ "$(cat "$T/oom")" = 100 ] && ok "the OOM score is set before the scripts run" || bad "oom: $(cat "$T/oom")"

# 2. safe mode: nothing runs, and the line says so
: > "$T/safemode"
run "$T/hm_mode" "$T/safemode" start
[ ! -s "$LOG" ] && ok "safe mode: nothing runs" || bad "safe mode: $(tr '\n' '|' < "$LOG")"
grep -q "skipping (safemode)" "$T/out" && ok "safe mode: said on the console" || bad "safe mode output: $(cat "$T/out")"

# 3. not in NORMAL mode: nothing at all
printf "HM_MODE='RECOVERY'\n" > "$T/hm_mode2"
run "$T/hm_mode2" "$T/nosafemode" start; rc=$?
[ ! -s "$LOG" ] && [ ! -s "$T/out" ] && [ "$rc" = 0 ] && ok "another HM_MODE: nothing runs, nothing said, exit 0" || bad "HM_MODE=RECOVERY: rc=$rc out=$(cat "$T/out") calls=$(tr '\n' '|' < "$LOG")"
run "$T/missing" "$T/nosafemode" start
[ ! -s "$LOG" ] && ok "no hm_mode file: nothing runs" || bad "no hm_mode: $(tr '\n' '|' < "$LOG")"

# 4. stop does nothing; an unknown action is refused
run "$T/hm_mode" "$T/nosafemode" stop; rc=$?
[ ! -s "$LOG" ] && [ "$rc" = 0 ] && ok "stop runs nothing" || bad "stop: rc=$rc $(tr '\n' '|' < "$LOG")"
run "$T/hm_mode" "$T/nosafemode" bogus; rc=$?
[ "$rc" = 1 ] && ok "an unknown action exits 1" || bad "bogus action exits $rc"

# 5. the unit runs this, not S55InitAddons.script through run-parts
UNIT="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system/occu-init-addons.service"
grep -qx 'ExecStart=/usr/libexec/occu/lite-init-addons start' "$UNIT" && ok "occu-init-addons.service starts through lite-init-addons" || bad "unit ExecStart: $(grep ^ExecStart "$UNIT")"
grep -q 'S55InitAddons.script' "$UNIT" && bad "the unit still runs S55InitAddons.script (run-parts over the .script files)" || ok "the unit no longer runs S55InitAddons.script"

[ "$fails" = 0 ] && echo "lite-init-addons: all cases passed" || { echo "lite-init-addons: $fails case(s) failed"; exit 1; }
