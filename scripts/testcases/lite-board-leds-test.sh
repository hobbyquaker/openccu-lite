#!/bin/sh
# openccu-lite (task 158): lite-board-leds, the LED half of S99SetupLEDs that
# occu-board-leds.service runs once the radio hardware is known. Against a fake root: the MODE2
# triggers at start, "none" with disableOnboardLED, the RPI-RF-MOD only in HM-LGW mode (blue, dark
# with disableLED, yellow at stop), MODE1 at stop, and no write to an LED the board does not have.
# Nothing needs root.
#
# Usage: sh scripts/testcases/lite-board-leds-test.sh    (from the fork's checkout)
set -u
HERE=$(cd "$(dirname "$0")/../.." && pwd)
S="$HERE/buildroot-external/overlay/lite/usr/libexec/occu/lite-board-leds"
[ -x "$S" ] || { echo "lite-board-leds not found or not executable at $S"; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails+1)); }
is() { # <file under the root> <want> <what>
  got=$(cat "$T$1" 2>/dev/null)
  [ "$got" = "$2" ] && ok "$3" || bad "$3: $1 is '$got', want '$2'"
}

# a Pi: ACT and PWR, heartbeat and default-on after the boot, mmc0 and default-on during it
pi() {
  rm -rf "${T:?}"/*
  mkdir -p "$T/var" "$T/etc/config" "$T/sys/class/leds/ACT" "$T/sys/class/leds/PWR"
  for c in red green blue; do mkdir -p "$T/sys/class/leds/rpi_rf_mod:$c"; echo none > "$T/sys/class/leds/rpi_rf_mod:$c/trigger"; done
  echo mmc0 > "$T/sys/class/leds/ACT/trigger"; echo default-on > "$T/sys/class/leds/PWR/trigger"
  cat > "$T/var/hm_mode" <<HM
HM_LED_GREEN="/sys/class/leds/ACT"
HM_LED_GREEN_MODE1="mmc0"
HM_LED_GREEN_MODE2="heartbeat"
HM_LED_RED="/sys/class/leds/PWR"
HM_LED_RED_MODE1="default-on"
HM_LED_RED_MODE2="none"
HM_LED_YELLOW=""
HM_MODE="NORMAL"
HM_HMIP_DEV="RPI-RF-MOD"
HM_HMRF_DEV="RPI-RF-MOD"
HM
}
run() { LITE_ROOT="$T" sh "$S" "$@" > "$T.out" 2>&1; }

pi; run start
[ "$?" = 0 ] && ok "start exits 0" || bad "start exited non-zero: $(cat "$T.out")"
is /sys/class/leds/ACT/trigger heartbeat "start: ACT to MODE2"
is /sys/class/leds/PWR/trigger none "start: PWR to MODE2"
is /sys/class/leds/rpi_rf_mod:blue/trigger none "start: the RPI-RF-MOD is occulited's outside HM-LGW mode"
run stop
is /sys/class/leds/ACT/trigger mmc0 "stop: ACT back to MODE1"
is /sys/class/leds/PWR/trigger default-on "stop: PWR back to MODE1"
is /sys/class/leds/rpi_rf_mod:red/trigger none "stop: the RPI-RF-MOD untouched outside HM-LGW mode"

pi; : > "$T/etc/config/disableOnboardLED"; run start
is /sys/class/leds/ACT/trigger none "disableOnboardLED: ACT dark"
is /sys/class/leds/PWR/trigger none "disableOnboardLED: PWR dark"

pi; sed -i 's/^HM_MODE=.*/HM_MODE="HM-LGW"/' "$T/var/hm_mode"; run start
is /sys/class/leds/rpi_rf_mod:blue/trigger default-on "HM-LGW: the module blue"
is /sys/class/leds/rpi_rf_mod:red/trigger none "HM-LGW: red off"
run stop
is /sys/class/leds/rpi_rf_mod:red/trigger default-on "HM-LGW stop: yellow (red)"
is /sys/class/leds/rpi_rf_mod:green/trigger default-on "HM-LGW stop: yellow (green)"
is /sys/class/leds/rpi_rf_mod:blue/trigger none "HM-LGW stop: blue off"
pi; sed -i 's/^HM_MODE=.*/HM_MODE="HM-LGW"/' "$T/var/hm_mode"; : > "$T/etc/config/disableLED"; run start
is /sys/class/leds/rpi_rf_mod:blue/trigger none "HM-LGW with disableLED: the module dark"

# a box without these LEDs (x86_64, LXC): nothing is created, and it still succeeds
rm -rf "${T:?}"/*; mkdir -p "$T/var"; printf 'HM_LED_GREEN=""\nHM_LED_RED=""\nHM_MODE="NORMAL"\n' > "$T/var/hm_mode"
run start; rc=$?
[ "$rc" = 0 ] && [ ! -e "$T/sys" ] && ok "no board LEDs: nothing written, exit 0" || bad "no board LEDs: rc $rc, $(find "$T" -path "$T/sys*" | head -3)"
rm -f "$T/var/hm_mode"; run stop; rc=$?
[ "$rc" = 0 ] && ok "no /var/hm_mode: exit 0" || bad "no /var/hm_mode: rc $rc"
run bogus; [ "$?" = 2 ] && ok "an unknown action: usage, exit 2" || bad "an unknown action"
rm -f "$T.out"

[ "$fails" = 0 ] && echo "lite board LEDs: all cases passed" || { echo "lite board LEDs: $fails case(s) failed"; exit 1; }
