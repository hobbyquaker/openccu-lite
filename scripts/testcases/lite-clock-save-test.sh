#!/bin/sh
# openccu-lite: lite-clock-save (B-192) - the save, a restore that sets the clock forward, one that
# leaves a clock ahead alone, no file, an unusable file, the unit's ordering, and the hourly timer.
#
# Usage: sh scripts/testcases/lite-clock-save-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
TOOL="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-clock-save"
UNIT="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system/occu-clock-save.service"
PRESET="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system-preset/50-openccu-lite.preset"
TIMER="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system/occu-clock-save-hourly.timer"
HOURLY="$HERE/buildroot-external/overlay/lite/usr/lib/systemd/system/occu-clock-save-hourly.service"
[ -f "$TOOL" ] || { echo "lite-clock-save not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# a date that reads its "now" from a file and logs a set
cat > "$T/date" <<'EOS'
#!/bin/sh
case "$1" in
  +%s) cat "$FAKE_NOW" ;;
  -s) echo "$2" | tr -d @ > "$FAKE_NOW"; echo "set $2" >> "$FAKE_LOG" ;;
esac
EOS
chmod +x "$T/date"
export CLOCK_DATE="$T/date" CLOCK_SAVE_FILE="$T/userfs/var/lib/lite-clock/saved" FAKE_NOW="$T/now" FAKE_LOG="$T/log"
: > "$T/log"

# restore without a saved time: nothing
echo 1000 > "$T/now"
out=$(sh "$TOOL" restore); rc=$?
[ $rc = 0 ] && [ ! -s "$T/log" ] && ok "no saved time: nothing set ($out)" || bad "no saved time: rc $rc, log $(cat "$T/log")"

# save writes the time, the directory made
echo 1790000000 > "$T/now"
sh "$TOOL" save; rc=$?
[ $rc = 0 ] && [ "$(cat "$CLOCK_SAVE_FILE")" = 1790000000 ] && ok "save writes the time" || bad "save: rc $rc"
[ ! -e "$CLOCK_SAVE_FILE.tmp" ] && ok "no temporary file left" || bad "temporary file left"

# a boot at the build epoch: set forward to the saved time
echo 1774000000 > "$T/now"
out=$(sh "$TOOL" restore); rc=$?
[ $rc = 0 ] && grep -q 'set @1790000000' "$T/log" && [ "$(cat "$T/now")" = 1790000000 ] && ok "behind: set forward ($out)" || bad "behind: rc $rc, log $(cat "$T/log")"
case "$out" in *"16000000 s"*) ok "the message names the step" ;; *) bad "message: $out" ;; esac

# a clock ahead (a real-time clock, or NTP already): never moved back
: > "$T/log"
echo 1790000500 > "$T/now"
sh "$TOOL" restore >/dev/null; rc=$?
[ $rc = 0 ] && [ ! -s "$T/log" ] && [ "$(cat "$T/now")" = 1790000500 ] && ok "ahead: left as it is" || bad "ahead: moved ($(cat "$T/log"))"

# an unusable file: a warning, nothing set
printf 'garbage\n' > "$CLOCK_SAVE_FILE"
echo 1000 > "$T/now"
out=$(sh "$TOOL" restore); rc=$?
[ $rc = 0 ] && [ ! -s "$T/log" ] && case "$out" in "<4>"*) true ;; *) false ;; esac && ok "unusable file: warning, nothing set" || bad "unusable: rc $rc out $out"

# a usage error
sh "$TOOL" bogus 2>/dev/null; [ $? = 2 ] && ok "unknown action: 2" || bad "unknown action"

# the unit: early, before what reads the clock, stopped before the userfs goes
grep -q '^DefaultDependencies=no' "$UNIT" && grep -q '^RequiresMountsFor=/usr/local' "$UNIT" && grep -q '^Conflicts=shutdown.target' "$UNIT" && ok "unit: early, stops before the userfs" || bad "unit: dependencies"
for u in lighttpd.service chrony.service occu-clock-valid.service; do
  grep '^Before=' "$UNIT" | grep -q "$u" && ok "unit: before $u" || bad "unit: not before $u"
done
grep -q '^After=.*occu-init-rtc.service' "$UNIT" && ok "unit: after the real-time clock" || bad "unit: not after occu-init-rtc"
grep -q '^ExecStart=/usr/libexec/occu/lite-clock-save restore$' "$UNIT" && grep -q '^ExecStop=/usr/libexec/occu/lite-clock-save save$' "$UNIT" && ok "unit: restore at start, save at stop" || bad "unit: exec lines"
grep -q '^enable occu-clock-save.service$' "$PRESET" && ok "preset enables it" || bad "preset"

# the hourly save (the maintainer, 2026-09-24): a timer an hour after the boot and every hour, its
# job the same save, only while the restore unit is active, not in a container
grep -q '^OnBootSec=1h$' "$TIMER" && grep -q '^OnUnitActiveSec=1h$' "$TIMER" && ok "timer: hourly" || bad "timer: interval"
grep -q '^DefaultDependencies=no' "$TIMER" && grep -q '^ConditionVirtualization=!container' "$TIMER" && ok "timer: no default dependencies, not in a container" || bad "timer: unit section"
grep -q '^ExecStart=/usr/libexec/occu/lite-clock-save save$' "$HOURLY" && ok "hourly job: the save" || bad "hourly job: exec"
grep -q '^Requisite=occu-clock-save.service$' "$HOURLY" && grep -q '^After=occu-clock-save.service$' "$HOURLY" && grep -q '^RequiresMountsFor=/usr/local$' "$HOURLY" && ok "hourly job: only after the restore, with the userfs" || bad "hourly job: dependencies"
grep -q '^enable occu-clock-save-hourly.timer$' "$PRESET" && ok "preset enables the timer" || bad "preset: timer"

[ $fails = 0 ] && echo "all passed" || echo "$fails failed"
[ $fails = 0 ]
