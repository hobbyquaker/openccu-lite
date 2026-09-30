#!/bin/sh
# openccu-lite: lite-clock-valid's window (openccu-lite task 299) - a clock is trusted only between
# the image's build and 15 years after it, on every path: a real-time clock inside the window passes
# at once; one before the build or beyond the window is refused (its time kept for the Status page)
# and the gate waits for NTP; a time server whose time lies outside the window is refused too. The
# untrusted ends carry their own state word: rtc-implausible, ntp-implausible, timeout. The gate's
# timing itself is lite-boot-path-test.sh's.
#
# Usage: sh scripts/testcases/lite-clock-valid-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
TOOL="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-clock-valid"
[ -f "$TOOL" ] || { echo "lite-clock-valid not found under $HERE"; exit 2; }

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }

# the stand-ins: a date that reads its "now" from a file, a chronyc that answers from a state file,
# a sleep that advances the uptime by 10 s (so the 60 s timeout passes in a few rounds)
mkdir -p "$T/bin"
cat > "$T/bin/date" <<'EOF'
#!/bin/sh
case "$1" in
  +%s) cat "$FAKE_NOW" ;;
  -u) shift; exec /bin/date -u "$@" ;;
esac
EOF
cat > "$T/bin/chronyc" <<'EOF'
#!/bin/sh
case "$(cat "$FAKE_CHRONY" 2>/dev/null)" in
  normal) printf 'Reference ID    : C0A80001 (192.0.2.1)\nLeap status     : Normal\n' ;;
  unsynced) printf 'Reference ID    : 00000000 ()\nLeap status     : Not synchronised\n' ;;
  *) exit 1 ;;
esac
EOF
cat > "$T/bin/sleep" <<'EOF'
#!/bin/sh
up=$(cut -d. -f1 "$CLOCK_UPTIME"); echo "$((up + 10)).00 0" > "$CLOCK_UPTIME"
EOF
chmod +x "$T/bin/date" "$T/bin/chronyc" "$T/bin/sleep"
export FAKE_NOW="$T/now" FAKE_CHRONY="$T/chrony" CLOCK_UPTIME="$T/uptime" CLOCK_STATE_DIR="$T/run" \
  CLOCK_HM_MODE="$T/hm_mode" CLOCK_VERSION_FILE="$T/VERSION" CLOCK_CHRONYC="$T/bin/chronyc" CLOCK_DATE="$T/bin/date"

# the image built 2026-09-19 12:00 UTC: the window ends 15 years after it
: > "$T/VERSION"; touch -d '2026-09-19 12:00:00 UTC' "$T/VERSION"
built=$(stat -c %Y "$T/VERSION")
year=$((365 * 86400))

# run <HM_RTC> <now epoch> <chrony state: normal|unsynced|none>: the state word in $st, the output in $out
run() {
  rm -rf "$T/run"; echo "HM_RTC='$1'" > "$T/hm_mode"; echo "$2" > "$FAKE_NOW"; echo "$3" > "$FAKE_CHRONY"
  echo "10.00 0" > "$CLOCK_UPTIME"
  out=$(PATH="$T/bin:$PATH" sh "$TOOL" 60 30 2>&1); rc=$?
  st=$(cat "$T/run/clock-state" 2>/dev/null)
}

# a real-time clock inside the window: trusted at once, chronyc not asked
run rx8130 $((built + 86400)) none
[ $rc = 0 ] && [ "$st" = rtc ] && [ ! -e "$T/run/clock-rtc-implausible" ] && ok "RTC a day after the build: rtc" || bad "RTC a day after the build: rc $rc state '$st' ($out)"
run rx8130 $((built + 14 * year)) none
[ "$st" = rtc ] && ok "RTC 14 years after the build: rtc" || bad "RTC 14 years after: '$st'"

# a real-time clock before the build: refused, its time kept, NTP waited for and never coming
run rx8130 $((built - 3600)) none
[ $rc = 0 ] && [ "$st" = rtc-implausible ] && ok "RTC an hour before the build, no NTP: rtc-implausible" || bad "RTC before the build: rc $rc state '$st' ($out)"
[ "$(cat "$T/run/clock-rtc-implausible" 2>/dev/null)" = "$(date -u -d "@$((built - 3600))" +%Y-%m-%dT%H:%M:%SZ)" ] && ok "the refused RTC time is kept for the Status page" || bad "clock-rtc-implausible: $(cat "$T/run/clock-rtc-implausible" 2>/dev/null)"
case "$out" in *"<4>the real-time clock (rx8130) says"*"outside the 15 years"*) ok "the refusal is a warning line" ;; *) bad "refusal line: $out" ;; esac

# a real-time clock beyond the window (16 years ahead): refused; NTP then answers a plausible time
run rx8130 $((built + 16 * year)) none
[ "$st" = rtc-implausible ] && ok "RTC 16 years after the build, no NTP: rtc-implausible" || bad "RTC 16 years after: '$st' ($out)"
rm -rf "$T/run"; echo "HM_RTC='rx8130'" > "$T/hm_mode"; echo "$((built + 16 * year))" > "$FAKE_NOW"; echo normal > "$FAKE_CHRONY"; echo "10.00 0" > "$CLOCK_UPTIME"
# chronyd's answer is the corrected clock: the fake date reads the same file, so the sync sets it
cat > "$T/bin/chronyc" <<EOF
#!/bin/sh
echo "$((built + 86400))" > "$FAKE_NOW"
printf 'Leap status     : Normal\n'
EOF
chmod +x "$T/bin/chronyc"
out=$(PATH="$T/bin:$PATH" sh "$TOOL" 60 30 2>&1); st=$(cat "$T/run/clock-state" 2>/dev/null)
[ "$st" = ntp ] && [ -e "$T/run/clock-rtc-implausible" ] && ok "a refused RTC, then NTP with a plausible time: ntp, the refused time still named" || bad "RTC refused then NTP: '$st' ($out)"
cat > "$T/bin/chronyc" <<'EOF'
#!/bin/sh
case "$(cat "$FAKE_CHRONY" 2>/dev/null)" in
  normal) printf 'Leap status     : Normal\n' ;;
  unsynced) printf 'Leap status     : Not synchronised\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/bin/chronyc"

# no real-time clock: NTP with a plausible time passes, one outside the window does not
run "" $((built + 86400)) normal
[ "$st" = ntp ] && ok "no RTC, NTP plausible: ntp" || bad "NTP plausible: '$st' ($out)"
run "" $((built + 20 * year)) normal
[ $rc = 0 ] && [ "$st" = ntp-implausible ] && ok "no RTC, NTP 20 years ahead: ntp-implausible after the timeout" || bad "NTP implausible: rc $rc state '$st' ($out)"
case "$out" in *"<4>the time server's time"*"outside the 15 years"*"<4>the clock is not trusted: the time server's time"*) ok "the NTP refusal is said once, and the end says why" ;; *) bad "NTP refusal lines: $out" ;; esac
run "" $((built - 86400)) normal
[ "$st" = ntp-implausible ] && ok "no RTC, NTP a day before the build: ntp-implausible" || bad "NTP before the build: '$st'"

# the plain timeout keeps its word
run "" $((built + 86400)) unsynced
[ "$st" = timeout ] && ok "no RTC, chronyd never synchronised: timeout" || bad "timeout: '$st' ($out)"

# without a build time (no /VERSION) there is no window: an RTC is trusted as before
rm -f "$T/VERSION"
run rx8130 1000000000 none
[ "$st" = rtc ] && ok "no /VERSION: the real-time clock is trusted as before" || bad "no /VERSION: '$st' ($out)"
: > "$T/VERSION"; touch -d '2026-09-19 12:00:00 UTC' "$T/VERSION"

# the state words occulited knows (radio.ClockTrusted): rtc, ntp and manual are trusted, the rest not
for w in rtc ntp; do grep -q "state $w\$" "$TOOL" && ok "the script writes $w" || bad "the script does not write $w"; done
for w in timeout rtc-implausible ntp-implausible; do grep -q "state $w\$" "$TOOL" && ok "the script writes $w" || bad "the script does not write $w"; done

[ $fails = 0 ] && echo "all passed" || echo "$fails failed"
[ $fails = 0 ]
